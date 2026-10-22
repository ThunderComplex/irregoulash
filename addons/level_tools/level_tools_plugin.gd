@tool
extends EditorPlugin
## Level authoring tools for the 2D editor.
##
## WALL BRUSH
##   Toggle "Wall brush" in the 2D editor's toolbar, then left-drag in the
##   viewport:
##     * drag along an axis      -> a wall band of the default thickness
##     * drag diagonally         -> a rectangle (rooms, blocks)
##     * click without dragging  -> a block of the default size
##     * hold Ctrl               -> force a square
##     * hold Alt                -> ignore grid snapping
##     * right-click or Esc      -> cancel
##   Walls go through the editor's undo history, and land in the selected Node2D
##   (so: select "Walls" first), else in a node called "Walls", else in the scene
##   root.
##
##   There is deliberately no on-canvas preview while dragging: it added a whole
##   second coordinate space (the editor's overlay draws in window space, not in the
##   2D viewport's space) for very little value. Draw, then adjust or undo.
##
## LINT LEVEL
##   Runs `LevelLint` over the open scene: no spawn point, no exit, an exit that
##   goes nowhere, content buried inside a wall, an enemy wired to a broken patrol
##   route, and content the player cannot reach. The same check runs headlessly:
##
##     Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##         res://src/ui/title_screen.tscn -- --probe=lint

const WALL_SCENE: PackedScene = preload("res://src/levels/wall.tscn")

## Grid step for snapping. Hold Alt while drawing to ignore it.
const SNAP: float = 32.0
## Thickness of a wall drawn as a band, and the size of a single click-block.
const DEFAULT_THICKNESS: float = 64.0
## A drag whose thin axis is under this many pixels becomes a band, not a rectangle.
const BAND_THRESHOLD: float = 24.0

var _brush_button: CheckButton = null
var _lint_button: Button = null

var _brush_on: bool = false
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_rect: Rect2 = Rect2()
var _preview: Wall = null
var _target_parent: Node = null
## Raw event positions, used only as a last-resort pointer fallback.
var _last_event_position: Vector2 = Vector2.ZERO
var _reported_sources: bool = false


#region plugin lifecycle

func _enter_tree() -> void:
	_brush_button = CheckButton.new()
	_brush_button.text = "Wall brush"
	_brush_button.tooltip_text = ("Left-drag to draw a wall. Drag along an axis for a wall band, "
		+ "diagonally for a rectangle, click for a block.\nCtrl = square, Alt = no snap, "
		+ "right-click or Esc = cancel.\nWalls are created in the selected Node2D, or in "
		+ "\"Walls\".\nTurn the brush off to select and move nodes again.")
	_brush_button.toggled.connect(_on_brush_toggled)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _brush_button)

	_lint_button = Button.new()
	_lint_button.text = "Lint level"
	_lint_button.tooltip_text = ("Check this level for problems: no spawn, no exit, exits that go "
		+ "nowhere, content inside walls, broken patrol routes, unreachable content.")
	_lint_button.pressed.connect(lint_level)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _lint_button)


func _exit_tree() -> void:
	_cancel_drag()
	if _brush_button != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _brush_button)
		_brush_button.queue_free()
		_brush_button = null
	if _lint_button != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _lint_button)
		_lint_button.queue_free()
		_lint_button = null


## The 2D editor only forwards canvas input while the plugin handles the selection.
## Always claiming Node2D is harmless because `_forward_canvas_gui_input` hands
## every event straight back unless the brush is switched on.
func _handles(object: Object) -> bool:
	return object is Node2D


func _on_brush_toggled(on: bool) -> void:
	_brush_on = on
	if not on:
		_cancel_drag()

#endregion


#region canvas input

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _brush_on:
		return false

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		_last_event_position = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_drag(_cursor_world())
			elif _dragging:
				_commit_drag(_cursor_world())
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _dragging:
			_cancel_drag()
			return true
		return false

	if event is InputEventMouseMotion:
		_last_event_position = (event as InputEventMouseMotion).position
		if _dragging:
			_update_drag(_cursor_world())
			return true
		# Not dragging: hand motion back to the editor so its own hover and selection
		# feedback keep working.
		return false

	if event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and key.keycode == KEY_ESCAPE and _dragging:
			_cancel_drag()
			return true

	return false

