extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures: Array[String] = []
	var scene: PackedScene = load("res://scenes/ai_help.tscn")
	for cycle in range(2):
		var menu = scene.instantiate()
		# Reproduce the production onready template copies without entering the
		# scene tree or starting dialogue/session work. Exercise its real destructor.
		menu.user_message = menu._user_message.duplicate()
		menu.ai_message = menu._ai_message.duplicate()
		var user_ref: WeakRef = weakref(menu.user_message)
		var ai_ref: WeakRef = weakref(menu.ai_message)
		var user_text_ref: WeakRef = weakref(menu.user_message.get_node("Content/txt"))
		var ai_text_ref: WeakRef = weakref(menu.ai_message.get_node("txt"))
		# Both templates remain reusable while the menu lives; message instances
		# are separate children owned by the menu, not the detached templates.
		for template in [menu.user_message, menu.ai_message]:
			assert(template.get_parent() == null)
			var message: Node = template.duplicate()
			menu.add_child(message)
		menu.free()
		var retained := 0
		for template_ref in [user_ref, ai_ref]:
			if template_ref.get_ref() != null:
				retained += 1
				template_ref.get_ref().free()
		print("AI_TEMPLATE_LIFETIME cycle=", cycle, " retained_after_owner_free=", retained)
		if retained != 0:
			failures.append("AI message templates outlive their owner")
		assert(user_text_ref.get_ref() == null and ai_text_ref.get_ref() == null, "template subtrees must be released")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS test_ai_help_template_lifecycle")
	quit(0 if failures.is_empty() else 1)
