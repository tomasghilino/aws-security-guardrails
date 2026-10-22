# delegating guardduty and security hub to this account turns both on here, so terraform adopts them
data "aws_guardduty_detector" "existing" {}

import {
  to = aws_guardduty_detector.security
  id = data.aws_guardduty_detector.existing.id
}

import {
  to = aws_securityhub_account.security
  id = data.aws_caller_identity.start.account_id
}
