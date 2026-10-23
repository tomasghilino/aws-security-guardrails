variable "region" {
  type    = string
  default = "us-east-1"
}

# ci plans pass the read-only sgr-terraform-plan roles; applies and local runs keep these defaults
variable "management_role" {
  type    = string
  default = "sgr-terraform"
}

variable "member_role" {
  type    = string
  default = "OrganizationAccountAccessRole"
}

# false turns security hub off in every member account through the central policy, the first step of the teardown
variable "securityhub_enabled" {
  type    = bool
  default = true
}
