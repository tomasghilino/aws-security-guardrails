# Deployment guide

How to build this from an empty organization, how changes flow once it's running, and how I tore it all down. The commands assume Git Bash or another POSIX shell at the repository root, Terraform 1.16, the AWS CLI, the GitHub CLI and Docker for the local checks.

## What you need first

An AWS Organization with all features on, IAM Identity Center, and at least three accounts besides management: one called `security` and the workload accounts. I sign in with one `aws sso login` and use one CLI profile per account (`management`, `security`, `segp`, `jsp`). Every command passes its profile explicitly, so nothing runs against the wrong account by accident.

The organization, the OUs and the accounts are imported, not created, so the account names in `infra/org/main.tf` must match yours. The alert email never goes in Git: it lives in `terraform.tfvars` inside `infra/org` and `infra/security`, which are ignored.

## First build

Every stack starts with security account credentials and reaches the other accounts through the management account, as described in the [architecture](architecture.md).

```bash
cd infra/bootstrap
AWS_PROFILE=security TF_VAR_management_profile=management terraform init
AWS_PROFILE=security TF_VAR_management_profile=management terraform apply
```

Bootstrap starts with local state. After the first apply, the backend block points at the new bucket and `terraform init -migrate-state` moves the state there. Bootstrap stays the only stack run with a profile per account, and it's the one that holds the pipeline's roles.

Then the other four, in this order, each with `AWS_PROFILE=security terraform apply`: `org`, `logging`, `baseline`, `security`. The order matters because `logging` needs the delegated admins from `org`, `baseline` needs the Config bucket from `logging`, and `security` reads outputs from `org`.

Two things AWS does differently in the management account bit me here. When a delegated administrator deploys Config organization rules or an organization Access Analyzer, AWS doesn't create the service-linked roles they need in the management account, so `baseline` creates them. And delegating GuardDuty or Security Hub turns them on in the security account, so `security` imports them instead of creating them.

## The pipeline

The repository needs five secrets: `AWS_PLAN_ROLE_ARN`, `AWS_PLAN_ROLE_ID` and `ALERT_EMAIL` for the repository, and `AWS_APPLY_ROLE_ARN` and `AWS_APPLY_ROLE_ID` in an environment called `production`. That environment needs me as a required reviewer and only allows the `dev` branch. The role ids are secrets only so that GitHub masks them in the public logs.

From then on a change is a pull request. CI runs the static checks, and the terraform workflow plans the four stacks with the read-only roles, checks every plan with Conftest and Access Analyzer, and prints a summary per stack. Merging to `dev` starts the apply job, which waits for my approval. Bootstrap never goes through the pipeline.

Locally, the same checks run like this:

```bash
pip install -r requirements-dev.txt
pytest && ruff check .
docker run --rm -v "$PWD:/work" -w /work openpolicyagent/conftest:v0.71.1 verify --policy policy
```

## Tearing it down

The guardrails are built to stop exactly what a teardown does, so taking them apart needs a few switches and the right order. I did it on October 23, 2026, all with `AWS_PROFILE=security`:

1. `TF_VAR_teardown=true` on bootstrap gives `sgr-terraform` AdministratorAccess back, because its own policy can't delete trails, detectors or budgets.
2. `TF_VAR_teardown=true` on `security` turns Security Hub off in every member account through the central policy, and stops GuardDuty from enrolling accounts. Destroying the stack alone would leave Security Hub on, and billing, in the workload accounts, and GuardDuty refuses to remove members while it auto-enrolls them.
3. Destroy the GuardDuty and Security Hub delegated admins in `org` with `-target`, then destroy `security`. While the security account is their delegated administrator, AWS won't remove members or turn Security Hub off there. Then delete the GuardDuty detectors left in the workload accounts, which GuardDuty created there by itself.
4. In `baseline`, remove the hardening modules from the state with `terraform state rm`, because those settings cost nothing and are worth keeping. Then destroy. The Config multi-account service-linked role in the management account can't be deleted while the organization still trusts that service, so it gets the same `state rm` and stays.
5. Empty the two buckets in `logging`, remove its `prevent_destroy` lines locally, and destroy.
6. In `org`, remove the organization, the accounts and the OUs from the state, so Terraform forgets them instead of deleting them. Then destroy, which takes the SCPs, the delegated admins and the budget.
7. Bootstrap last: move its state back to local, empty the state bucket, remove `prevent_destroy` locally, and destroy.

The KMS keys wait seven days before AWS deletes them, and keys pending deletion don't bill.
