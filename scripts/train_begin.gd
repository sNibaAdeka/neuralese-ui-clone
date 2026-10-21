extends Graph

const Card = preload("res://scripts/claude_training_card.gd")
var _dataset_caption: Label
var _status_caption: Label
var _epoch_minus: Button
var _epoch_plus: Button

func get_training_data():
	#(not dataset_meta["name"] in glob._load)
	if get_ancestor() and get_ancestor().cfg["name"]:
		return {"epochs": epochs if epochs else 1, "dataset": get_ancestor().cfg["name"], "test_dataset": "", 
		"batch_size": 0, "local": not dataset_meta["name"] in glob._load}

@onready var clearbut = $train2

var dataset_meta: Dictionary = {}

func display_ds_meta():
	$ColorRect2/Control.push_cfg(dataset_meta)
	if is_instance_valid(_dataset_caption):
		_dataset_caption.text = str(dataset_meta.get("name", "")) if not dataset_meta.is_empty() else "Не выбран"
		_dataset_caption.tooltip_text = _dataset_caption.text
		if not training:
			_set_status("" if dataset_meta.get("name", "") else "Подключите датасет")

func set_dataset_meta(meta: Dictionary):
	#(meta)
	var old_meta = dataset_meta
#	print(meta)
	dataset_meta = meta
	#(meta)
	display_ds_meta()
	var a 
	#(meta)
	#(graphs.simple_reach(self))
	#for i in graphs.get_cache("", self):
	#	i.push_meta(self, dataset_meta)
	#(dataset_meta)
	set_meta("input_features", dataset_meta.get("inputs", {}))
	if dataset_meta.get("inputs", {}).has("is_env"):
		dataset_meta = dataset_meta.duplicate()
		dataset_meta["inputs"] = {}
	await get_tree().process_frame
#	print(get_descendant())
#	print(get_descendant().input_keys[0].hint)
	if not graphs.loading and not "env" in old_meta and get_descendant() and not get_descendant()._is_suitable_other_conn(outputs[0], get_descendant().input_keys[0]):
		#(get_descendant()._is_suitable_conn(outputs[0], get_descendant().input_keys[0]))
		#await get_tree().process_frame
		#(dataset_meta["name"])
		#_stack()
		outputs[0].disconnect_all()

#func _just_attached(other_conn: Connection, my_conn: Connection):
		#set_dataset_meta({"name": "mnist", "outputs": [
		#{"label": "bbox", "length": 5, "dtype": "1d"}, {"label": "bbox", "length": 5, "dtype": "1d"}
	#]})

var scrolling = false
@onready var vbar = $ColorRect2/Control/ScrollContainer.get_v_scroll_bar()
func _ready() -> void:
	super()
	_setup_reference_card()

func get_training_head():
	var r = []
	var def_call = func(from: Connection, to: Connection, branch_cache: Dictionary):
		if graphs.is_node(to.parent_graph, "TrainInput"):
			r.append(to.parent_graph)
	graphs.reach(self, def_call)
	return r[0] if r else null

func _can_train() -> bool:
	var res = true
	return res

func _stop_label() -> String:
	match glob.get_lang():
		"kz":
			return "Тоқта"
		"ru":
			return "Стоп"
		_:
			return "Stop"

func _show_training_progress(data: Dictionary) -> void:
	var stage := str(data.get("stage", ""))
	train.text = _stop_label()
	if stage == "batch":
		_set_status("Эпоха %d · %d/%d" % [int(data.get("epoch", 0)) + 1, int(data.get("batch", 0)), int(data.get("batches", 0))])
	elif stage == "epoch_start":
		_set_status("Эпоха %d из %d" % [int(data.get("epoch", 0)) + 1, int(data.get("epochs", epochs))])
	else:
		_set_status("Обучение…")
func additional_call(dict):
	if training:
		var phase := str(dict.get("phase", ""))
		if phase == "progress":
			_show_training_progress(dict.get("data", {}))
		if phase == "state":
			#(dict)
			if "epoch" in dict["data"] and $YY.text.is_valid_int():
				var new_text = max(0, int(dict["data"].get("left", 0)))
				$YY.set_line(str(new_text) if new_text else "")
			train.text = _stop_label()
		if phase in ["done", "stopped", "error"]:
			train_stop(true, false)
			_set_status("Готово" if phase == "done" else ("Остановлено" if phase == "stopped" else "Ошибка обучения"), phase == "error")

var epochs: int = 0

var training: bool = false
var delaying: bool = false
func train_stop(force: bool = false, send: bool = true):
	#$ColorRect2.alive = false
	if training and (not delaying or force) and _can_train():
		$YY.editable = true
		delaying = true
		training = false
		train.text = "Учись!" if glob.get_lang() == "ru" else "Train!"
		_update_epoch_actions()
		_set_status("Остановлено")
		if old_head:
			old_head.train_stop()
			if send:
				nn.stop_train(old_head)
		if int($YY.text) <= 1:
			$YY.set_line("")
		await glob.wait(2)
		delaying = false

func vbox_focus():
	#($ColorRect2/Control/ScrollContainer.get_v_scroll_bar().get_global_rect().has_point(get_global_mouse_position()))
	#if scrolling:
	#	return true
	return vbox_vis() and glob.mouse_pressed and $ColorRect2/Control/ScrollContainer.get_v_scroll_bar().get_global_rect().has_point(get_global_mouse_position())

func vbox_vis():
	return $ColorRect2/Control/ScrollContainer.get_v_scroll_bar().visible

