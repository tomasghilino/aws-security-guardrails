# Taking admin away from the pipeline

The management role the pipeline applies with had AdministratorAccess until the end of the project. I asked IAM Access Advisor which services it had actually used: 12 of them, from budgets to STS. The new policy covers those, with writes limited to `sgr-*` names where the service allows it.

IAM was the part that mattered, because a role that can create roles can create itself an admin. Now it can only create or edit roles named `sgr-*` that carry a permissions boundary, a policy that caps whatever a role is given. This one denies IAM, Organizations, STS and Identity Center. I ran the new policy through the IAM policy simulator before applying it:

```text
create role sgr-x with the boundary                     allowed
create role sgr-x without a boundary                    implicitDeny
create a role not named sgr-*                           implicitDeny
attach a policy to sgr-terraform itself                 explicitDeny
edit the boundary policy                                explicitDeny
create an iam user                                      implicitDeny
leave the organization                                  explicitDeny
```

The first real write with the narrowed role was the pull request that brought it: after my approval the pipeline put the boundary on the four roles it manages in the management account and applied `3 added, 7 changed, 0 destroyed`. The remediation roles still work through the boundary.

The plan roles kept ReadOnlyAccess but lost the reads that return data. Listing security groups is allowed, while reading an S3 object or a secret is an explicit deny.

Every plan also sends each policy in it to Access Analyzer's `ValidatePolicy`: 45 policies across the four stacks, including the SCPs, and no findings. An error or a security warning would fail the job.
