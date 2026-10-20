provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "aws-security-guardrails"
      Stack     = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}

provider "aws" {
  alias   = "management"
  region  = var.region
  profile = var.management_profile

  default_tags {
    tags = {
      Project   = "aws-security-guardrails"
      Stack     = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}
