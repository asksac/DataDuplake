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
