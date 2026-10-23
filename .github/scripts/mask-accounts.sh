#!/usr/bin/env bash
# the repository is public and so are its logs: from here on every account id, email and the
# organization id show up as *** in this job
set -euo pipefail

{
  aws organizations list-accounts --query 'Accounts[].[Id,Email]' --output text
  aws organizations describe-organization --query 'Organization.Id' --output text
} | tr '\t' '\n' | while read -r value; do
  [ -n "$value" ] && echo "::add-mask::$value"
done

# the login step prints the role id, and ids like AROA... encode the account id; github masks the
# secret that holds it, but an empty or stale secret would mask nothing without anyone noticing
[ "$(aws sts get-caller-identity --query UserId --output text | cut -d: -f1)" = "$ROLE_ID" ] || {
  echo "the role id secret does not match the role, so the log would show its id"
  exit 1
}
