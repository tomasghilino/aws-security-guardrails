output "log_bucket" {
  value = aws_s3_bucket.logs.bucket
}

output "trail_arn" {
  value = aws_cloudtrail.organization.arn
}
