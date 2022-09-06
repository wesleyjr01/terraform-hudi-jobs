output "main_buckets_arns" {
  value = module.s3_main.*.s3_bucket_arn
}
