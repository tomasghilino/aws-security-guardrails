variable "alert_email" {
  type      = string
  sensitive = true
}

locals {
  security_id = data.aws_caller_identity.start.account_id
}

data "aws_iam_policy_document" "alerts_key" {
  #checkov:skip=CKV_AWS_109:key policy, where "*" means this key only (aws default statement)
  #checkov:skip=CKV_AWS_111:key policy, where "*" means this key only (aws default statement)
  #checkov:skip=CKV_AWS_356:key policy, where "*" means this key only (aws default statement)
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.security_id}:root"]
    }
  }

  # eventbridge publishes to the encrypted topic, so it needs a data key from this key
  statement {
    sid       = "EventBridgePublish"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.security_id]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description             = "security alerts topic encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.alerts_key.json
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/sgr-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

resource "aws_sns_topic" "alerts" {
  name              = "sgr-security-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn
}

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid       = "EventBridgePublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.security_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# every account in the organization forwards its sign-in and iam events to this bus
data "aws_iam_policy_document" "default_bus" {
  statement {
    sid       = "OrganizationForwarding"
    actions   = ["events:PutEvents"]
    resources = ["arn:aws:events:${var.region}:${local.security_id}:event-bus/default"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.lookup.id]
    }
  }
}

resource "aws_cloudwatch_event_bus_policy" "default" {
  event_bus_name = "default"
  policy         = data.aws_iam_policy_document.default_bus.json
}

# patterns and paths are json strings so every entry has the same type
# security hub, guardduty and access analyzer already send member findings to this account as delegated admin;
# sign-ins and iam calls happen in each account and arrive through the forwarders in infra/baseline
locals {
  alert_rules = {
    "sgr-alert-securityhub-critical" = {
      description = "security hub findings rated critical, except the ones guardduty and access analyzer report themselves"
      pattern = jsonencode({
        source        = ["aws.securityhub"]
        "detail-type" = ["Security Hub Findings - Imported"]
        detail = {
          findings = {
            Severity    = { Label = ["CRITICAL"] }
            RecordState = ["ACTIVE"]
            Workflow    = { Status = ["NEW"] }
            ProductName = [{ "anything-but" = ["GuardDuty", "IAM Access Analyzer"] }]
          }
        }
      })
      paths = jsonencode({
        account = "$.detail.findings[0].AwsAccountId"
        title   = "$.detail.findings[0].Title"
        control = "$.detail.findings[0].Compliance.SecurityControlId"
      })
      message = "Security Hub CRITICAL in account <account>: <title> (<control>)"
    }
    "sgr-alert-guardduty-high" = {
      description = "guardduty findings with severity 7 or more"
      pattern = jsonencode({
        source        = ["aws.guardduty"]
        "detail-type" = ["GuardDuty Finding"]
        detail        = { severity = [{ numeric = [">=", 7] }] }
      })
      paths = jsonencode({
        account  = "$.detail.accountId"
        severity = "$.detail.severity"
        type     = "$.detail.type"
      })
      message = "GuardDuty severity <severity> in account <account>: <type>"
    }
    "sgr-alert-external-access" = {
      description = "resources shared outside the organization"
      pattern = jsonencode({
        source        = ["aws.access-analyzer"]
        "detail-type" = ["Access Analyzer Finding"]
        detail        = { status = ["ACTIVE"] }
      })
      paths = jsonencode({
        account  = "$.detail.accountId"
        resource = "$.detail.resource"
      })
      message = "Access Analyzer: <resource> in account <account> is shared outside the organization"
    }
    "sgr-alert-root-login" = {
      description = "console sign-in with the root user of any account"
      pattern = jsonencode({
        source        = ["aws.signin"]
        "detail-type" = ["AWS Console Sign In via CloudTrail"]
        detail        = { userIdentity = { type = ["Root"] } }
      })
      paths = jsonencode({
        account = "$.detail.userIdentity.accountId"
        ip      = "$.detail.sourceIPAddress"
        time    = "$.detail.eventTime"
      })
      message = "Root user signed in to account <account> from <ip> at <time>"
    }
    "sgr-alert-access-key-created" = {
      description = "a long-lived iam access key was created in any account"
      pattern = jsonencode({
        source        = ["aws.iam"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail        = { eventName = ["CreateAccessKey"] }
      })
      paths = jsonencode({
        account = "$.account"
        caller  = "$.detail.userIdentity.arn"
        user    = "$.detail.requestParameters.userName"
        time    = "$.detail.eventTime"
      })
      message = "Access key created for IAM user <user> in account <account> by <caller> at <time>"
    }
  }
}

resource "aws_cloudwatch_event_rule" "alert" {
  for_each = local.alert_rules

  name          = each.key
  description   = each.value.description
  event_pattern = each.value.pattern
}

resource "aws_cloudwatch_event_target" "alert" {
  for_each = local.alert_rules

  rule = aws_cloudwatch_event_rule.alert[each.key].name
  arn  = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = jsondecode(each.value.paths)
    # jsonencode would escape the angle brackets and eventbridge would no longer see the placeholders
    input_template = "\"${each.value.message}\""
  }
}
