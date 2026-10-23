terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67"
    }
  }
}

variable "trusted_role_arns" {
  type = list(string)
}

# the read-only twin of OrganizationAccountAccessRole: plans chain through here instead
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.trusted_role_arns
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "sgr-terraform-plan"
  description          = "read-only terraform plans"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# readonlyaccess also reads data; a plan only needs settings, so the data reads are taken back
data "aws_iam_policy_document" "no_data_reads" {
  statement {
    sid    = "DenyDataReads"
    effect = "Deny"
    actions = [
      "athena:GetQueryResults",
      "dynamodb:BatchGetItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "ec2:GetPasswordData",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "kinesis:GetRecords",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:StartQuery",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "secretsmanager:GetSecretValue",
      "sqs:ReceiveMessage",
      "ssm:GetParameter",
      "ssm:GetParameterHistory",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = ["*"]
  }

  # lambda decrypts its environment variables with the caller's rights; without this a plan sees them empty and reports drift
  statement {
    sid       = "DenyDecryptOutsideLambda"
    effect    = "Deny"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringNotLike"
      variable = "kms:ViaService"
      values   = ["lambda.*.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "no_data_reads" {
  name   = "deny-data-reads"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.no_data_reads.json
}

output "name" {
  value = aws_iam_role.this.name
}

output "arn" {
  value = aws_iam_role.this.arn
}
