# security hub and guardduty pick their delegated admin through their own apis, and both need to be on
# in the management account first; from then on the security account configures every account
resource "aws_guardduty_detector" "management" {
  #checkov:skip=CKV2_AWS_3:the organization configuration lives with the delegated admin in infra/security
  enable = true
}

# foundational detection only (cloudtrail, vpc flow logs, dns); the paid protection plans stay off
resource "aws_guardduty_detector_feature" "management" {
  for_each = toset(local.guardduty_paid_features)

  detector_id = aws_guardduty_detector.management.id
  name        = each.key
  status      = "DISABLED"

  dynamic "additional_configuration" {
    for_each = lookup(local.guardduty_paid_sub_features, each.key, [])

    content {
      name   = additional_configuration.value
      status = "DISABLED"
    }
  }
}

resource "aws_guardduty_organization_admin_account" "security" {
  admin_account_id = aws_organizations_account.member["security"].id

  depends_on = [aws_organizations_organization.this, aws_guardduty_detector.management]
}

resource "aws_securityhub_account" "management" {
  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
}

resource "aws_securityhub_organization_admin_account" "security" {
  admin_account_id = aws_organizations_account.member["security"].id

  depends_on = [aws_organizations_organization.this, aws_securityhub_account.management]
}

locals {
  # aws reports these sub-options of the paid features even when they are off, so they are declared off here too
  guardduty_paid_sub_features = {
    RDS_LOGIN_EVENTS   = ["RDS_DATA_RISK"]
    RUNTIME_MONITORING = ["EC2_AGENT_MANAGEMENT", "ECS_FARGATE_AGENT_MANAGEMENT", "EKS_ADDON_MANAGEMENT"]
  }

  guardduty_paid_features = [
    "EBS_MALWARE_PROTECTION",
    "EKS_AUDIT_LOGS",
    "LAMBDA_NETWORK_LOGS",
    "RDS_LOGIN_EVENTS",
    "RUNTIME_MONITORING",
    "S3_DATA_EVENTS",
  ]
}
