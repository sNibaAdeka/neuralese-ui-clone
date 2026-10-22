extends Graph

const Card = preload("res://scripts/claude_training_card.gd")
var _advanced_open := false
var _advanced_toggle: Button
var _rate_minus: Button
var _rate_plus: Button
var _empty_chart: Label
var _has_samples := false
var _settings_panel: Panel
const SETTINGS_ROW_HEIGHT := 44.0
const CLOSED_HEIGHT := 184.0
const OPEN_HEIGHT := 276.0 + SETTINGS_ROW_HEIGHT

@export var fade_speed: float = 10.0
@export var size_lerp_speed: float = 12.0

func _useful_properties() -> Dictionary:
	return {
		"config":{
			"optimizer":cfg["optimizer"], "lr": learning_rates[cfg["optimizer"]][cfg["lr"]], 
			"weight_decay": "1" if cfg["weight_decay"] else "",
			"momentum": cfg["momentum"]
		}
	}

func _exit_tree() -> void:
	super()

func _after_ready():
	super()
	_setup_reference_card()
	graphs._training_head = self
	for k in optimizers:
		var n: CanvasItem = optimizers[k]
		_set_alpha(n, 0.0)
		n.hide()
		_fade_targets[n] = 0.0
	select_optimizer(current_optimizer)
	set_weight_dec(false)
	is_training = true
	_target_size_y = CLOSED_HEIGHT

var last_acc: float = 0.0
func _after_process(delta: float):
	_update_reference_chart()
	for n in _fade_targets.keys():
		var target_a: float = _fade_targets[n]
		var curr_a: float = n.modulate.a
		if _advanced_open and target_a > curr_a and not n.visible:
			n.show()
		var next_a: float = lerp(curr_a, target_a, delta * fade_speed)
		_set_alpha(n, next_a)
		hold_for_frame()
		if target_a < 0.5 and next_a < 0.02 and n.visible:
			n.hide()

	var sz = $ColorRect.size
	sz.y = lerp(sz.y, _target_size_y, delta * size_lerp_speed)
	$ColorRect.size = sz
	
	if $ColorRect2.alive:
		#($ColorRect2.get_time())
		$ColorRect2/time_passed.text = "Точность"
		$ColorRect2.tooltip_text = "Время обучения: " + str(glob.cap($ColorRect2.get_time() + timing_offset, 1)) + " с"
		if not _has_samples:
			$ColorRect2/acc.text = "—"
		elif abs(last_acc*100) > 1000:
			$ColorRect2/acc.text = str(glob.compact(last_acc*100)) + "%"
		else:
			$ColorRect2/acc.text = str(glob.cap(last_acc*100, 1)) + "%"

var learning_rates = {"adam": ["1e-1", "1e-2", "1e-3"], "sgd": ["2e-1","3e-2","1e-2"]}

@onready var base_size: float = $ColorRect.size.y
@export var tab_size_adds: Dictionary[StringName, float] = {"adam": 0.0, "sgd": 10.0}

var is_training: bool = false
func _proceed_hold() -> bool:
	return training

func _can_drag() -> bool:
	return (not switch.is_visible_in_tree() or not switch.is_mouse_inside()) \
		and not ui.is_focus($sgd_tab/Label4/HSlider) and not _reference_control_hovered()

@onready var optimizer = $optimizer
func _opt_selected(opt: StringName):
	_target_size_y = OPEN_HEIGHT if _advanced_open else CLOSED_HEIGHT

	current_optimizer = opt
	optimizer.text = optimizer.button_by_hint[opt].text

	for o in optimizers:
		_set_fade_target(optimizers[o], 0.0)
	_set_fade_target(optimizers[opt], 1.0)

	if opt == "sgd" or opt == "adam":
		var idx: int = -1
		for i in lr._contained:
			idx += 1
			i.text = learning_rates[opt][idx]
		#lr.text = lr.button_by_hint["1"].text
		update_config({"lr": 1})

@onready var lr = $lr
func select_lr(index: int):
	lr.text = learning_rates[current_optimizer][index]

@onready var optimizers = {"sgd": $sgd_tab, "adam": $adam_tab}
var current_optimizer: StringName = "adam"
func select_optimizer(name: StringName):
	_opt_selected(name)

