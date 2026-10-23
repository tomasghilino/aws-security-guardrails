# Threat model

This organization has four accounts: management, a security account that acts as delegated administrator for every security service, and two workload accounts from my earlier projects. What I'm protecting is less the workloads than the guardrails around them: the service control policies, the organization trail and its log archive, the Config recorders, Security Hub, GuardDuty and Access Analyzer, the alert topic, the remediation Lambdas, and the pipeline that changes all of it. If an attacker can quietly turn one of those off, everything else in this repository stops meaning much.

## Who can change what

People sign in through IAM Identity Center, and a root sign-in in any account sends an alert.

The pipeline has two identities, both in the security account and both reached through GitHub OIDC, so nothing in GitHub stores an AWS secret. A pull request gets `sgr-github-plan`, which can read the Terraform state, write its lock file and chain into `sgr-terraform-plan` in every account. Those plan roles have ReadOnlyAccess minus the actions that read data (S3 objects, secrets, parameters, log events, KMS decrypt), because a plan needs settings, not contents. A merge to dev gets `sgr-github-apply` only after I approve the production environment, which only dev can deploy to. That role chains into `sgr-terraform` in management and from there into `OrganizationAccountAccessRole` in the member accounts.

The trust policies match the immutable form of the OIDC subject, which carries the numeric ids of my user and the repository. A renamed repository, or a new one created under the old name, gets a different subject and no access. Pull requests from forks get no token at all.

Both pipeline roles, the plan roles in management and the boundary below live in the bootstrap stack. Only a person applies bootstrap, with their own SSO session, so no change that goes through the pipeline can widen the pipeline's own access.

## What I expect an attacker to try

The first threat is code in a pull request. Terraform providers and data sources run during a plan, so I treat a plan as running untrusted code. The worst it can do with the plan chain is read settings across the organization. It can't write anything except a lock file, and it can't read data.

The second is a change that looks fine in review and weakens a guardrail once merged. Every plan, in the pull request and again inside the approved apply job, goes through three checks: Checkov on the code, Conftest on the plan JSON, and IAM Access Analyzer on every policy in the plan. Conftest is the one that sees what the code alone doesn't show: a replace that hides a delete, a `removed` block that drops a resource from the state, a statement that quietly disappears from an SCP, an alert subscription pointed at another address. The demo pull request that stopped the trail and removed its SCP statement failed all of these.

The third is the pipeline escalating itself. `sgr-terraform` used to have AdministratorAccess. Now it has a policy built from what Access Advisor showed it actually used, and the IAM part is the important bit. It can only create or change roles named `sgr-*`, and only if they carry `sgr-pipeline-boundary`. That boundary denies IAM, Organizations, STS, SSO and account actions, so any role the pipeline makes is capped at service work. The role can't edit the boundary, can't touch its own roles, can't create users, and can't leave the organization or close accounts. I checked each of these with the IAM policy simulator before applying it.

The fourth is someone with admin in a member account switching things off. The baseline SCP denies stopping or changing the trail, the Config recorders, GuardDuty, Security Hub, Access Analyzer, the log buckets, the log key and the alerting and remediation resources. The only exception is `OrganizationAccountAccessRole`, the role Terraform uses. If something slips through anyway, Config and Security Hub see it, and three cases are fixed automatically within seconds: an SSH or RDP port open to the world, S3 Block Public Access turned off, and the organization trail stopped.

The fifth is tampering with the logs. The archive bucket is versioned, its policy denies writes and deletes from anyone except CloudTrail and the organization role, and CloudTrail log file validation catches edited files. I tested that one by modifying a log file and watching `validate-logs` report it.

Last, this repository is public, and so are its Actions logs. Every pipeline job masks the account ids, the account emails and the organization id before Terraform runs, and the role ARNs are secrets.

## What I accept

SCPs don't apply to the management account, and that's where the most powerful role lives. I keep management free of workloads, sign in only through SSO, alert on root sign-ins and narrowed `sgr-terraform`, but a compromise of management is still the worst case.

I write the code and I approve the deployment. In a team, the production environment would require a reviewer other than the author, with CODEOWNERS on `infra/` and `policy/`. Right now my GitHub account is effectively a key to the organization, which is the best argument for that second reviewer.

The member accounts are still changed through `OrganizationAccountAccessRole`, which is full admin. I kept it because the SCP and bucket policy exceptions are written around it. The next step would be a narrowed deploy role per account with the exceptions moved to it.

The plan I review in the pull request and the plan the apply job runs can differ if dev moved in between. The apply job checks its own plan again with Conftest and Access Analyzer before applying, but the approval comes before that plan exists.

Breaking glass is possible on purpose. Someone with the SSO admin role can still apply locally, and Conftest never sees those plans. CloudTrail records it, and the nightly drift check fails the next morning if the change isn't in the code.

Logs live in the security account rather than a separate log archive account. In production I'd split them, so the team that runs the security tools can't touch the evidence of what they did.
