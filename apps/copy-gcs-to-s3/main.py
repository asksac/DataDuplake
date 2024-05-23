import os, sys, time
import base64, logging, json
import argparse
from urllib.parse import urlparse
import concurrent.futures

# add lib directory to path if this program runs inside lambda runtime
if os.environ.get('LAMBDA_TASK_ROOT'):
  sys.path.insert(0, f"{os.environ['LAMBDA_TASK_ROOT']}/lib")

# aws sdk
import boto3

# gcp storage and auth modules
from google.cloud import storage
from google.oauth2 import service_account

import crc32c

# gcp credentials must be stored in an aws secrets manager 
# secret value must be a valid json object with the following attributes:
#   - credentials: base64 encoded string containing the gcp service account credentials

# define global variables
DEFAULT_CHUNK_SIZE = 1024 * 1024 * 64 # 64 MB
DEFAULT_MAX_WORKERS = 2

s3_client = None
gcs_client = None

# configures logging and sets global variable values
# we use global variables carefully and in order to improve performance
def _initializer(): 
  global s3_client, gcs_client

  # get the log level from environment variable
  log_level = os.environ.get('LOG_LEVEL', 'INFO')
  if logging.getLogger().hasHandlers():
    # lambda environment pre-configures a logging handler, and `.basicConfig` will not execute
    logging.getLogger().setLevel(log_level)
  else:
    logging.basicConfig(format='%(asctime)s - %(levelname)s - %(message)s', level=log_level)

  logging.info('Initializing Lambda runtime...')

  # initialize aws s3 and gcp storage clients
  s3_client = boto3.client('s3')

  if os.environ.get('GOOGLE_APPLICATION_CREDENTIALS'): 
    # if GOOGLE_APPLICATION_CREDENTIALS is set, use the default gcp client
    #gcs_client = storage.Client()
    key_path = os.environ['GOOGLE_APPLICATION_CREDENTIALS']
    credentials = service_account.Credentials.from_service_account_file(key_path)
    gcs_client = storage.Client(credentials=credentials, project=credentials.project_id)
  else: 
    # if not, lets fetch a service account credentials via aws secrets manager
    # get value of 'GOOGLE_CREDENTIALS_SECRETS_MGR_ID' environment variable 
    secrets_mgr_id = os.environ.get('GOOGLE_CREDENTIALS_SECRETS_MGR_ID')
    if (not secrets_mgr_id):
      logging.error('No default GCP credentials found, and no credentials Secrets Manager secret id defined. This Lambda function cannot create a GCP client, and therefore cannot continue. Goodbye!')
      sys.exit(1)
    else: 
      logging.info('Fetching GCP credentials from AWS Secrets Manager (Secret Id: %s)...', secrets_mgr_id)
      credentials_json = get_credentials_from_secrets_mgr(secrets_mgr_id) 
      logging.info('Read GCP credentials json (size %s bytes)', len(credentials_json))
      storage_credentials = service_account.Credentials.from_service_account_info(json.loads(credentials_json))
      gcs_client = storage.Client(credentials=storage_credentials)
  logging.info('Initialization complete with AWS and GCS clients created')


# splits an aws s3 or gcp storage object uri into bucket name and object name
def _split_uri(uri):
  parsed_uri = urlparse(uri)
  bucket_name = parsed_uri.netloc
  object_name = parsed_uri.path.lstrip('/')
  return bucket_name, object_name


# copy a chunk of a gcs object to s3 using multi-part upload
def _copy_part(gcs_object, s3_bucket_name, s3_object_name, part_num: int, total_parts: int, mpu_id: int, start_byte: int, end_byte: int, checksum: bool) -> dict:
  logging.info('Reading GCS object chunk #%s of %s: start byte: %s | end byte: %s', part_num, total_parts, start_byte, end_byte)
  gcs_chunk = gcs_object.download_as_bytes(start=start_byte, end=end_byte) 
  logging.info('Read GCS object chunk of length: %s bytes', len(gcs_chunk))

  if checksum: 
    crc_checksum = crc32c.crc32c(gcs_chunk) # returns an int
    crc_checksum_b64 = base64.b64encode(crc_checksum.to_bytes(4, byteorder='big', signed=False)).decode('ascii') # convert int to 32 bit and then base64 encode
    logging.info('GCS object chunk CRC32C checksum: int(%s) and base64(%s)', crc_checksum, crc_checksum_b64)
    s3_response = s3_client.upload_part(Bucket=s3_bucket_name, Key=s3_object_name, Body=gcs_chunk, PartNumber=part_num, UploadId=mpu_id, ChecksumAlgorithm='CRC32C', ChecksumCRC32C=crc_checksum_b64)
    logging.info('Wrote GCS object chunk to S3 part: %s', s3_response)
    return {"ETag": s3_response["ETag"], "PartNumber": part_num, "ChecksumCRC32C": crc_checksum_b64}
  else: 
    s3_response = s3_client.upload_part(Bucket=s3_bucket_name, Key=s3_object_name, Body=gcs_chunk, PartNumber=part_num, UploadId=mpu_id)
    logging.info('Wrote GCS object chunk to S3 part: %s', s3_response)
    return {"ETag": s3_response["ETag"], "PartNumber": part_num}


