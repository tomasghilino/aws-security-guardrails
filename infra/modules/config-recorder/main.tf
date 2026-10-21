terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67"
    }
  }
}

variable "bucket_name" {
  type = string
}

resource "aws_iam_service_linked_role" "config" {
  aws_service_name = "config.amazonaws.com"
}

resource "aws_config_configuration_recorder" "this" {
  #checkov:skip=CKV2_AWS_48:records everything except AWS::Config::ResourceCompliance, left out on purpose (see below)
  name     = "sgr"
  role_arn = aws_iam_service_linked_role.config.arn

  recording_group {
    all_supported = false

    # one item per compliance change of every resource, which security hub would turn into a billing loop
    exclusion_by_resource_types {
      resource_types = ["AWS::Config::ResourceCompliance"]
    }

    recording_strategy {
      use_only = "EXCLUSION_BY_RESOURCE_TYPES"
    }
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "sgr"
  s3_bucket_name = var.bucket_name

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  #checkov:skip=CKV2_AWS_45:the recorder covers every type except AWS::Config::ResourceCompliance, left out on purpose
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}
