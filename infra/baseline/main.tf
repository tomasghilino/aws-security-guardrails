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

locals {
  security_bus_arn = "arn:aws:events:${var.region}:${local.account_ids["security"]}:event-bus/default"
}

module "forwarder_management" {
  source    = "../modules/event-forwarder"
  providers = { aws = aws.management }

  target_bus_arn = local.security_bus_arn
}

module "forwarder_segp" {
  source    = "../modules/event-forwarder"
  providers = { aws = aws.segp }

  target_bus_arn = local.security_bus_arn
}

module "forwarder_jsp" {
  source    = "../modules/event-forwarder"
  providers = { aws = aws.jsp }

  target_bus_arn = local.security_bus_arn
}

module "remediation_management" {
  source    = "../modules/remediation-roles"
  providers = { aws = aws.management }

  security_account_id    = local.account_ids["security"]
  organization_trail_arn = "arn:aws:cloudtrail:${var.region}:${data.aws_organizations_organization.lookup.master_account_id}:trail/sgr-org-trail"
}

module "remediation_security" {
  source    = "../modules/remediation-roles"
  providers = { aws = aws.security }

  security_account_id = local.account_ids["security"]
}

module "remediation_segp" {
  source    = "../modules/remediation-roles"
  providers = { aws = aws.segp }

  security_account_id = local.account_ids["security"]
}

module "remediation_jsp" {
  source    = "../modules/remediation-roles"
  providers = { aws = aws.jsp }

  security_account_id = local.account_ids["security"]
}

module "plan_role_security" {
  source    = "../modules/plan-role"
  providers = { aws = aws.security }

  management_account_id = data.aws_organizations_organization.lookup.master_account_id
}

module "plan_role_segp" {
  source    = "../modules/plan-role"
  providers = { aws = aws.segp }

  management_account_id = data.aws_organizations_organization.lookup.master_account_id
}

module "plan_role_jsp" {
  source    = "../modules/plan-role"
  providers = { aws = aws.jsp }

  management_account_id = data.aws_organizations_organization.lookup.master_account_id
}
