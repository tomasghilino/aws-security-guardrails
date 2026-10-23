variable "region" {
  type    = string
  default = "us-east-1"
}

variable "trail_name" {
  type    = string
  default = "sgr-org-trail"
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
