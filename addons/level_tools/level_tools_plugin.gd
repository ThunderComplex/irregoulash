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
const ENEMY_SCENE: PackedScene = preload("res://src/enemies/enemy.tscn")

## Grid step for snapping. Hold Alt while drawing or placing to ignore it.
const SNAP: float = 32.0
## Thickness of a wall drawn as a band, and the size of a single click-block.
const DEFAULT_THICKNESS: float = 64.0
## A drag whose thin axis is under this many pixels becomes a band, not a rectangle.
const BAND_THRESHOLD: float = 24.0

var _brush_button: CheckButton = null
var _lint_button: Button = null
var _enemy_button: CheckButton = null
var _enemy_type: OptionButton = null

var _brush_on: bool = false
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_rect: Rect2 = Rect2()
var _preview: Wall = null
## The container walls are drawn into. Resolved once and kept, so drawing does not
## depend on whatever happens to be selected.
var _target_parent: Node = null
## The node this plugin last put into the selection itself, so a selection that is
## *not* this can be recognised as the user picking a different container.
var _our_selection: Node = null
## Raw event positions, used only as a last-resort pointer fallback.
var _last_event_position: Vector2 = Vector2.ZERO
var _reported_sources: bool = false

## Enemy tool state: the enemy waiting for waypoints, and its route.
var _enemy_on: bool = false
var _pending_enemy: Enemy = null
var _pending_route: PatrolRoute = null


#region plugin lifecycle

func _enter_tree() -> void:
	_brush_button = CheckButton.new()
	_brush_button.text = "Wall brush"
	_brush_button.tooltip_text = ("Left-drag to draw a wall. Drag along an axis for a wall band, "
		+"diagonally for a rectangle, click for a block.\nCtrl = square, Alt = no snap, "
		+"right-click or Esc = cancel.\nWalls go into the container the brush is pinned to "
		+"(a selected Node2D, else \"Walls\"), which stays selected so you can keep drawing.\n"
		+"Select a different Node2D in the Scene dock to redirect it. Turn the brush off to "
		+"select, move and resize nodes.")
	_brush_button.toggled.connect(_on_brush_toggled)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _brush_button)

	_enemy_type = OptionButton.new()
	_enemy_type.tooltip_text = "Archetype placed by the enemy tool."
	for id: String in EnemyLibrary.ids():
		_enemy_type.add_item(EnemyLibrary.by_id(id).display_name)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _enemy_type)

	_enemy_button = CheckButton.new()
	_enemy_button.text = "Place enemy"
	_enemy_button.tooltip_text = ("Click to place the selected enemy, then keep left-clicking to "
		+"add patrol waypoints, then right-click (or Esc) to finish. Finishing switches the "
		+"tool off, so press it again for the next enemy.\n"
		+"No waypoints: it wanders near where it stands. One: it stands there and scans. "
		+"Two or more: it patrols them in order.\nAlt = no snap.")
	_enemy_button.toggled.connect(_on_enemy_toggled)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _enemy_button)

	_lint_button = Button.new()
	_lint_button.text = "Lint level"
	_lint_button.tooltip_text = ("Check this level for problems: no spawn, no exit, exits that go "
		+"nowhere, content inside walls, broken patrol routes, unreachable content.")
	_lint_button.pressed.connect(lint_level)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _lint_button)


func _exit_tree() -> void:
	_cancel_drag()
	_forget_pending_enemy()
	if _brush_button != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _brush_button)
		_brush_button.queue_free()
		_brush_button = null
	if _enemy_button != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _enemy_button)
		_enemy_button.queue_free()
		_enemy_button = null
	if _enemy_type != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _enemy_type)
		_enemy_type.queue_free()
		_enemy_type = null
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
		return
	# Both tools want the left mouse button, so switching one on switches the other off.
	if _enemy_button != null and _enemy_button.button_pressed:
		_enemy_button.button_pressed = false
	# Anchor the brush to a container and select it, so the editor keeps forwarding
	# canvas input and the first drag already goes to the right place.
	_resolve_target_parent()


func _on_enemy_toggled(on: bool) -> void:
	_enemy_on = on
	if not on:
		# Finishing rather than discarding: the enemy is already a real node.
		_finish_enemy()
		return
	if _brush_button != null and _brush_button.button_pressed:
		_brush_button.button_pressed = false


## Archetype currently selected in the toolbar.
func _selected_archetype() -> String:
	var ids: Array[String] = EnemyLibrary.ids()
	if _enemy_type == null or ids.is_empty():
		return "guard"
	return ids[clampi(_enemy_type.selected, 0, ids.size() - 1)]

