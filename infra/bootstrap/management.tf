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

resource "aws_iam_role_policy_attachment" "terraform" {
  #checkov:skip=CKV_AWS_274:manages the organization and chains into every member account; narrowed once all stacks exist
  provider = aws.management

  role       = aws_iam_role.terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# plans see every setting and change none; member accounts trust this role through the same name
data "aws_iam_policy_document" "terraform_plan_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = concat(tolist(data.aws_iam_roles.sso_admin.arns), [aws_iam_role.github["plan"].arn])
    }
  }
}

resource "aws_iam_role" "terraform_plan" {
  provider = aws.management

  name                 = "sgr-terraform-plan"
  description          = "read-only terraform plans from the security account"
  assume_role_policy   = data.aws_iam_policy_document.terraform_plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "terraform_plan" {
  provider = aws.management

  role       = aws_iam_role.terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
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
  role   = aws_iam_role.terraform_plan.id
  policy = data.aws_iam_policy_document.terraform_plan_chain.json
}
