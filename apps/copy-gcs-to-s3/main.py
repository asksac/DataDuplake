import os, sys, time
from datetime import datetime
import base64, logging, json
import argparse
from urllib.parse import urlparse
import concurrent.futures

# add lib directory to path if this program runs inside lambda runtime
if os.environ.get('LAMBDA_TASK_ROOT'):
  sys.path.insert(0, f"{os.environ['LAMBDA_TASK_ROOT']}/lib")

# aws sdk
import boto3
from botocore.config import Config

# gcp storage and auth modules
import google.auth
from google.cloud import storage
from google.oauth2 import service_account

import jsonschema
import crc32c

# define global variables
DEFAULT_CHUNK_SIZE = 1024 * 1024 * 64 # 64 MB
DEFAULT_MAX_WORKERS = 2
DEFAULT_CHECKSUM_ENABLED = False
RETRY_DELAY = 2 # number of seconds to wait before retrying on read/write failure

# define lambda payload schema
LAMBDA_PAYLOAD_SCHEMA = {
  "type": "object", 
  "properties": {
    "objects": {
      "type": "array", 
      "items": {
        "type": "object",
        "properties": {
          "source_uri": {
            "type": "string"
          },
          "target_uri": {
            "type": "string"
          },
          "checksum": {
            "type": "string"
          }, 
          "chunk_size": {
            "type": "integer"
          }, 
          "max_workers": {
            "type": "integer"
          }, 
          "kms_key_arn": {
            "type": "string"
          } 
        },
        "required": ["source_uri", "target_uri"]
      }, 
      "minItems" : 1
    }, 
    "defaults": {
      "type": "object",
      "properties": {
        "checksum": {
          "type": "string"
        }, 
        "chunk_size": {
          "type": "integer"
        },
        "max_workers": {
          "type": "integer"
        }, 
        "kms_key_arn": {
          "type": "string"
        } 
      }
    }
  }, 
  "required": ["objects"]
}

LAMBDA_PAYLOAD_EXAMPLE = '''{ 
  "objects" : [ 
    { 
      "source_uri": "gs://xxxx", 
      "target_uri": "s3://yyyy", 
      "checksum": "yes", 
      "max_workers": 1
    }, 
    { 
      "source_uri": "gs://abcd", 
      "target_uri": "s3://pqrs", 
      "chunk_size": 102400
    } 
  ], 
  "defaults": { 
    "checksum": "false",
    "chunk_size": 1024, 
    "max_workers": 2, 
    "kms_key_arn": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  } 
}'''

s3_client = None
gcs_client = None
lambda_schema_validator = None

