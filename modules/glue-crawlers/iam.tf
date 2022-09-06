resource "aws_iam_role" "glue_crawlers_role" {
  name = "glue-crawlers-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
    ]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"]

  inline_policy {
    name = "acess_s3_bucket_policy"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "s3:GetObject",
            "s3:List*",
            "s3:PutObject"
          ]
          Effect = "Allow"
          Resource = [
            "${var.raw_bucket_arn}*",
            "${var.processed_bucket_arn}*",
          ]
        }
      ]
    })
  }

  # include this one if you use KMS for encryption at s3
  #   inline_policy {
  #     name = "GlueCrawler-ReadKmsAccess"

  #     policy = jsonencode({
  #       Version = "2012-10-17"
  #       Statement = [
  #         {
  #           Action = [
  #             "kms:*"
  #           ]
  #           Effect   = "Allow"
  #           Resource = var.kms_keys_arns
  #         }
  #       ]
  #     })
  #   }
}
