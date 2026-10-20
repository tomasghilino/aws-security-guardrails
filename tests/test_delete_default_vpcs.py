import boto3
import pytest
from moto import mock_aws

from delete_default_vpcs import clean_region


@pytest.fixture
def ec2():
    with mock_aws():
        yield boto3.client("ec2", region_name="eu-west-1")


def default_vpc_ids(ec2):
    return [v["VpcId"] for v in ec2.describe_vpcs(Filters=[{"Name": "is-default", "Values": ["true"]}])["Vpcs"]]


def test_dry_run_deletes_nothing(ec2):
    [vpc_id] = default_vpc_ids(ec2)

    assert clean_region(ec2, apply=False) == [(vpc_id, "would delete")]
    assert default_vpc_ids(ec2) == [vpc_id]


def test_apply_deletes_vpc_with_its_gateway_and_subnets(ec2):
    [vpc_id] = default_vpc_ids(ec2)

    assert clean_region(ec2, apply=True) == [(vpc_id, "deleted")]
    assert default_vpc_ids(ec2) == []
    assert ec2.describe_subnets(Filters=[{"Name": "vpc-id", "Values": [vpc_id]}])["Subnets"] == []
    assert (
        ec2.describe_internet_gateways(Filters=[{"Name": "attachment.vpc-id", "Values": [vpc_id]}])["InternetGateways"]
        == []
    )


def test_vpc_in_use_is_left_alone(ec2):
    [vpc_id] = default_vpc_ids(ec2)
    subnet_id = ec2.describe_subnets(Filters=[{"Name": "vpc-id", "Values": [vpc_id]}])["Subnets"][0]["SubnetId"]
    ec2.create_network_interface(SubnetId=subnet_id)

    assert clean_region(ec2, apply=True) == [(vpc_id, "skipped, 1 network interfaces in use")]
    assert default_vpc_ids(ec2) == [vpc_id]


def test_other_vpcs_are_never_touched(ec2):
    custom = ec2.create_vpc(CidrBlock="10.0.0.0/16")["Vpc"]["VpcId"]

    clean_region(ec2, apply=True)

    assert [v["VpcId"] for v in ec2.describe_vpcs()["Vpcs"]] == [custom]
