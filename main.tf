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
# TODO update for loading hlc frontend files
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.webpage.id
  key          = "index.html"
  source       = "index.html"
  etag         = filemd5("index.html")
  content_type = "text/html; charset=utf-8"
}

# elastic beanstalk

# iam service role
resource "aws_iam_role" "beanstalk_service_role" {
  name = "aws-elasticbeanstalk-service-role-terraform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "elasticbeanstalk.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# application top level container
resource "aws_elastic_beanstalk_application" "chatlab" {
  name        = "chatlab"
  description = "Chatlab application"

  appversion_lifecycle {
    service_role          = aws_iam_role.beanstalk_service_role.arn
    max_count             = 50
    delete_source_from_s3 = true
  }
}

resource "aws_iam_role_policy_attachment" "beanstalk_service_enhanced_health" {
  role       = aws_iam_role.beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "beanstalk_service_managed_updates" {
  role       = aws_iam_role.beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

# instance role for EC2 instances
resource "aws_iam_role" "beanstalk_ec2" {
  name = "aws-elasticbeanstalk-ec2-role-terraform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "beanstalk_ec2_web" {
  role       = aws_iam_role.beanstalk_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "beanstalk_ec2_docker" {
  role       = aws_iam_role.beanstalk_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_instance_profile" "beanstalk_ec2" {
  name = "elastic-beanstalk-ec2-profile"
  role = aws_iam_role.beanstalk_ec2.name
}

# beanstalk environment
resource "aws_elastic_beanstalk_environment" "production" {
  name                = "production"
  application         = aws_elastic_beanstalk_application.chatlab.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.11.0 running Docker"

  # settings
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.beanstalk_ec2.name
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t3.small"
  }

  # autoscaling configuration
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "2"
  }
  # scaling triggers
  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "MeasureName"
    value     = "CPUUtilization"
  }
  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "UpperThreshold"
    value     = "70"
  }
  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "LowerThreshold"
    value     = "30"
  }
  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "DeploymentPolicy"
    value     = "Rolling"
  }
  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "BatchSizeType"
    value     = "Percentage"
  }
  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "BatchSize"
    value     = "30"
  }

  # Enhanced health monitoring
  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "SystemType"
    value     = "enhanced"
  }
  # env var
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "Surveillance for Surveillance"
    value     = "WASSSAAAPPPP 6"
  }
}

# outputs
output "bucket_name" {
  value = aws_s3_bucket.webpage.bucket
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "environment_url" {
  description = "URL of the Elastic Beanstalk environment"
  value       = aws_elastic_beanstalk_environment.production.endpoint_url
}

output "environment_cname" {
  description = "CNAME of the Elastic Beanstalk environment"
  value       = aws_elastic_beanstalk_environment.production.cname
}

output "application_name" {
  description = "Name of the Elastic Beanstalk application"
  value       = aws_elastic_beanstalk_application.chatlab.name
}
