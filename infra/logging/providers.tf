locals {
  default_tags = {
    Project   = "aws-security-guardrails"
    Stack     = "logging"
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

locals {
  organization_id = data.aws_organizations_organization.lookup.id
  management_id   = data.aws_organizations_organization.lookup.master_account_id
  security_id     = data.aws_caller_identity.start.account_id
}

provider "aws" {
  alias  = "management"
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${local.management_id}:role/sgr-terraform"
    session_name = "terraform-logging"
  }

  default_tags {
    tags = local.default_tags
  }
}

# the log archive is changed through the organization role, the one principal the log archive scp lets in
provider "aws" {
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${local.management_id}:role/sgr-terraform"
    session_name = "terraform-logging"
  }

  assume_role {
    role_arn     = "arn:aws:iam::${local.security_id}:role/OrganizationAccountAccessRole"
    session_name = "terraform-logging"
  }

  default_tags {
    tags = local.default_tags
  }
}
