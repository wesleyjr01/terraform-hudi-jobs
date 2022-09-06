provider "aws" {
  region = var.aws_region
  alias  = "main"
}

module "s3_main" {
  # https://github.com/terraform-aws-modules/terraform-aws-s3-bucket
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.2.3"
  count   = length(var.bucket_names)

  providers = { aws = aws.main }

  # bucket input is the name of the bucket
  bucket = var.bucket_names[count.index]

  # Controls if S3 bucket should have bucket policy attached (set to true to use value of policy as bucket policy)
  # We are desabling policies on first version of Data Lake.
  attach_policy = false

  # block_public_acls has a default value as false. However a Data Lake must not be public ever
  # So this configuration is hardcoded here and is not possible to parametrize another value
  block_public_acls = true

  # block_public_policy has a default value as false. However a Data Lake must not be public ever
  # So this configuration is hardcoded here and is not possible to parametrize another value
  block_public_policy = true

  # ignore_public_acls has a default value as false. However a Data Lake must not be public ever
  # So this configuration is hardcoded here and is not possible to parametrize another value
  ignore_public_acls = true

  # restrict_public_buckets has a default value as false. However a Data Lake must not be public ever
  # So this configuration is hardcoded here and is not possible to parametrize another value
  restrict_public_buckets = true

  server_side_encryption_configuration = { rule = { apply_server_side_encryption_by_default = { sse_algorithm = "AES256" } } }

  versioning = {
    enabled = false
  }
}
