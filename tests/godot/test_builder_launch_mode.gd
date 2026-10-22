extends SceneTree

const LaunchMode = preload("res://scripts/startup/builder_launch_mode.gd")

func _initialize() -> void:
	assert(not LaunchMode.resolve(PackedStringArray()), "ordinary builder defaults to the standard launch")
	assert(not LaunchMode.resolve(PackedStringArray(["--local-api", "--graphics=high"])), "network and graphics arguments do not select pilot identity")
	assert(LaunchMode.resolve(PackedStringArray(["--pilot"])), "explicit pilot user argument selects the classroom launch")
	assert(LaunchMode.resolve(PackedStringArray(), true), "pilot export feature selects the classroom launch")
	assert(not LaunchMode.resolve(PackedStringArray(["--pilot=false", "--pilot-other"])), "only the explicit supported pilot argument opts in")
	var source := FileAccess.get_file_as_string("res://scripts/glob.gd")
	assert('preload("res://scripts/startup/builder_launch_mode.gd").resolve(OS.get_cmdline_user_args(), OS.has_feature("neuralese_pilot"))' in source, "production global uses the tested startup resolver")
	var pilot_config := RegEx.new()
	assert(pilot_config.compile('var\\s+PILOT_ENROLLMENT_CONFIG\\s*:\\s*Dictionary\\s*=\\s*\\{\\s*\\}') == OK)
	assert(pilot_config.search(source) != null, "versioned pilot enrollment configuration must remain empty; supply explicit pilot configuration through the environment")
	print("PASS test_builder_launch_mode")
	quit(0)
