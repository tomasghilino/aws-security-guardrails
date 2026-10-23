import json

from validate_policies import check, policies

TRUST = json.dumps({"Version": "2012-10-17", "Statement": []})


def plan(*changes):
    return {
        "resource_changes": [
            {"address": f"{resource_type}.this", "type": resource_type, "change": {"after": after}}
            for resource_type, after in changes
        ]
    }


class FakeAnalyzer:
    """Returns the findings it was given for every policy and records what it was asked to check."""

    def __init__(self, *findings):
        self.findings = list(findings)
        self.calls = []

    def get_paginator(self, name):
        assert name == "validate_policy"
        return self

    def paginate(self, **arguments):
        self.calls.append(arguments)
        return [{"findings": self.findings}]


def finding(finding_type):
    return {"findingType": finding_type, "issueCode": "CODE", "findingDetails": "details"}


def test_trust_policies_are_checked_as_assume_role_documents():
    [(_, document, policy_type, validate_as)] = policies(plan(("aws_iam_role", {"assume_role_policy": TRUST})))

    assert (document, policy_type, validate_as) == (TRUST, "RESOURCE_POLICY", "AWS::IAM::AssumeRolePolicyDocument")


def test_only_service_control_policies_are_checked_as_scps():
    found = policies(
        plan(
            ("aws_organizations_policy", {"content": TRUST, "type": "SERVICE_CONTROL_POLICY"}),
            ("aws_organizations_policy", {"content": TRUST, "type": "TAG_POLICY"}),
        )
    )

    assert [policy_type for _, _, policy_type, _ in found] == ["SERVICE_CONTROL_POLICY"]


def test_deleted_and_unknown_policies_are_skipped():
    assert list(policies(plan(("aws_iam_role_policy", None), ("aws_kms_key", {"policy": None})))) == []


def test_errors_and_security_warnings_block():
    analyzer = FakeAnalyzer(finding("ERROR"), finding("SECURITY_WARNING"), finding("WARNING"), finding("SUGGESTION"))

    assert check(analyzer, plan(("aws_iam_role_policy", {"policy": TRUST}))) == 2


def test_resource_type_is_only_sent_when_known():
    analyzer = FakeAnalyzer()

    check(analyzer, plan(("aws_sns_topic_policy", {"policy": TRUST}), ("aws_s3_bucket_policy", {"policy": TRUST})))

    assert [call.get("validatePolicyResourceType") for call in analyzer.calls] == [None, "AWS::S3::Bucket"]
