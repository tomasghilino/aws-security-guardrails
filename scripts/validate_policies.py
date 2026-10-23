"""Check every IAM, resource and service control policy in Terraform plans with IAM Access Analyzer.

Usage: validate_policies.py plan.json [plan.json ...]

Reads the JSON from `terraform show -json`. Errors and security warnings fail the run;
warnings and suggestions are only printed.
"""

import json
import sys

import boto3

# (resource type, attribute) -> (policy type, resource type access analyzer checks it against)
POLICY_ATTRIBUTES = {
    ("aws_cloudwatch_event_bus_policy", "policy"): ("RESOURCE_POLICY", None),
    ("aws_iam_policy", "policy"): ("IDENTITY_POLICY", None),
    ("aws_iam_role", "assume_role_policy"): ("RESOURCE_POLICY", "AWS::IAM::AssumeRolePolicyDocument"),
    ("aws_iam_role_policy", "policy"): ("IDENTITY_POLICY", None),
    ("aws_kms_key", "policy"): ("RESOURCE_POLICY", None),
    ("aws_organizations_policy", "content"): ("SERVICE_CONTROL_POLICY", None),
    ("aws_s3_bucket_policy", "policy"): ("RESOURCE_POLICY", "AWS::S3::Bucket"),
    ("aws_sns_topic_policy", "policy"): ("RESOURCE_POLICY", None),
}

BLOCKING = {"ERROR", "SECURITY_WARNING"}


def policies(plan):
    """Yield (address, document, policy type, resource type) for every policy the plan leaves in place."""
    for change in plan.get("resource_changes", []):
        after = change["change"].get("after") or {}
        for (resource_type, attribute), (policy_type, validate_as) in POLICY_ATTRIBUTES.items():
            document = after.get(attribute)
            # unknown until apply shows up as a missing value; other organization policy types are not scps
            if change["type"] != resource_type or not isinstance(document, str):
                continue
            if resource_type == "aws_organizations_policy" and after.get("type") != "SERVICE_CONTROL_POLICY":
                continue
            yield change["address"], document, policy_type, validate_as


def findings(client, document, policy_type, validate_as):
    arguments = {"policyDocument": document, "policyType": policy_type}
    if validate_as:
        arguments["validatePolicyResourceType"] = validate_as
    for page in client.get_paginator("validate_policy").paginate(**arguments):
        yield from page["findings"]


def check(client, plan):
    """Print every finding and return how many block the plan."""
    blocking = 0
    for address, document, policy_type, validate_as in policies(plan):
        for finding in findings(client, document, policy_type, validate_as):
            print(f"{finding['findingType']} {address}: {finding['issueCode']}: {finding['findingDetails']}")
            blocking += finding["findingType"] in BLOCKING
    return blocking


def main(paths):
    client = boto3.client("accessanalyzer")
    checked = blocking = 0
    for path in paths:
        with open(path) as file:
            plan = json.load(file)
        checked += len(list(policies(plan)))
        blocking += check(client, plan)
    print(f"access analyzer: {checked} policies checked, {blocking} blocking findings")
    return 1 if blocking else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
