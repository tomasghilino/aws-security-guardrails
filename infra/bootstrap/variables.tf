variable "region" {
  type    = string
  default = "us-east-1"
}

# bootstrap is the only stack run with a human sso session per account; everything else assumes the role below
variable "management_profile" {
  type = string
}

# immutable subject: owner and repository ids are part of it, so a renamed or recreated repository gets no access
variable "github_subject_prefix" {
  type    = string
  default = "repo:tomasghilino@86894891/aws-security-guardrails@1427339997"
}
