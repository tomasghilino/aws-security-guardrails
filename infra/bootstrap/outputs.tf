output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "state_kms_key_alias" {
  value = aws_kms_alias.state.name
}

output "management_role_name" {
  value = aws_iam_role.terraform.name
}

output "github_role_names" {
  value = { for k, role in aws_iam_role.github : k => role.name }
}
