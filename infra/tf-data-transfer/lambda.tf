locals {
  lambda                    = {
    name                    = "copy-gcs-to-s3"
    handler                 = "main.lambda_handler"
    runtime                 = "python3.9"
    code_dir                = "${path.module}/../../apps/copy-gcs-to-s3"
  }

  python_version            = "3.9"

  gcp_proxy                 = "${aws_vpc_endpoint.proxy_endpoint.dns_entry[0].dns_name}:${var.proxy_listen_port}"
}

resource "aws_cloudwatch_log_group" "copy_gcs_s3_log_group" {
  name                      = "/aws/lambda/${local.lambda.name}"
  retention_in_days         = 90
}

resource "null_resource" "copy_gcs_s3_pip_install" {
  triggers = {
    shell_hash              = "${sha256(file("${local.lambda.code_dir}/requirements.txt"))}"
  }

  provisioner "local-exec" {
    command                 = "python3 -m pip install --platform manylinux2014_x86_64 --only-binary=:all: --python-version ${local.python_version} -r ${local.lambda.code_dir}/requirements.txt -t ${local.lambda.code_dir}/lib"
  }
}

data "archive_file" "copy_gcs_s3_archive" {
  type                      = "zip"
  excludes                  = ["**/*.md", "**/*.txt"]
  source_dir                = "${local.lambda.code_dir}"
  output_path               = "${local.lambda.code_dir}.zip"
  depends_on                = [ null_resource.copy_gcs_s3_pip_install ]
}

resource "aws_lambda_function" "copy_gcs_s3_lambda" {
  function_name             = local.lambda.name

  handler                   = local.lambda.handler
  role                      = aws_iam_role.lambda_exec_role.arn
  runtime                   = local.lambda.runtime
  memory_size               = 1769 # at 1769 memory we get 1 vCPU 
  timeout                   = 900 # 15 mins (max value)

  vpc_config {
    subnet_ids              = var.lambda_subnet_ids
    security_group_ids      = [ var.lambda_security_group_id ] 
  }

  filename                  = data.archive_file.copy_gcs_s3_archive.output_path
  source_code_hash          = data.archive_file.copy_gcs_s3_archive.output_base64sha256

  environment {
    variables               = {
      #GCP_CREDENTIALS_FILE = "keyfile.json"
      GCP_CREDENTIALS_SECRET_ID = aws_secretsmanager_secret.gcp_secret.arn
      GCP_PROXY             = local.gcp_proxy
      LOG_LEVEL             = "INFO"
      TZ                    = "US/Eastern"
    }
  }

  tags                      = local.common_tags
}

resource "aws_lambda_alias" "copy_gcs_s3_latest" {
  name                      = "${local.lambda.name}-latest"
  description               = "Alias for latest Lambda version"
  function_name             = aws_lambda_function.copy_gcs_s3_lambda.function_name
  function_version          = "$LATEST"
}


resource "aws_iam_role" "lambda_exec_role" {
  name                      = "${var.app_shortcode}_Lambda_Exec_Role"
  assume_role_policy        = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
      "Action": [
        "sts:AssumeRole"
      ],
      "Principal": {
          "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": "LambdaAssumeRolePolicy"
      }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_policy" {
  name                      = "${var.app_shortcode}_Lambda_Policy"
  path                      = "/"
  description               = "IAM policy with minimum permissions for Lambda functions"

  policy                    = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:*:*:log-group:/aws/lambda/*", 
        "arn:aws:logs:*:*:log-group:/aws/lambda/*:*"
      ],
      "Effect": "Allow"
    }, 
    {
      "Action": [
        "secretsmanager:GetSecretValue",
        "s3:GetObject*", 
        "s3:PutObject*", 
        "kms:GenerateDataKey",
        "kms:Encrypt",
        "kms:Decrypt"
      ],
      "Resource": [
        "*"
      ], 
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_exec_policy" {
  role                      = aws_iam_role.lambda_exec_role.name
  policy_arn                = aws_iam_policy.lambda_policy.arn
}

data "aws_iam_policy" "AWSLambdaVPCAccessExecutionRole" {
  name                      = "AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_exec_vpc_policy" {
  role                      = aws_iam_role.lambda_exec_role.name
  policy_arn                = data.aws_iam_policy.AWSLambdaVPCAccessExecutionRole.arn
}
