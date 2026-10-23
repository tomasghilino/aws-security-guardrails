variable "region" {
  type    = string
  default = "us-east-1"
}

variable "alert_email" {
  type      = string
  sensitive = true
}

variable "monthly_budget_usd" {
  type    = number
  default = 20
}

variable "allowed_regions" {
  type    = list(string)
  default = ["us-east-1"]
}

# ci plans pass the read-only sgr-terraform-plan roles; applies and local runs keep these defaults
variable "management_role" {
  type    = string
  default = "sgr-terraform"
}
