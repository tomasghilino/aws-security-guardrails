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

# true is the first step of the teardown: security hub off in every member account through the central policy,
# and guardduty no longer enrolling accounts, which aws requires before members can be removed
variable "teardown" {
  type    = bool
  default = false
}
