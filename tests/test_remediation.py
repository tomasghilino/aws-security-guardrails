from datetime import datetime, timezone

import boto3
import pytest
from moto import mock_aws

import remediate_cloudtrail
import remediate_s3_public_access
import remediate_security_group

ACCOUNT = "123456789012"


def cloudtrail_event(event_name, **request):
    return {
        "detail": {
            "eventName": event_name,
            "eventTime": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "awsRegion": "us-east-1",
            "recipientAccountId": ACCOUNT,
            "userIdentity": {"arn": "arn:aws:sts::123456789012:assumed-role/admin/someone"},
            "requestParameters": request,
        }
    }


@pytest.fixture
def notified(monkeypatch):
    messages = []
    for module in (remediate_security_group, remediate_s3_public_access, remediate_cloudtrail):
        monkeypatch.setattr(module, "account_session", lambda account, role: boto3.Session(region_name="us-east-1"))
        monkeypatch.setattr(module, "notify", messages.append)
    monkeypatch.setenv("REMEDIATION_ROLE", "sgr-remediate")
    with mock_aws():
        yield messages


def security_group(ec2):
    vpc = ec2.create_vpc(CidrBlock="10.0.0.0/16")["Vpc"]["VpcId"]
    return ec2.create_security_group(GroupName="demo", Description="demo", VpcId=vpc)["GroupId"]


def ingress(ec2, group, port, cidr, protocol="tcp"):
    rule = {"IpProtocol": protocol, "IpRanges": [{"CidrIp": cidr}]}
    if protocol != "-1":
        rule.update(FromPort=port, ToPort=port)
    ec2.authorize_security_group_ingress(GroupId=group, IpPermissions=[rule])


def ingress_rules(ec2, group):
    rules = ec2.describe_security_group_rules(Filters=[{"Name": "group-id", "Values": [group]}])["SecurityGroupRules"]
    return sorted((r["IpProtocol"], r.get("FromPort"), r.get("CidrIpv4")) for r in rules if not r["IsEgress"])


@pytest.mark.parametrize(
    ("port", "protocol"),
    [(22, "tcp"), (3389, "tcp"), (None, "-1")],
)
def test_world_open_admin_access_is_revoked(notified, port, protocol):
    ec2 = boto3.client("ec2", region_name="us-east-1")
    group = security_group(ec2)
    ingress(ec2, group, port, "0.0.0.0/0", protocol)

    result = remediate_security_group.handler(cloudtrail_event("AuthorizeSecurityGroupIngress", groupId=group), None)

    assert len(result["revoked"]) == 1
    assert ingress_rules(ec2, group) == []
    assert group in notified[0]


def test_other_rules_are_left_alone(notified):
    ec2 = boto3.client("ec2", region_name="us-east-1")
    group = security_group(ec2)
    ingress(ec2, group, 443, "0.0.0.0/0")
    ingress(ec2, group, 22, "10.0.0.0/8")

    result = remediate_security_group.handler(cloudtrail_event("AuthorizeSecurityGroupIngress", groupId=group), None)

    assert result == {"revoked": []}
    assert ingress_rules(ec2, group) == [("tcp", 22, "10.0.0.0/8"), ("tcp", 443, "0.0.0.0/0")]
    assert notified == []


def test_weakened_bucket_block_is_turned_back_on(notified):
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket="demo")
    s3.put_public_access_block(
        Bucket="demo",
        PublicAccessBlockConfiguration={**remediate_s3_public_access.ALL_ON, "BlockPublicPolicy": False},
    )

    result = remediate_s3_public_access.handler(cloudtrail_event("PutBucketPublicAccessBlock", bucketName="demo"), None)

    assert result == {"remediated": True}
    assert (
        s3.get_public_access_block(Bucket="demo")["PublicAccessBlockConfiguration"] == remediate_s3_public_access.ALL_ON
    )
    assert "demo" in notified[0]


def test_deleted_account_block_is_put_back(notified):
    s3control = boto3.client("s3control", region_name="us-east-1")

    result = remediate_s3_public_access.handler(cloudtrail_event("DeleteAccountPublicAccessBlock"), None)

    assert result == {"remediated": True}
    block = s3control.get_public_access_block(AccountId=ACCOUNT)["PublicAccessBlockConfiguration"]
    assert block == remediate_s3_public_access.ALL_ON


def test_a_block_that_is_already_on_is_not_touched(notified):
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket="demo")
    s3.put_public_access_block(Bucket="demo", PublicAccessBlockConfiguration=remediate_s3_public_access.ALL_ON)

    result = remediate_s3_public_access.handler(cloudtrail_event("PutBucketPolicy", bucketName="demo"), None)

    assert result == {"remediated": False}
    assert notified == []


def trail(cloudtrail, s3):
    s3.create_bucket(Bucket="trail-logs")
    cloudtrail.create_trail(Name="org-trail", S3BucketName="trail-logs")
    cloudtrail.start_logging(Name="org-trail")


def test_stopped_trail_is_restarted(notified):
    cloudtrail = boto3.client("cloudtrail", region_name="us-east-1")
    trail(cloudtrail, boto3.client("s3", region_name="us-east-1"))
    cloudtrail.stop_logging(Name="org-trail")

    result = remediate_cloudtrail.handler(cloudtrail_event("StopLogging", name="org-trail"), None)

    assert result == {"restarted": True}
    assert cloudtrail.get_trail_status(Name="org-trail")["IsLogging"] is True
    assert "org-trail" in notified[0]


def test_a_running_trail_is_left_alone(notified):
    cloudtrail = boto3.client("cloudtrail", region_name="us-east-1")
    trail(cloudtrail, boto3.client("s3", region_name="us-east-1"))

    assert remediate_cloudtrail.handler(cloudtrail_event("StopLogging", name="org-trail"), None) == {"restarted": False}
    assert notified == []


def test_a_member_copy_of_the_event_reaches_the_account_that_owns_the_trail(notified, monkeypatch):
    reached = []
    monkeypatch.setattr(
        remediate_cloudtrail,
        "account_session",
        lambda account, role: reached.append(account) or boto3.Session(region_name="us-east-1"),
    )
    cloudtrail = boto3.client("cloudtrail", region_name="us-east-1")
    trail(cloudtrail, boto3.client("s3", region_name="us-east-1"))
    cloudtrail.stop_logging(Name="org-trail")
    event = cloudtrail_event("StopLogging", name=f"arn:aws:cloudtrail:us-east-1:{ACCOUNT}:trail/org-trail")
    event["detail"]["recipientAccountId"] = "222222222222"

    result = remediate_cloudtrail.handler(event, None)

    assert reached == [ACCOUNT]
    assert result == {"restarted": True}
