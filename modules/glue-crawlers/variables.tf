variable "raw_bucket_arn" {
  type        = string
  description = "ARN of the Data Lake Raw Bucket."
}

variable "processed_bucket_arn" {
  type        = string
  description = "ARN of the Data Lake processed Bucket."
}

variable "bucket_names" {
  description = "The list of Data Lake Storage Bucket Names"
  type        = list(string)
}

variable "personality_ratings_raw_db" {
  description = "Name of the glue catalog database with all tables from Personality Ratings data, on Raw Layer."
  type        = string
}
