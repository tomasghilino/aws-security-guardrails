# the pipeline's own identity lives here, in the stack only a human runs, so a merged change can never widen it

locals {
  state_objects = "${aws_s3_bucket.state.arn}/*"

  # who may plan: pull requests, plus the nightly drift check that runs on dev
  plan_subjects  = ["${var.github_subject_prefix}:pull_request", "${var.github_subject_prefix}:ref:refs/heads/dev"]
  apply_subjects = ["${var.github_subject_prefix}:environment:production"]
}

# aws checks the token signature against github's published keys, so no thumbprint is pinned here
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  for_each = { plan = local.plan_subjects, apply = local.apply_subjects }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

resource "aws_iam_role" "github" {
  for_each = data.aws_iam_policy_document.github_trust

  name                 = "sgr-github-${each.key}"
  description          = "github actions ${each.key} for this repository; chains into the management account"
  assume_role_policy   = each.value.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_plan" {
  statement {
    sid       = "ReadState"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadStateObjects"
    actions   = ["s3:GetObject"]
    resources = [local.state_objects]
  }

  # a plan only writes its lock file
  statement {
    sid       = "LockState"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*.tflock"]
  }

  statement {
    sid       = "StateKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.state.arn]
  }

  # the stacks look up the management account id, and the pipeline masks every account id and email in its logs
  statement {
    sid       = "FindAccounts"
    actions   = ["organizations:DescribeOrganization", "organizations:ListAccounts"]
    resources = ["*"]
  }

  statement {
    sid       = "ChainToManagement"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.terraform_plan.arn]
  }
}

data "aws_iam_policy_document" "github_apply" {
  source_policy_documents = [data.aws_iam_policy_document.github_plan.json]

  statement {
    sid       = "ReadStateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.state_objects]
  }

  statement {
    sid       = "ChainToManagement"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.terraform.arn]
  }
}

resource "aws_iam_role_policy" "github" {
  for_each = aws_iam_role.github

  name   = "terraform-${each.key}"
  role   = each.value.id
  policy = each.key == "plan" ? data.aws_iam_policy_document.github_plan.json : data.aws_iam_policy_document.github_apply.json
}
