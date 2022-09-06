locals {
  glue_crawler_default_configuration = jsonencode(
    {
      CrawlerOutput = {
        # partitions inherit metadata properties from their parent table
        Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
        # New columns are added as they are encountered, including nested data types. But existing columns are not removed
        Tables = { AddOrUpdateBehavior = "MergeNewColumns" }
      }
      Version = 1
    }
  )

  schedule_cron = "cron(35 7 * * ? *)"

  raw_bucket_name       = var.bucket_names[0]
  processed_bucket_name = var.bucket_names[1]
}

resource "aws_glue_crawler" "crawler_personality_ratings_raw_db" {
  database_name = var.personality_ratings_raw_db
  #   schedule      = local.schedule_cron # currently triggering manually
  name = "/crawler/db/${var.personality_ratings_raw_db}"
  role = aws_iam_role.glue_crawlers_role.arn
  tags = {
    context = "Crawl all data from database ${var.personality_ratings_raw_db} on raw bucket"
    # environment = var.environment
  }

  configuration = local.glue_crawler_default_configuration

  s3_target {
    path        = "s3://${local.raw_bucket_name}/personality_ratings/"
    sample_size = 249 # remove this line if you want to crawl all files
  }
}
