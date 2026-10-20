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

data "aws_iam_policy_document" "terraform_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = data.aws_iam_roles.sso_admin.arns
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