func _on_optimizer_child_button_release(button: BlockComponent) -> void:
	open_undo_redo()
	update_config({"optimizer": button.hint})
	close_undo_redo()
	button.is_contained.menu_hide()

func _on_loss_child_button_release(button: BlockComponent) -> void:
	pass

func push_acceptance(acc: float, time: float):
	_has_samples = true
	last_acc = acc
	$ColorRect2.push_input(time, acc, $ColorRect2._window_end)

func _on_lr_child_button_release(button: BlockComponent) -> void:
	open_undo_redo()
	update_config({"lr": int(button.hint)})
	close_undo_redo()
	button.is_contained.menu_hide()

func set_weight_dec(on: bool):
	if on:
		switch.base_modulate = Color(0.583, 0.578, 0.85) * 1.3
		switch.text = "I"
	else:
		switch.base_modulate = Color(0.583, 0.578, 0.85) * 0.7
		switch.text = "O"

@onready var switch = $switch
func _on_switch_released() -> void:
	open_undo_redo()
	update_config({"weight_decay": switch.text != "I"})
	close_undo_redo()
	#@set_weight_dec(switch.text != "I")

func _map_properties(pack: Dictionary):
	update_config({"lr": cfg["lr"]})

func _config_field(field: StringName, value: Variant):
	match field:
		"weight_decay":
			set_weight_dec(value)
		"momentum":
			#(value)
			$sgd_tab/Label4/HSlider.value = float(value) * (100.0 / 0.9)
			$sgd_tab/n.text = str(glob.cap(value, 1))
			#if $sgd_tab/n.text != "0.0":
			#$sgd_tab/n.text = $sgd_tab/n.text.trim_prefix('0')
		"lr":
			select_lr(int(value))
		"optimizer":
			select_optimizer(value)

func train_stop():
	if 1:#training:
		if training:
			if $ColorRect2.get_time() + timing_offset < 0.0:
				timing_offset = -$ColorRect2.get_time()
				$ColorRect2/time_passed.text = "0.0"
		training = false
		$ColorRect2.alive = false
		hold_for_frame()

	
	#train.text = "Train!"
	#nn.stop_train(self)
var training: bool = false
func train_start():
	if 1:#not training:
		training = true
		$ColorRect2.clear_window()
		timing_offset = -$ColorRect2.get_time()
		$ColorRect2.alive = true
		hold_for_frame()
		_has_samples = false
		$ColorRect2/time_passed.text = "Точность"
		$ColorRect2/acc.text = "—"
	#train.text = "Stop"
	#nn.start_train(self, {"additional_call": additional_call})

func clear():
	$ColorRect2.clear_window()
	$ColorRect2/time_passed.text = "Точность"
	$ColorRect2/acc.text = "—"
	_has_samples = false


var timing_offset: float = 0.0

	#graphs.train()

var _fade_targets: Dictionary = {}
var _target_size_y: float = 0.0

func _set_fade_target(n: CanvasItem, a: float) -> void:
	if not _advanced_open:
		a = 0.0
	_fade_targets[n] = clamp(a, 0.0, 1.0)
	if a > 0.0 and not n.visible and n.modulate.a <= 0.02:
		n.show()

func _set_alpha(n: CanvasItem, a: float) -> void:
	var c: Color = n.modulate
	c.a = clamp(a, 0.0, 1.0)
	n.modulate = c


func _on_h_slider_value_changed(value: float) -> void:
	open_undo_redo()
	#("ff")
	update_config({"momentum": value / (100.0 / 0.9)})
	close_undo_redo()


