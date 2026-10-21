extends Node
## Controlled fake backend acceptance/rejection only; this does not train a model.

class FakeBackendBegin:
	extends "res://scripts/train_begin.gd"
	var accepts := false
	var requests := 0
	var test_dataset: Node
	var test_head: Node
	func get_ancestor():
		return test_dataset
	func get_training_head():
		return test_head
	func _request_training_start() -> bool:
		requests += 1
		await get_tree().process_frame
		return accepts

class ControlledBridge:
	extends "res://scripts/simulations/simulation_training_bridge.gd"
	var candidates: Array[Dictionary] = []
	func _collect_pipeline_candidates() -> Array[Dictionary]:
		return candidates

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var app = get_tree().root.get_node("glob")
	app.tree = get_tree()
	var project = load("res://scenes/project.tscn").instantiate()
	get_tree().root.add_child(project)
	await _frames(4)
	var manager = get_tree().root.get_node("graphs")
	manager.get_graph(&"input")
	var dataset = manager.get_graph(&"dataset")
	var head = manager.get_graph(&"train_input")
	var begin = load("res://scenes/train_begin.tscn").instantiate()
	begin.set_script(FakeBackendBegin)
	begin.set_meta("created_with", "train_begin")
	begin.test_dataset = dataset
	begin.test_head = head
	manager.storage.add_child(begin)
	await _frames(3)
	var bridge := ControlledBridge.new()
	get_tree().root.add_child(bridge)
	var dataset_name := "audit-fake-training-start"
	app.dataset_datas[dataset_name] = {
		"name": dataset_name, "size": 1, "outputs_from": 1,
		"arr": [[0.0, 1.0]], "inputs": {}, "outputs": [],
	}
	bridge.candidates = [{
		"dataset_node": dataset, "train_begin": begin,
		"model_name": app.DEFAULT_MODEL_NAME,
		"input_width": 1, "output_width": 1,
	}]
	bridge.configure_dataset(dataset_name)
	var statuses: Array[String] = []
	bridge.status_changed.connect(func(message: String): statuses.append(message))
	_expect(not await bridge.start_training(), "bridge propagates backend rejection")
	_expect(begin.requests == 1, "rejected request reaches controlled fake backend once")
	_expect(not begin.training and begin.get_node("YY").editable, "rejection restores graph controls")
	_expect(not bridge.last_error().is_empty(), "bridge exposes start failure")
	_expect(begin.get_node("TrainingStatus").text == "Не удалось начать обучение", "graph reports backend rejection")
	for message in statuses:
		_expect(not message.begins_with("Training "), "rejected request never reports training")
	await get_tree().create_timer(2.1).timeout
	begin.accepts = true
	statuses.clear()
	_expect(await bridge.start_training(), "bridge propagates backend acceptance")
	_expect(begin.requests == 2 and begin.training, "accepted request leaves graph training active")
	_expect(bridge.last_error().is_empty(), "accepted retry clears previous bridge error")
	_expect(statuses == ["Training " + dataset_name], "accepted request reports training once")
	_expect(not await begin.train_start() and begin.requests == 2, "duplicate start returns false without a second backend request")
	begin.additional_call({"phase": "progress", "data": {"stage": "epoch_start", "epoch": 0, "epochs": 1}})
	_expect(begin.get_node("TrainingStatus").text == "Эпоха 1 из 1", "accepted request still receives progress")
	begin.additional_call({"phase": "done"})
	_expect(not begin.training and begin.get_node("TrainingStatus").text == "Готово", "done event restores graph controls")
	await get_tree().create_timer(2.1).timeout
	begin.test_dataset = null
	_expect(not await begin.train_start() and begin.requests == 2, "preparation failure returns false without backend request")
	app.dataset_datas.erase(dataset_name)
	app.undo_redo.clear_history()
	bridge.queue_free()
	project.queue_free()
	await _frames(4)
	if failures.is_empty():
		print("PASS test_audit_training_start_result")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)

func _frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
