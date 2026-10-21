extends HBoxContainer
## Test support: reports every NOTIFICATION_THEME_CHANGED (a redraw request) to `owner_test`.

var owner_test: Object


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and owner_test != null:
		owner_test.theme_changes += 1
