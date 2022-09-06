data "aws_caller_identity" "current" {}

# data "archive_file" "etl_library" {
#   type        = "zip"
#   source_dir  = "./jobs/src"
#   output_path = "./jobs/src/draft/draft.zip"
#   excludes    = ["draft/draft.zip", "curated", "processed"]
# }

locals {
  account_id = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket" "glue_jobs_scripts" {
  bucket = "glue-jobs-scripts-draft-${var.environment}"
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    environment = var.environment
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = aws_s3_bucket.glue_jobs_scripts.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "block_access_glue_jobs_scripts_bucket" {
  bucket = aws_s3_bucket.glue_jobs_scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "glue_jobs_logs" {
  bucket = "glue-jobs-logs-draft-${var.environment}"
  acl    = "private"

  versioning {
    enabled = false
  }

  lifecycle_rule {
    id      = "remove-all-logs-after-7-days"
    enabled = true

    expiration {
      days = 7
    }
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "block_access_glue_jobs_logs_bucket" {
  bucket = aws_s3_bucket.glue_jobs_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "raw_to_processed_etl" {
  bucket = aws_s3_bucket.glue_jobs_scripts.bucket
  key    = "processed/raw_to_processed_hudi_job.py"
  source = "./jobs/src/processed/raw_to_processed_hudi_job.py"
  etag   = filemd5("./jobs/src/processed/raw_to_processed_hudi_job.py")
}
