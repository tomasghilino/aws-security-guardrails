# each function fixes one kind of change and reaches the account where it happened through a role that can do only that
locals {
  remediations = {
    "security-group" = {
      module = "remediate_security_group"
      pattern = jsonencode({
        source        = ["aws.ec2"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventName = ["AuthorizeSecurityGroupIngress"]
          errorCode = [{ exists = false }]
        }
      })
    }
    "s3-public-access" = {
      module = "remediate_s3_public_access"
      pattern = jsonencode({
        source        = ["aws.s3"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventName = [
            "DeleteAccountPublicAccessBlock",
            "DeleteBucketPublicAccessBlock",
            "PutAccountPublicAccessBlock",
            "PutBucketAcl",
            "PutBucketPolicy",
            "PutBucketPublicAccessBlock",
          ]
          errorCode = [{ exists = false }]
        }
      })
    }
    "cloudtrail" = {
      module = "remediate_cloudtrail"
      pattern = jsonencode({
        source        = ["aws.cloudtrail"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventName = ["StopLogging"]
          errorCode = [{ exists = false }]
        }
      })
    }
  }
}

data "archive_file" "remediation" {
  for_each = local.remediations

  type        = "zip"
  output_path = "${path.module}/.build/${each.value.module}.zip"

  source {
    content  = file("${path.module}/../../lambdas/${each.value.module}.py")
    filename = "${each.value.module}.py"
  }

  source {
    content  = file("${path.module}/../../lambdas/common.py")
    filename = "common.py"
  }
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "remediation" {
  for_each = local.remediations

  name               = "sgr-lambda-remediate-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

data "aws_iam_policy_document" "remediation" {
  for_each = local.remediations

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.remediation[each.key].arn}:*"]
  }

  # only the matching role, and only in accounts of this organization
  statement {
    sid       = "ReachAccount"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/sgr-remediate-${each.key}"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceOrgID"
      values   = [data.aws_organizations_organization.lookup.id]
    }
  }

  statement {
    sid       = "Report"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid       = "EncryptedTopic"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.alerts.arn]
  }
}

resource "aws_iam_role_policy" "remediation" {
  for_each = local.remediations

  name   = "remediate-${each.key}"
  role   = aws_iam_role.remediation[each.key].id
  policy = data.aws_iam_policy_document.remediation[each.key].json
}

resource "aws_cloudwatch_log_group" "remediation" {
  #checkov:skip=CKV_AWS_158:the logs hold resource ids and outcomes, no secrets
  #checkov:skip=CKV_AWS_338:a month of history is enough to review what was remediated
  for_each = local.remediations

  name              = "/aws/lambda/sgr-remediate-${each.key}"
  retention_in_days = 30
}

resource "aws_lambda_function" "remediation" {
  #checkov:skip=CKV_AWS_117:the functions only call aws apis, there is nothing in a vpc to reach
  #checkov:skip=CKV_AWS_116:eventbridge retries failed deliveries for 24 hours and its FailedInvocations metric shows the rest
  #checkov:skip=CKV_AWS_173:the environment only holds a topic arn and a role name
  #checkov:skip=CKV_AWS_115:new accounts get 10 concurrent executions in total, so nothing can be reserved
  #checkov:skip=CKV_AWS_272:the code is reviewed in pull requests and deployed by terraform from this repository
  #checkov:skip=CKV_AWS_50:x-ray tracing adds nothing to functions that make two or three api calls
  for_each = local.remediations

  function_name    = "sgr-remediate-${each.key}"
  role             = aws_iam_role.remediation[each.key].arn
  runtime          = "python3.13"
  handler          = "${each.value.module}.handler"
  filename         = data.archive_file.remediation[each.key].output_path
  source_code_hash = data.archive_file.remediation[each.key].output_base64sha256
  timeout          = 30

  environment {
    variables = {
      ALERTS_TOPIC_ARN = aws_sns_topic.alerts.arn
      REMEDIATION_ROLE = "sgr-remediate-${each.key}"
    }
  }

  depends_on = [aws_iam_role_policy.remediation]
}

resource "aws_cloudwatch_event_rule" "remediation" {
  for_each = local.remediations

  name          = "sgr-remediate-${each.key}"
  description   = "runs sgr-remediate-${each.key} on the change it fixes, in any account"
  event_pattern = each.value.pattern
}

resource "aws_cloudwatch_event_target" "remediation" {
  for_each = local.remediations

  rule = aws_cloudwatch_event_rule.remediation[each.key].name
  arn  = aws_lambda_function.remediation[each.key].arn
}

resource "aws_lambda_permission" "remediation" {
  for_each = local.remediations

  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.remediation[each.key].arn
}
