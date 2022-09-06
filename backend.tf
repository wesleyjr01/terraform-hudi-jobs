terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  backend "s3" {
    bucket = "tfstate-cde-wesley"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}
