terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67"
    }
  }
}

variable "manage_ebs_default_encryption" {
  type    = bool
  default = true
}

# security hub IAM.7, IAM.15, IAM.16, IAM.17; nobody uses IAM users here, so this guards the day someone creates one
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
}

# security hub S3.1: a bucket can't become public in this account, whatever its own settings say
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# security hub EC2.7
resource "aws_ebs_encryption_by_default" "this" {
  count = var.manage_ebs_default_encryption ? 1 : 0

  enabled = true
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# security hub SSM.7: ssm documents can't be shared publicly from this account
resource "aws_ssm_service_setting" "document_public_sharing" {
  setting_id    = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:servicesetting/ssm/documents/console/public-sharing-permission"
  setting_value = "Disable"
}
