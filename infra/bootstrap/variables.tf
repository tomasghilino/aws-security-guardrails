variable "region" {
  type    = string
  default = "us-east-1"
}

# bootstrap is the only stack run with a human sso session per account; everything else assumes the role below
variable "management_profile" {
  type = string
}
