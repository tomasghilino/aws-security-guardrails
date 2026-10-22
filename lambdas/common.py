"""Shared helpers: reach the account where the change happened and report what was done."""

import os
from datetime import datetime, timezone

import boto3


def account_session(account_id, role_name):
    credentials = boto3.client("sts").assume_role(
        RoleArn=f"arn:aws:iam::{account_id}:role/{role_name}",
        RoleSessionName="sgr-remediation",
    )["Credentials"]
    return boto3.Session(
        aws_access_key_id=credentials["AccessKeyId"],
        aws_secret_access_key=credentials["SecretAccessKey"],
        aws_session_token=credentials["SessionToken"],
    )


def seconds_since(event_time):
    started = datetime.fromisoformat(event_time.replace("Z", "+00:00"))
    return round((datetime.now(timezone.utc) - started).total_seconds())


def notify(message):
    print(message)
    boto3.client("sns").publish(TopicArn=os.environ["ALERTS_TOPIC_ARN"], Message=message)
