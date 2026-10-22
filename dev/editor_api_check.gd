extends SceneTree
## DEV HELPER - prints the editor API names this project's plugin relies on, so
## they can be checked against the running engine instead of guessed from memory.
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       --script res://dev/editor_api_check.gd

func _initialize() -> void:
	_print_matching("EditorInterface", ["viewport", "selection", "undo", "edited", "theme"])
	_print_matching("EditorUndoRedoManager", [""])
	_print_matching("EditorSelection", [""])
	_print_matching("EditorPlugin", ["container"])
	_print_matching("Viewport", ["mouse", "canvas_transform", "screen_transform"])
	_print_matching("Control", ["mouse"])
	quit()


func _print_matching(klass: String, filters: Array) -> void:
	print("\n=== %s ===" % klass)
	for method: Dictionary in ClassDB.class_get_method_list(klass, true):
		var name: String = method["name"]
		if str(name).begins_with("_"):
			continue
		var keep: bool = filters.is_empty()
		for filter: String in filters:
			if filter.is_empty() or name.contains(filter):
				keep = true
				break
		if not keep:
			continue
		var args: Array[String] = []
		for arg: Dictionary in method["args"]:
			args.append("%s: %s" % [arg["name"], type_string(arg["type"])])
		print("  %s(%s) -> %s" % [name, ", ".join(args), type_string(method["return"]["type"])])
