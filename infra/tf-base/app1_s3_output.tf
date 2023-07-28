# create S3 bucket for Athena query output

resource "aws_s3_bucket" "athena_output" {
  bucket                  = "${var.app_shortcode}-${local.account_id}-athena-output"
  force_destroy           = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_output_config" {
  bucket                  = aws_s3_bucket.athena_output.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm       = "aws:kms"
    }
  }
}

data "aws_iam_policy_document" "athena_output_bucket_policy" {
  statement {
    actions               = [ "s3:GetObject", "s3:PutObject", "s3:DeleteObject" ]
    resources             = [ "${aws_s3_bucket.athena_output.arn}/*" ]

    principals {
      type                = "AWS"
      identifiers         = [ local.account_id ]
    }
  }

  statement {
    actions               = [ "s3:ListBucket" ]
    resources             = [ aws_s3_bucket.athena_output.arn ]

    principals {
      type                = "AWS"
      identifiers         = [ local.account_id ]
    }
  }
}

resource "aws_s3_bucket_policy" "athena_output" {
  bucket                  = aws_s3_bucket.athena_output.id
  policy                  = data.aws_iam_policy_document.athena_output_bucket_policy.json 
}
