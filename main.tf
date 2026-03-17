# aws provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# variables
variable "aws_region" {
  default = "us-east-1"
}

# locals
locals {
  s3_frontend_name = "chatlab-client"
}

# Configure the AWS provider
provider "aws" {
  region = var.aws_region
}

# frontend s3 bucket
resource "aws_s3_bucket" "webpage" {
  bucket_prefix = local.s3_frontend_name
}

resource "aws_s3_bucket_public_access_block" "webpage" {
  bucket = aws_s3_bucket.webpage.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "webpage" {
  bucket = aws_s3_bucket.webpage.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "webpage" {
  depends_on = [aws_s3_bucket_ownership_controls.webpage, aws_s3_bucket_public_access_block.webpage]
  bucket     = aws_s3_bucket.webpage.id
  acl        = "private"
}

resource "aws_s3_bucket_website_configuration" "webpage" {
  bucket = aws_s3_bucket.webpage.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }

}

# outputs
output "bucket_name" {
  value = aws_s3_bucket.webpage.bucket
}
