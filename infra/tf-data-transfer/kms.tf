resource "aws_kms_key" "s3_key" {
  deletion_window_in_days = 7 # waiting period to purge key material after key is deleted
  description             = "${var.app_name} - S3 Bucket Encryption Key"

  policy                  = jsonencode({
    Version               = "2012-10-17"
    Statement             = [
      {
        Sid               = "AllowAccountAdminToManageKey"
        Principal         = {
          AWS             = "arn:aws:iam::${local.account_id}:root"
        }
        Action            = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ]
        Effect            = "Allow"
        Resource          = "*"
      },
      {
        Sid               = "AllowKeyUseForS3"
        Principal         = {
          AWS             = [
            "arn:aws:iam::${local.account_id}:root"
          ]
        }
        Action            = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*", 
        ]
        Effect            = "Allow"
        Resource          = "*"
      },
    ] 
  })
}
