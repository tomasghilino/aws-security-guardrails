"""Start logging again when someone stops a trail; the management account is the one place scps can't stop them."""

import os

from common import account_session, notify, seconds_since


def trail_home(detail):
    trail = detail["requestParameters"]["name"]
    if trail.startswith("arn:"):
        _, _, _, region, account, _ = trail.split(":", 5)
        return trail, account, region
    return trail, detail["recipientAccountId"], detail["awsRegion"]


def handler(event, context):
    detail = event["detail"]
    # every member account also records the stop of an organization trail, so the trail arn, not the
    # account that reported the event, says where the trail lives
    trail, account, region = trail_home(detail)
    session = account_session(account, os.environ["REMEDIATION_ROLE"])
    cloudtrail = session.client("cloudtrail", region_name=region)

    if cloudtrail.get_trail_status(Name=trail)["IsLogging"]:
        return {"restarted": False}

    cloudtrail.start_logging(Name=trail)
    notify(
        f"Remediated: restarted logging on {trail}, {seconds_since(detail['eventTime'])} seconds after "
        f"{detail['userIdentity'].get('arn', 'someone')} stopped it"
    )
    return {"restarted": True}
