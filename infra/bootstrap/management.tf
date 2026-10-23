data "aws_organizations_organization" "current" {
  return_organization_only = true
}

data "aws_caller_identity" "management" {
  provider = aws.management
}

data "aws_iam_roles" "sso_admin" {
  name_regex  = "^AWSReservedSSO_AdministratorAccess_"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

# people apply with their sso admin role, the pipeline only after the production environment approval
data "aws_iam_policy_document" "terraform_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = concat(tolist(data.aws_iam_roles.sso_admin.arns), [aws_iam_role.github["apply"].arn])
    }
  }
}

resource "aws_iam_role" "terraform" {
  provider = aws.management

  name                 = "sgr-terraform"
  description          = "terraform runs from the security account land here to manage the organization"
  assume_role_policy   = data.aws_iam_policy_document.terraform_trust.json
  max_session_duration = 3600

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.management.account_id == data.aws_organizations_organization.current.master_account_id
      error_message = "management_profile must point at the management account."
    }
  }
}

locals {
  management_id = data.aws_caller_identity.management.account_id
  boundary_arn  = "arn:aws:iam::${local.management_id}:policy/sgr-pipeline-boundary"
  # the service-linked roles the stacks create or hand to a service in the management account
  service_linked = [
    "access-analyzer.amazonaws.com",
    "cloudtrail.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
  ]
}

