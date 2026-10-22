extends SplashMenu

const Design = preload("res://scripts/claude_design_theme.gd")
const ExportResult = preload("res://scripts/export_result.gd")

var _model_export_busy := false
var _project_export_busy := false
var _robot_export_dialog: Window

func _ready() -> void:
	super()
	$ColorRect/Label.text = glob.DEFAULT_MODEL_NAME
	#$ColorRect/Label.set_is_valid_call(func(input):
	#	#(graphs.get_input_graph_by_name(input))
	#	return len(input)> 0 and graphs.get_input_graph_by_name(input))
	un_all()
	quant_un_all()
	_on_onnx_released()
	if nn.FULLY_LOCAL_TRAINING:
		_on_none_released()
	else:
		_on_int_8_released()
	_skin_export_chrome.call_deferred()
	_add_robot_export_button.call_deferred()

func _process(delta: float) -> void:
	# SplashMenu polls global Enter/Escape; keep it inert while the child owns focus.
	if is_instance_valid(_robot_export_dialog) and _robot_export_dialog.blocks_parent_input():
		return
	super(delta)

func _splash():
	pass

func quit(data: Dictionary = {}):
	quitting.emit()
	if can_go:
		hide()
		ui.blur.self_modulate.a = 0
		emitter.res.emit(data)

func _resultate(data: Dictionary):
	emitter.res.emit(data)
	#glob.env_dump[data["text"]] = "-- Scene '%s'\nprint('Hello, world!')" % data["text"]
	#glob.tree_windows["env"].reload_scenes()
	go_away()

@onready var dl_but = $ColorRect/train
func set_downloading():
	_model_export_busy = true
	$ColorRect/ProgressBar.show()
	dl_but.hide()

func reset_downloading():
	_model_export_busy = false
	$ColorRect/ProgressBar.hide()
	dl_but.show()

@onready var export_but: BlockComponent = $ColorRect/train
func _on_trainn_released() -> void:
	if _model_export_busy:
		return
	#$ColorRect/Label.update_valid()
	
	if 1:#$ColorRect/Label.is_valid:
		#await glob.wait(1)
		#reset_downloading()
		#return
		var export_txt = "  Model"
		var saved_txt = "  Saved!"
		match glob.get_lang():
			"ru":
				export_txt = "  Модель"
				saved_txt = "  Скачано"
			"kz":
				export_txt = "  Модель"
				saved_txt = "  Сақт.!"
		export_but.text = export_txt
		var got = graphs.get_input_graph_by_name($ColorRect/Label.text)
		var ext = ".bin"
		match type:
			"windows": ext = ".exe"
			"linux": ext = ""
			"onnx": ext = ".onnx"
			"tensorrt": ext = ".trt"
		var filename = 'MODEL_GRAPH_%s_%s%s' % [glob.fg.get_scene_name(), type_quant, ext]

		if nn.FULLY_LOCAL_TRAINING:
			set_downloading()
			var output_path := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS).path_join(filename)
			var local_result = await nn.export_fully_local_model(got, type, type_quant, output_path)
			reset_downloading()
			if local_result is Dictionary and local_result.get("status", "") == "ok":
				var saved_path := str(local_result.get("output_path", output_path))
				if FileAccess.file_exists(saved_path):
					export_but.text = saved_txt
					await glob.wait(1.0)
					export_but.text = export_txt
				else:
					ui.error("Export reported success, but the file was not found: " + saved_path)
					export_but.text = export_txt
			else:
				var err := "FullyLocal export failed."
				if local_result is Dictionary:
					err = str(local_result.get("error", err))
				ui.error(err)
				export_but.text = export_txt
			return
		if not glob.require_remote_session():
			return
		set_downloading()

		var handle = web.POST("export", {"user": cookies.user(), "pass": cookies.pwd(), 
		"graph": graphs.get_syntax_tree(got),
		"context": str(got.context_id), "scene_id": glob.get_project_id(),
		"quant": type_quant,
		"platform": type}, false, true)
		#handle.on_chunk.connect(print)
		var response = await handle.completed
		var output_path := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS).path_join(filename)
		var result := ExportResult.save_remote(response, output_path)
		reset_downloading()
		if not result.ok:
			export_but.text = export_txt
			ui.error(str(result.error))
			return
		_model_export_busy = true
		export_but.text = saved_txt
		await glob.wait(1.0)
		export_but.text = export_txt
		_model_export_busy = false


