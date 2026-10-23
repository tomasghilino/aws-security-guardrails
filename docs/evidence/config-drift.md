# Changes made by hand, flagged by Config

I made two changes the way someone would in the console. In a workload account I created a security group with SSH open to the world and no tags. In the security account I removed the `Project` tag from a bucket Terraform manages.

About two minutes later the aggregator in the security account showed both:

```text
sgr-restricted-ssh   NON_COMPLIANT   AWS::EC2::SecurityGroup   sg-<id>
sgr-required-tags    NON_COMPLIANT   AWS::EC2::SecurityGroup   sg-<id>
sgr-required-tags    NON_COMPLIANT   AWS::S3::Bucket           sgr-config-<acct>
```

Security Hub flagged the same group under its own controls. For the tag, `terraform plan` showed the drift and an apply put it back. Config sees the change, Terraform undoes it. Later the pipeline got a nightly plan that fails when any stack drifts, so this kind of change gets noticed even if nobody looks at Config.

Getting the organization rules deployed was the harder part. The first apply hung for about 90 minutes. The rules worked in the three member accounts and failed in the management account:

```text
UnableToAssumeServiceLinkedRoleException: AWS Config can't assume the service-linked role (SLR) because this is an
organization management account and you have used a delegated administrator for organizational deployment.
```

AWS creates that role by itself everywhere except the management account when the rules come from a delegated admin, and the Terraform provider kept waiting for a success that couldn't happen. I stopped it, released the stale state lock, imported the rules that already existed, added the missing role to the baseline stack and replaced the five rules. Now I check on long applies every few minutes instead of waiting.
