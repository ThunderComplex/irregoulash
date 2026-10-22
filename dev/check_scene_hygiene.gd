extends SceneTree
## DEV CHECK - level file hygiene.
##
## `Wall` generates its collider, its light occluder and its visual from a single
## `size` property. If those generated nodes can be serialised into a level file
## when Godot saves an edited scene, then a level that is edited in the editor
## would bake stale geometry into itself and stop tracking future changes to
## `Wall`. This measures whether that actually happens.
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       --script res://dev/check_scene_hygiene.gd

const LEVEL: String = "res://src/levels/level_01.tscn"
const OUT: String = "user://hygiene_repacked.tscn"
const PROBE_OUT: String = "user://hygiene_unowned_probe.tscn"


func _initialize() -> void:
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		print("[hygiene] cannot load %s" % LEVEL)
		quit()
		return

	# 1. As the game builds it: generated children belong to nobody.
	var runtime_root: Node = packed.instantiate()
	root.add_child(runtime_root)
	var runtime_stats: Dictionary = _pack_and_measure(runtime_root, false)
	runtime_root.queue_free()

	# 2. As the editor would have it: Godot only serialises nodes that are *owned*
	#    by the packed root, and the editor assigns ownership. Forcing ownership
	#    here reproduces what saving an edited level would write out.
	var editor_root: Node = packed.instantiate()
	root.add_child(editor_root)
	var editor_stats: Dictionary = _pack_and_measure(editor_root, true)
	editor_root.queue_free()

	print("[hygiene] runtime-built : generated_children=%d sub_resources=%d shape_refs=%d" % [
		runtime_stats["generated"], runtime_stats["sub_resources"], runtime_stats["shape_refs"],
	])
	print("[hygiene] editor-saved  : generated_children=%d sub_resources=%d shape_refs=%d" % [
		editor_stats["generated"], editor_stats["sub_resources"], editor_stats["shape_refs"],
	])
	if int(editor_stats["sub_resources"]) > 0:
		print("[hygiene] VERDICT: saving an edited level WOULD bake generated data into it.")
	else:
		print("[hygiene] VERDICT: generated data stays out of the level file.")
	_check_unowned_children()
	quit()


func _pack_and_measure(scene_root: Node, assign_owner: bool) -> Dictionary:
	var generated: int = 0
	for node: Node in _descendants(scene_root):
		if node.owner == null and node != scene_root:
			generated += 1
			if assign_owner:
				node.owner = scene_root

	var packed := PackedScene.new()
	packed.pack(scene_root)
	ResourceSaver.save(packed, OUT)

	var text: String = FileAccess.get_file_as_string(OUT)
	var sub_resources: int = 0
	var shape_refs: int = 0
	for line: String in text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("[sub_resource"):
			sub_resources += 1
		if stripped.begins_with("shape = SubResource") or stripped.begins_with("occluder = SubResource"):
			shape_refs += 1
	return {"generated": generated, "sub_resources": sub_resources, "shape_refs": shape_refs}


## Direct test of the rule the editor gizmos rely on: an unowned child must not be
## written into a scene file, which is what makes editor-only helper nodes (like
## the lighting preview) safe to add from a @tool script.
func _check_unowned_children() -> void:
	var probe := Node2D.new()
	probe.name = "Probe"
	var owned := Node2D.new()
	owned.name = "OwnedChild"
	probe.add_child(owned)
	owned.owner = probe
	var unowned := Node2D.new()
	unowned.name = "UnownedChild"
	probe.add_child(unowned)

	var packed := PackedScene.new()
	packed.pack(probe)
	ResourceSaver.save(packed, PROBE_OUT)
	var text: String = FileAccess.get_file_as_string(PROBE_OUT)
	print("[hygiene] scene file contains owned child: %s, unowned child: %s" % [
		text.contains("OwnedChild"), text.contains("UnownedChild"),
	])
	probe.free()


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out
