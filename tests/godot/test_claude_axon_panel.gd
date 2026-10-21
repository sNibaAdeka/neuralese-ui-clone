extends SceneTree
## Local selection, documentation and geometry checks. No requests are sent.

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app = root.get_node("glob")
	var manager = root.get_node("graphs")
	app.tree = self
	app.curr_window = "graph"
	root.content_scale_factor = 1.0
	root.size = Vector2i(1440, 900)
	var panel = load("res://scripts/claude_axon_panel.gd").new()
	root.add_child(panel)
	await _settle()
	panel.layout_for_workspace(80)
	_expect_font_weight(panel.theme.default_font, 600)
	_expect_font_weight(panel._bold_font, 700)
	_expect_font_weight(panel._strong_font, 800)
	_expect(panel.visible, "dock opens on graph workspace")
	_expect(panel.get_reserved_width() > 300, "desktop reserves right dock width")
	_expect(panel._info.is_empty(), "no invented selected node")
	_expect("без входа" in panel.explain_button.tooltip_text, "local explanation advertises no-login contract before activation")
	_expect("Онлайн" in panel.next_button.tooltip_text and "вход" in panel.quiz_button.tooltip_text, "online actions disclose login before activation")
	_expect("отдельном диалоге" in panel.question.tooltip_text, "composer discloses answer destination before submit")
	_expect(panel.mascot.self_modulate.r > 1.0 and panel.mascot.self_modulate.r <= 1.1, "mascot has a subtle display-only brightness gain")
	_expect(panel.mascot.SEQUENCES.blink == [1, 2, 3, 0] and is_equal_approx(panel.mascot._timer.wait_time, 0.12), "brightness change preserves cel sequence and timing")
	_expect(not panel.explanation.visible, "no invented explanation")
	panel.mascot.react("blink")
	_expect(panel.mascot.frame_index == 1, "mascot starts an event-driven cel reaction")
	await create_timer(0.8).timeout
	_expect(panel.mascot.frame_index == 0, "reaction returns to rest in under a second")
	await create_timer(0.4).timeout
	_expect(panel.mascot.frame_index == 0 and panel.mascot._timer.is_stopped(), "idle mascot does not restart its animation")
	panel.mascot.reactions_enabled = false
	panel.mascot.react("wave")
	_expect(panel.mascot.frame_index == 0, "disabled motion keeps the resting cel")
	panel.mascot.reactions_enabled = true
	panel.explain_button.pressed.emit()
	_expect(not panel.explanation.visible and "Выбери" in panel.state_label.text, "empty selection gives actionable guidance")
	var node = load("res://scripts/base_graph.gd").new()
	node.set_meta("created_with", "layer")
	manager.selected_nodes[node] = true
	panel._sync_context()
	_expect(not panel.explain_button.disabled, "real selected node enables documentation")
	if app.get_lang() == "ru":
		_expect("Плотный слой" in panel.context_label.text, "selected Dense has a natural Russian title")
	panel.explain_button.pressed.emit()
	_expect(panel.explanation.visible, "explanation opens")
	_expect(not panel.state_label.visible, "local help does not repeat its no-login subtitle in the narrow footer")
	var design = load("res://scripts/claude_design_theme.gd")
	_expect(panel.question.get_theme_font_size("font_size") == design.UI_FONT_SIZE, "composer uses shared body typography")
	var send_style: StyleBoxFlat = panel.send_button.get_theme_stylebox("normal")
	_expect(send_style.corner_radius_top_left == design.CONTROL_RADIUS, "send button uses the shared control radius")
	panel.question.text = "Сохранить этот черновик"
	panel._busy = true
	panel._sync_actions()
	_expect(panel.send_button.disabled and not panel.question.editable, "busy question cannot be submitted twice")
	_expect(panel.explain_button.get_node("Contents").modulate.a < 1, "busy action visibly dims its custom child content")
	panel._send_question("Второй запрос")
	_expect(panel.question.text == "Сохранить этот черновик", "busy submit cannot replace the pending draft")
	panel._busy = false
	panel._sync_actions()
	_expect(panel.explain_button.get_node("Contents").modulate.a == 1, "action child content returns to normal after busy state")
	panel._open_profile()
	_expect(panel.state_label.get_theme_color("font_color") == design.DANGER and panel.question.text == "Сохранить этот черновик", "failed dialog is distinct and preserves the draft")
	panel._show_status("Можно повторить")
	_expect(panel.state_label.get_theme_color("font_color") == design.INK_SECONDARY, "ordinary status restores its semantic color after an error")
	_expect(panel.explanation.text.contains(str(panel._info.summary)), "explanation uses bundled catalog text")
	_expect(not panel.explanation.text.contains("Шаг 3 из 4"), "no fake lesson progress")
	_expect(not panel.next_button.disabled and not panel.quiz_button.disabled, "question actions remain actionable before login")
	if not app.remote_session_ready():
		panel.quiz_button.pressed.emit()
		_expect(panel.login_button.visible and panel.state_label.visible, "question without a session explains the login step")
		_expect("Плотный слой" in panel.question.text or not panel.question.text.is_empty(), "question is retained as a draft without sending")
		_expect(not panel.send_button.disabled, "draft can resume through the existing login guidance")
		var draft: String = panel.question.text
		panel.close_panel()
		panel.open_panel()
		_expect(panel.question.text == draft, "closing and reopening keeps the login draft")
		panel._send_question(draft)
		_expect(panel.question.text == draft and not panel._busy, "login retry keeps the draft without a fake response")
	for width in [375, 768, 1024, 1440]:
		root.size = Vector2i(width, 900)
		await _settle()
		panel.layout_for_workspace(80)
		await _settle()
		if width < 1000:
			_expect(not panel.visible and not panel.is_overlay_open(), "desktop-open dock does not cover mobile canvas at %d" % width)
			panel.toggle_panel()
			await _settle()
			_expect(panel.visible and panel.is_overlay_open(), "explicit toggle opens mobile overlay at %d" % width)
			_expect(not panel.explain_button.disabled, "mobile overlay retains actual selected node context")
		else:
			_expect(panel.visible and not panel.is_overlay_open(), "return to desktop restores dock preference at %d" % width)
			var geometry = load("res://scripts/claude_workspace_geometry.gd")
			var margin: float = geometry.horizontal_margin(width)
			var canvas: Rect2 = geometry.graph_rect(Vector2(width, 900), Vector2(0, 80), Vector2(width - panel.get_reserved_width(), 900))
			_expect(is_equal_approx(panel.size.x, 377.0), "desktop panel follows reference width at %d" % width)
			_expect(is_equal_approx(panel.get_global_rect().end.x, width - margin), "panel aligns with workspace right margin at %d" % width)
			_expect(is_equal_approx(panel.position.x - canvas.end.x, 13.0), "canvas and panel keep reference 13px gap at %d" % width)
		_expect(panel.position.x >= 0 and panel.get_global_rect().end.x <= width + 1, "panel fits viewport %d" % width)
		_expect(panel.size.y <= 900 - panel.position.y, "panel fits height %d" % width)
		_expect(panel.get_reserved_width() == 0 if width < 1000 else panel.get_reserved_width() > 0, "overlay only on narrow viewport %d" % width)
		_expect(panel.send_button.size.x >= 44 and panel.send_button.size.y >= 44, "send target remains accessible %d" % width)
		if width < 1000:
			panel.toggle_panel()
			_expect(not panel.visible and not panel.is_overlay_open(), "toggle closes mobile overlay at %d" % width)
			_expect(panel.is_open, "mobile close preserves desktop dock preference")
	panel.close_panel()
	_expect(not panel.visible and panel.get_reserved_width() == 0, "close releases reserved canvas")
	panel.open_panel()
	app.curr_window = "ds"
	panel._update_visibility()
	_expect(not panel.visible and panel.get_reserved_width() == 0, "datasets do not inherit graph assistant dock")
	app.curr_window = "graph"
	panel._update_visibility()
	_expect(panel.visible, "returning to graph restores open state")
	manager.selected_nodes.erase(node)
	node.free()
	panel._sync_context()
	_expect(panel._info.is_empty() and not panel.explanation.visible, "deleted selection clears documentation")
	panel.queue_free()
	await _settle()
	if failures.is_empty():
		print("PASS test_claude_axon_panel")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _settle() -> void:
	for frame in range(5):
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)


func _expect_font_weight(font: Font, expected: int) -> void:
	var rids: Array[RID] = font.get_rids()
	_expect(not rids.is_empty(), "Nunito reaches the text renderer")
	if rids.is_empty():
		return
	var coordinates: Dictionary = TextServerManager.get_primary_interface().font_get_variation_coordinates(rids[0])
	var actual := int(coordinates.get(0x77676874, -1))
	print("AXON_FONT expected=%d actual=%d" % [expected, actual])
	_expect(actual == expected, "text renderer receives Nunito weight %d" % expected)
