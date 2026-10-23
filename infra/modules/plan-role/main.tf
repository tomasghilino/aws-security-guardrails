terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67"
    }
  }
}

variable "management_account_id" {
  type = string
}

# the read-only twin of OrganizationAccountAccessRole: plans chain through here instead
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.management_account_id}:role/sgr-terraform-plan"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "sgr-terraform-plan"
  description          = "read-only terraform plans, reached from the management account"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
