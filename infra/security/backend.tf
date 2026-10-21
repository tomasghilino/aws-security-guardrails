terraform {
  backend "s3" {
    bucket = "sgr-tfstate-8c145eef7b4e195de3eae9b801"
    key    = "security/terraform.tfstate"
    region = "us-east-1"

    encrypt = true
    # without kms_key_id, encrypt = true writes with sse-s3 and skips the state key
    kms_key_id   = "alias/sgr-tfstate"
    use_lockfile = true
  }
}
