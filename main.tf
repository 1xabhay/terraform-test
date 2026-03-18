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

# cloud front distribution
resource "aws_cloudfront_origin_access_control" "current" {
  name                              = "${local.s3_frontend_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on          = [aws_s3_bucket.webpage]
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.webpage.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.webpage.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.current.id
  }
  comment = "Chatlab client distribution"
  enabled = true
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-${aws_s3_bucket.webpage.id}"
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

}

# bucket policy to allow cloudfront access
data "aws_iam_policy_document" "cloudfront" {
  statement {
    sid     = "AllowCloudFrontServicePrincipalReadOnly"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      aws_s3_bucket.webpage.arn,
      "${aws_s3_bucket.webpage.arn}/*"
    ]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.webpage.id
  policy = data.aws_iam_policy_document.cloudfront.json
}

# upload files to s3 bucket
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.webpage.id
  key          = "index.html"
  source       = "index.html"
  etag         = filemd5("index.html")
  content_type = "text/html; charset=utf-8"
}

# outputs
output "bucket_name" {
  value = aws_s3_bucket.webpage.bucket
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}
