## Secret Manager

resource "aws_secretsmanager_secret" "bq_secret" {
  name                    = "${var.app_shortcode}/glue/bigquery/credentials-${formatdate("YYYYMMDD", timestamp())}"
}

resource "aws_secretsmanager_secret_policy" "bq_secret_policy" {
  secret_arn              = aws_secretsmanager_secret.bq_secret.arn

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
        Resource          = [ aws_secretsmanager_secret.bq_secret.arn ]
      }
    ]
  })

}

resource "aws_secretsmanager_secret_version" "bq_secret_data" {
  secret_id               = aws_secretsmanager_secret.bq_secret.arn
  secret_string           = jsonencode({"credentials": filebase64("${path.module}/bg-connector/bigquery.json")})
}

## Glue Custom Connector

resource "aws_glue_connection" "bq_custom_connector" {
  connection_type         = "CUSTOM"

  connection_properties = {
    CONNECTOR_TYPE        = "Spark",
    CONNECTOR_CLASS_NAME  = "bigquery"
    CONNECTOR_URL         = "s3://${var.hub_glue_assets_bucket}/jars/spark-3.3-bigquery-0.32.2.jar",
  }

  name                    = "custom-spark-3.3-bigquery-0.32.2"
  description             = "Apache Spark Connector to access Google BigQuery tables"
  match_criteria          = ["template-connection"]
}

# Make sure the VPC has Nat Gateway attched and routed defined
# Glue Connection ENIs only have Private IPs and cannot access
# Internet endpoints without a NAT Gateway
resource "aws_glue_connection" "bq_connection" {
  connection_type         = "CUSTOM"

  connection_properties = {
    CONNECTOR_TYPE        = "Spark",
    SECRET_ID             = aws_secretsmanager_secret.bq_secret.name,
    CONNECTOR_URL         = "s3://${var.hub_glue_assets_bucket}/jars/spark-3.3-bigquery-0.32.2.jar",
    CONNECTOR_CLASS_NAME  = "bigquery"
  }

  physical_connection_requirements {
    availability_zone      = data.aws_subnet.app2_subnet[0].availability_zone
    subnet_id              = data.aws_subnet.app2_subnet[0].id
    security_group_id_list = [ aws_security_group.app2_sg.id ]
  }

  name                    = "My_BQ_Connection"
  description             = "Connection to Google BigQuery via VPC"
  match_criteria          = ["Connection", aws_glue_connection.bq_custom_connector.name]
}

# BigQuery Connection not associated with VPC
# Useful for testing jobs
resource "aws_glue_connection" "bq_connection_open" {
  connection_type         = "CUSTOM"

  connection_properties = {
    CONNECTOR_TYPE        = "Spark",
    SECRET_ID             = aws_secretsmanager_secret.bq_secret.name,
    CONNECTOR_URL         = "s3://${var.hub_glue_assets_bucket}/jars/spark-3.3-bigquery-0.32.2.jar",
    CONNECTOR_CLASS_NAME  = "bigquery"
  }

  name                    = "My_BQ_Connection_Open"
  description             = "Connection to Google BigQuery via Internet"
  match_criteria          = ["Connection", aws_glue_connection.bq_custom_connector.name]
}
