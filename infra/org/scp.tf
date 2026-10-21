data "aws_iam_policy_document" "region_deny" {
  statement {
    sid    = "DenyUnusedRegions"
    effect = "Deny"
    # global services live in us-east-1 but are called from any region, so they are left out
    not_actions = [
      "a4b:*",
      "account:*",
      "acm:*",
      "aws-marketplace-management:*",
      "aws-marketplace:*",
      "aws-portal:*",
      "billing:*",
      "budgets:*",
      "ce:*",
      "chime:*",
      "cloudfront:*",
      "cur:*",
      "directconnect:*",
      "ec2:DescribeRegions",
      "ec2:DescribeTransitGateways",
      "ec2:DescribeVpnGateways",
      "fms:*",
      "freetier:*",
      "globalaccelerator:*",
      "health:*",
      "iam:*",
      "importexport:*",
      "invoicing:*",
      "networkmanager:*",
      "organizations:*",
      "payments:*",
      "pricing:*",
      "route53-recovery-cluster:*",
      "route53-recovery-control-config:*",
      "route53-recovery-readiness:*",
      "route53:*",
      "route53domains:*",
      "s3:GetAccountPublic*",
      "s3:ListAllMyBuckets",
      "s3:ListMultiRegionAccessPoints",
      "s3:PutAccountPublic*",
      "shield:*",
      "sts:*",
      "support:*",
      "tax:*",
      "trustedadvisor:*",
      "waf-regional:*",
      "waf:*",
      "wafv2:*",
      "wellarchitected:*",
    ]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }
}

resource "aws_organizations_policy" "region_deny" {
  name        = "sgr-region-deny"
  description = "deny every regional service outside the allowed regions"
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.region_deny.json

  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy_attachment" "region_deny" {
  policy_id = aws_organizations_policy.region_deny.id
  target_id = local.root_id
}

# one policy that grows with each guarded service: a target takes at most five scps, FullAWSAccess included
data "aws_iam_policy_document" "baseline" {
  statement {
    sid       = "DenyLeavingOrganization"
    effect    = "Deny"
    actions   = ["organizations:LeaveOrganization"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyRootUser"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:root"]
    }
  }

  # the organization trail lives in the management account, which scps never reach; this covers every other trail
  statement {
    sid    = "ProtectCloudTrail"
    effect = "Deny"
    actions = [
      "cloudtrail:DeleteTrail",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:PutInsightSelectors",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ProtectLogArchive"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
    ]
    resources = ["arn:aws:s3:::sgr-logs-*"]

    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
    }
  }

  statement {
    sid    = "ProtectLogKey"
    effect = "Deny"
    actions = [
      "kms:DisableKey",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
    ]
    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ResourceAliases"
      values   = ["alias/sgr-logs"]
    }

    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
    }
  }
}

resource "aws_organizations_policy" "baseline" {
  name        = "sgr-baseline"
  description = "guardrails every member account gets"
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.baseline.json

  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy_attachment" "baseline" {
  policy_id = aws_organizations_policy.baseline.id
  target_id = local.root_id
}