@onready var buts = [$ColorRect/windows, $ColorRect/linux, $ColorRect/onnx, $ColorRect/tensor]
@onready var quants = [$ColorRect/quant/float16, $ColorRect/quant/int8, $ColorRect/quant/none]

func un_all():
		#switch.base_modulate = Color(0.583, 0.578, 0.85) * 1.3
		#switch.text = "I"
	for switch in buts:
		_skin_switch(switch, false)

func quant_un_all():
		#switch.base_modulate = Color(0.583, 0.578, 0.85) * 1.3
		#switch.text = "I"
	for switch in quants:
		_skin_switch(switch, false)

var type: String = ""
func on(who: BlockComponent):
	_skin_switch(who, true)
	type = who.hint

var type_quant: String = ""
func qon(who: BlockComponent):
	_skin_switch(who, true)
	type_quant = who.hint

func _on_tensor_released() -> void:
	un_all()
	on(buts[3])


func _on_onnx_released() -> void:
	un_all()
	on(buts[2])


func _on_linux_released() -> void:
	un_all()
	on(buts[1])


func _on_windows_released() -> void:
	un_all()
	on(buts[0])


func _on_float_16_released() -> void:
	quant_un_all()
	qon(quants[0])

func _on_int_8_released() -> void:
	quant_un_all()
	qon(quants[1])

func _on_none_released() -> void:
	quant_un_all()
	qon(quants[2])


@onready var saveall = $ColorRect/train2
func _on_saveall_released() -> void:
	if _project_export_busy:
		return
	_project_export_busy = true
	var export_txt = "  Project"
	var saved_txt = "  Saved!"
	match glob.get_lang():
		"ru":
			export_txt = "  Проект"
			saved_txt = "  Скачано"
		"kz":
			export_txt = "  Проект"
			saved_txt = "  Сақт.!"
	saveall.text = export_txt
	var bytes = await glob.export_project()
	var output_path := str(cookies.downloads_dir).path_join("save_%s.nls" % glob.fg.get_scene_name())
	var result := ExportResult.write_bytes(bytes, output_path)
	if not result.ok:
		_project_export_busy = false
		ui.error(str(result.error))
		return
	saveall.text = saved_txt
	await glob.wait(1.0)
	saveall.text = export_txt
	_project_export_busy = false


func _skin_switch(button: BlockComponent, selected: bool) -> void:
	button.base_modulate = Color.WHITE
	button.color = Design.PRIMARY_SOFT if selected else Design.FILL
	button.set_instance_shader_parameter("outline_color", Design.PRIMARY if selected else Design.LINE_STRONG)

func _skin_export_chrome() -> void:
	for button in buts:
		_skin_switch(button, str(button.hint) == type)
	for button in quants:
		_skin_switch(button, str(button.hint) == type_quant)
	$ColorRect/root/Label.text = "Экспорт"
	$ColorRect/root/Label.modulate = Color.WHITE
	var icon := Design._icon("M12 3v12M7 10l5 5 5-5M4 17v4h16v-4", Design.INK_SECONDARY)
	# BlockComponent wraps/reparents itself after ready, so use the live tree.
	for sprite in $ColorRect.find_children("*", "Sprite2D", true, false):
		if str(sprite.name) in ["i", "Download"]:
			sprite.texture = icon
			sprite.modulate = Color.WHITE


func _add_robot_export_button() -> void:
	var button := Button.new()
	button.name = "EV3Export"
	button.text = "EV3 · Настроить и экспортировать…"
	button.tooltip_text = "Локальная обученная модель → датчики и моторы → пакет для ручного переноса"
	button.theme = Design.create_theme()
	# Keep the added action within the existing modal's bottom padding.
	button.position = Vector2(40, 258)
	button.size = Vector2(341, 36)
	$ColorRect.add_child(button)
	button.pressed.connect(_open_robot_export)

func _open_robot_export() -> void:
	if _model_export_busy or _project_export_busy:
		return
	if not is_instance_valid(_robot_export_dialog):
		_robot_export_dialog = preload("res://scripts/robot_export_dialog.gd").new()
		add_child(_robot_export_dialog)
	var input = graphs.get_input_graph_by_name($ColorRect/Label.text)
	_robot_export_dialog.open_for(input, str(glob.get_project_id()), nn)
