
locals {
  customer_data_file      = "${path.module}/../../data/synth/mdm/customer/customer.csv"
}


# customer file
resource "aws_s3_object" "upload_customer_data" {
  bucket                  = aws_s3_bucket.data_files.id
  key                     = "data/synth/mdm/customer/customer.csv"
  source                  = local.customer_data_file
  source_hash             = filemd5(local.customer_data_file)
}
