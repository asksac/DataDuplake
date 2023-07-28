# iam role for glue crawler

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
  statement {
    actions = [
      "s3:GetBucketLocation", 
      "s3:ListBucket", 
      "s3:ListAllMyBuckets", 
      "s3:GetBucketAcl", 
      "s3:GetObject"
    ]
    resources = [
      aws_s3_bucket.data_files.arn,
      "${aws_s3_bucket.data_files.arn}/*"
    ]
  }

  statement {
    actions = [
      "secretsmanager:*" 
    ]
    resources = [
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

#
# glue data catalog and s3 crawler setup
#

resource "aws_glue_catalog_database" "s3_mdm_catalog_db" {
  name                    = "${var.app_shortcode}-s3-mdm-catalog-db"
  description             = "${var.app_name} - S3 MDM Catalog"
}

resource "aws_glue_crawler" "s3_mdm_glue_crawler" {
  database_name           = aws_glue_catalog_database.s3_mdm_catalog_db.name
  name                    = "${var.app_shortcode}-s3-mdm-crawler"
  description             = "${var.app_name} - S3 MDM Crawler"

  role                    = aws_iam_role.glue_role.arn

  configuration           = jsonencode(
      {
        Grouping = {
          TableGroupingPolicy = "CombineCompatibleSchemas"
          TableLevelConfiguration = 5
        }
        CrawlerOutput = {
          Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
        }
        Version = 1
      }
  )
    
  s3_target {
    path                  = "s3://${aws_s3_bucket.data_files.bucket}/data/synth/mdm"
  }
  
}
