# Overview

This module implements infrastructure to enable data transfers from GCP Storage to AWS S3. 
Specifically, it deploys the AWS Lambda function (`copy-gcs-to-s3`). 

# Installation

## First time running Terraform

```shell
terraform init
```

## Deploy AWS Lambda function and associated dependencies

Configure terraform.tfvars file, and run: 

```shell
terraform apply
```

