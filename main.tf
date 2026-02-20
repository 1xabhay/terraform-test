terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "smoke" {
  bucket_prefix = "tf-8020-smoke-"
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  value = data.aws_caller_identity.current.arn
}

output "bucket_name" {
  value = aws_s3_bucket.smoke.bucket
}
