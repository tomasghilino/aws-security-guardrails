"""Revoke security group rules that open SSH or RDP, or every port, to the whole internet."""

import os

from common import account_session, notify, seconds_since

ADMIN_PORTS = (22, 3389)
WORLD = ("0.0.0.0/0", "::/0")


def is_world_admin_access(rule):
    if rule["IsEgress"] or (rule.get("CidrIpv4") or rule.get("CidrIpv6")) not in WORLD:
        return False
    if rule["IpProtocol"] == "-1":
        return True
    if rule["IpProtocol"] != "tcp":
        return False
    return any(rule["FromPort"] <= port <= rule["ToPort"] for port in ADMIN_PORTS)


def handler(event, context):
    detail = event["detail"]
    account = detail["recipientAccountId"]
    group_id = detail["requestParameters"]["groupId"]
    session = account_session(account, os.environ["REMEDIATION_ROLE"])
    ec2 = session.client("ec2", region_name=detail["awsRegion"])

    rules = ec2.describe_security_group_rules(Filters=[{"Name": "group-id", "Values": [group_id]}])[
        "SecurityGroupRules"
    ]
    open_rules = [rule for rule in rules if is_world_admin_access(rule)]
    if not open_rules:
        return {"revoked": []}

    ec2.revoke_security_group_ingress(
        GroupId=group_id, SecurityGroupRuleIds=[r["SecurityGroupRuleId"] for r in open_rules]
    )
    ports = ", ".join(
        sorted({"all" if r["IpProtocol"] == "-1" else f"{r['FromPort']}-{r['ToPort']}" for r in open_rules})
    )
    notify(
        f"Remediated: revoked internet access to ports {ports} on {group_id} in account {account}, "
        f"{seconds_since(detail['eventTime'])} seconds after {detail['userIdentity'].get('arn', 'someone')} opened it"
    )
    return {"revoked": [r["SecurityGroupRuleId"] for r in open_rules]}