# copy full gcs object to s3
def _copy_full(gcs_object, s3_bucket_name, s3_object_name, checksum: bool) -> dict:
  logging.info('Reading full GCS object')
  gcs_data = gcs_object.download_as_bytes() 
  logging.info('Read GCS object of length: %s bytes', len(gcs_data))

  if checksum: 
    crc_checksum = crc32c.crc32c(gcs_data) # returns an int
    crc_checksum_b64 = base64.b64encode(crc_checksum.to_bytes(4, byteorder='big', signed=False)).decode('ascii') # convert int to 32 bit and then base64 encode
    logging.info('GCS object CRC32C checksum: int(%s) and base64(%s)', crc_checksum, crc_checksum_b64)
    s3_response = s3_client.put_object(Bucket=s3_bucket_name, Key=s3_object_name, Body=gcs_data, ChecksumAlgorithm='CRC32C', ChecksumCRC32C=crc_checksum_b64)
    logging.info('Wrote GCS object to S3: %s', s3_response)
    return {"ETag": s3_response["ETag"], "ChecksumCRC32C": crc_checksum_b64}
  else: 
    s3_response = s3_client.put_object(Bucket=s3_bucket_name, Key=s3_object_name, Body=gcs_data)
    logging.info('Wrote GCS object to S3: %s', s3_response)
    return {"ETag": s3_response["ETag"]}