#endregion


#region canvas input

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _brush_on:
		return _brush_input(event)
	if _enemy_on:
		return _enemy_input(event)
	return false


## The wall brush's input. Both tools want the left mouse button, so only one of them
## can be switched on at a time (see the toolbar toggles).
func _brush_input(event: InputEvent) -> bool:
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


#region enemy tool

## Left-click places the selected enemy, then each further click adds a waypoint to
## that enemy's own route; right-click or Esc finishes. The enemy is committed to the
## scene immediately and the route is committed point by point, so undo walks the
## route back instead of throwing the whole enemy away.
func _enemy_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		_last_event_position = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_enemy_click(_snap_point(_cursor_world()))
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _pending_enemy != null:
			_finish_enemy()
			return true
		return false

	if event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and key.keycode == KEY_ESCAPE and _pending_enemy != null:
			_finish_enemy()
			return true

	return false


func _enemy_click(at: Vector2) -> void:
	if _pending_enemy == null or not is_instance_valid(_pending_enemy):
		_place_enemy(at)
	else:
		_add_waypoint(at)


## Places one enemy of the selected archetype, which then collects waypoints.
func _place_enemy(at: Vector2) -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null:
		return
	var archetype: String = _selected_archetype()
	var display: String = EnemyLibrary.by_id(archetype).display_name
	var enemy: Enemy = ENEMY_SCENE.instantiate() as Enemy
	enemy.name = _unique_child_name(root, display)
	enemy.archetype_id = archetype
	enemy.position = at
	enemy.rotation = 0.0
	_add_through_undo("Place %s" % display, _enemy_parent(root), enemy, root)
	_pending_enemy = enemy
	_pending_route = null
	_focus_node(enemy)


## Adds one waypoint, creating the route and wiring the enemy to it on the first one
## (all in the same undo step, so one undo unlinks it again).
func _add_waypoint(at: Vector2) -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null or _pending_enemy == null or not is_instance_valid(_pending_enemy):
		return

	if _pending_route == null or not is_instance_valid(_pending_route):
		_pending_route = PatrolRoute.new()
		_pending_route.name = "%sRoute" % _pending_enemy.name
		var undo: EditorUndoRedoManager = get_undo_redo()
		undo.create_action("Add patrol route")
		undo.add_do_method(_route_parent(root, _pending_enemy), "add_child", _pending_route, true)
		undo.add_do_method(_pending_route, "set_owner", root)
		undo.add_undo_method(_route_parent(root, _pending_enemy), "remove_child", _pending_route)
		undo.add_do_reference(_pending_route)
		undo.add_do_method(self, "_link_route", _pending_enemy, _pending_route)
		undo.add_undo_method(self, "_link_route", _pending_enemy, null)
		undo.commit_action()

	# Waypoints are added in click order, which is the order PatrolRoute reads them
	# back in, so the enemy patrols them in the order you clicked them.
	var marker := Marker2D.new()
	marker.name = "P%d" % _pending_route.get_child_count()
	marker.position = _pending_route.to_local(at)
	_add_through_undo("Add patrol point", _pending_route, marker, root)


## Ends the current enemy's route and switches the tool off, so placing another enemy
## is a deliberate act (press the button again) rather than something that can happen
## while you meant to select a node. Nothing needs committing -- the enemy and its
## waypoints are already real nodes -- so this only stops collecting points and says
## what the enemy will do with what it has.
func _finish_enemy() -> void:
	var enemy: Enemy = _pending_enemy
	var waypoints: int = 0
	if _pending_route != null and is_instance_valid(_pending_route):
		waypoints = _pending_route.points().size()
	_forget_pending_enemy()

	if enemy != null and is_instance_valid(enemy):
		if waypoints == 0:
			print("[Level Tools] %s has no waypoints: it will wander near where it stands." % enemy.name)
		elif waypoints == 1:
			print("[Level Tools] %s has one waypoint: it will stand there and scan." % enemy.name)
		else:
			print("[Level Tools] %s patrols %d waypoints." % [enemy.name, waypoints])

	# `set_pressed_no_signal` rather than `button_pressed`: un-pressing normally emits
	# `toggled`, which calls straight back into this function.
	if _enemy_button != null and _enemy_button.button_pressed:
		_enemy_button.set_pressed_no_signal(false)
	_enemy_on = false


## Drops the tool's state without touching the scene (the enemy is already real).
func _forget_pending_enemy() -> void:
	_pending_enemy = null
	_pending_route = null


