import {
  to = aws_organizations_organization.this
  id = data.aws_organizations_organization.current.id
}

# the resource owns these lists: a principal missing here gets its trusted access turned off
resource "aws_organizations_organization" "this" {
  feature_set = "ALL"
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "sso.amazonaws.com",
  ]
  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]

  lifecycle {
    # destroying this resource deletes the organization
    prevent_destroy = true
  }
}
