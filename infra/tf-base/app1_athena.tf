#
# Sets up an Athena database and named queries
#

# KMS key used to encrypt Athena db
resource "aws_kms_key" "athena_db_key" {
  deletion_window_in_days = 7
  description             = "${var.app_name} - Athena KMS Key"
}

resource "aws_athena_workgroup" "athena_wg" {
  name                    = "${var.app_shortcode}-primary"

  configuration {
    result_configuration {
      output_location     = "s3://${aws_s3_bucket.athena_output.id}/output/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.athena_db_key.arn
      }
    }
  }
}

resource "aws_athena_named_query" "customer_record_count" {
  name                    = "${var.app_shortcode}-customer-record-count"
  workgroup               = aws_athena_workgroup.athena_wg.id
  database                = aws_glue_catalog_database.s3_mdm_catalog_db.name # aws_athena_database.athena_db.name
  query                   = "SELECT COUNT(*) FROM customer;"
}