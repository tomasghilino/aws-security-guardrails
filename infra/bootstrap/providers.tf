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
