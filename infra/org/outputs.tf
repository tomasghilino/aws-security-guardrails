output "management_account_id" {
  value = data.aws_organizations_organization.current.master_account_id
}

output "account_ids" {
  value = { for name, account in aws_organizations_account.member : name => account.id }
}

output "organizational_unit_ids" {
  value = { for name, ou in aws_organizations_organizational_unit.this : name => ou.id }
}
