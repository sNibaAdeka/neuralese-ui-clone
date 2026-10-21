extends Graph

const Card = preload("res://scripts/claude_training_card.gd")
var _preview_hint: Label
var _preview_count: Label
var _preview_images: Array[TextureRect] = []

func _can_drag() -> bool:
#	print(run)
	return not run.is_mouse_inside()

func _llm_map(pack: Dictionary):
	if not pack: return
	var old = pack["dataset_name"]
	pack.erase("dataset_name")
	pack["name"] = old
	if len(base_config) == 1:
		update_config({base_config.keys()[0]: pack.values()[0]})
		if pack.values()[0] is Dictionary:
			update_config_subfield({base_config.keys()[0]: pack.values()[0]})
	else:
		update_config(pack)
		for f in pack:
			if pack[f] is Dictionary:
				update_config_subfield({f: pack[f]})

func _config_field(field: StringName, value: Variant):
	_refresh_reference_preview.call_deferred()
	#(llm_mapping)
	if field == "name":
		#(value)
		if not value:
			#("B")
			(func():
			#	print("A")
				await get_tree().process_frame
				await get_tree().process_frame
				await get_tree().process_frame
				output_key_by_conn.keys()[0].disconnect_all()).call()
		if value and glob.load_dataset(value).size() == 0:
			update_config({"name": ""})
			return
		if not upd:
			if not value: value = "[none]"
			$LabelAutoResize.text = value
			$LabelAutoResize.resize()
		if llm_mapping and value:
			await get_tree().process_frame
			#(glob.dataset_datas.keys())
			var loaded = glob.load_dataset(value)
			if "fail" in loaded: 
				unpush_meta()
				output_key_by_conn.keys()[0].disconnect_all()
			else:push_meta(loaded)
	if field == "meta":
	#	print(glob.dataset_datas.keys())
		#if value == ""
		var loaded = glob.load_dataset(cfg["name"])
		if "fail" in loaded: unpush_meta()
		else:push_meta(loaded)

var upd: bool = false

func _ready() -> void:
	super()
	_setup_reference_card()
	glob.ds_invalid.connect(func(who: String):
		if who == cfg["name"] and get_first_descendants():
			update_config({"name": cfg["name"], "meta": ""})
			unpush_meta()
			output_key_by_conn.keys()[0].disconnect_all()
			)
	glob.ds_change.connect(func(who: String):
		#("aa ", who, " ", cfg['name'])
		if who == cfg["name"]:
			push_meta(glob.previewed.get(who))
			)
			

func _is_suitable_conn(who: Connection, other: Connection) -> bool:
	var loaded = glob.load_dataset(cfg["name"])
	#(loaded)
	return not "fail" in loaded

func _on_line_edit_changed() -> void:
	upd = true
	open_undo_redo()
	update_config({"name": $LineEdit.text})
	close_undo_redo()
	upd = false

func _just_connected(who: Connection, to: Connection):
	push_meta(saved_meta)

var saved_meta: Dictionary = {}

func push_meta(meta: Dictionary):
	_refresh_reference_preview.call_deferred()
	saved_meta = meta
	#(meta)
	#(saved_meta)
	saved_meta.merge({"name": "", "outputs": [], "inputs": {}}, false)
	#(saved_meta)
	for i in get_first_descendants():
		i.set_dataset_meta(saved_meta)

func unpush_meta():
	for i in get_first_descendants():
		i.set_dataset_meta({"name": "", "outputs": [], "inputs": {}})

func _just_disconnected(who: Connection, to: Connection):
	to.parent_graph.set_dataset_meta({"name": "", "outputs": []})

@onready var run = $run
func _on_run_released() -> void:
	run.block_input()
	if is_instance_valid(_preview_hint):
		_preview_hint.text = "Выбор датасета…"
	var res = await ui.splash_and_get_result("select_dataset", run, null, false, {"with_who": cfg["name"]})
	hold_for_frame()
	if res:
	#	print(res["meta"])
		update_config({"name": res["ds"]})
		update_config({"meta": res["meta"]})
	await get_tree().process_frame
	hold_for_frame()
	var m = func(): return glob.mouse_pressed
	while m.call():
		await get_tree().process_frame
	run.unblock_input()
	_refresh_reference_preview()


func _setup_reference_card() -> void:
	Card.title_font($ColorRect/root/Label)
	var body := Card.panel(self, "DatasetBody", Rect2(-44, -59, 88, 138))
	move_child(body, $ColorRect.get_index() + 1)
	# Body has no data of its own: previews below are only from the selected dataset.
	_preview_hint = Card.label(self, "DatasetPreviewHint", Rect2(-37, -18, 74, 66), "Выберите\nдатасет", 12)
	_preview_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_count = Card.label(self, "DatasetCount", Rect2(-40, 56, 80, 18), "", 10)
	_preview_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for index in range(4):
		var sample := TextureRect.new()
		sample.name = "DatasetSample" + str(index)
		sample.position = Vector2(-35 + (index % 2) * 38, -20 + (index / 2) * 37)
		sample.size = Vector2(34, 34)
		sample.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sample.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sample.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sample)
		_preview_images.append(sample)
	var family_colors := _VISUAL_FAMILY.colors(_reference_visual_family())
	Card.tint_button.call_deferred(run, family_colors[1], family_colors[3])
	_refresh_reference_preview()


func _refresh_reference_preview() -> void:
	if not is_instance_valid(_preview_hint):
		return
	for sample in _preview_images:
		sample.hide()
	var selected_name := str(cfg.get("name", ""))
	run.text = (selected_name if selected_name else "Выбрать") + "  ▾"
	run.tooltip_text = "Выбрать датасет" if selected_name.is_empty() else "Датасет: " + selected_name
	_preview_hint.show()
	_preview_count.text = ""
	if selected_name.is_empty():
		_preview_hint.text = "Выберите\nдатасет"
		return
	var meta: Dictionary = glob.load_dataset(selected_name)
	if meta.is_empty() or meta.has("fail"):
		_preview_hint.text = "Данные\nнедоступны"
		_preview_hint.tooltip_text = "Выберите другой датасет или исправьте данные во вкладке Датасеты."
		return
	if meta.has("size"):
		_preview_count.text = str(int(meta.size)) + " записей"
	var shape: Dictionary = meta.get("inputs", {})
	_preview_hint.text = ("%s × %s" % [shape.get("x", "?"), shape.get("y", "?")]) if shape.has("y") else (str(shape.get("x", "?")) + " признаков")
	# These thumbnails were generated from rows 0..3 of the bundled MNIST file.
	# A user dataset called mnist must never display the bundled examples.
	if selected_name != "mnist" or glob.dataset_datas.has(selected_name) or not FileAccess.file_exists("res://local_runtime/datasets/mnist/train.npz"):
		return
	var loaded := 0
	for index in range(4):
		var source := "res://game_assets/dataset_previews/mnist/%d.png" % index
		if not FileAccess.file_exists(source):
			continue
		var sample_texture := load(source) as Texture2D
		if sample_texture == null:
			continue
		_preview_images[index].texture = sample_texture
		_preview_images[index].tooltip_text = "MNIST · пример %d из локального датасета" % (index + 1)
		_preview_images[index].show()
		loaded += 1
	_preview_hint.visible = loaded == 0
