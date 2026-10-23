# Editing the logs, and getting caught

The organization trail writes to a bucket in the security account. I tried to touch it as that account's own administrator, using changes that would have been harmless if they had gone through:

```text
PutObject AWSLogs/fake.json   -> explicit deny in a resource-based policy
PutBucketPolicy (same policy) -> explicit deny in a service control policy
PutKeyPolicy (same policy)    -> explicit deny in a service control policy
```

The bucket policy only lets CloudTrail and the organization role write, and the SCP covers the bucket's settings and its key. Stopping the trail from a workload account failed too, first because AWS never lets member accounts operate an organization trail, and second because of the SCP.

Then I played an attacker who has the one role that can write there. I took a delivered log file with a denied call in it, removed that record and uploaded it under the same name:

```text
== validate before touching anything
59/59 log files valid
== validate again
Log file s3://sgr-logs-<suffix>/AWSLogs/o-<org>/<acct>/CloudTrail/us-east-1/2026/10/21/..._CloudTrail_us-east-1_20261021T1630Z_<id>.json.gz  INVALID: hash value doesn't match
58/59 log files valid, 1/59 log files INVALID
```

Every hour CloudTrail writes a signed digest with the hash of each file it delivered, and only CloudTrail holds the signing key, so the digest can't be rewritten to match. Versioning kept the original, and copying it back made all 59 valid again.

It took a while to get there. My first target never reached the archive, because I made that call minutes after creating the trail, before it covered the member accounts. Then `validate-logs` kept finding no digests, because Python on Windows had left a `\r` at the end of the account ID I passed it.