# every role the pipeline creates here carries this, so nothing it applies can make a role that runs the organization
data "aws_iam_policy_document" "pipeline_boundary" {
  #checkov:skip=CKV_AWS_1:a boundary only caps what a role may do, its own policy grants the access
  #checkov:skip=CKV_AWS_49:a boundary only caps what a role may do, its own policy grants the access
  #checkov:skip=CKV_AWS_107:a boundary only caps what a role may do, its own policy grants the access
  #checkov:skip=CKV_AWS_108:a boundary only caps what a role may do, its own policy grants the access
  #checkov:skip=CKV_AWS_109:a boundary only caps what a role may do, its own policy grants the access
  #checkov:skip=CKV_AWS_110:a boundary only caps what a role may do, its own policy grants the access
  #checkov:skip=CKV_AWS_111:a boundary only caps what a role may do, its own policy grants the access
  #checkov:skip=CKV_AWS_356:a boundary only caps what a role may do, its own policy grants the access
  statement {
    sid       = "AllowServiceWork"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyOrganizationControl"
    effect = "Deny"
    actions = [
      "account:*",
      "iam:*",
      "identitystore:*",
      "organizations:*",
      "sso:*",
      "sts:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "pipeline_boundary" {
  provider = aws.management

  name        = "sgr-pipeline-boundary"
  description = "the most any role created by the terraform pipeline in the management account may do"
  policy      = data.aws_iam_policy_document.pipeline_boundary.json
}

# what the four stacks do in the management account, from its access advisor data, plus the hop into member accounts
data "aws_iam_policy_document" "terraform" {
  #checkov:skip=CKV_AWS_111:organizations, config, guardduty and security hub calls take no resource arn, scoped resources are listed below
  #checkov:skip=CKV_AWS_356:organizations, config, guardduty and security hub calls take no resource arn, scoped resources are listed below
  statement {
    sid = "ReadManagedSettings"
    actions = [
      "budgets:Describe*",
      "budgets:ListTagsForResource",
      "budgets:View*",
      "cloudtrail:Describe*",
      "cloudtrail:Get*",
      "cloudtrail:List*",
      "config:Describe*",
      "config:Get*",
      "config:List*",
      "ec2:Describe*",
      "ec2:GetEbsEncryptionByDefault",
      "events:Describe*",
      "events:List*",
      "guardduty:Get*",
      "guardduty:List*",
      "iam:Get*",
      "iam:List*",
      "organizations:Describe*",
      "organizations:List*",
      "s3:GetAccountPublicAccessBlock",
      "securityhub:Describe*",
      "securityhub:Get*",
      "securityhub:List*",
      "ssm:GetServiceSetting",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageOrganization"
    actions = [
      "organizations:AttachPolicy",
      "organizations:CreateOrganizationalUnit",
      "organizations:CreatePolicy",
      "organizations:DeleteOrganizationalUnit",
      "organizations:DeletePolicy",
      "organizations:DeregisterDelegatedAdministrator",
      "organizations:DetachPolicy",
      "organizations:DisableAWSServiceAccess",
      "organizations:DisablePolicyType",
      "organizations:EnableAWSServiceAccess",
      "organizations:EnablePolicyType",
      "organizations:MoveAccount",
      "organizations:RegisterDelegatedAdministrator",
      "organizations:TagResource",
      "organizations:UntagResource",
      "organizations:UpdateOrganizationalUnit",
      "organizations:UpdatePolicy",
    ]
    resources = ["*"]
  }

  # the security services keep their own settings here and delegate to the security account
  statement {
    sid = "ManageSecurityServices"
    actions = [
      "config:DeleteConfigurationRecorder",
      "config:DeleteDeliveryChannel",
      "config:PutConfigurationRecorder",
      "config:PutDeliveryChannel",
      "config:StartConfigurationRecorder",
      "config:StopConfigurationRecorder",
      "config:TagResource",
      "config:UntagResource",
      "guardduty:CreateDetector",
      "guardduty:DisableOrganizationAdminAccount",
      "guardduty:EnableOrganizationAdminAccount",
      "guardduty:TagResource",
      "guardduty:UntagResource",
      "guardduty:UpdateDetector",
      "securityhub:DisableOrganizationAdminAccount",
      "securityhub:EnableOrganizationAdminAccount",
      "securityhub:EnableSecurityHub",
      "securityhub:TagResource",
      "securityhub:UntagResource",
      "securityhub:UpdateSecurityHubConfiguration",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageOrganizationTrail"
    actions = [
      "cloudtrail:AddTags",
      "cloudtrail:CreateTrail",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:RemoveTags",
      "cloudtrail:StartLogging",
      "cloudtrail:UpdateTrail",
    ]
    resources = ["arn:aws:cloudtrail:*:${local.management_id}:trail/sgr-*"]
  }

  statement {
    sid = "ManageOwnRules"
    actions = [
      "events:DeleteRule",
      "events:PutRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:TagResource",
      "events:UntagResource",
    ]
    resources = ["arn:aws:events:*:${local.management_id}:rule/sgr-*"]
  }

  statement {
    sid       = "ManageOwnBudget"
    actions   = ["budgets:ModifyBudget", "budgets:TagResource", "budgets:UntagResource"]
    resources = ["arn:aws:budgets::${local.management_id}:budget/sgr-*"]
  }

  statement {
    sid = "AccountHardening"
    actions = [
      "ec2:EnableEbsEncryptionByDefault",
      "iam:UpdateAccountPasswordPolicy",
      "s3:PutAccountPublicAccessBlock",
      "ssm:UpdateServiceSetting",
    ]
    resources = ["*"]
  }

  # a role the pipeline writes to must carry the boundary, and nothing below lets it be taken off
  statement {
    sid = "ManageBoundedRoles"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:PutRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.management_id}:role/sgr-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }

  statement {
    sid = "ManageOwnRoles"
    actions = [
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
    ]
    resources = ["arn:aws:iam::${local.management_id}:role/sgr-*"]
  }

  statement {
    sid       = "PassForwarderRole"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.management_id}:role/sgr-event-forwarder"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["events.amazonaws.com"]
    }
  }

  statement {
    sid       = "PassConfigRole"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.management_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"]
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = local.service_linked
    }
  }

  statement {
    sid       = "ChainToMemberAccounts"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceOrgID"
      values   = [data.aws_organizations_organization.current.id]
    }
  }

  # the pipeline's own roles stay with the people who apply bootstrap
  statement {
    sid    = "DenyOwnIdentity"
    effect = "Deny"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DeleteRole",
      "iam:DeleteRolePermissionsBoundary",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:PutRolePolicy",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.management_id}:role/sgr-terraform*"]
  }

  statement {
    sid    = "DenyBoundaryChanges"
    effect = "Deny"
    actions = [
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
    resources = [local.boundary_arn]
  }

  statement {
    sid    = "DenyLeavingOrClosing"
    effect = "Deny"
    actions = [
      "organizations:CloseAccount",
      "organizations:DeleteOrganization",
      "organizations:LeaveOrganization",
      "organizations:RemoveAccountFromOrganization",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "terraform" {
  provider = aws.management

  name   = "manage-organization"
  role   = aws_iam_role.terraform.id
  policy = data.aws_iam_policy_document.terraform.json
}

# plans see every setting and change none; member accounts trust this role through the same name
module "plan_role_management" {
  source    = "../modules/plan-role"
  providers = { aws = aws.management }

  trusted_role_arns = concat(tolist(data.aws_iam_roles.sso_admin.arns), [aws_iam_role.github["plan"].arn])
}

moved {
  from = aws_iam_role.terraform_plan
  to   = module.plan_role_management.aws_iam_role.this
}

moved {
  from = aws_iam_role_policy_attachment.terraform_plan
  to   = module.plan_role_management.aws_iam_role_policy_attachment.this
}

# readonlyaccess has no sts, so the next hop is granted here, and only inside the organization
data "aws_iam_policy_document" "terraform_plan_chain" {
  statement {
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/sgr-terraform-plan"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceOrgID"
      values   = [data.aws_organizations_organization.current.id]
    }
  }
}

resource "aws_iam_role_policy" "terraform_plan_chain" {
  provider = aws.management

  name   = "chain-to-member-accounts"
  role   = module.plan_role_management.name
  policy = data.aws_iam_policy_document.terraform_plan_chain.json
}