func _setup_reference_card() -> void:
	Card.title_font($ColorRect/root/Label)
	move_child($ColorRect, 0)
	_settings_panel = Card.panel(self, "TrainingSettings", Rect2(-78, -64 + SETTINGS_ROW_HEIGHT, 156, 90))
	move_child(_settings_panel, 1)
	# Reuse the existing settings controls and their original paths/configuration.
	# The disclosure gets its own row; ports and graph origin stay in place.
	for control in [optimizer, lr, switch, $sgd_tab, $adam_tab]:
		control.position.y += SETTINGS_ROW_HEIGHT
	for label in $labels.get_children():
		if label is Control: label.position.y += SETTINGS_ROW_HEIGHT
	_rate_minus = Card.button(self, "DecreaseRate", Rect2(-70, -2 + SETTINGS_ROW_HEIGHT, 23, 24), "−", _change_rate.bind(1))
	_rate_plus = Card.button(self, "IncreaseRate", Rect2(48, -2 + SETTINGS_ROW_HEIGHT, 23, 24), "+", _change_rate.bind(-1))
	_rate_minus.tooltip_text = "Меньший шаг обучения"
	_rate_plus.tooltip_text = "Больший шаг обучения"
	_advanced_toggle = Card.button(self, "TrainingOptions", Rect2(-78, -64, 156, SETTINGS_ROW_HEIGHT), "Настройки", _toggle_advanced)
	_advanced_toggle.toggle_mode = true
	_advanced_toggle.accessibility_name = "Настройки обучения"
	_advanced_toggle.tooltip_text = "Настройки обучения: метод, размер шага, уменьшение весов и моментум"
	_empty_chart = Card.label($ColorRect2, "NoMeasurements", Rect2(10, 5, 136, 23), "Нет данных", 11)
	_empty_chart.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$ColorRect2/acc.text = "—"
	$ColorRect2/time_passed.text = "Точность"
	$labels/Label4.hide()
	switch.hide()
	$sgd_tab.hide()
	$adam_tab.hide()
	Card.tint_button.call_deferred(optimizer, Color("d8efff"), Card.BLUE)
	Card.tint_button.call_deferred(lr, Color("e3f3ff"), Card.BLUE)
	_sync_settings_visibility()


func _change_rate(direction: int) -> void:
	if training:
		return
	var next_index := clampi(int(cfg.get("lr", 1)) + direction, 0, learning_rates[current_optimizer].size() - 1)
	open_undo_redo(true)
	update_config({"lr": next_index})
	close_undo_redo()


func _toggle_advanced() -> void:
	_advanced_open = not _advanced_open
	_target_size_y = OPEN_HEIGHT if _advanced_open else CLOSED_HEIGHT
	_sync_settings_visibility()
	for key in optimizers:
		_set_fade_target(optimizers[key], 1.0 if _advanced_open and key == current_optimizer else 0.0)
	hold_for_frame()


func _reference_control_hovered() -> bool:
	for control in [_advanced_toggle, _rate_minus, _rate_plus, optimizer, lr]:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(get_global_mouse_position()):
			return true
	return false


func _update_reference_chart() -> void:
	if not is_instance_valid(_empty_chart):
		return
	_empty_chart.visible = not _has_samples
	for pair in $ColorRect2.lines.values():
		pair[0].hide()
		pair[1].visible = _has_samples
		pair[1].default_color = Color("65b6ea")
	if not _has_samples:
		$ColorRect2/acc.text = "—"
	_rate_minus.disabled = training or int(cfg.get("lr", 1)) >= learning_rates[current_optimizer].size() - 1
	_rate_plus.disabled = training or int(cfg.get("lr", 1)) <= 0


func _sync_settings_visibility() -> void:
	var closing: Array[Control] = []
	if not _advanced_open:
		for selector in [optimizer, lr]:
			if selector.current_type == BlockComponent.ButtonType.CONTEXT_MENU:
				# Open dropdowns move to follow_menus. Their native close
				# animation must return them before the control is hidden.
				selector.menu_hide()
				closing.append(selector)
				_hide_closed_settings_dropdown(selector)
	for control in [_settings_panel, optimizer, lr, _rate_minus, _rate_plus, $labels/Label, $labels/Label3, $labels/Label4, switch]:
		if control not in closing:
			control.visible = _advanced_open
	$ColorRect2.position.y = 32.0 + (SETTINGS_ROW_HEIGHT if _advanced_open else 0.0)
	_advanced_toggle.set_pressed_no_signal(_advanced_open)


func _hide_closed_settings_dropdown(selector: BlockComponent) -> void:
	while is_instance_valid(selector) and selector.state.tween_hide:
		await get_tree().process_frame
	if is_instance_valid(selector):
		selector.visible = _advanced_open