#endregion


#region drag handling

## The mouse position in world space.
##
## The 2D editor delivers canvas input events in *editor window* coordinates, which
## are not the same as the 2D viewport's own coordinates: the viewport sits to the
## right of and below the surrounding docks, so converting a raw event position puts
## the cursor down-and-right of the mouse by exactly that offset. That is the bug
## this function exists to avoid.
##
## `Viewport.get_mouse_position()` is documented as being in the viewport's own
## coordinates -- the same space `get_canvas_transform()` expects -- so it is asked
## for first, independently of whatever space the event arrived in.
func _cursor_world() -> Vector2:
	var viewport: Object = get_editor_interface().get_editor_viewport_2d()
	if viewport == null or not viewport.has_method("get_canvas_transform"):
		push_warning("Level Tools: cannot find the 2D editor viewport; wall brush disabled.")
		_brush_on = false
		if _brush_button != null:
			_brush_button.button_pressed = false
		return _last_event_position
	var canvas_transform: Transform2D = viewport.call("get_canvas_transform")
	return canvas_transform.affine_inverse() * _cursor_viewport_position(viewport)


## The mouse position in the 2D viewport's own coordinates. The viewport is the only
## source that is in the space `get_canvas_transform()` expects; the raw event
## position is a last resort.
func _cursor_viewport_position(viewport: Object) -> Vector2:
	if viewport.has_method("get_mouse_position"):
		var from_viewport: Vector2 = viewport.call("get_mouse_position")
		if from_viewport.is_finite():
			return from_viewport
	return _last_event_position


## Prints, once, where the brush's cursor resolved from and to. If placement ever
## lands in the wrong place again, this one line says whether the pointer source or
## the canvas transform should be blamed.
func _report_pointer_once(world: Vector2) -> void:
	if _reported_sources:
		return
	_reported_sources = true
	var viewport: Object = get_editor_interface().get_editor_viewport_2d()
	var viewport_mouse: Variant = "n/a"
	if viewport != null and viewport.has_method("get_mouse_position"):
		viewport_mouse = viewport.call("get_mouse_position")
	print("[Level Tools] cursor: 2D viewport mouse=%s  raw event=%s  ->  world=%s" % [
		viewport_mouse, _last_event_position, world])


func _snap_point(point: Vector2) -> Vector2:
	if SNAP <= 0.0 or Input.is_key_pressed(KEY_ALT):
		return point
	return (point / SNAP).round() * SNAP


## Starts a drag. The wall being drawn is created immediately as a real but *unowned*
## child and follows the drag, so what you see is the actual geometry. Unowned
## children are never serialised, so it cannot be saved into the level by accident.
func _begin_drag(world: Vector2) -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null:
		return
	_target_parent = _wall_parent(root)
	if _target_parent == null:
		return
	_report_pointer_once(world)
	_dragging = true
	_drag_start = _snap_point(world)
	_drag_rect = Rect2(_drag_start - Vector2.ONE * DEFAULT_THICKNESS * 0.5,
		Vector2.ONE * DEFAULT_THICKNESS)

	if _preview == null:
		_preview = WALL_SCENE.instantiate() as Wall
		_preview.name = "WallBrushPreview"
		# Deliberately unowned: Godot does not serialise children that are not owned
		# by the scene root, so the preview can never be saved into the level file.
		_target_parent.add_child(_preview, false, Node.INTERNAL_MODE_DISABLED)
	_apply_preview_rect()


func _update_drag(world: Vector2) -> void:
	if not _dragging:
		return
	_drag_rect = _rect_between(_drag_start, _snap_point(world))
	_apply_preview_rect()


## Moves the in-scene preview wall onto the pending rectangle.
func _apply_preview_rect() -> void:
	if _preview == null or not is_instance_valid(_preview):
		return
	_preview.position = _drag_rect.get_center()
	_preview.size = _drag_rect.size


func _commit_drag(world: Vector2) -> void:
	if not _dragging:
		return
	_update_drag(world)
	var rect: Rect2 = _drag_rect
	_cancel_drag()
	_create_wall(rect)


func _cancel_drag() -> void:
	_dragging = false
	if _preview != null and is_instance_valid(_preview):
		if _preview.get_parent() != null:
			_preview.get_parent().remove_child(_preview)
		_preview.free()
	_preview = null


