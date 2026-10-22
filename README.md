# AWS Security Guardrails

> Work in progress. This project is still being built, so expect missing pieces and changes.

This project secures a multi-account AWS Organization by preventing, detecting and correcting insecure configuration, with everything written as Terraform and Python. A dedicated security account runs the guardrails for the whole organization: service control policies block risky actions and unused regions, an organization CloudTrail and AWS Config record what happens and how resources change, and Security Hub, GuardDuty and IAM Access Analyzer will report findings. On top of that, EventBridge and Python Lambdas will alert on and automatically fix a few clear-cut problems, like a security group opened to the world on port 22 or a bucket made public, and the whole thing will be deployed by its own GitHub Actions pipeline with OIDC and policy checks on every Terraform plan.
