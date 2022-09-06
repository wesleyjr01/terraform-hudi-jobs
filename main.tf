provider "aws" {
  region = var.aws_region
}

module "dl_storage_layer" {
  source = "./modules/s3-dl-storage/"

  bucket_names = var.bucket_names
  aws_region   = var.aws_region
}

module "glue_crawlers" {
  source = "./modules/glue-crawlers"

  bucket_names         = var.bucket_names
  raw_bucket_arn       = module.dl_storage_layer.main_buckets_arns[0]
  processed_bucket_arn = module.dl_storage_layer.main_buckets_arns[1]

  personality_ratings_raw_db = var.personality_ratings_raw_db
}

module "glue_jobs" {
  source = "./modules/glue-jobs"

  processed_etl_metadata = var.processed_etl_metadata

  bucket_names = var.bucket_names
  environment  = var.environment

  raw_bucket_arn       = module.dl_storage_layer.main_buckets_arns[0]
  processed_bucket_arn = module.dl_storage_layer.main_buckets_arns[1]

}
