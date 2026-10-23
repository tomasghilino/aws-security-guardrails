# Alerts that read like a sentence

Five kinds of events send me an email: Security Hub critical findings, GuardDuty findings with severity 7 or more, resources shared outside the organization, root sign-ins and new IAM access keys. To test them I created an access key for a throwaway user in a workload account, deactivated it right away, and generated GuardDuty sample findings in two accounts. The mails came a minute later:

```text
"Access key created for IAM user sgr-demo-alert-user in account <jsp> by arn:aws:sts::<jsp>:assumed-role/AWSReservedSSO_AdministratorAccess_<id>/tomas at 2026-10-22T21:42:59Z"
"GuardDuty severity 8 in account <segp>: Backdoor:EC2/C&CActivity.B!DNS"
"GuardDuty severity 8 in account <security>: Backdoor:EC2/C&CActivity.B!DNS"
```

The first mail actually said `Access key created for IAM user <user>...`. Terraform's `jsonencode` escapes angle brackets, so EventBridge never saw its placeholders. The template is a plain quoted string now.

For external access I shared a demo bucket with an account outside the organization. My first try used AWS's own load balancer account and Access Analyzer didn't flag it, since it trusts AWS service accounts. An ordinary outside account worked. The analyzer also flagged four roles I hadn't thought about: the Identity Center roles, which trust its SAML provider, and my previous project's GitHub OIDC role. Those are expected, so they have archive rules.

Two more surprises. The first GuardDuty sample in one account didn't alert, because I made it a minute after the account joined and delivery to the admin account wasn't in place yet. And GuardDuty's organization auto-enable only covered new accounts, so the existing ones are enrolled explicitly in Terraform.

Hours after the remediation demo, a Security Hub critical mail arrived about that same security group. It had no open rules by then. Security Hub had processed an old evaluation late, and marked the finding resolved again shortly after.
