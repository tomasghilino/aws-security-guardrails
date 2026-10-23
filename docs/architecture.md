# Architecture

The organization has four accounts in two organizational units. The management account holds the organization, billing and Identity Center, and nothing else. The security account, in the Security OU, is the delegated administrator for every security service and keeps the logs. The two workload accounts, in the Workloads OU, are the ones my earlier projects deployed to. Everything runs in us-east-1, which the region deny SCP enforces for the member accounts.

## Layers and state

The Terraform code is split into five stacks, each with its own state file in one S3 bucket in the security account. The bucket is versioned, encrypted with its own KMS key, refuses plain HTTP and uses S3's native lock file.

`bootstrap` creates that bucket and the pipeline's own identity: the GitHub OIDC provider, the plan and apply roles, `sgr-terraform` in the management account and its permissions boundary. It's the only stack applied by a person, with an SSO profile for each account it touches.

`org` manages the organization itself, the OUs, the delegated administrators, the SCPs and a monthly budget. The organization and the accounts were imported and carry `prevent_destroy`, because destroying the first deletes the organization and destroying the others closes accounts.

`logging` creates the organization trail in the management account, the log archive bucket and its KMS key in the security account, and the bucket Config delivers to.

`baseline` puts the same pieces in every account through modules: a Config recorder, account hardening (password policy, account-level S3 Block Public Access, EBS encryption by default, no public SSM documents), the event forwarder, the remediation roles and a read-only plan role.

`security` sets up the services in the security account: the Config aggregator and organization rules, Security Hub, GuardDuty, Access Analyzer, the alerts and the remediation Lambdas.

## How Terraform reaches each account

Every stack starts with credentials in the security account, because that's where the state lives. From there it assumes `sgr-terraform` in the management account, and from the management account it assumes `OrganizationAccountAccessRole` in a member account, the role AWS creates in every account it adds to an organization. A provider block can chain several `assume_role` blocks, so one stack manages all four accounts with one provider per account.

That chain matters for the SCPs. The statements that protect the trail, the log archive, the recorders, the security services and the alerting deny everyone except `OrganizationAccountAccessRole`. So even the SSO administrator of the security account can't touch its own log bucket, while Terraform, coming through the management account, can.

Plans use a second chain with the same shape: `sgr-terraform-plan` in the management account and in every member account, with ReadOnlyAccess minus the actions that read data. The stacks take the role names as variables, so CI switches chains without any other change.

## Prevent

Three SCPs are attached to the root: AWS's default FullAWSAccess, the region deny and the baseline. The region deny uses `NotAction` to leave out the global services that live in us-east-1 but get called from anywhere, like IAM, STS, Organizations and billing. The baseline grows one statement per guarded service, because a target can have at most five SCPs. SCPs never apply to the management account, which is why it holds no workloads.

## Detect

The organization trail logs management events from all four accounts in every region, with log file validation, to a bucket in the security account. Only CloudTrail and the organization role may write there, versioning keeps every overwritten object, and an hourly signed digest lets `validate-logs` prove a file wasn't changed.

Every account runs a Config recorder that delivers to one bucket, and an aggregator in the security account sees all of them. Five organization rules, deployed from the security account, check for SSH open to the world, public buckets, a disabled trail, KMS keys without rotation and missing `Project` or `ManagedBy` tags.

Security Hub uses central configuration from the security account: one policy on the root enables AWS Foundational Security Best Practices, CIS 3.0 and NIST 800-53 rev5 in every account, with consolidated control findings and 16 controls disabled for services I left out on purpose. GuardDuty runs foundational detection in every account with the paid protection plans off. Access Analyzer has one organization analyzer, with archive rules for the roles that are supposed to trust something outside the organization.

## Correct and alert

An API call only reaches the default event bus of the account where it happened. Each account except security has a forwarder rule that sends sign-ins, new access keys, security group ingress, S3 public access changes and `StopLogging` to the security account's bus, which accepts events from anyone in the organization. Security Hub, GuardDuty and Access Analyzer findings already arrive there because of the delegation.

Three rules on that bus start the remediation Lambdas. Each one assumes a role in the account where the change happened, and that role trusts only that Lambda's own role and can make only that one fix. The security group function revokes ingress rules that open 22, 3389 or every port to the world. The S3 function turns Block Public Access back on, but only if it ended up weaker. The CloudTrail function restarts the organization trail, reading the owner account from the trail's ARN, because stopping an organization trail is also recorded in every member account. Each function emails what it did.

Five more rules send email through an SNS topic encrypted with its own key: Security Hub critical findings, GuardDuty findings with severity 7 or more, Access Analyzer external access, root sign-ins and new IAM access keys. Input transformers turn the events into one readable sentence.

## Pipeline

`ci.yml` runs on every push: Gitleaks over the history, ruff and pytest, `terraform fmt` and `validate`, TFLint, Checkov and the Conftest unit tests. `terraform.yml` runs on pull requests and every night. It plans the four stacks in parallel with the read-only chain, then runs Conftest on the plan JSON and sends every policy in it to Access Analyzer `ValidatePolicy`. A push to `dev` runs one apply job in the `production` environment, which waits for my approval and only accepts `dev`. That job plans each stack again, runs the same checks and applies exactly the plan it checked, in order: org, logging, baseline, security. The nightly run fails if any stack has drifted from the code.
