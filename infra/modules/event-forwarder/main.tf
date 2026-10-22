terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67"
    }
  }
}

variable "target_bus_arn" {
  type = string
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "put_events" {
  statement {
    actions   = ["events:PutEvents"]
    resources = [var.target_bus_arn]
  }
}

resource "aws_iam_role" "forwarder" {
  name               = "sgr-event-forwarder"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy" "forwarder" {
  name   = "put-events-security-bus"
  role   = aws_iam_role.forwarder.id
  policy = data.aws_iam_policy_document.put_events.json
}

# api calls only show up on the bus of the account where they happen, so the ones the security
# account alerts on or remediates are sent there
resource "aws_cloudwatch_event_rule" "forward" {
  name        = "sgr-forward-to-security"
  description = "sends sign-ins and the api calls the security account watches to its event bus"
  event_pattern = jsonencode({
    source        = ["aws.cloudtrail", "aws.ec2", "aws.iam", "aws.s3", "aws.signin"]
    "detail-type" = ["AWS Console Sign In via CloudTrail", "AWS API Call via CloudTrail"]
    detail = {
      eventName = [
        "AuthorizeSecurityGroupIngress",
        "ConsoleLogin",
        "CreateAccessKey",
        "DeleteAccountPublicAccessBlock",
        "DeleteBucketPublicAccessBlock",
        "PutAccountPublicAccessBlock",
        "PutBucketAcl",
        "PutBucketPolicy",
        "PutBucketPublicAccessBlock",
        "StopLogging",
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "forward" {
  rule     = aws_cloudwatch_event_rule.forward.name
  arn      = var.target_bus_arn
  role_arn = aws_iam_role.forwarder.arn
}
