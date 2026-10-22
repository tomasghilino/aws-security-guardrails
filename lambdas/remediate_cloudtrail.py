"""Start logging again when someone stops a trail; the management account is the one place scps can't stop them."""

import os

from common import account_session, notify, seconds_since


def handler(event, context):
    detail = event["detail"]
    account = detail["recipientAccountId"]
    trail = detail["requestParameters"]["name"]
    session = account_session(account, os.environ["REMEDIATION_ROLE"])
    cloudtrail = session.client("cloudtrail", region_name=detail["awsRegion"])

    if cloudtrail.get_trail_status(Name=trail)["IsLogging"]:
        return {"restarted": False}

    cloudtrail.start_logging(Name=trail)
    notify(
        f"Remediated: restarted logging on {trail}, {seconds_since(detail['eventTime'])} seconds after "
        f"{detail['userIdentity'].get('arn', 'someone')} stopped it"
    )
    return {"restarted": True}
