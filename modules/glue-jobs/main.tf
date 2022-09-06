resource "aws_cloudwatch_log_group" "glue_jobs_log_group" {
  name              = "${var.environment}_glue_jobs_log_group"
  retention_in_days = 14
}

locals {
  glue_job_default_arguments = {
    # ... potentially other arguments ...
    "--job-language"                     = "python"
    "--continuous-log-logGroup"          = aws_cloudwatch_log_group.glue_jobs_log_group.name
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-spark-ui"                  = "true"
    "--enable-metrics"                   = ""
    "--spark-event-logs-path"            = "s3://${aws_s3_bucket.glue_jobs_logs.bucket}/"
    "--enable-glue-datacatalog"          = "true"
    "--enable-job-insights"              = "true"
  }
}

resource "aws_glue_job" "raw_to_processed_upsert_hudi_job" {
  for_each = var.processed_etl_metadata

  name              = "raw-to-processed-job-${each.key}"
  role_arn          = aws_iam_role.glue_jobs_role.arn
  glue_version      = "3.0"
  max_retries       = 0
  timeout           = 480
  worker_type       = "G.1X"
  number_of_workers = var.environment == "prod" ? each.value.worker_count : 2

  command {
    script_location = "s3://${aws_s3_object.raw_to_processed_etl.bucket}/${aws_s3_object.raw_to_processed_etl.key}"
  }

  connections = ["Apache Hudi Connector 0.10.1 for AWS Glue 3.0"]

  default_arguments = merge(
    local.glue_job_default_arguments,
    {
      # "--job-bookmark-option"       = "job-bookmark-enable",
      "--job-bookmark-option"       = "job-bookmark-disable",
      "--target_bucket_name"        = var.bucket_names[1] # processed bucket
      "--duplicate_ranking_column"  = each.value.duplicate_ranking_column
      "--primary_key"               = each.value.primary_key_column
      "--catalog_source_database"   = each.value.catalog_source_database
      "--catalog_source_table"      = each.value.catalog_source_table
      "--catalog_source_datasource" = each.value.catalog_source_datasource
      #   "--catalog_target_database"   = var.glue_catalog_processed_db
      #This is needed for Spark SQL to deserialize JSON. See https://docs.aws.amazon.com/en_en/glue/latest/dg/aws-glue-programming-etl-glue-data-catalog-hive.html
      "--extra-jars" = "s3://crawler-public/json/serde/json-serde.jar"
    }
  )
}
