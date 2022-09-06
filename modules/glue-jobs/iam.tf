resource "aws_iam_role" "glue_jobs_role" {
  name = "glue-jobs-role"
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
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" #needed for Apache Hudi Glue connector connection
  ]

  inline_policy {
    name = "DataLakePolicy-GlueEtl"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "s3:GetObject",
            "s3:ListBucket"
          ],
          Resource = [
            "${var.raw_bucket_arn}/*",
            "${var.processed_bucket_arn}/*",
            "${aws_s3_bucket.glue_jobs_scripts.arn}/*",
            "${aws_s3_bucket.glue_jobs_logs.arn}/*"
          ],
          Effect = "Allow"
        },
        {
          Action = [
            "s3:PutObject"
          ],
          Resource = [
            "${var.processed_bucket_arn}/*",
            "${aws_s3_bucket.glue_jobs_logs.arn}/*"
          ],
          Effect = "Allow"
        },
        {
          Action = [
            "s3:DeleteObject",
            "s3:DeleteObjectVersion"
          ],
          Resource = ["${var.processed_bucket_arn}/*"],
          Effect   = "Allow"
        },
        {
          "Action" : "lakeformation:GetDataAccess",
          "Effect" : "Allow",
          "Resource" : "*"
        }
      ]
    })
  }

  inline_policy {
    name = "DataLakePolicy-Cloudwatch-Logging"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "logs:CreateLogGroup"
          ]
          Effect   = "Allow"
          Resource = ["*"]
        },
        {
          Action = [
            "logs:PutLogEvents",
            "logs:CreateLogStream"
          ]
          Effect   = "Allow"
          Resource = "arn:aws:logs:*:*:*:${aws_cloudwatch_log_group.glue_jobs_log_group.name}*"
        }
      ]
    })
  }
}