func _can_drag() -> bool:
	return not train.is_mouse_inside() and not ui.is_focus($YY) and not vbox_focus() and not clearbut.is_mouse_inside() and not _reference_button_hovered()

func _stopped_processing():
	glob.set_scroll_possible(self)

func _process(delta: float) -> void:
	#if glob.space_just_pressed:
	#	print(get_training_data())
	super(delta)
	if $ColorRect2.get_global_rect().has_point(get_global_mouse_position()) and vbox_vis():
		glob.set_scroll_impossible(self)
	else:
		glob.set_scroll_possible(self)
	#(func(): scrolling = false).call_deferred()
		

func _proceed_hold() -> bool:
	#if glob.space_just_pressed:
	#	set_dataset_meta({"outputs": [{"label": "hii"}]})
	return ui.is_focus($YY) or vbox_focus()

var old_head = null
func train_start() -> bool:
	#timing_offset = -$ColorRect2.get_time()
	if not training and not delaying:
		if not graphs.has_input():
			_set_status("Добавьте вход модели", true)
			ui.error("Пожалуйста создайте Input2D или Input1D.")
			return false
		
		if not get_ancestor() or not get_ancestor().cfg.get("name", ""):
			_set_status("Подключите датасет", true)
			ui.error("Подключите датасет к началу обучения.")
			return false
		if not is_instance_valid(get_training_head()):
			_set_status("Подключите шаг обучения", true)
			ui.error("Соедините начало обучения, запуск модели и шаг обучения.")
			return false
		$YY.editable = false
		training = true
		_update_epoch_actions()
		_set_status("Подготовка…")
		train.text = _stop_label()
		old_head = get_training_head()
		#(old_head)
		if not $YY.text: $YY.set_line("1"); epochs = 1
		else: epochs = int($YY.text)
		if old_head:
			#("AA")
			old_head.train_start()
			if not await _request_training_start():
				hold_for_frame()
				train_stop(false, false)
				_set_status("Не удалось начать обучение", true)
				return false
		#($YY.text)
		return true
	return false


func _request_training_start() -> bool:
	return await nn.start_train(old_head, additional_call, train)

@onready var train = $train
func _on_train_released() -> void:
	if training:
		train_stop()
	else:
		events.event_ping("train", {"id": graph_id, })
		train_start()


func _on_train_2_released() -> void:
	var anc = null

	for i in graphs.simple_reach(self):
		if graphs.is_node(i, "RunModel"):
			var active_name: String = i.name_graph
			if active_name == "":
				active_name = glob.DEFAULT_MODEL_NAME

			anc = graphs.get_input_graph_by_name(active_name)

		if graphs.is_node(i, "TrainInput"):
			i.clear()

	if is_instance_valid(anc):
		nn.delete_ctx(anc.context_id)
		#await web.POST("delete_ctx", {"user": cookies.user(), "pass": cookies.pwd(), "scene": str(glob.get_project_id()), "contexts": [str(anc.context_id)]})


func _setup_reference_card() -> void:
	Card.title_font($ColorRect/root/Label)
	# Keep the original metadata renderer as the authoritative receiver; the card
	# presents its dataset name without the old scrolling inspector occupying it.
	$ColorRect2/Control.hide()
	Card.label(self, "DatasetCaption", Rect2(-68, -38, 56, 24), "Датасет")
	_dataset_caption = Card.label(self, "DatasetValue", Rect2(-11, -38, 79, 24), "Не выбран")
	_dataset_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dataset_caption.add_theme_color_override("font_color", Card.BLUE)
	_status_caption = Card.label(self, "TrainingStatus", Rect2(-77, 71, 154, 17), "Подключите датасет", 10)
	_status_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_epoch_minus = Card.button(self, "DecreaseEpochs", Rect2(-17, -9, 23, 24), "−", _change_epochs.bind(-1))
	_epoch_plus = Card.button(self, "IncreaseEpochs", Rect2(48, -9, 23, 24), "+", _change_epochs.bind(1))
	_epoch_minus.tooltip_text = "Меньше эпох"
	_epoch_plus.tooltip_text = "Больше эпох"
	$YY.position = Vector2(8, -9)
	$YY.custom_minimum_size = Vector2(39, 24)
	$YY.size = Vector2(39, 24)
	for state in ["normal", "focus", "read_only"]:
		var field := StyleBoxFlat.new()
		field.bg_color = Color("e3f3ff")
		field.set_corner_radius_all(8)
		$YY.add_theme_stylebox_override(state, field)
	Card.tint_button.call_deferred(train, Color("1a66f0"), Color.WHITE)
	Card.tint_button.call_deferred(clearbut, Color("eaf7ff"), Card.BLUE)
	display_ds_meta()
	_update_epoch_actions()


func _change_epochs(amount: int) -> void:
	if training or not $YY.editable:
		return
	var current := maxi(1, int($YY.text))
	$YY.set_line(str(clampi(current + amount, 1, 999)), true)
	_update_epoch_actions()


func _update_epoch_actions() -> void:
	if is_instance_valid(_epoch_minus):
		_epoch_minus.disabled = training or maxi(1, int($YY.text)) <= 1
		_epoch_plus.disabled = training or int($YY.text) >= 999


func _reference_button_hovered() -> bool:
	for control in [_epoch_minus, _epoch_plus]:
		if is_instance_valid(control) and control.get_global_rect().has_point(get_global_mouse_position()):
			return true
	return false


func _set_status(message: String, error: bool = false) -> void:
	if is_instance_valid(_status_caption):
		_status_caption.text = message
		_status_caption.tooltip_text = message
		_status_caption.add_theme_color_override("font_color", Color("b33b51") if error else Card.MUTED)
