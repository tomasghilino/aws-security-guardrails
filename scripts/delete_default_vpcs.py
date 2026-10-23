"""Delete the default VPC in every region of every account in the organization.

Runs with security account credentials and reaches the other accounts through
sgr-terraform in the management account, then OrganizationAccountAccessRole.
Without --apply it only reports what it would delete.

Already run once. sgr-terraform has since lost its ec2 delete rights in the management
account, so a rerun only cleans the member accounts there.
"""

import argparse
import sys

import boto3

MANAGEMENT_ROLE = "sgr-terraform"
MEMBER_ROLE = "OrganizationAccountAccessRole"
SESSION_NAME = "delete-default-vpcs"


def assume(session, role_arn):
    credentials = session.client("sts").assume_role(RoleArn=role_arn, RoleSessionName=SESSION_NAME)["Credentials"]
    return boto3.Session(
        aws_access_key_id=credentials["AccessKeyId"],
        aws_secret_access_key=credentials["SecretAccessKey"],
        aws_session_token=credentials["SessionToken"],
    )


def account_sessions(start):
    management_id = start.client("organizations").describe_organization()["Organization"]["MasterAccountId"]
    management = assume(start, f"arn:aws:iam::{management_id}:role/{MANAGEMENT_ROLE}")
    pages = management.client("organizations").get_paginator("list_accounts").paginate()
    for account in (a for page in pages for a in page["Accounts"]):
        if account["Status"] != "ACTIVE":
            continue
        if account["Id"] == management_id:
            yield account["Name"], management
        else:
            yield account["Name"], assume(management, f"arn:aws:iam::{account['Id']}:role/{MEMBER_ROLE}")


def enabled_regions(session):
    regions = session.client("ec2", region_name="us-east-1").describe_regions()["Regions"]
    return sorted(r["RegionName"] for r in regions)


def clean_region(ec2, apply):
    vpcs = ec2.describe_vpcs(Filters=[{"Name": "is-default", "Values": ["true"]}])["Vpcs"]
    results = []
    for vpc in vpcs:
        vpc_id = vpc["VpcId"]
        in_use = ec2.describe_network_interfaces(Filters=[{"Name": "vpc-id", "Values": [vpc_id]}])["NetworkInterfaces"]
        if in_use:
            results.append((vpc_id, f"skipped, {len(in_use)} network interfaces in use"))
            continue
        if not apply:
            results.append((vpc_id, "would delete"))
            continue
        gateways = ec2.describe_internet_gateways(Filters=[{"Name": "attachment.vpc-id", "Values": [vpc_id]}])
        for gateway in gateways["InternetGateways"]:
            ec2.detach_internet_gateway(InternetGatewayId=gateway["InternetGatewayId"], VpcId=vpc_id)
            ec2.delete_internet_gateway(InternetGatewayId=gateway["InternetGatewayId"])
        for subnet in ec2.describe_subnets(Filters=[{"Name": "vpc-id", "Values": [vpc_id]}])["Subnets"]:
            ec2.delete_subnet(SubnetId=subnet["SubnetId"])
        ec2.delete_vpc(VpcId=vpc_id)
        results.append((vpc_id, "deleted"))
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--apply", action="store_true", help="delete instead of only reporting")
    args = parser.parse_args(argv)

    skipped = 0
    for name, session in account_sessions(boto3.Session()):
        for region in enabled_regions(session):
            for vpc_id, outcome in clean_region(session.client("ec2", region_name=region), args.apply):
                print(f"{name:16} {region:16} {vpc_id:24} {outcome}")
                skipped += outcome.startswith("skipped")
    return 1 if skipped else 0


if __name__ == "__main__":
    sys.exit(main())
