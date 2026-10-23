locals {
  default_tags = {
    Project   = "aws-security-guardrails"
    Stack     = "baseline"
    ManagedBy = "terraform"
  }
}

# runs with security account credentials, which only need to find the management account id
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

provider "aws" {
  alias  = "management"
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${data.aws_organizations_organization.lookup.master_account_id}:role/${var.management_role}"
    session_name = "terraform-baseline"
  }

  default_tags {
    tags = local.default_tags
  }
}

data "aws_organizations_organization" "current" {
  provider = aws.management
}

locals {
  account_ids = { for account in data.aws_organizations_organization.current.accounts : account.name => account.id }
}

# member accounts are reached from the management role through the role aws creates in every new account
provider "aws" {
  alias  = "security"
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${data.aws_organizations_organization.lookup.master_account_id}:role/${var.management_role}"
    session_name = "terraform-baseline"
  }

  assume_role {
    role_arn     = "arn:aws:iam::${local.account_ids["security"]}:role/${var.member_role}"
    session_name = "terraform-baseline"
  }

  default_tags {
    tags = local.default_tags
  }
}

provider "aws" {
  alias  = "segp"
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${data.aws_organizations_organization.lookup.master_account_id}:role/${var.management_role}"
    session_name = "terraform-baseline"
  }

  assume_role {
    role_arn     = "arn:aws:iam::${local.account_ids["segp-workloads"]}:role/${var.member_role}"
    session_name = "terraform-baseline"
  }

  default_tags {
    tags = local.default_tags
  }
}

provider "aws" {
  alias  = "jsp"
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${data.aws_organizations_organization.lookup.master_account_id}:role/${var.management_role}"
    session_name = "terraform-baseline"
  }

  assume_role {
    role_arn     = "arn:aws:iam::${local.account_ids["jsp-workloads"]}:role/${var.member_role}"
    session_name = "terraform-baseline"
  }

  default_tags {
    tags = local.default_tags
  }
}