# copy a gcs object to s3 using mpu
def copy_object_gcs_to_s3(source_object_uri, target_object_uri, chunk_size: int, max_workers: int, checksum: bool = False) -> dict: 
  gcs_bucket_name, gcs_object_name = _split_uri(source_object_uri)
  s3_bucket_name, s3_object_name = _split_uri(target_object_uri)

  logging.info('GCS source bucket `%s` and object key `%s`', gcs_bucket_name, gcs_object_name)
  logging.info('S3 target bucket `%s` and object key `%s`', s3_bucket_name, s3_object_name)

  gcs_bucket = gcs_client.bucket(gcs_bucket_name)
  gcs_object = gcs_bucket.get_blob(gcs_object_name)
  gcs_object.reload() # required to read blob attributes like size

  gcs_object_size = gcs_object.size
  logging.info('GCS source object size and etag: %s, %s', gcs_object_size, gcs_object.etag)

  # s3 mpu requires parts to be atleast 5Mb, so if gcs object size is less than 5Mb, 
  # or less than chunk size, we direct copy the object
  if gcs_object_size < 5242880 or gcs_object_size <= chunk_size: 
    # initiate direct file copy
    logging.info('Starting full object copy because GCS object size is either less than 5Mb or less than chunk-size')
    _copy_full(gcs_object, s3_bucket_name, s3_object_name, checksum)
  else: 
    # initiatize multi-part copy
    total_parts = (gcs_object_size // chunk_size) + 1 
    mpu_parts = [None] * total_parts
    logging.info('Starting multi-part object copy using %s parts, and checksum validation set to %s', total_parts, checksum)

    if checksum: 
      mpu = s3_client.create_multipart_upload(Bucket=s3_bucket_name, Key=s3_object_name, ChecksumAlgorithm='CRC32C')
    else: 
      mpu = s3_client.create_multipart_upload(Bucket=s3_bucket_name, Key=s3_object_name)

    mpu_id = mpu['UploadId']

    if (max_workers <= 1):
      # perform a single threaded copy
      logging.info('Using single threaded multi-part object copy because max-workers is less than or equal to 1')
      for part_index in range(total_parts):
        start_byte = part_index * chunk_size
        end_byte = min((part_index + 1) * chunk_size, gcs_object_size) - 1 # end byte index is inclusive, so we minus 1
        part_num = part_index + 1 # part numbers start at 1
        copy_part_response = _copy_part(gcs_object, s3_bucket_name, s3_object_name, part_num, total_parts, mpu_id, start_byte, end_byte, checksum)
        logging.info('copy_part response: %s', copy_part_response)
        mpu_parts[part_index] = copy_part_response
    else: 
      # perform a multi-threaded copy
      logging.info('Using multi-threaded multi-part object copy with max-workers equal to %s', max_workers)
      futures = []
      with concurrent.futures.ThreadPoolExecutor(max_workers = max_workers) as executor:
        for part_index in range(total_parts):
          start_byte = part_index * chunk_size
          end_byte = min((part_index + 1) * chunk_size, gcs_object_size) - 1 # end byte index is inclusive, so we minus 1
          part_num = part_index + 1 # part numbers start at 1
          futures.append(executor.submit(_copy_part, gcs_object, s3_bucket_name, s3_object_name, part_num, total_parts, mpu_id, start_byte, end_byte, checksum))
        
      for future in concurrent.futures.as_completed(futures):
        copy_part_response = future.result()
        mpu_parts[copy_part_response['PartNumber']-1] = copy_part_response
        logging.info('copy_part response: %s', copy_part_response)

    s3_response = s3_client.complete_multipart_upload(Bucket=s3_bucket_name, Key=s3_object_name, MultipartUpload={'Parts': mpu_parts}, UploadId=mpu_id)
    logging.info('S3 complete_multipart_upload response: %s', s3_response)

  # lets read some attributes of the final s3 target object
  s3_object_attr = s3_client.get_object_attributes(Bucket=s3_bucket_name, Key=s3_object_name, ObjectAttributes=['ETag', 'Checksum', 'ObjectSize'])
  s3_object_size = s3_object_attr.get('ObjectSize')
  logging.info('S3 target object attributes: %s', s3_object_attr)

  if gcs_object_size != s3_object_size:
    raise Exception('GCS and S3 object sizes do not match. GCS size: %s, S3 size: %s', gcs_object_size, s3_object_size)
  else: 
    logging.info('GCS and S3 object sizes match. GCS size: %s, S3 size: %s', gcs_object_size, s3_object_size)

  response = dict(
    bucket_name = s3_bucket_name,
    object_name = s3_object_name,
    object_size = s3_object_size, 
    chunk_size = chunk_size,
    max_workers = max_workers,
    etag = s3_object_attr.get('ETag')
  )
  if checksum: response['checksum_crc32c'] = s3_object_attr.get('Checksum').get('ChecksumCRC32C') if isinstance(s3_object_attr.get('Checksum'), dict) else None
  return response


def get_credentials_from_secrets_mgr(secret_id):
  client = boto3.client('secretsmanager')
  response = client.get_secret_value(SecretId=secret_id)
  credentials_base64 = json.loads(response['SecretString'])['credentials']
  return base64.b64decode(credentials_base64).decode('utf-8')


def lambda_handler(event, context):
  # capture start time
  start_time = time.time()

  source_object_uri = event.get('source_object_uri')
  target_object_uri = event.get('target_object_uri')
  chunk_size = int(event.get('chunk_size', DEFAULT_CHUNK_SIZE))
  max_workers = int(event.get('max_workers', DEFAULT_MAX_WORKERS))
  checksum = event.get('checksum', False) in [True, 'True', 'true', 'Yes', 'yes', 'Y', 'y', '1'] 

  logging.info('Lambda called with event payload: %s', event) 

  if not source_object_uri or not target_object_uri: 
    err_msg = 'Request payload must include `source_object_uri` and `target_object_uri` attributes'
    logging.error(err_msg)

    return dict(
      statusCode = 500,
      headers = { 'Content-Type': 'application/json' }, 
      body = dict(
        err_code = 500, 
        err_message = err_msg
      )
    )
  else: 
    copy_response = copy_object_gcs_to_s3(source_object_uri, target_object_uri, chunk_size, max_workers, checksum)
    end_time = time.time() # capture end time
    execution_time = end_time - start_time
    copy_response['execution_time'] = execution_time
    logging.info('Total execution time: %s seconds', execution_time)
    return dict(
      statusCode = 200,
      headers = { 'Content-Type': 'application/json' }, 
      body = copy_response
    )

#-----

# initialize lambda runtime
_initializer()

# if this program is executed from a terminal
if __name__ == "__main__":
  cliparser = argparse.ArgumentParser(
    description='Copy an object from GCP Storage to AWS S3, with support for large files.',
  )
  cliparser.add_argument('--source-uri', '-s',
                          required=True,
                          help='source gcs object uri (e.g. gs://bucketname/path/file)'
                          )
  cliparser.add_argument('--target-uri', '-t',
                          required=True,
                          help='target s3 object uri (e.g. s3://bucketname/path/file)'
                          )
  cliparser.add_argument('--chunk-size', '-c',
                          required=False,
                          default=DEFAULT_CHUNK_SIZE,
                          help='chunk size in bytes (default: %s)' % DEFAULT_CHUNK_SIZE
                        )
  cliparser.add_argument('--max-workers', '-w',
                          required=False,
                          default=DEFAULT_MAX_WORKERS,
                          help='max number of concurrent workers (default: %s)' % DEFAULT_MAX_WORKERS
                        )
  cliparser.add_argument('--checksum', '-k',
                          required=False,
                          default=False,
                          help='whether checksum validation should be performed (valid values are True or False)'
                        )

  # extract cli option values and set program behavior
  args = cliparser.parse_args()

  response = lambda_handler(dict(source_object_uri=args.source_uri, target_object_uri=args.target_uri, chunk_size=args.chunk_size, max_workers=args.max_workers, checksum=args.checksum), None)
  logging.info('Response from lambda_handler: %s', response)