## Assigning and clearing the link through a method means the NodePath is resolved
## while both nodes are in the tree, which is true during do and undo but not while
## the action is being built.
func _link_route(enemy: Enemy, route: PatrolRoute) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if route == null or not is_instance_valid(route):
		enemy.patrol_route = NodePath("")
		return
	enemy.patrol_route = enemy.get_path_to(route)


## Enemies go in a node called "Enemies" when the level has one.
func _enemy_parent(root: Node) -> Node:
	var container: Node = root.find_child("Enemies", true, false)
	return container if container != null else root


## Routes live in the level's "Routes" container when it has one, next to the enemy
## otherwise. Either way they are *not* children of the enemy: a route must not move
## when the thing patrolling it moves.
func _route_parent(root: Node, enemy: Node) -> Node:
	var container: Node = root.find_child("Routes", true, false)
	if container != null:
		return container
	var parent: Node = enemy.get_parent()
	return parent if parent != null else root

#endregion


#region placing nodes (shared by both tools)

## Adds a node to the scene through the editor's undo history, owned by the edited
## scene so that it is actually saved with the level.
func _add_through_undo(action: String, parent: Node, node: Node, root: Node) -> void:
	if parent == null:
		parent = root
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action(action)
	undo.add_do_method(parent, "add_child", node, true)
	undo.add_do_method(node, "set_owner", root)
	undo.add_undo_method(parent, "remove_child", node)
	undo.add_do_reference(node)
	undo.commit_action()


## First free "<base>N" in the edited scene, so repeated placement reads tidily.
func _unique_child_name(root: Node, base: String) -> String:
	var index: int = 1
	while root.find_child("%s%d" % [base, index], true, false) != null:
		index += 1
	return "%s%d" % [base, index]


## Selects exactly one node, and remembers that this selection was made by the plugin:
## the editor forwards canvas input based on the selection, and a selection that is
## not ours means the user has picked something themselves.
func _focus_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_our_selection = node
	var selection: EditorSelection = get_editor_interface().get_selection()
	if selection == null:
		return
	var current: Array = selection.get_selected_nodes()
	if current.size() == 1 and current[0] == node:
		return
	selection.clear()
	selection.add_node(node)

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
	_target_parent = _resolve_target_parent()
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

## Where a drawn wall should go, resolved once and then remembered.
##
## The editor forwards canvas input based on what is selected, and this used to be
## re-derived from the selection on every drag while drawing *changed* the selection
## to the new wall -- so after the first wall the brush had to guess at a parent and
## stopped behaving. Now:
##   * a selection that is not the one this plugin made means the user picked a
##     different container, so that wins,
##   * otherwise the remembered container is reused (draw wall after wall),
##   * and failing all that, the conventional "Walls" node, else the scene root.
func _resolve_target_parent() -> Node:
	var root: Node = get_tree().edited_scene_root
	if root == null:
		return null

	var selection: Array = get_editor_interface().get_selection().get_selected_nodes()
	for node: Node in selection:
		if node is Node2D and not _is_content_node(node) and node != _our_selection:
			_target_parent = node
			_focus_target_parent()
			return _target_parent

	if _target_parent != null and is_instance_valid(_target_parent):
		return _target_parent

	_target_parent = root.find_child("Walls", true, false)
	if _target_parent == null:
		_target_parent = root
	_focus_target_parent()
	return _target_parent


## Puts the drawing container back in the selection, and remembers that this selection
## was ours. Keeping a plain Node2D selected is what lets canvas input keep reaching
## the plugin, so the brush can be used over and over without touching the Scene dock.
func _focus_target_parent() -> void:
	_focus_node(_target_parent)


func _is_content_node(node: Node) -> bool:
	return node is Wall or node is Enemy or node is Pickup or node is ExitZone or node is Lamp


func _create_wall(rect: Rect2) -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null or _target_parent == null or not is_instance_valid(_target_parent):
		return

	var wall: Wall = WALL_SCENE.instantiate() as Wall
	wall.name = _unique_child_name(root, "DrawnWall")
	# Properties are set before the action, so undo only has to move the node in and
	# out of the tree (and redo reuses this same instance).
	wall.position = rect.get_center()
	wall.size = rect.size
	_add_through_undo("Draw wall", _target_parent, wall, root)

	# Keep the container selected, not the new wall: canvas input forwarding follows
	# the selection, and the whole point is to draw several walls in a row.
	_focus_target_parent()

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
