data "terraform_remote_state" "org" {
  backend = "s3"

  config = {
    bucket = "sgr-tfstate-8c145eef7b4e195de3eae9b801"
    key    = "org/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  guardduty_paid_features = [
    "EBS_MALWARE_PROTECTION",
    "EKS_AUDIT_LOGS",
    "LAMBDA_NETWORK_LOGS",
    "RDS_LOGIN_EVENTS",
    "RUNTIME_MONITORING",
    "S3_DATA_EVENTS",
  ]

  # aws reports these sub-options of the paid features even when they are off, so they are declared off here too
  guardduty_paid_sub_features = {
    RDS_LOGIN_EVENTS   = ["RDS_DATA_RISK"]
    RUNTIME_MONITORING = ["ECS_FARGATE_AGENT_MANAGEMENT", "EC2_AGENT_MANAGEMENT", "EKS_ADDON_MANAGEMENT"]
  }

  securityhub_standards = [
    "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0",
    "arn:aws:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/3.0.0",
    "arn:aws:securityhub:${var.region}::standards/nist-800-53/v/5.0.0",
  ]
}

resource "aws_guardduty_detector" "security" {
  enable = true
}

resource "aws_guardduty_detector_feature" "security" {
  for_each = toset(local.guardduty_paid_features)

  detector_id = aws_guardduty_detector.security.id
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

# every current and future account gets foundational detection and none of the paid plans
resource "aws_guardduty_organization_configuration" "this" {
  detector_id                      = aws_guardduty_detector.security.id
  auto_enable_organization_members = "ALL"
}

resource "aws_guardduty_organization_configuration_feature" "paid" {
  for_each = toset(local.guardduty_paid_features)

  detector_id = aws_guardduty_detector.security.id
  name        = each.key
  auto_enable = "NONE"

  dynamic "additional_configuration" {
    for_each = lookup(local.guardduty_paid_sub_features, each.key, [])

    content {
      name        = additional_configuration.value
      auto_enable = "NONE"
    }
  }
}

resource "aws_securityhub_account" "security" {
  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
}

# central configuration needs a home region even when nothing is aggregated from other regions
resource "aws_securityhub_finding_aggregator" "home" {
  linking_mode = "NO_REGIONS"

  depends_on = [aws_securityhub_account.security]
}

resource "aws_securityhub_organization_configuration" "this" {
  auto_enable           = false
  auto_enable_standards = "NONE"

  organization_configuration {
    configuration_type = "CENTRAL"
  }

  depends_on = [aws_securityhub_finding_aggregator.home]
}

resource "aws_securityhub_configuration_policy" "baseline" {
  name        = "sgr-baseline"
  description = "fsbp, cis 3.0 and nist 800-53 rev5 in every account"

  configuration_policy {
    service_enabled       = true
    enabled_standard_arns = local.securityhub_standards

    security_controls_configuration {
      disabled_control_identifiers = []
    }
  }

  depends_on = [aws_securityhub_organization_configuration.this]
}

resource "aws_securityhub_configuration_policy_association" "root" {
  target_id = data.terraform_remote_state.org.outputs.root_id
  policy_id = aws_securityhub_configuration_policy.baseline.id
}

resource "aws_accessanalyzer_analyzer" "organization" {
  analyzer_name = "sgr-organization"
  type          = "ORGANIZATION"
}
