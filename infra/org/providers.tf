locals {
  default_tags = {
    Project   = "aws-security-guardrails"
    Stack     = "org"
    ManagedBy = "terraform"
  }
}

# runs with security account credentials, which only need to find the management account id
provider "aws" {
  alias  = "security"
  region = var.region

  default_tags {
    tags = local.default_tags
  }
}

data "aws_organizations_organization" "lookup" {
  provider = aws.security

  return_organization_only = true
}

provider "aws" {
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${data.aws_organizations_organization.lookup.master_account_id}:role/sgr-terraform"
    session_name = "terraform-org"
  }

  default_tags {
    tags = local.default_tags
  }
}
