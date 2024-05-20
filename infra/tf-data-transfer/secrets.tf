## Secret Manager

resource "aws_secretsmanager_secret" "gcp_secret" {
  name                    = "${var.app_shortcode}/gcp/credentials/${var.gcp_project_id}"

  lifecycle {
    ignore_changes        = [name]
  }
}

resource "aws_secretsmanager_secret_policy" "gcp_secret_policy" {
  secret_arn              = aws_secretsmanager_secret.gcp_secret.arn

  policy = jsonencode({
    Version               = "2012-10-17"
    Statement             = [
      {
        Sid               = "EnableGetSecretAccess"
        Effect            = "Allow"
        Principal         = {
          AWS             = local.account_id
        }
        Action            = "secretsmanager:GetSecretValue"
        Resource          = [ aws_secretsmanager_secret.gcp_secret.arn ]
      }
    ]
  })

}

resource "aws_secretsmanager_secret_version" "gcp_secret_data" {
  secret_id               = aws_secretsmanager_secret.gcp_secret.arn
  secret_string           = jsonencode({"credentials": filebase64("${path.module}/${var.gcp_access_keyfile}")})
}

