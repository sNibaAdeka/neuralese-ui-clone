extends SceneTree





var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var TopPanelScript = load("res://scripts/top_panel.gd")
	var AIHelpScript = load("res://scripts/ai_help.gd")
	var LearnerScript = load("res://scripts/learner.gd")
	_expect_equal(
		TopPanelScript.workslist_route(false, true, false),
		TopPanelScript.WorkslistRoute.STARTUP,
		"startup navigation wins while remote auth is pending"
	)
	_expect_equal(
		TopPanelScript.workslist_route(false, false, true),
		TopPanelScript.WorkslistRoute.CLOSE_ACTIVE,
		"an open menu can be closed without remote auth"
	)
	_expect_equal(
		TopPanelScript.workslist_route(true, false, false),
		TopPanelScript.WorkslistRoute.OPEN_LOCAL,
		"local workslist never needs remote auth"
	)
	_expect_equal(
		AIHelpScript.send_route(true, false, false),
		AIHelpScript.SendRoute.STOP_RECORDING,
		"recording cleanup wins before remote auth"
	)
	_expect_equal(
		AIHelpScript.send_route(false, true, false),
		AIHelpScript.SendRoute.BUSY,
		"a transcription in flight blocks reentrant recording"
	)
	_expect_equal(
		AIHelpScript.send_route(false, false, true),
		AIHelpScript.SendRoute.STOP_STREAM,
		"existing stream cleanup wins before remote auth"
	)
	var classroom_state := {"room": "abc"}
	if LearnerScript.remote_response_allows_mutation({"ok": false}):
		classroom_state["room"] = ""
	_expect_equal(
		classroom_state["room"],
		"abc",
		"failed remote response preserves classroom state"
	)
	if LearnerScript.remote_response_allows_mutation({"ok": true}):
		classroom_state["room"] = ""
	_expect_equal(classroom_state["room"], "", "successful response commits state")
	_finish()


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])


func _finish() -> void:
	if failures.is_empty():
		print("PASS test_remote_action_behavior")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
