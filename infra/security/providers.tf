locals {
  default_tags = {
    Project   = "aws-security-guardrails"
    Stack     = "security"
    ManagedBy = "terraform"
  }
}

# runs with security account credentials, which only need to find the organization and their own account
provider "aws" {
  alias  = "start"
  region = var.region

  default_tags {
    tags = local.default_tags
  }
}

data "aws_organizations_organization" "lookup" {
  provider = aws.start

  return_organization_only = true
}

data "aws_caller_identity" "start" {
  provider = aws.start
}

# the organization role is the one principal the scps let change config and the security services
provider "aws" {
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${data.aws_organizations_organization.lookup.master_account_id}:role/${var.management_role}"
    session_name = "terraform-security"
  }

  assume_role {
    role_arn     = "arn:aws:iam::${data.aws_caller_identity.start.account_id}:role/${var.member_role}"
    session_name = "terraform-security"
  }

  default_tags {
    tags = local.default_tags
  }
}
