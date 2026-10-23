resource "aws_cloudtrail" "organization" {
  enable_logging = false
  #checkov:skip=CKV2_AWS_10:alerts come from eventbridge in the security account, not from cloudwatch metric filters
  #checkov:skip=CKV_AWS_252:delivery notifications are not needed, the log archive is read on demand
  provider = aws.management

  name                          = var.trail_name
  s3_bucket_name                = aws_s3_bucket.logs.id
  kms_key_id                    = aws_kms_key.logs.arn
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.logs]
}
