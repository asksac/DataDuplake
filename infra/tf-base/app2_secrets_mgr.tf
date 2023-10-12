
resource "aws_secretsmanager_secret" "key_secret" {
  name                    = "${var.app_shortcode}/rds/aurora-sl-mysql/master-${formatdate("YYYYMMDD", timestamp())}"
}

resource "aws_secretsmanager_secret_policy" "key_secret_policy" {
  secret_arn              = aws_secretsmanager_secret.key_secret.arn

  policy = jsonencode({
    Version               = "2012-10-17"
    Statement             = [
      {
        Sid               = "EnableGetSecretAccess"
        Effect            = "Allow"
        Principal         = {
          AWS             = aws_iam_role.glue_role.arn
        }
        Action            = "secretsmanager:GetSecretValue"
        Resource          = [ aws_secretsmanager_secret.key_secret.arn ]
      }
    ]
  })

}

resource "aws_secretsmanager_secret_version" "key_secret_data" {
  secret_id               = aws_secretsmanager_secret.key_secret.arn
  secret_string           = jsonencode({
    username    = var.app2_db_master_user
    password    = random_password.rds_master_password.result
  })
}
