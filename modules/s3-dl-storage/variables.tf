# General
variable "aws_region" {
  type = string
}

variable "bucket_names" {
  description = "The list of Data Lake Storage Bucket Names"
  type        = list(string)
}
