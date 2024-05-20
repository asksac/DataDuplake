locals {
  lambdas = [
    {
      name = "copy-gcs-to-s3"
      handler = "main.lambda_handler"
      runtime = "python3.9"
      code_dir = "apps/copy-gcs-to-s3"
    },
  ]
}

resource "aws_cloudwatch_log_group" "copy_gcs_s3_log_group" {
  name              = "/aws/lambda/copy-gcs-to-s3"
  retention_in_days = 90
}

resource "null_resource" "copy_gcs_s3_pip_install" {
  triggers = {
    shell_hash      = "${sha256(file("${path.module}/../../apps/copy-gcs-to-s3/requirements.txt"))}"
  }

  provisioner "local-exec" {
    command         = "python3 -m pip install --platform manylinux2014_x86_64 --only-binary=:all: -r ${path.module}/../../apps/copy-gcs-to-s3/requirements.txt -t ${path.module}/../../apps/copy-gcs-to-s3/lib"
  }
}

data "archive_file" "copy_gcs_s3_archive" {
  type              = "zip"
  excludes          = ["**/*.md", "**/*.txt"]
  source_dir        = "${path.module}/../../apps/copy-gcs-to-s3"
  output_path       = "${path.module}/../../apps/copy-gcs-to-s3.zip"
  depends_on        = [ null_resource.copy_gcs_s3_pip_install ]
}

resource "aws_lambda_function" "copy_gcs_s3_lambda" {
  function_name     = "copy-gcs-to-s3"

  handler           = "main.lambda_handler"
  role              = aws_iam_role.lambda_exec_role.arn
  runtime           = "python3.11"
  memory_size       = 1024 # 1 GB 
  timeout           = 900 # 15 mins

  filename          = data.archive_file.copy_gcs_s3_archive.output_path
  source_code_hash  = data.archive_file.copy_gcs_s3_archive.output_base64sha256

  environment {
    variables       = {
      LOG_LEVEL     = "INFO"
      GOOGLE_CREDENTIALS_SECRETS_MGR_ID = aws_secretsmanager_secret.gcp_secret.arn
    }
  }

  tags             = local.common_tags
}

resource "aws_lambda_alias" "copy_gcs_s3_latest" {
  name             = "copy-gcs-to-s3-latest"
  description      = "Alias for latest Lambda version"
  function_name    = aws_lambda_function.copy_gcs_s3_lambda.function_name
  function_version = "$LATEST"
}


resource "aws_iam_role" "lambda_exec_role" {
  name                = "${var.app_shortcode}_Lambda_Exec_Role"
  assume_role_policy  = <<EOF
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
  name        = "${var.app_shortcode}_Lambda_Policy"
  path        = "/"
  description = "IAM policy with minimum permissions for Lambda functions"

  policy = <<EOF
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
        "s3:*"
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
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


