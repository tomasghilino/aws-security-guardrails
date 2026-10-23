# Fixed in seconds, and the one that failed first

In a workload account I opened RDP to the world on the security group that already had SSH open from the Config demo, and I weakened the account's S3 Block Public Access. Both were back to safe before my first check, 16 seconds later. The Lambdas mail what they did:

```text
Remediated: revoked internet access to ports 22-22, 3389-3389 on sg-<id> in account <jsp>, 11 seconds after arn:aws:sts::<jsp>:assumed-role/AWSReservedSSO_<id>/tomas opened it
Remediated: turned Block Public Access back on for the account-level block of account <jsp>, 13 seconds after PutAccountPublicAccessBlock by arn:aws:sts::<jsp>:assumed-role/AWSReservedSSO_<id>/tomas
```

The security group function looks at the whole group every time, so it removed the old SSH rule too. Rules that aren't admin ports open to the world, like 443 from anywhere or 22 from a private range, are left alone, and the pytest suite checks that with moto.

The CloudTrail function didn't work the first time. I stopped the organization trail from the management account and it stayed stopped. The Lambda had run twice and failed both times with `AccessDenied` on `sts:AssumeRole`, aimed at the security account and at a workload account. Stopping an organization trail is recorded in every member account too, and the function took the account from the event instead of from the trail, so it knocked on accounts where its role doesn't exist. I restarted the trail by hand right away.

The fix reads the owner account and region from the trail ARN, so any copy of the event is enough. Second try:

```text
Remediated: restarted logging on arn:aws:cloudtrail:us-east-1:<management>:trail/sgr-org-trail, 9 seconds after arn:aws:sts::<acct>:assumed-role/AWSServiceRoleForCloudTrail/...
```
