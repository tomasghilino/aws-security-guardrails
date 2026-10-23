# Admin of a member account, and still told no

SCPs are the one control an account admin can't switch off, because they live in the organization, not in the account. I checked two of them from the AdministratorAccess role in a workload account.

The region deny first. Listing VPCs in Ireland:

```text
An error occurred (UnauthorizedOperation) when calling the DescribeVpcs operation:
User: arn:aws:sts::<acct>:assumed-role/AWSReservedSSO_AdministratorAccess_<id>/tomas
is not authorized to perform: ec2:DescribeVpcs with an explicit deny in a service control policy
```

The same call in us-east-1 worked, and IAM still answered through the Ireland endpoint, because global services are left out of the policy on purpose.

Leaving the organization is not something I wanted to try for real, in case the SCP didn't work. The IAM policy simulator evaluates a role's permissions together with the SCPs without running anything:

```text
organizations:LeaveOrganization   explicitDeny   AllowedByOrganizations=False
ec2:DescribeVpcs                  allowed        AllowedByOrganizations=True
```

IAM alone would allow both, since the role is an admin. The organization says no to the first one.

Before turning on the region deny I deleted the 68 default VPCs (17 regions in 4 accounts) with a script. Once the SCP was on, the script couldn't even look in those regions. The management account still could, because SCPs never apply to it, and that's the reason it holds nothing else.
