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

# vpc configuration
resource "aws_vpc" "chatlab_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  tags = {
    Name = "chatlab-vpc"
  }
}

# 2 public subnets and 2 private subnets across 2 availability zones
variable "public_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}
variable "private_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}
variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.chatlab_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "chatlab-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.chatlab_vpc.id
  cidr_block              = element(var.private_subnet_cidrs, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false
  tags = {
    Name = "chatlab-private-subnet-${count.index + 1}"
  }
}
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.chatlab_vpc.id
  tags = {
    Name = "chatlab-igw"
  }
}
resource "aws_route_table" "secondary_route_table" {
  vpc_id = aws_vpc.chatlab_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "chatlab-public-rt"
  }

}
resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.secondary_route_table.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  depends_on = [aws_internet_gateway.gw]

  tags = {
    Name = "chatlab-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.gw]

  tags = {
    Name = "chatlab-nat"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.chatlab_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "chatlab-private-rt"
  }
}

resource "aws_route_table_association" "private_subnet_association" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = element(aws_subnet.private[*].id, count.index)
  route_table_id = aws_route_table.private_route_table.id
}

# s3 bucket for beanstalk application versions
resource "aws_s3_bucket" "beanstalk_app_versions" {
  bucket = "${aws_elastic_beanstalk_application.chatlab.name}-app-versions"
  tags = {
    Purpose = "beanstalk-deployments"
  }
}

data "aws_caller_identity" "current" {}

# upload the application zip
resource "aws_s3_object" "app_version_zip" {
  bucket = aws_s3_bucket.beanstalk_app_versions.id
  key    = "versions/v1.0.0.zip"
  source = "chatlab-app-version.zip"
  etag   = filemd5("chatlab-app-version.zip")
}

# register application version
resource "aws_elastic_beanstalk_application_version" "v1" {
  name        = "v1.0.0"
  application = aws_elastic_beanstalk_application.chatlab.name
  description = "Application version 1.0.0"
  bucket      = aws_s3_bucket.beanstalk_app_versions.id
  key         = aws_s3_object.app_version_zip.key
}

# beanstalk environment
resource "aws_elastic_beanstalk_environment" "production" {
  name                = "production"
  application         = aws_elastic_beanstalk_application.chatlab.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.11.0 running Docker"
  version_label       = aws_elastic_beanstalk_application_version.v1.name

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
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.beanstalk_service_role.arn
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

  # vpc configuration
  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.chatlab_vpc.id
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     = "false"
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBScheme"
    value     = "public"
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", aws_subnet.private[*].id)
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", aws_subnet.public[*].id)

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
    name      = "Surveillance"
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
