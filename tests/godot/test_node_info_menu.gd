extends SceneTree

const MENUS_SCENE := "res://scenes/menus.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(MENUS_SCENE)
	_expect(packed != null, "menus scene loads")
	if packed == null:
		_finish()
		return

	# The real menu is mounted below the project, whose catalog order is shared
	# by Add Graph and the palette. Supply that same project context here.
	var app: Node = root.get_node("glob")
	app.tree = self
	var project_context: Node = load("res://scripts/project.gd").new()
	root.add_child(project_context)

	var menus := packed.instantiate()
	menus.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(menus)
	await process_frame

	var info_menu = menus.get_node_or_null("debug_info")
	_expect(info_menu != null, "debug_info exists")
	if info_menu != null:
		_expect_equal(info_menu.get_script().resource_path, "res://scripts/node_info_menu.gd", "dedicated controller")
		_expect(info_menu.has_method("configure_for_node_id"), "configuration API")
		_expect(not info_menu.button_by_hint.has(&"bottom"), "bottom button removed")
		var ask_button = info_menu.get_ask_button() if info_menu.has_method("get_ask_button") else null
		_expect(ask_button != null, "Ask Axon button exists")
		if ask_button != null:
			_expect_equal(str(ask_button.hint), "ask_axon", "Ask Axon hint")

		if info_menu.has_method("configure_for_node_id"):
			info_menu.configure_for_node_id("input", "en")
			var input_text: String = info_menu.get_body_text()
			info_menu.configure_for_node_id("run_model", "en")
			var run_text: String = info_menu.get_body_text()
			_expect(input_text.contains("Input2D"), "Input2D content")
			_expect(run_text.contains("RunModel"), "RunModel content")
			_expect(input_text != run_text, "selected node changes content")
			_expect_equal(ask_button.text, "Ask Axon", "localized action text")

	var detached_templates: Array = []
	_collect_owned_templates(menus, detached_templates)
	_expect(not detached_templates.is_empty(), "menus own reusable detached button templates")
	menus.queue_free()
	await process_frame
	for template in detached_templates:
		_expect(not is_instance_valid(template), "freeing menus releases their detached button templates")
	app.menu_canvas = null
	app.base_node = null
	project_context.free()
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("PASS test_node_info_menu")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _collect_owned_templates(node: Node, output: Array) -> void:
	for property in node.get_property_list():
		if property.name in ["_button_template", "frozen_duplicate", "instance"]:
			var template = node.get(property.name)
			if template is Node and is_instance_valid(template) and template.get_parent() == null:
				output.append(template)
	for child in node.get_children():
		_collect_owned_templates(child, output)
