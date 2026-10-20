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
