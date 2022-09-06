variable "processed_etl_metadata" {
  type = map(object({
    duplicate_ranking_column  = string
    primary_key_column        = string
    catalog_source_database   = string
    catalog_source_table      = string
    catalog_source_datasource = string
    worker_count              = number
  }))
}

variable "bucket_names" {
  description = "The list of Data Lake Storage Bucket Names"
  type        = list(string)
}

variable "raw_bucket_arn" {
  type        = string
  description = "The s3 bucket containing raw staging data"
}

variable "processed_bucket_arn" {
  type        = string
  description = "The s3 bucket containing processed data"
}

variable "environment" {
  description = "The environment name"
  type        = string
}
