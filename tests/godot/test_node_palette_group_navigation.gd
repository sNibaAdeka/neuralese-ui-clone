extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	root.content_scale_factor = 1.0
	var app = root.get_node("glob")
	app.tree = self
	var project = load("res://scenes/project.tscn").instantiate()
	root.add_child(project)
	await _frames(5)
	var palette = project.get_node("WIN_GRAPH/NodePalette")
	var picker: OptionButton = palette.category_selector
	_expect(picker.item_count == 6, "six visible semantic categories")
	_expect(palette.search_button.text == "Все узлы" and palette.search_button.icon == null, "all nodes has an explicit text label instead of ellipsis")
	_expect(palette.is_in_group("tutorial_node_palette_anchor") and palette.panel.get_meta("tutorial_target_id") == "node_palette", "tutorial palette targets remain stable")
	var expected: Array[StringName] = palette.entry_type_ids()
	var reachable: Array[StringName] = []
	for index in picker.item_count:
		picker.select(index)
		picker.item_selected.emit(index)
		await _frames(2)
		_expect(not palette._search_open and not palette.search_header.visible, "category selection stays compact")
		for group in palette.items.get_children():
			for card in group.get_node("Cards").get_children():
				_expect(card.custom_minimum_size.y >= 44, "node creation target retains minimum hit height")
				if not card.disabled:
					reachable.append(card.type_id)
	_expect(_same_ids(reachable, expected), "category selection reaches every available creation ID exactly once")
	for width in [375, 768, 1440]:
		root.size = Vector2i(width, 900)
		palette._on_viewport_size_changed()
		await _frames(4)
		var bounds: Rect2 = palette.panel.get_global_rect()
		_expect(bounds.position.x >= 0 and bounds.end.x <= width + 1, "palette fits viewport %s" % width)
		_expect(bounds.end.y <= 901 and bounds.size.y <= 161, "collapsed search dock remains compact at %s" % width)
		for control in [picker, palette.search_button, palette.collapse_button]:
			_expect(bounds.encloses(control.get_global_rect()), "all category controls fit viewport %s" % width)
			_expect(control.size.y >= 44, "native category/search/collapse targets retain44px height")
		palette.search_button.pressed.emit()
		await _frames(3)
		_expect(palette._search_open and palette.search_header.visible, "labelled all nodes opens search at %s" % width)
		_expect(palette.search.size.y >= 44, "search retains44px height")
		palette.search.text = "flatten"
		palette._on_search_changed("flatten")
		await _frames(2)
		_expect(_rendered_ids(palette.items) == [&"flatten"], "search crosses current selected category")
		palette.search_button.pressed.emit()
		await _frames(2)
		_expect(not palette._search_open and palette.search.text.is_empty(), "all nodes returns to selected category")
		_expect(palette._selected_category == &"training", "search preserves explicit group selection")
	picker.select(3)
	picker.item_selected.emit(3)
	await _frames(2)
	var first_card = palette.items.get_child(0).get_node("Cards").get_child(0)
	var activated := [0]
	first_card.activated.connect(func(_id): activated[0] += 1)
	first_card.grab_focus()
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	first_card._gui_input(event)
	_expect(activated[0] == 1, "keyboard activation remains connected")
	first_card.force_drag({"kind": &"neuralese_node_palette", "type_id": first_card.type_id}, null)
	_expect(first_card._get_drag_data(Vector2.ZERO).type_id == first_card.type_id, "drag payload preserves exact creation ID")
	root.gui_cancel_drag()
	palette.set_collapsed(true, false)
	_expect(palette.reopen_button.visible and not palette.panel.visible, "palette can still collapse")
	palette.reopen_button.pressed.emit()
	await _frames(15)
	_expect(not palette._collapsed, "reopen control remains connected")
	app.undo_redo.clear_history()
	project.queue_free()
	await _frames(3)
	if failures.is_empty():
		print("PASS test_node_palette_group_navigation")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _frames(count: int) -> void:
	for index in count:
		await process_frame

func _rendered_ids(items: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for group in items.get_children():
		var cards = group.get_node_or_null("Cards")
		if cards:
			for card in cards.get_children():
				ids.append(card.type_id)
	return ids

func _same_ids(a: Array, b: Array) -> bool:
	var left := a.duplicate()
	var right := b.duplicate()
	left.sort()
	right.sort()
	return left == right

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
