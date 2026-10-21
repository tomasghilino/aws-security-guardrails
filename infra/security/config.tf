data "aws_iam_policy_document" "config_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config_aggregator" {
  name               = "sgr-config-aggregator"
  assume_role_policy = data.aws_iam_policy_document.config_trust.json
}

resource "aws_iam_role_policy_attachment" "config_aggregator" {
  role       = aws_iam_role.config_aggregator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_aggregator" "organization" {
  name = "sgr-organization"

  organization_aggregation_source {
    role_arn = aws_iam_role.config_aggregator.arn
    regions  = [var.region]
  }

  depends_on = [aws_iam_role_policy_attachment.config_aggregator]
}

locals {
  organization_rules = {
    "sgr-restricted-ssh" = {
      identifier = "INCOMING_SSH_DISABLED"
      parameters = null
      types      = ["AWS::EC2::SecurityGroup"]
    }
    "sgr-s3-public-access" = {
      identifier = "S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED"
      parameters = null
      types      = ["AWS::S3::Bucket"]
    }
    "sgr-cloudtrail-enabled" = {
      identifier = "CLOUD_TRAIL_ENABLED"
      parameters = null
      types      = null
    }
    "sgr-kms-rotation" = {
      identifier = "CMK_BACKING_KEY_ROTATION_ENABLED"
      parameters = null
      types      = null
    }
    "sgr-required-tags" = {
      identifier = "REQUIRED_TAGS"
      parameters = jsonencode({ tag1Key = "Project", tag2Key = "ManagedBy" })
      types      = ["AWS::EC2::SecurityGroup", "AWS::S3::Bucket"]
    }
  }
}

resource "aws_config_organization_managed_rule" "this" {
  for_each = local.organization_rules

  name                        = each.key
  rule_identifier             = each.value.identifier
  input_parameters            = each.value.parameters
  resource_types_scope        = each.value.types
  maximum_execution_frequency = each.value.types == null ? "TwentyFour_Hours" : null
}
