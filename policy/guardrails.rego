# runs on `terraform show -json` of every plan, in pull requests and right before an apply
package main

# the resources the guardrails stand on; changing them is fine, removing them is not
protected := {
	"aws_accessanalyzer_analyzer": "the access analyzer",
	"aws_cloudtrail": "the organization trail",
	"aws_cloudwatch_event_rule": "an alert or remediation rule",
	"aws_config_configuration_aggregator": "the config aggregator",
	"aws_config_configuration_recorder": "a config recorder",
	"aws_config_configuration_recorder_status": "a config recorder status",
	"aws_config_delivery_channel": "a config delivery channel",
	"aws_config_organization_managed_rule": "an organization config rule",
	"aws_guardduty_detector": "a guardduty detector",
	"aws_kms_key": "a kms key",
	"aws_lambda_function": "a remediation lambda",
	"aws_organizations_policy": "a service control policy",
	"aws_organizations_policy_attachment": "a service control policy attachment",
	"aws_s3_bucket": "a log bucket",
	"aws_securityhub_account": "security hub",
	"aws_securityhub_configuration_policy_association": "the security hub policy association",
	"aws_sns_topic": "the alert topic",
	"aws_sns_topic_subscription": "the alert email subscription",
}

# a replace shows up as delete plus create; forget drops it from the state and leaves it unmanaged
removing := {"delete", "forget"}

deny contains msg if {
	some rc in input.resource_changes
	what := protected[rc.type]
	some action in rc.change.actions
	action in removing
	msg := sprintf("%s: the plan would %s %s", [rc.address, action, what])
}

deny contains msg if {
	some rc in changed("aws_cloudtrail")
	rc.change.after.enable_logging == false
	msg := sprintf("%s: the plan would stop the organization trail", [rc.address])
}

deny contains msg if {
	some rc in changed("aws_config_configuration_recorder_status")
	rc.change.after.is_enabled == false
	msg := sprintf("%s: the plan would stop a config recorder", [rc.address])
}

deny contains msg if {
	some rc in changed("aws_guardduty_detector")
	rc.change.after.enable == false
	msg := sprintf("%s: the plan would suspend guardduty", [rc.address])
}

deny contains msg if {
	some rc in changed("aws_cloudwatch_event_rule")
	rc.change.after.state == "DISABLED"
	msg := sprintf("%s: the plan would disable an alert or remediation rule", [rc.address])
}

# an scp keeps its name while a statement quietly disappears from it, so the statement ids are compared
deny contains msg if {
	some rc in changed("aws_organizations_policy")
	some sid in (statement_ids(rc.change.before) - statement_ids(rc.change.after))
	msg := sprintf("%s: the plan would remove statement %s from a service control policy", [rc.address, sid])
}

changed(type) := {rc |
	some rc in input.resource_changes
	rc.type == type
	"update" in rc.change.actions
}

statement_ids(state) := {s.Sid | some s in json.unmarshal(state.content).Statement}
