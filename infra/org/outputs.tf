output "management_account_id" {
  value = data.aws_organizations_organization.current.master_account_id
}

output "account_ids" {
  value = { for name, account in aws_organizations_account.member : name => account.id }
}

output "organizational_unit_ids" {
  value = { for name, ou in aws_organizations_organizational_unit.this : name => ou.id }
}

output "root_id" {
  value = local.root_id
}

# guardduty needs each member's email to enroll it explicitly
output "account_emails" {
  value     = merge({ for name, account in aws_organizations_account.member : name => account.email }, { management = data.aws_organizations_organization.current.master_account_email })
  sensitive = true
}