# must be called once at startup, configures logging and sets global variables
# we use global variables carefully and in order to improve performance
def _initializer(): 
  global s3_client, gcs_client, lambda_schema_validator

  # get the log level from environment variable
  log_level = os.environ.get('LOG_LEVEL', 'INFO')
  if logging.getLogger().hasHandlers():
    # lambda environment pre-configures a logging handler, and `.basicConfig` will not execute
    logging.getLogger().setLevel(log_level)
  else:
    logging.basicConfig(format='%(asctime)s - %(levelname)s - %(message)s', level=log_level)

  logging.info('Initializing Lambda runtime...')

  ## create aws s3 client
  config = Config(
    retries = {
      'max_attempts': 3, # change to set boto3 s3 max retries count
      'mode': 'legacy' # legacy mode is default 
    }, 
    proxies = {} # override any environment based proxy settings
  )
  s3_client = boto3.client('s3', config=config)

  ## create gcp storage client
  OAUTH_SCOPES = ['https://www.googleapis.com/auth/devstorage.read_write']
  if os.environ.get('GCP_CREDENTIALS_FILE'): 
    # if GCP_CREDENTIALS_FILE variable is set, use that to create gcp client
    key_path = os.environ['GCP_CREDENTIALS_FILE']
    gcp_credentials = service_account.Credentials.from_service_account_file(key_path, scopes=OAUTH_SCOPES)
  else: 
    # if not, lets fetch a service account credentials via aws secrets manager
    # get value of 'GCP_CREDENTIALS_SECRET_ID' environment variable 
    # gcp credentials must be stored in aws secrets manager as a json object with attribute:
    #   - credentials: base64 encoded string containing the gcp service account credentials
    secrets_mgr_id = os.environ.get('GCP_CREDENTIALS_SECRET_ID')
    if (not secrets_mgr_id):
      logging.error('No GCP credentials found. This Lambda function cannot create a GCP client, and therefore cannot continue. Goodbye!')
      sys.exit(1)
    else: 
      logging.info('Fetching GCP credentials from AWS Secrets Manager (Secret Id: %s)...', secrets_mgr_id)
      credentials_json = get_credentials_from_secrets_mgr(secrets_mgr_id) 
      logging.info('Read GCP credentials json (size %s bytes)', len(credentials_json))
      gcp_credentials = service_account.Credentials.from_service_account_info(json.loads(credentials_json), scopes=OAUTH_SCOPES)

  gcp_proxy = os.environ.get('GCP_PROXY') # proxy server used for GCP connections only
  if gcp_proxy: 
    auth_session = google.auth.transport.requests.AuthorizedSession(credentials=gcp_credentials)
    auth_session.proxies.update({'https': gcp_proxy})
    gcs_client = storage.Client(credentials=gcp_credentials, _http=auth_session)
  else: 
    gcs_client = storage.Client(credentials=gcp_credentials)

  lambda_schema_validator = jsonschema.Draft202012Validator(LAMBDA_PAYLOAD_SCHEMA) 
  logging.info('Initialization complete with AWS and GCS clients created')

# fetch and base64 decode credentials from aws secrets manager
def get_credentials_from_secrets_mgr(secret_id: str) -> str:
  client = boto3.client('secretsmanager')
  response = client.get_secret_value(SecretId=secret_id)
  credentials_base64 = json.loads(response['SecretString'])['credentials']
  return base64.b64decode(credentials_base64).decode('utf-8')

# splits an aws s3 or gcp storage object uri into bucket name and object name
def _split_uri(uri: str) -> tuple:
  parsed_uri = urlparse(uri)
  bucket_name = parsed_uri.netloc
  # object_name is also referred to as an object's key (especially in S3)
  # in this program, we call it object_name to avoid any confusion with encryption key
  object_name = parsed_uri.path.lstrip('/') 
  return bucket_name, object_name

# copy gcs object to s3 using multi-part upload
def _copy_mpu(gcs_object: str, s3_bucket_name: str, s3_object_name: str, gcs_object_size: int, total_parts: int, chunk_size: int, max_workers: int, checksum: bool, kms_key_arn: str): 
  create_mpu_args = {
    'Bucket': s3_bucket_name,
    'Key': s3_object_name
  }
  if checksum: 
    create_mpu_args.update({'ChecksumAlgorithm': 'CRC32C'})

  if isinstance(kms_key_arn, str) and kms_key_arn.startswith('arn:aws'): 
    create_mpu_args.update({'ServerSideEncryption': 'aws:kms', 'SSEKMSKeyId': kms_key_arn})
  else: 
    create_mpu_args.update({'ServerSideEncryption': 'AES256'})

  # call s3 create_multipart_upload() with arguments
  mpu = s3_client.create_multipart_upload(**create_mpu_args)

  mpu_id = mpu['UploadId']
  mpu_parts = [None] * total_parts

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
        try: 
          copy_part_response = future.result()
        except Exception as e:
          logging.error('One of the multi-part object copy threads returned an exception [%s]. Aborting copy operation now!', e)
          # cancel all pending tasks and bubble up the exception
          executor.shutdown(wait=False, cancel_futures=True)
          raise e
        mpu_parts[copy_part_response['PartNumber']-1] = copy_part_response
        logging.info('copy_part response: %s', copy_part_response)

  s3_response = s3_client.complete_multipart_upload(Bucket=s3_bucket_name, Key=s3_object_name, MultipartUpload={'Parts': mpu_parts}, UploadId=mpu_id)
  logging.info('S3 complete_multipart_upload response: %s', s3_response)

