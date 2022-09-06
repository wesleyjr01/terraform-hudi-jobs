# General
variable "aws_region" {
  type = string
}

variable "environment" {
  description = "The environment name"
  type        = string
}

variable "bucket_names" {
  description = "The list of Data Lake Storage Bucket Names"
  type        = list(string)
}

variable "personality_ratings_raw_db" {
  description = "Name of the glue catalog database with all tables from Personality Ratings data, on Raw Layer."
  type        = string
}

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
