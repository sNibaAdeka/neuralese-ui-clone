extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var global_script: GDScript = load("res://scripts/glob.gd")
	var owner: Node = global_script.new()
	# Detached owner: no UI startup, sockets, saved settings or automatic ticks.
	var callbacks := [0]
	var pending: Object = owner.timer(60.0)
	var pending_id := pending.get_instance_id()
	pending.timeout.connect(func(): callbacks[0] += 1)
	var waiting: Signal = owner.wait(60.0, true)
	var waiting_id := waiting.get_object_id()
	waiting.connect(func(): callbacks[0] += 1)
	_expect(owner.timers.size() == 2, "Both public timer APIs must retain their objects in the owner")
	print("TIMER_LIFECYCLE before owner teardown: ", [pending_id, waiting_id])
	owner.free()
	_expect(not is_instance_id_valid(pending_id), "timer() object must be freed with its owner")
	_expect(not is_instance_id_valid(waiting_id), "wait() signal object must be freed with its owner")
	_expect(callbacks[0] == 0, "Owner teardown must not emit pending timeout callbacks")
	print("TIMER_LIFECYCLE after owner teardown valid: ",
		[is_instance_id_valid(pending_id), is_instance_id_valid(waiting_id)])
	# Keep the intentionally failing pre-fix reproduction from creating its own
	# exit warning; ID assertions above establish the ownership regression.
	for instance_id in [pending_id, waiting_id]:
		if is_instance_id_valid(instance_id):
			instance_from_id(instance_id).free()
	await process_frame
	await _test_normal_expiration(global_script)
	await _test_reentrant_callback(global_script)
	await _test_teardown_before_deferred_release(global_script)
	await _test_deferred_consumer_lifetime(global_script)
	await _test_callback_teardown(global_script)
	_finish()

func _test_normal_expiration(global_script: GDScript) -> void:
	var owner: Node = global_script.new()
	var callbacks := [0, 0]
	var seconds: Object = owner.timer(1.0)
	var seconds_id := seconds.get_instance_id()
	seconds.timeout.connect(func(): callbacks[0] += 1)
	owner._process_timers(1.0)
	_expect(callbacks[0] == 0 and is_instance_id_valid(seconds_id),
		"Seconds timer must retain the existing strict greater-than threshold")
	owner._process_timers(0.01)
	_expect(callbacks[0] == 1 and is_instance_id_valid(seconds_id),
		"Timeout must fire once while the object stays valid until deferred release")
	owner._process_timers(10.0)
	_expect(callbacks[0] == 1, "An expired timer must not emit again before deferred release")
	await process_frame
	_expect(not is_instance_id_valid(seconds_id), "Normal expiration must release the Object on the deferred turn")
	var frames: Signal = owner.wait(2.0, true)
	var frames_id := frames.get_object_id()
	frames.connect(func(): callbacks[1] += 1)
	owner._process_timers(100.0)
	owner._process_timers(100.0)
	_expect(callbacks[1] == 0, "Frame timers must advance by one per tick regardless of delta")
	owner._process_timers(0.0)
	_expect(callbacks[1] == 1, "A two-frame wait must retain its existing third-tick timeout")
	await process_frame
	_expect(not is_instance_id_valid(frames_id), "Expired wait() signal owners must also be freed")
	owner.free()

func _test_reentrant_callback(global_script: GDScript) -> void:
	var owner: Node = global_script.new()
	var callbacks := [0, 0]
	var child_id := [0]
	var parent: Object = owner.timer(0.0)
	parent.timeout.connect(func():
		callbacks[0] += 1
		var child: Object = owner.timer(0.0)
		child_id[0] = child.get_instance_id()
		child.timeout.connect(func(): callbacks[1] += 1)
	)
	owner._process_timers(0.1)
	_expect(callbacks == [1, 0] and is_instance_id_valid(child_id[0]),
		"A callback-created timer must survive without being advanced in its creation tick")
	owner._process_timers(0.1)
	_expect(callbacks == [1, 1], "A callback-created timer must run exactly once on the next tick")
	await process_frame
	_expect(not is_instance_id_valid(child_id[0]), "Callback-created timers must use the same deferred release")
	owner.free()

func _test_teardown_before_deferred_release(global_script: GDScript) -> void:
	var owner: Node = global_script.new()
	var callbacks := [0]
	var expired: Object = owner.timer(0.0)
	var expired_id := expired.get_instance_id()
	expired.timeout.connect(func(): callbacks[0] += 1)
	owner._process_timers(0.1)
	_expect(callbacks[0] == 1 and is_instance_id_valid(expired_id),
		"Fixture must stop between timeout emission and deferred object deletion")
	owner.free()
	_expect(not is_instance_id_valid(expired_id),
		"Owner teardown must reclaim expired timers whose deferred release has not run")
	await process_frame
	_expect(callbacks[0] == 1, "Deferred work after owner destruction must neither emit twice nor double-free")

func _test_deferred_consumer_lifetime(global_script: GDScript) -> void:
	var owner: Node = global_script.new()
	var expired: Object = owner.timer(0.0)
	var expired_id := expired.get_instance_id()
	var observations := []
	expired.timeout.connect(func(): observations.append(is_instance_id_valid(expired_id)), CONNECT_DEFERRED)
	owner._process_timers(0.1)
	_expect(observations.is_empty(), "CONNECT_DEFERRED consumers must not execute synchronously")
	await process_frame
	_expect(observations == [true], "Deferred timeout consumers must see a live timer before its deferred deletion")
	_expect(not is_instance_id_valid(expired_id), "Timer must be released after its deferred timeout consumers")
	owner.free()

func _test_callback_teardown(global_script: GDScript) -> void:
	var owner: Node = global_script.new()
	var expired: Object = owner.timer(0.0)
	var expired_id := expired.get_instance_id()
	expired.timeout.connect(func(): instance_from_id(expired_id).free.call_deferred())
	owner._process_timers(0.1)
	_expect(is_instance_id_valid(expired_id), "Callback-requested timer deletion must wait until signal emission unlocks the Object")
	await process_frame
	_expect(not is_instance_id_valid(expired_id), "A timeout consumer can schedule its timer for deferred deletion")
	_expect(owner._timers_pending_free.is_empty(), "Deferred owner cleanup must retire an already freed timer without double-free")
	owner.free()
	if is_instance_id_valid(expired_id):
		instance_from_id(expired_id).free()

	var teardown_owner: Node = global_script.new()
	var owner_id := teardown_owner.get_instance_id()
	var pending: Object = teardown_owner.timer(60.0)
	var pending_id := pending.get_instance_id()
	var ending: Object = teardown_owner.timer(0.0)
	var ending_id := ending.get_instance_id()
	ending.timeout.connect(func(): instance_from_id(owner_id).free.call_deferred())
	teardown_owner._process_timers(0.1)
	_expect(is_instance_id_valid(owner_id) and is_instance_id_valid(ending_id),
		"Callback-requested owner deletion must wait until the active method and signal return")
	await process_frame
	_expect(not is_instance_id_valid(owner_id), "A timeout callback may schedule its detached owner for deletion")
	_expect(not is_instance_id_valid(ending_id) and not is_instance_id_valid(pending_id),
		"Callback-triggered owner teardown must release both active and expiring timers")
	# If a regression prevented deletion, clean up only after recording it.
	if is_instance_id_valid(owner_id):
		instance_from_id(owner_id).free()
	for instance_id in [ending_id, pending_id]:
		if is_instance_id_valid(instance_id):
			instance_from_id(instance_id).free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("PASS test_global_timer_lifecycle")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
