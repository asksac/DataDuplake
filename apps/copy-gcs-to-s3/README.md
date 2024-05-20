# File transfer from GCP Storage to AWS S3

This module provides code to run within AWS Lambda to support transferring of objects/files
from GCP Storage (GCS) to AWS S3. Following features are currently supported: 

1. Ability to run/test code locally before deploying in AWS Lambda
2. Support for full or chunked file transfer
3. Support for single threaded or multi-threaded operation
4. Support for optionally enabling checksum validation for S3 uploads

# How to Execute Code

## Executing code locally

### To get help with parameters
```shell
python main.py --help
```

## To transfer a file (single threaded, default chunk size, no checksum validation)
```shell
python main.py -s gs://[source-bucket]/[source-object-name] -t s3://[target-bucket]/[target-object-name]
```

## Executing via AWS Lambda 

Invoke Lambda from CLI: 
```shell
aws lambda invoke --function-name copy-gcs-to-s3 --invocation-type RequestResponse --cli-binary-format raw-in-base64-out --payload '{"source_object_uri": "gs://[source-bucket]/[source-object-name]", "target_object_uri": "s3://[target-bucket]/[target-object-name]", "checksum": "true"}' /tmp/copy-gcs-to-s3-response.log && cat /tmp/copy-gcs-to-s3-response.log
```

Invoke Lambda and retrieve logs: 
```shell
aws lambda invoke --function-name copy-gcs-to-s3 --invocation-type RequestResponse --cli-binary-format raw-in-base64-out --payload '{"source_object_uri": "gs://[source-bucket]/[source-object-name]", "target_object_uri": "s3://[target-bucket]/[target-object-name]", "checksum": "true"}' /tmp/copy-gcs-to-s3-response.log --log-type Tail --query 'LogResult' --output text |  base64 -d
```

# Limitations

This module currently does not support: 
- Transferring object meta data
- Support for other checksum algorithms (e.g. SHA1, SHA256)

