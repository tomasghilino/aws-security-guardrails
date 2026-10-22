locals {
  config_bucket = "sgr-config-${local.account_ids["security"]}"
}

module "config_management" {
  source    = "../modules/config-recorder"
  providers = { aws = aws.management }

  bucket_name = local.config_bucket
}

module "config_security" {
  source    = "../modules/config-recorder"
  providers = { aws = aws.security }

  bucket_name = local.config_bucket
}

module "config_segp" {
  source    = "../modules/config-recorder"
  providers = { aws = aws.segp }

  bucket_name = local.config_bucket
}

module "config_jsp" {
  source    = "../modules/config-recorder"
  providers = { aws = aws.jsp }

  bucket_name = local.config_bucket
}

# aws creates these roles in member accounts, but not in the management account when a delegated admin deploys to the organization
resource "aws_iam_service_linked_role" "config_multiaccount_management" {
  provider = aws.management

  aws_service_name = "config-multiaccountsetup.amazonaws.com"
}

resource "aws_iam_service_linked_role" "access_analyzer_management" {
  provider = aws.management

  aws_service_name = "access-analyzer.amazonaws.com"
}

module "hardening_management" {
  source    = "../modules/account-hardening"
  providers = { aws = aws.management }
}

module "hardening_security" {
  source    = "../modules/account-hardening"
  providers = { aws = aws.security }
}

module "hardening_segp" {
  source    = "../modules/account-hardening"
  providers = { aws = aws.segp }

  # project 2's shared stack already owns this setting in segp
  manage_ebs_default_encryption = false
}

module "hardening_jsp" {
  source    = "../modules/account-hardening"
  providers = { aws = aws.jsp }
}
