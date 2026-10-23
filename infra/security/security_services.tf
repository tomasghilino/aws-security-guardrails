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

  # accepted risks: controls for services this organization deliberately doesn't run, each with its reason
  securityhub_disabled_controls = {
    "CloudTrail.5" = "alerts come from eventbridge rules, not from cloudwatch logs metric filters"
    "GuardDuty.5"  = "paid protection plan left off on purpose: no eks clusters run here"
    "GuardDuty.6"  = "paid protection plan left off on purpose: lambda network logs not needed"
    "GuardDuty.7"  = "paid protection plan left off on purpose: no eks clusters run here"
    "GuardDuty.8"  = "paid protection plan left off on purpose: no ec2 workloads run here"
    "GuardDuty.9"  = "paid protection plan left off on purpose: no rds databases run here"
    "GuardDuty.10" = "paid protection plan left off on purpose: s3 data events would dominate the bill"
    "GuardDuty.11" = "paid protection plan left off on purpose: no compute workloads run here"
    "GuardDuty.12" = "paid protection plan left off on purpose: no ecs workloads run here"
    "GuardDuty.13" = "paid protection plan left off on purpose: no ec2 workloads run here"
    "Inspector.1"  = "inspector left out of scope: images are scanned with trivy in ci"
    "Inspector.2"  = "inspector left out of scope: images are scanned with trivy in ci"
    "Inspector.3"  = "inspector left out of scope: lambda code is scanned in ci"
    "Inspector.4"  = "inspector left out of scope: lambda dependencies are scanned in ci"
    "Macie.1"      = "no sensitive customer data is stored in this organization"
    "Macie.2"      = "no sensitive customer data is stored in this organization"
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
  auto_enable_organization_members = var.teardown ? "NONE" : "ALL"
}

# auto-enable only reached new accounts, so the existing ones are enrolled explicitly
resource "aws_guardduty_member" "existing" {
  for_each = toset(["management", "segp-workloads", "jsp-workloads"])

  detector_id = aws_guardduty_detector.security.id
  account_id  = each.key == "management" ? data.aws_organizations_organization.lookup.master_account_id : data.terraform_remote_state.org.outputs.account_ids[each.key]
  email       = data.terraform_remote_state.org.outputs.account_emails[each.key]

  lifecycle {
    # aws reports organization members as invited even though nobody was sent an invitation
    ignore_changes = [email, invite]
  }
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
    service_enabled       = !var.teardown
    enabled_standard_arns = var.teardown ? [] : local.securityhub_standards

    # aws only takes standards and controls while the service is on
    dynamic "security_controls_configuration" {
      for_each = var.teardown ? [] : [1]

      content {
        disabled_control_identifiers = sort(keys(local.securityhub_disabled_controls))
      }
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

# expected external access: sso roles trust the identity center saml provider, and the project 2 ci role trusts github oidc
resource "aws_accessanalyzer_archive_rule" "sso_roles" {
  analyzer_name = aws_accessanalyzer_analyzer.organization.analyzer_name
  rule_name     = "sso-permission-set-roles"

  filter {
    criteria = "resource"
    contains = ["role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_"]
  }
}

resource "aws_accessanalyzer_archive_rule" "github_oidc_role" {
  analyzer_name = aws_accessanalyzer_analyzer.organization.analyzer_name
  rule_name     = "github-oidc-ci-role"

  filter {
    criteria = "resource"
    contains = ["role/segp-github-ci"]
  }
}
