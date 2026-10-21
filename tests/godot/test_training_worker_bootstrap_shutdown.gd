extends SceneTree
## Real owned-child cleanup before worker readiness; no actual training.

const Worker = preload("res://scripts/local_training_worker.gd")

class ReadyWorker:
	extends "res://scripts/local_training_worker.gd"
	var commands: Array[String] = []
	func _send_command(command: String, _payload: Dictionary = {}) -> int:
		commands.append(command)
		return 1

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var bootstrap_service = root.get_node("local_runtime")
	var python: String = await bootstrap_service.python_path()
	if python.is_empty():
		# The test is also useful in CI before runtime installation. Use the
		# configured system Python only to launch a controlled sleeping child.
		python = "python3"
	var entry := "user://training-worker-bootstrap-child.py"
	var file := FileAccess.open(entry, FileAccess.WRITE)
	file.store_string("import time\ntime.sleep(30)\n")
	file.close()
	for initial_state in ["bootstrapping", "connecting"]:
		var worker = Worker.new()
		worker.configure(python, ProjectSettings.globalize_path(entry), "", ProjectSettings.globalize_path("user://bootstrap-shutdown-test"), OS.get_process_id())
		# No production runtime is needed to reproduce ownership of an unready
		# child; the real Python process intentionally never publishes bootstrap.
		worker._runtime_root = ProjectSettings.globalize_path("res://local_runtime")
		_expect(worker.start_warm(), "controlled child starts")
		var pid: int = worker.process_pid
		worker.state = initial_state
		worker.shutdown()
		var deadline := Time.get_ticks_msec() + 2000
		while _pid_alive(python, pid) and Time.get_ticks_msec() < deadline:
			await process_frame
		_expect(not _pid_alive(python, pid), initial_state + " shutdown terminates owned child")
		_expect(worker.process_pid == -1 and worker.state == "stopped", "unready shutdown clears child ownership")
		_expect(not worker.start_warm(), "shutdown worker cannot restart from a deferred callback")
		if _pid_alive(python, pid): OS.kill(pid)
	var ready := ReadyWorker.new()
	ready.state = "ready"
	ready.shutdown()
	ready.shutdown()
	_expect(ready.commands == ["SHUTDOWN"] and ready.state == "stopping", "ready worker retains one orderly shutdown command")
	DirAccess.remove_absolute(entry)
	if failures.is_empty():
		print("PASS test_training_worker_bootstrap_shutdown")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _pid_alive(python: String, pid: int) -> bool:
	# Godot logs an engine error when querying a child already reaped by kill().
	# Verify externally so a successful teardown has a clean engine log.
	var output := []
	var code := OS.execute(python, ["-c", "import sys\nsys.path.insert(0,sys.argv[2])\nfrom neuralese_local.stop_flag import StopFlag\nsys.exit(1 if StopFlag('unused',int(sys.argv[1]))._parent_dead() else 0)\n", str(pid), ProjectSettings.globalize_path("res://local_runtime")], output)
	return code == 0
