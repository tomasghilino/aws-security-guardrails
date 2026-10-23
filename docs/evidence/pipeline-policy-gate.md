# A pull request that weakens a guardrail

The pipeline plans every stack on each pull request and checks the plan with Conftest, a policy engine that reads the plan as JSON. To test it I opened a pull request that stopped the organization trail and deleted the `ProtectCloudTrail` statement from the baseline SCP. Both plans failed:

```text
FAIL - infra/org/plan.json - main - aws_organizations_policy.baseline: the plan would remove statement ProtectCloudTrail from a service control policy
FAIL - infra/logging/plan.json - main - aws_cloudtrail.organization: the plan would stop the organization trail
```

Checkov caught the stopped trail too, in the static job. It didn't catch the missing statement, and it couldn't: the code is still a valid SCP. What changed is only visible by comparing the policy before and after, which is what the plan has and the code doesn't. The same goes for a replace that hides a delete, or a `removed` block that drops a guardrail from the state without destroying it. The rules for those are in `policy/`, with unit tests that run in CI.

The plans run with a read-only role chain, so a pull request can never change anything, even if its code tries to. When I merged the pipeline itself, the apply job waited for my approval in the `production` environment, then planned, checked and applied the four stacks in order:

```text
No changes. Your infrastructure matches the configuration.
6 tests, 6 passed, 0 warnings, 0 failures, 0 exceptions
```

The repository is public, so its Actions logs are too. Every job masks the account IDs, account emails and the organization ID before Terraform runs. I scanned the full logs of the first runs and found none of them, and no role IDs either.
