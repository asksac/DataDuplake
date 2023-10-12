locals {
  covid_job_id            = "bq-to-s3-covid-data-01"
  covid_job_script        = "${path.module}/../../apps/glue-jobs/bq-s3-covid/main.py"
}

# upload Glue job script
resource "aws_s3_object" "upload_bq_to_s3_covid_job_script" {
  bucket                  = var.hub_glue_assets_bucket
  key                     = "glue-scripts/${local.covid_job_id}/main.py"
  source                  = local.covid_job_script
  source_hash             = filemd5(local.covid_job_script)
}


resource "aws_glue_job" "bq_to_s3_covid" {
  name                    = local.covid_job_id
  description             = "Copy Covid Data From BQ to S3"
  role_arn                = aws_iam_role.glue_role.arn

  glue_version            = "4.0"
  number_of_workers       = "2"
  worker_type             = "Standard"

  connections             = [ aws_glue_connection.bq_connection.name ]
  security_configuration  = aws_glue_security_configuration.default.name

  command {
    name                  = "glueetl"
    python_version        = "3"
    script_location       = "s3://${var.hub_glue_assets_bucket}/glue-scripts/${local.covid_job_id}/main.py"
  }

  default_arguments       = {
    # Job specific parameters
    "--GCP_PROJECT_NAME"                  = var.hub_gcp_project_id
    "--SRC_BQ_CONN_NAME"                  = aws_glue_connection.bq_connection.name
    "--TGT_S3_PATH"                       = "s3://${aws_s3_bucket.data_files.id}/jobs/${local.covid_job_id}/output/"

    # AWS Glue parameters 
    "--disable-proxy-v2"                  = "true"
    "--enable-spark-ui"                   = "true"
    "--enable-continuous-cloudwatch-log"  = "true"

    # default log group is /aws-glue/jobs/logs-v2/
    "--continuous-log-logGroup"           = "/aws-glue/jobs/logs-v2" 

    # if true, prunes out non-useful Spark driver/executor and Hadoop YARN heartbeat log messages
    "--enable-continuous-log-filter"      = "true"

    "--continuous-log-logStreamPrefix"    = "${var.app_shortcode}-"
    "--enable-metrics"                    = "true"
  }
}