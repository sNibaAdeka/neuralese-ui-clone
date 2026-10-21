extends SceneTree

const Worker = preload("res://scripts/simulations/simulation_dataset_worker.gd")
const Compiler = preload("res://scripts/simulations/simulation_compiler.gd")
const World = preload("res://scripts/simulations/simulation_world_state.gd")
const Catalog = preload("res://scripts/simulations/simulation_object_catalog.gd")

class PhysicsAction extends Node:
	signal completed
	var action: Callable

	func _ready() -> void:
		set_physics_process(false)

	func _physics_process(_delta: float) -> void:
		set_physics_process(false)
		action.call()
		action = Callable()
		completed.emit()

class SharedState extends RefCounted:
	var mutex := Mutex.new()
	var values: Dictionary = {}

	func put(key: String, value: Variant) -> void:
		mutex.lock()
		values[key] = value
		mutex.unlock()

	func read(key: String, fallback: Variant = null) -> Variant:
		mutex.lock()
		var value: Variant = values.get(key, fallback)
		mutex.unlock()
		return value

var failures: Array[String] = []
var _physics_action: PhysicsAction

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_physics_action = PhysicsAction.new()
	root.add_child(_physics_action)
	var world := World.new()
	world.add_object(&"car", Transform2D.IDENTITY)
	var worker := Worker.new()
	var prepared := worker.prepare({"blueprint": Compiler.compile(world.to_dictionary())})
	_expect(prepared, "handshake fixture must use a real compiled physics world")
	if not prepared:
		await _during_physics(worker.shutdown)
		_finish()
		return
	for i in 8:
		_expect(not worker.pulse(), "early main-thread callbacks must not bank a future tick")
	var state := SharedState.new()
	var next_step := Semaphore.new()
	var probe := Thread.new()
	var started := probe.start(_prepare_steps.bind(worker, state, next_step)) == OK
	_expect(started, "the readiness probe must run on an actual worker thread")
	if not started:
		await _during_physics(worker.shutdown)
		_finish()
		return
	await _wait_until(func(): return worker.is_ready_for_tick(), "first prepared step must publish readiness")
	_expect(worker._kernel._physics.queued_body_param_count() == 2,
		"readiness must be published after both material parameters are queued")
	_expect(not worker.pulse(), "a prepared step must not advance with undrained parameters")
	_expect(not bool(state.read("first_released", false)), "early permits must not advance the first step")
	await _during_physics(_flush_and_acknowledge.bind(worker))
	await _wait_until(func(): return bool(state.read("first_released", false)), "the acknowledged first step must resume")
	for i in 8:
		_expect(not worker.pulse(), "callbacks during slow preparation must not release later steps")
	next_step.post()
	await _wait_until(func(): return worker.is_ready_for_tick(), "the second step must publish its own readiness")
	await process_frame
	_expect(not bool(state.read("finished", false)), "the second step must still wait without its own acknowledgement")
	_expect(worker._kernel._physics.queued_body_param_count() == 2,
		"the second step must retain its own unacknowledged material update")
	worker.request_cancel()
	await _wait_until(func(): return bool(state.read("finished", false)), "cancellation must wake a waiting worker without another physics callback")
	if not bool(state.read("finished", false)):
		# A failed cancellation assertion must not leave the test hanging in
		# Thread destruction. Release only during failure cleanup, after the
		# timeout has already recorded the regression as a test failure.
		next_step.post()
		worker._tick.post()
		await _wait_until(func(): return bool(state.read("finished", false)), "failed probe must stop during cleanup")
	if probe.is_started():
		probe.wait_to_finish()
	_expect(state.read("second_released", true) == false, "cancelled waits must never report a physics acknowledgement")
	await _during_physics(worker.shutdown)
	_expect(worker._kernel == null, "cancelled worker shutdown must release its physics kernel")
	var idle_worker := Worker.new()
	idle_worker.request_cancel()
	_expect(not idle_worker._wait_for_physics_tick(), "cancellation before readiness must not block a later wait")
	_finish()

func _during_physics(action: Callable) -> void:
	# Direct-space access follows the generator's actual _physics_process
	# contract; an idle-frame coroutine is not a valid physics notification.
	_physics_action.action = action
	_physics_action.set_physics_process(true)
	await _physics_action.completed
	await process_frame

func _flush_and_acknowledge(worker: RefCounted) -> void:
	_expect(worker.apply_queued_body_params() == 2, "main thread must drain the prepared material update")
	worker.force_space_flush()
	var body: RID = worker._kernel._physics.body_rid(0)
	_expect(is_equal_approx(float(PhysicsServer2D.body_get_param(body, PhysicsServer2D.BODY_PARAM_FRICTION)),
		float(Catalog.definition(&"ice")["friction"])), "real friction must be applied before acknowledging the step")
	_expect(worker.pulse(), "one prepared and flushed step must receive one acknowledgement")

func _prepare_steps(worker: RefCounted, state: SharedState, next_step: Semaphore) -> void:
	worker._kernel._physics.set_material(0, Catalog.definition(&"ice"))
	var accepted: bool = worker._wait_for_physics_tick()
	state.put("first_released", accepted)
	if accepted:
		next_step.wait()
		worker._kernel._physics.set_material(0, Catalog.definition(&"sand"))
		state.put("second_released", worker._wait_for_physics_tick())
	state.put("finished", true)

func _wait_until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(bool(predicate.call()), message)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	_physics_action.free()
	if failures.is_empty():
		print("PASS test_simulation_worker_handshake")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	push_error("FAIL test_simulation_worker_handshake: %d failure(s)" % failures.size())
	quit(1)
