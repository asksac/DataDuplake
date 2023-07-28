# iam role for glue crawler

resource "aws_iam_role" "rds_glue_crawler_role" {
  name                    = "${var.app_shortcode}_rds_glue_crawler_role"
  assume_role_policy      = data.aws_iam_policy_document.rds_glue_crawler_assume_role_policy.json
}

data "aws_iam_policy_document" "rds_glue_crawler_assume_role_policy" {
  statement {
    actions               = ["sts:AssumeRole"]

    principals {
      type                = "Service"
      identifiers         = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "rds_glue_crawler_role_inline_policy" {
  name                    = "${var.app_shortcode}_rds_glue_crawler_inline_policy"
  description             = "Inline policy attached to Glue Crawler Role"
  policy                  = data.aws_iam_policy_document.rds_glue_crawler_role_inline_policy.json

}

data "aws_iam_policy_document" "rds_glue_crawler_role_inline_policy" {
  statement {
    actions = [
      "secretsmanager:*" 
    ]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "rds_glue_crawler_role_inline_policy_attachment" {
  role                    = aws_iam_role.rds_glue_crawler_role.name
  policy_arn              = aws_iam_policy.rds_glue_crawler_role_inline_policy.arn
}

data "aws_iam_policy" "rds_glue_crawler_AWSGlueServiceRole" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "rds_glue_crawler_role_managed_policy_attachment" {
  role                    = aws_iam_role.rds_glue_crawler_role.name
  policy_arn              = data.aws_iam_policy.rds_glue_crawler_AWSGlueServiceRole.arn
}


# -----

resource "aws_glue_catalog_database" "rds_mdm_catalog_db" {
  name                    = "${var.app_shortcode}-rds-mdm-catalog-db"
  description             = "${var.app_name} - RDS MDM Catalog"
}

resource "aws_glue_connection" "rds_glue_connection" {
  connection_properties   = {
    JDBC_CONNECTION_URL   = "jdbc:mysql://${aws_rds_cluster.aurora_serverless_v1.endpoint}:${aws_rds_cluster.aurora_serverless_v1.port}/${var.db_name}"
    SECRET_ID             = aws_secretsmanager_secret.key_secret.name
  }

  name                    = "${var.app_shortcode}-mdm-rds-connection"

  physical_connection_requirements {
    availability_zone      = data.aws_subnet.db_subnet[0].availability_zone
    subnet_id              = data.aws_subnet.db_subnet[0].id
    security_group_id_list = [ aws_security_group.db_sg.id ]
  }
}

resource "aws_glue_crawler" "rds_mdm_glue_crawler" {
  database_name           = aws_glue_catalog_database.rds_mdm_catalog_db.name
  name                    = "${var.app_shortcode}-rds-mdm-crawler"
  description             = "${var.app_name} - RDS MDM Crawler"

  role                    = aws_iam_role.rds_glue_crawler_role.arn

  jdbc_target {
    connection_name       = aws_glue_connection.rds_glue_connection.name
    path                  = "${var.db_name}/%"
  }  
}
