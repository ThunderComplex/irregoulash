extends SceneTree
## DEV HELPER - prints the engine API this project relies on, so names, argument
## lists, properties and enum constants can be checked against the running engine
## instead of guessed from memory.
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       --script res://dev/editor_api_check.gd

const CLASSES: Array = [
	["EditorInterface", ["viewport", "selection", "undo", "edited"]],
	["EditorUndoRedoManager", [""]],
	["EditorSelection", [""]],
	["NavigationRegion2D", ["bake", "polygon", "enabled"]],
	["NavigationPolygon", ["outline", "polygon", "bake", "geometry", "agent", "cell", "border"]],
	["NavigationServer2D", ["map_get", "bake", "region", "source"]],
	["NavigationAgent2D", ["target", "path", "radius", "avoid", "navigation"]],
	["Viewport", ["mouse", "canvas_transform"]],
]


func _initialize() -> void:
	for entry: Array in CLASSES:
		_print_class(String(entry[0]), entry[1])
	quit()


func _print_class(klass: String, filters: Array) -> void:
	print("\n=== %s ===" % klass)

	print("  -- methods")
	for method: Dictionary in ClassDB.class_get_method_list(klass, true):
		var name: String = method["name"]
		if name.begins_with("_"):
			continue
		if not _matches(name, filters):
			continue
		var args: Array[String] = []
		for arg: Dictionary in method["args"]:
			args.append("%s: %s" % [arg["name"], type_string(arg["type"])])
		var has_default: bool = method.has("default_args")
		print("    %s(%s)%s -> %s" % [name, ", ".join(args),
			"  [has defaults]" if has_default else "", type_string(method["return"]["type"])])

	print("  -- properties")
	for prop: Dictionary in ClassDB.class_get_property_list(klass, true):
		var name: String = prop["name"]
		if name.begins_with("_") or name.contains("/"):
			continue
		if not _matches(name, filters):
			continue
		print("    %s: %s" % [name, type_string(prop["type"])])

	print("  -- constants")
	for constant: String in ClassDB.class_get_integer_constant_list(klass, true):
		if not _matches(constant, filters):
			continue
		print("    %s = %s" % [constant, ClassDB.class_get_integer_constant(klass, constant)])


func _matches(name: String, filters: Array) -> bool:
	if filters.is_empty():
		return true
	for filter: String in filters:
		if filter.is_empty() or name.to_lower().contains(filter.to_lower()):
			return true
	return false