# copy a chunk of a gcs object to s3 using multi-part upload
# if checksum is true, we will use ultrafast crc32c checksum algorithm
def _copy_part(gcs_object, s3_bucket_name, s3_object_name, part_num: int, total_parts: int, mpu_id: int, start_byte: int, end_byte: int, checksum: bool) -> dict:
  logging.info('Reading GCS object chunk #%s of %s (start byte: %s; end byte: %s)', part_num, total_parts, start_byte, end_byte)
  try: 
    gcs_chunk = gcs_object.download_as_bytes(start=start_byte, end=end_byte) 
  except Exception as e:
    logging.error('Encountered an error reading GCS object chunk #%s: %s', part_num, e)
    # let's retry reading gcs chunk one more time
    logging.info('Retrying reading GCS object chunk #%s after a delay of %s seconds', part_num, RETRY_DELAY)
    time.sleep(RETRY_DELAY)
    gcs_chunk = gcs_object.download_as_bytes(start=start_byte, end=end_byte) 

  # download successful if reached here
  logging.info('Read GCS object chunk #%s of length: %s bytes', part_num, len(gcs_chunk))

  upload_part_args = dict(Bucket=s3_bucket_name, Key=s3_object_name, Body=gcs_chunk, PartNumber=part_num, UploadId=mpu_id)
  if checksum: 
    crc_checksum = crc32c.crc32c(gcs_chunk) # returns an int
    crc_checksum_b64 = base64.b64encode(crc_checksum.to_bytes(4, byteorder='big', signed=False)).decode('ascii') # convert int to 32 bits and then base64 encode
    upload_part_args.update(dict(ChecksumAlgorithm='CRC32C', ChecksumCRC32C=crc_checksum_b64))
    logging.info('Uploading GCS object chunk #%s to S3 with CRC32C checksum: int(%s) and base64(%s)', part_num, crc_checksum, crc_checksum_b64)
  else: 
    logging.info('Uploading GCS object chunk #%s to S3 without checksum', part_num)

  try: 
    # boto3 has retry mechanism built-in for failures, including checksum failures 
    s3_response = s3_client.upload_part(**upload_part_args)
  except Exception as e:
    logging.error('Encountered an error uploading GCS object chunk #%s to S3: %s', part_num, e)
    raise # re-raise the exception so that the caller can handle it

  # upload successful if reached here
  logging.info('Wrote GCS object chunk #%s to S3 part, which returned: %s', part_num, s3_response) 

  if checksum:
    return {"ETag": s3_response["ETag"], "PartNumber": part_num, "ChecksumCRC32C": crc_checksum_b64}
  else: 
    return {"ETag": s3_response["ETag"], "PartNumber": part_num}


# copy full gcs object to s3
def _copy_full(gcs_object, s3_bucket_name, s3_object_name, checksum: bool, kms_key_arn: str) -> dict:
  logging.info('Reading full GCS object')
  gcs_data = gcs_object.download_as_bytes() 
  logging.info('Read GCS object of length: %s bytes', len(gcs_data))

  put_object_args = {
    'Bucket': s3_bucket_name,
    'Key': s3_object_name, 
    'Body': gcs_data
  }
  if checksum: 
    crc_checksum = crc32c.crc32c(gcs_data) # returns an int
    crc_checksum_b64 = base64.b64encode(crc_checksum.to_bytes(4, byteorder='big', signed=False)).decode('ascii') # convert int to 32 bit and then base64 encode
    logging.info('GCS object CRC32C checksum: int(%s) and base64(%s)', crc_checksum, crc_checksum_b64)
    put_object_args.update({'ChecksumAlgorithm': 'CRC32C', 'ChecksumCRC32C' : crc_checksum_b64})

  if isinstance(kms_key_arn, str) and kms_key_arn.startswith('arn:aws'): 
    put_object_args.update({'ServerSideEncryption': 'aws:kms', 'SSEKMSKeyId': kms_key_arn})
  else: 
    put_object_args.update({'ServerSideEncryption': 'AES256'})

  s3_response = s3_client.put_object(**put_object_args)
  logging.info('Wrote GCS object to S3: %s', s3_response)

  if checksum: 
    return {"ETag": s3_response["ETag"], "ChecksumCRC32C": crc_checksum_b64}
  else: 
    return {"ETag": s3_response["ETag"]}


