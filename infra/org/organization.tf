import {
  to = aws_organizations_organization.this
  id = data.aws_organizations_organization.current.id
}

# the resource owns these lists: a principal missing here gets its trusted access turned off
resource "aws_organizations_organization" "this" {
  feature_set = "ALL"
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "config.amazonaws.com",
    "sso.amazonaws.com",
  ]
  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]

  lifecycle {
    # destroying this resource deletes the organization
    prevent_destroy = true
  }
}

# the security account runs these services for the whole organization, so the management account stays empty
resource "aws_organizations_delegated_administrator" "security" {
  for_each = toset([
    "config-multiaccountsetup.amazonaws.com",
    "config.amazonaws.com",
  ])

  account_id        = aws_organizations_account.member["security"].id
  service_principal = each.key

  depends_on = [aws_organizations_organization.this]
}
