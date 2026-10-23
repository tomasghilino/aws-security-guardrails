terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67"
    }
  }
}

variable "security_account_id" {
  type = string
}

# only the management account holds the organization trail
variable "organization_trail_arn" {
  type    = string
  default = null
}

# set in the management account, where the pipeline may only create roles that carry this boundary
variable "permissions_boundary" {
  type    = string
  default = null
}

data "aws_iam_policy_document" "permissions" {
  for_each = local.remediations

  dynamic "statement" {
    for_each = each.value

    content {
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

locals {
  all_remediations = {
    "security-group" = [
      { actions = ["ec2:DescribeSecurityGroupRules"], resources = ["*"] },
      { actions = ["ec2:RevokeSecurityGroupIngress"], resources = ["arn:aws:ec2:*:*:security-group/*"] },
    ]
    "s3-public-access" = [
      { actions = ["s3:GetAccountPublicAccessBlock", "s3:PutAccountPublicAccessBlock"], resources = ["*"] },
      { actions = ["s3:GetBucketPublicAccessBlock", "s3:PutBucketPublicAccessBlock"], resources = ["arn:aws:s3:::*"] },
    ]
    "cloudtrail" = [
      { actions = ["cloudtrail:GetTrailStatus", "cloudtrail:StartLogging"], resources = [coalesce(var.organization_trail_arn, "none")] },
    ]
  }

  remediations = { for name, statements in local.all_remediations : name => statements if name != "cloudtrail" || var.organization_trail_arn != null }
}

data "aws_iam_policy_document" "trust" {
  for_each = local.remediations

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.security_account_id}:role/sgr-lambda-remediate-${each.key}"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.remediations

  name               = "sgr-remediate-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.trust[each.key].json

  permissions_boundary = var.permissions_boundary
}

resource "aws_iam_role_policy" "this" {
  for_each = local.remediations

  name   = "remediate-${each.key}"
  role   = aws_iam_role.this[each.key].id
  policy = data.aws_iam_policy_document.permissions[each.key].json
}
