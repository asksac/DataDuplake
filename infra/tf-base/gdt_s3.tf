# create S3 bucket for data files

resource "aws_s3_bucket" "data_files" {
  bucket                  = "${var.app_shortcode}-${local.account_id}-data-files"
  force_destroy           = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_files_config" {
  bucket                  = aws_s3_bucket.data_files.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm       = "aws:kms"
    }
  }
}

data "aws_iam_policy_document" "data_files_bucket_policy" {
  statement {
    actions               = [ "s3:GetObject", "s3:PutObject", "s3:DeleteObject" ]
    resources             = [ "${aws_s3_bucket.data_files.arn}/*" ]

    principals {
      type                = "AWS"
      identifiers         = [ local.account_id ]
    }
  }

  statement {
    actions               = [ "s3:ListBucket" ]
    resources             = [ aws_s3_bucket.data_files.arn ]

    principals {
      type                = "AWS"
      identifiers         = [ local.account_id ]
    }
  }
}

resource "aws_s3_bucket_policy" "data_files" {
  bucket                  = aws_s3_bucket.data_files.id
  policy                  = data.aws_iam_policy_document.data_files_bucket_policy.json 
}
