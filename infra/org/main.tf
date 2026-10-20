data "aws_organizations_organization" "current" {}

locals {
  root_id = data.aws_organizations_organization.current.roots[0].id

  account_ous = {
    "security"       = "Security"
    "jsp-workloads"  = "Workloads"
    "segp-workloads" = "Workloads"
  }

  accounts = {
    for account in data.aws_organizations_organization.current.non_master_accounts :
    account.name => account if contains(keys(local.account_ous), account.name)
  }
}

resource "aws_organizations_organizational_unit" "this" {
  for_each = toset(values(local.account_ous))

  name      = each.key
  parent_id = local.root_id
}

import {
  for_each = local.accounts

  to = aws_organizations_account.member[each.key]
  id = each.value.id
}

resource "aws_organizations_account" "member" {
  for_each = local.accounts

  name      = each.value.name
  email     = each.value.email
  parent_id = aws_organizations_organizational_unit.this[local.account_ous[each.key]].id

  lifecycle {
    # destroying this resource removes the account from the organization
    prevent_destroy = true
    # write-only at creation time, never returned by the api
    ignore_changes = [role_name, iam_user_access_to_billing]
  }
}