## Turns a drag into a rectangle. Along an axis it makes a wall band of the default
## thickness; a click makes a block; Ctrl forces a square. Never degenerate.
func _rect_between(from: Vector2, to: Vector2) -> Rect2:
	var delta: Vector2 = to - from
	var rect: Rect2

	if Input.is_key_pressed(KEY_CTRL):
		var side: float = maxf(absf(delta.x), absf(delta.y))
		var sx: float = -1.0 if delta.x < 0.0 else 1.0
		var sy: float = -1.0 if delta.y < 0.0 else 1.0
		rect = Rect2(from, Vector2(side * sx, side * sy))
	elif absf(delta.x) < BAND_THRESHOLD and absf(delta.y) < BAND_THRESHOLD:
		rect = Rect2(from - Vector2.ONE * DEFAULT_THICKNESS * 0.5,
			Vector2.ONE * DEFAULT_THICKNESS)
	elif absf(delta.y) < BAND_THRESHOLD:
		rect = Rect2(Vector2(minf(from.x, to.x), from.y - DEFAULT_THICKNESS * 0.5),
			Vector2(absf(delta.x), DEFAULT_THICKNESS))
	elif absf(delta.x) < BAND_THRESHOLD:
		rect = Rect2(Vector2(from.x - DEFAULT_THICKNESS * 0.5, minf(from.y, to.y)),
			Vector2(DEFAULT_THICKNESS, absf(delta.y)))
	else:
		rect = Rect2(Vector2(minf(from.x, to.x), minf(from.y, to.y)),
			Vector2(absf(delta.x), absf(delta.y)))

	rect.size.x = maxf(rect.size.x, SNAP * 0.5)
	rect.size.y = maxf(rect.size.y, SNAP * 0.5)
	return rect

#endregion


#region wall creation

## Where a drawn wall should go: the selected Node2D, else a node named "Walls",
## else the scene root. Never inside level content.
func _wall_parent(root: Node) -> Node:
	var selection: Array = get_editor_interface().get_selection().get_selected_nodes()
	for node: Node in selection:
		if node is Node2D and not _is_content_node(node):
			return node
	var container: Node = root.find_child("Walls", true, false)
	return container if container != null else root


func _is_content_node(node: Node) -> bool:
	return node is Wall or node is Enemy or node is Pickup or node is ExitZone or node is Lamp


func _unique_name() -> String:
	var root: Node = get_tree().edited_scene_root
	var index: int = 1
	while root != null and root.find_child("DrawnWall%d" % index, true, false) != null:
		index += 1
	return "DrawnWall%d" % index


func _create_wall(rect: Rect2) -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null or _target_parent == null or not is_instance_valid(_target_parent):
		return

	var wall: Wall = WALL_SCENE.instantiate() as Wall
	wall.name = _unique_name()
	# Properties are set before the action, so undo only has to move the node in and
	# out of the tree (and redo reuses this same instance).
	wall.position = rect.get_center()
	wall.size = rect.size

	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Draw wall")
	undo.add_do_method(_target_parent, "add_child", wall, true)
	undo.add_do_method(wall, "set_owner", root)
	undo.add_undo_method(_target_parent, "remove_child", wall)
	undo.add_do_reference(wall)
	undo.commit_action()

	var selection: EditorSelection = get_editor_interface().get_selection()
	if selection != null:
		selection.add_node(wall)

#endregion


#region lint

func lint_level() -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null:
		print_rich("[b]Level lint[/b]: no scene open.")
		return

	var report: Dictionary = LevelLint.run(root)
	print_rich("[b]Level lint[/b] - %s" % root.name)
	print("  %s" % report["summary"])
	for note: String in report["notes"]:
		print("  note: %s" % note)

	var problems: Array = report["problems"]
	if problems.is_empty():
		print_rich("  [color=lightgreen]clean[/color]")
		return
	for problem: String in problems:
		print_rich("  [color=salmon]problem:[/color] %s" % problem)
		push_warning("Level lint: %s" % problem)
	for line: String in report["map"]:
		print("  " + line + "   ('#' wall, '.' walkable, ' ' sealed off)")

#endregion
