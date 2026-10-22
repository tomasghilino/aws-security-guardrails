"""Turn S3 Block Public Access back on, for the account or the bucket that just had it weakened."""

import os

from botocore.exceptions import ClientError

from common import account_session, notify, seconds_since

ALL_ON = {
    "BlockPublicAcls": True,
    "IgnorePublicAcls": True,
    "BlockPublicPolicy": True,
    "RestrictPublicBuckets": True,
}


def current_block(read):
    try:
        return read()["PublicAccessBlockConfiguration"]
    except ClientError as error:
        if error.response["Error"]["Code"] == "NoSuchPublicAccessBlockConfiguration":
            return {}
        raise


def handler(event, context):
    detail = event["detail"]
    account = detail["recipientAccountId"]
    session = account_session(account, os.environ["REMEDIATION_ROLE"])

    if "Account" in detail["eventName"]:
        s3control = session.client("s3control", region_name=detail["awsRegion"])
        target = f"the account-level block of account {account}"
        block = current_block(lambda: s3control.get_public_access_block(AccountId=account))
        fix = lambda: s3control.put_public_access_block(AccountId=account, PublicAccessBlockConfiguration=ALL_ON)  # noqa: E731
    else:
        bucket = detail["requestParameters"]["bucketName"]
        s3 = session.client("s3", region_name=detail["awsRegion"])
        target = f"bucket {bucket} in account {account}"
        block = current_block(lambda: s3.get_public_access_block(Bucket=bucket))
        fix = lambda: s3.put_public_access_block(Bucket=bucket, PublicAccessBlockConfiguration=ALL_ON)  # noqa: E731

    # terraform and other legitimate changes leave the block fully on, so they need nothing
    if all(block.get(setting) for setting in ALL_ON):
        return {"remediated": False}

    fix()
    notify(
        f"Remediated: turned Block Public Access back on for {target}, "
        f"{seconds_since(detail['eventTime'])} seconds after {detail['eventName']} "
        f"by {detail['userIdentity'].get('arn', 'someone')}"
    )
    return {"remediated": True}
