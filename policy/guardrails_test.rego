package main

change(type, actions, before, after) := {"resource_changes": [{
	"address": sprintf("%s.this", [type]),
	"type": type,
	"change": {"actions": actions, "before": before, "after": after},
}]}

scp(sids) := {"content": json.marshal({"Statement": [{"Sid": sid} | some sid in sids]})}

test_deleting_an_scp_is_denied if {
	count(deny) == 1 with input as change("aws_organizations_policy", ["delete"], scp(["A"]), null)
}

test_replacing_the_trail_is_denied if {
	count(deny) == 1 with input as change("aws_cloudtrail", ["delete", "create"], {}, {})
}

test_forgetting_a_detector_is_denied if {
	count(deny) == 1 with input as change("aws_guardduty_detector", ["forget"], {}, null)
}

test_stopping_the_trail_is_denied if {
	count(deny) == 1 with input as change("aws_cloudtrail", ["update"], {"enable_logging": true}, {"enable_logging": false})
}

test_stopping_a_recorder_is_denied if {
	count(deny) == 1 with input as change("aws_config_configuration_recorder_status", ["update"], {"is_enabled": true}, {"is_enabled": false})
}

test_suspending_guardduty_is_denied if {
	count(deny) == 1 with input as change("aws_guardduty_detector", ["update"], {"enable": true}, {"enable": false})
}

test_disabling_a_rule_is_denied if {
	count(deny) == 1 with input as change("aws_cloudwatch_event_rule", ["update"], {"state": "ENABLED"}, {"state": "DISABLED"})
}

test_removing_an_scp_statement_is_denied if {
	count(deny) == 1 with input as change("aws_organizations_policy", ["update"], scp(["A", "B"]), scp(["A"]))
}

test_adding_an_scp_statement_is_allowed if {
	count(deny) == 0 with input as change("aws_organizations_policy", ["update"], scp(["A"]), scp(["A", "B"]))
}

test_rerouting_the_alert_email_is_denied if {
	count(deny) == 1 with input as change("aws_sns_topic_subscription", ["delete", "create"], {}, {})
}

test_unprotected_deletes_are_allowed if {
	count(deny) == 0 with input as change("aws_iam_role_policy", ["delete"], {}, null)
}

test_creating_guardrails_is_allowed if {
	count(deny) == 0 with input as change("aws_cloudtrail", ["create"], null, {"enable_logging": true})
}