# copy a gcs object to s3 using mpu
def copy_object_gcs_to_s3(source_object_uri, target_object_uri, chunk_size: int, max_workers: int, checksum: bool = False, kms_key_arn: str = None) -> dict: 
  start_time = time.time() # capture start time

  # use naive object to get local time based on system timezone (use TZ environment variable to set timezone)
  now = datetime.now() 
  source_object_uri = source_object_uri.format(now)
  target_object_uri = target_object_uri.format(now)
  gcs_bucket_name, gcs_object_name = _split_uri(source_object_uri)
  s3_bucket_name, s3_object_name = _split_uri(target_object_uri)

  logging.info('GCS source bucket `%s` and object key `%s`', gcs_bucket_name, gcs_object_name)
  logging.info('S3 target bucket `%s` and object key `%s`', s3_bucket_name, s3_object_name)

  # fetch gcs blob
  gcs_bucket = gcs_client.bucket(gcs_bucket_name)
  gcs_object = gcs_bucket.get_blob(gcs_object_name)
  gcs_object.reload() # required to read blob attributes like size
  gcs_object_size = gcs_object.size
  logging.info('GCS source object size and etag: %s, %s', gcs_object_size, gcs_object.etag)

  # s3 mpu requires parts to be atleast 5Mb, so if gcs object size is less than 5Mb, 
  # or less than chunk size, we direct copy the object
  if gcs_object_size < 5242880 or gcs_object_size <= chunk_size: 
    # initiate direct file copy
    total_parts = 1
    logging.info('Starting full object copy because GCS object size is either less than 5Mb or less than chunk-size')
    _copy_full(gcs_object, s3_bucket_name, s3_object_name, checksum, kms_key_arn)
  else: 
    # initiate multi-part copy
    total_parts = (gcs_object_size // chunk_size) + 1 
    logging.info('Starting multi-part object copy using %s parts, and checksum validation set to %s', total_parts, checksum)
    _copy_mpu(gcs_object, s3_bucket_name, s3_object_name, gcs_object_size, total_parts, chunk_size, max_workers, checksum, kms_key_arn)

  # lets read some attributes of the final s3 target object
  s3_object_attr = s3_client.get_object_attributes(Bucket=s3_bucket_name, Key=s3_object_name, ObjectAttributes=['ETag', 'Checksum', 'ObjectSize', ''])
  s3_object_size = s3_object_attr.get('ObjectSize')
  logging.info('S3 target object attributes: %s', s3_object_attr)

  if gcs_object_size != s3_object_size:
    logging.error('Original GCS object (%s bytes) and copied S3 object (%s bytes) sizes do not match', gcs_object_size, s3_object_size)
    status = 'COPY_SUCCESS_SIZE_MISMATCHED'
  else: 
    logging.info('GCS and S3 object sizes match. GCS size: %s, S3 size: %s', gcs_object_size, s3_object_size)

    status = 'COPY_SUCCESS_SIZE_MATCHED'

  end_time = time.time() # capture end time
  execution_time = end_time - start_time
  logging.info('Object copy total execution time: %s seconds', execution_time)

  response = dict(
    status = status,    
    bucket_name = s3_bucket_name,
    object_name = s3_object_name,
    object_size = s3_object_size, 
    parts = total_parts,
    etag = s3_object_attr.get('ETag'), 
    execution_time = execution_time
  )
  if checksum: 
    response['checksum_crc32c'] = s3_object_attr.get('Checksum', {}).get('ChecksumCRC32C')
  if kms_key_arn: 
    response['kms_key_arn'] = kms_key_arn

  return response


def lambda_handler(event, context):
  # validate lambda payload using the defined json schema
  if lambda_schema_validator.is_valid(event): 
    # json payload conforms to schema
    logging.info('Lambda invoked with a valid payload: %s', event) 
    default_chunk_size = event.get('defaults', {}).get('chunk_size', DEFAULT_CHUNK_SIZE)
    default_max_workers = event.get('defaults', {}).get('max_workers', DEFAULT_MAX_WORKERS)
    default_checksum = event.get('defaults', {}).get('checksum', DEFAULT_CHECKSUM_ENABLED)
    default_kms_key_arn = event.get('defaults', {}).get('kms_key_arn')

    copy_count = 0
    copy_responses = []
    for object_def in event.get('objects'): 
      copy_count += 1
      source_object_uri = object_def.get('source_uri')
      target_object_uri = object_def.get('target_uri')
      chunk_size = int(object_def.get('chunk_size', default_chunk_size))
      max_workers = int(object_def.get('max_workers', default_max_workers))
      checksum = object_def.get('checksum', default_checksum) in [True, 'True', 'true', 'Yes', 'yes', 'Y', 'y', '1'] 
      kms_key_arn = object_def.get('kms_key_arn', default_kms_key_arn)

      try: 
        logging.info('Copying object #%s: %s -> %s', copy_count, source_object_uri, target_object_uri)
        copy_object_response = copy_object_gcs_to_s3(source_object_uri, target_object_uri, chunk_size, max_workers, checksum, kms_key_arn)
        logging.info('Copying object #%s completed with response: %s', copy_count, copy_object_response)
      except Exception as e:
        logging.error('Error encountered copying object #%s: %s', copy_count, e)
        copy_object_response = dict(
          status = 'COPY_FAILED',
          err_code = 500,
          err_message = str(e)
        )
      copy_responses.append(copy_object_response)

    # return copy responses
    return dict(
      statusCode = 200,
      headers = { 'Content-Type': 'application/json' }, 
      body = { "results": copy_responses } 
    )
  else: 
    # payload schema is not valid
    logging.error('Lambda invoked with an invalid payload: %s', event)
    logging.info('Example of a valid payload is: %s', LAMBDA_PAYLOAD_EXAMPLE)
    payload_errors = [ err.message for err in lambda_schema_validator.iter_errors(event) ]
    logging.error('Lambda payload errors: %s', payload_errors)
    return dict(
      statusCode = 400,
      headers = { 'Content-Type': 'application/json' }, 
      body = dict(
        error = dict(
          code = 400, 
          message = 'Lambda payload invalid',
          details = payload_errors
        )
      )
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
                          type=int,
                          default=DEFAULT_CHUNK_SIZE,
                          help='chunk size in bytes (default: %s)' % DEFAULT_CHUNK_SIZE
                        )
  cliparser.add_argument('--max-workers', '-w',
                          required=False,
                          type=int,
                          default=DEFAULT_MAX_WORKERS,
                          help='max number of concurrent workers (default: %s)' % DEFAULT_MAX_WORKERS
                        )
  cliparser.add_argument('--checksum', '-k',
                          required=False,
                          type=str,
                          default='False',
                          help='whether checksum validation should be performed (valid values are True or False)'
                        )

  # extract cli option values and set program behavior
  args = cliparser.parse_args()

  lambda_payload = { "objects": [ dict(source_uri=args.source_uri, target_uri=args.target_uri, chunk_size=args.chunk_size, max_workers=args.max_workers, checksum=args.checksum) ] }
  response = lambda_handler(lambda_payload, None)
  logging.info('Response from lambda_handler: %s', response)