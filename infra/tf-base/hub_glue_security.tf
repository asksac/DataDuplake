## Glue Execution Role (for Jobs/Crawlers)

resource "aws_iam_role" "glue_role" {
  name                    = "${var.app_shortcode}_glue_role"
  assume_role_policy      = data.aws_iam_policy_document.glue_assume_role_policy.json
}

data "aws_iam_policy_document" "glue_assume_role_policy" {
  statement {
    actions               = ["sts:AssumeRole"]

    principals {
      type                = "Service"
      identifiers         = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "glue_role_inline_policy" {
  name                    = "${var.app_shortcode}_glue_inline_policy"
  description             = "Inline policy attached to Glue Role"
  policy                  = data.aws_iam_policy_document.glue_role_inline_policy.json

}

data "aws_iam_policy_document" "glue_role_inline_policy" {
  # permission to glue jobs/crawlers to write to cloudwatch logs with encryption 
  statement {
    effect                = "Allow"
    actions               = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources             = ["*"]
  }

  statement {
    effect                = "Allow"
    actions               = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams", 
      "logs:AssociateKmsKey", # needed for glue continuous logging with security configuration
      #"logs:*"
    ]
    resources             = ["arn:aws:logs:*:*:*"]
  }

  statement {
    actions               = [
      "s3:GetBucketLocation", 
      "s3:ListBucket", 
      "s3:ListAllMyBuckets", 
      "s3:GetBucketAcl", 
      "s3:GetObject*", 
      "s3:PutObject*"
    ]
    resources             = [
      aws_s3_bucket.data_files.arn,
      "${aws_s3_bucket.data_files.arn}/*"
    ]
  }

  statement {
    actions               = [
      "secretsmanager:*" 
    ]
    resources             = [
      "*"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "glue_role_inline_policy_attachment" {
  role                    = aws_iam_role.glue_role.name
  policy_arn              = aws_iam_policy.glue_role_inline_policy.arn
}

data "aws_iam_policy" "AWSGlueServiceRole" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_managed_policy_attachment" {
  role                    = aws_iam_role.glue_role.name
  policy_arn              = data.aws_iam_policy.AWSGlueServiceRole.arn
}

## Glue Security Configuration

resource "aws_glue_security_configuration" "default" {
  name                    = "${var.app_shortcode}-default"

  encryption_configuration {
    cloudwatch_encryption {
      cloudwatch_encryption_mode = "SSE-KMS"
      kms_key_arn         = aws_kms_key.cw_logs_key.arn
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "DISABLED"
    }

    s3_encryption {
      s3_encryption_mode  = "SSE-KMS"
      kms_key_arn         = aws_kms_key.s3_key.arn
    }
  }
}