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
## WALL EDGES
##   Select one wall (with every tool switched off) and each of its four edges gets a
##   handle. Drag a handle, or anywhere along an edge, to move that edge in or out:
##     * drag                    -> only that edge moves; the opposite one stays put
##     * hold Ctrl               -> the opposite edge moves the same amount the other
##                                  way, so the wall grows or shrinks about its centre
##     * hold Alt                -> ignore grid snapping
##     * right-click or Esc      -> cancel the drag
##   Each drag is one undo step. Dragging the wall's body still moves it as usual.
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
const DOOR_SCENE: PackedScene = preload("res://src/levels/door.tscn")
const SURFACE_DOCK_SCRIPT: GDScript = preload("res://addons/level_tools/surface_dock.gd")
const WALL_EDGES: GDScript = preload("res://addons/level_tools/wall_edges.gd")

## Grid step for snapping. Hold Alt while drawing or placing to ignore it.
const SNAP: float = 32.0
## Thickness of a wall drawn as a band, and the size of a single click-block.
const DEFAULT_THICKNESS: float = 64.0
## A drag whose thin axis is under this many pixels becomes a band, not a rectangle.
const BAND_THRESHOLD: float = 24.0
## Edge handles, in screen pixels so they are the same size at every zoom: the drawn square, how close
## the mouse must be to grab a handle, and to grab an edge anywhere along its length.
const EDGE_HANDLE_SIZE: float = 9.0
const EDGE_HANDLE_GRAB: float = 11.0
const EDGE_LINE_GRAB: float = 6.0
const EDGE_COLOR: Color = Color(1.0, 0.72, 0.25)

var _brush_button: CheckButton = null
var _lint_button: Button = null
var _enemy_button: CheckButton = null
var _enemy_type: OptionButton = null
var _nav_button: Button = null

var _door_button: CheckButton = null
var _door_lock: CheckButton = null

var _surface_dock: EditorDock = null
var _surface_panel: Control = null

var _brush_on: bool = false
var _door_on: bool = false
## Where a door drag started, so the drag direction can set the door's orientation.
var _door_drag_start: Vector2 = Vector2.ZERO
var _door_dragging: bool = false
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

## Wall edge editing: the edge under the mouse, and the drag in progress (which wall, which edge, and its
## rectangle and position when the drag began, so a cancel or an undo can put it back exactly).
var _edge_hover: int = -1
var _edge_wall: Wall = null
var _edge_drag: int = -1
var _edge_start_rect: Rect2 = Rect2()
var _edge_start_position: Vector2 = Vector2.ZERO
## The control the 2D editor lets plugins draw on. The handles are drawn on it *and* the mouse is read
## from it, so the two share one coordinate space and a handle is exactly where it can be grabbed.
var _edge_overlay: Control = null


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

	_nav_button = Button.new()
	_nav_button.text = "Bake navmesh"
	_nav_button.tooltip_text = ("Bake a navigation mesh for this level from its Wall nodes, "
		+"so enemies path around corners instead of grinding into them.\n"
		+"One click: it creates and positions the navigation polygon itself. Re-bake after "
		+"moving walls (the linter reports a mesh that no longer matches the level).")
	_nav_button.pressed.connect(bake_navmesh)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _nav_button)

	_door_button = CheckButton.new()
	_door_button.text = "Place door"
	_door_button.tooltip_text = ("Click where a doorway should be, then drag along the wall to set "
		+"its direction; release to place it. A plain click places a door across the gap "
		+"horizontally.\nA door belongs IN a gap: leave a door-sized opening in the wall first "
		+"(the door does not cut the wall for you).\nDoors are left out of the navmesh bake on "
		+"purpose, so enemies path through doorways and then open the door.\nAlt = no snap.")
	_door_button.toggled.connect(_on_door_toggled)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _door_button)

	_door_lock = CheckButton.new()
	_door_lock.text = "Locked"
	_door_lock.tooltip_text = ("Place locked doors: they need a key to open, and dashing into one "
		+"only makes noise. Keys are universal, and the player can carry as many as they find.")
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _door_lock)

	_lint_button = Button.new()
	_lint_button.text = "Lint level"
	_lint_button.tooltip_text = ("Check this level for problems: no spawn, no exit, exits that go "
		+"nowhere, content inside walls, broken patrol routes, unreachable content.")
	_lint_button.pressed.connect(lint_level)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _lint_button)

	_add_surface_dock()
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)


func _exit_tree() -> void:
	_cancel_drag()
	_forget_pending_enemy()
	_cancel_edge_drag()
	var selection: EditorSelection = EditorInterface.get_selection()
	if selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)
	_remove_surface_dock()
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
	if _nav_button != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _nav_button)
		_nav_button.queue_free()
		_nav_button = null
	if _door_button != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _door_button)
		_door_button.queue_free()
		_door_button = null
	if _door_lock != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _door_lock)
		_door_lock.queue_free()
		_door_lock = null
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


#region surfaces dock

func _add_surface_dock() -> void:
	_surface_panel = SURFACE_DOCK_SCRIPT.new()
	_surface_panel.set("undo", get_undo_redo())
	_surface_dock = EditorDock.new()
	_surface_dock.title = "Surfaces"
	_surface_dock.layout_key = "level_tools_surfaces"
	_surface_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_surface_dock.add_child(_surface_panel)
	add_dock(_surface_dock)
	# New, renamed or deleted style files, and switching between levels, both change what the dock
	# should list and which entries are in use.
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_surfaces_maybe_changed)
	scene_changed.connect(_on_scene_changed_for_surfaces)
	EditorInterface.get_inspector().property_edited.connect(_on_inspector_property_edited)


func _remove_surface_dock() -> void:
	var file_system: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if file_system.filesystem_changed.is_connected(_on_surfaces_maybe_changed):
		file_system.filesystem_changed.disconnect(_on_surfaces_maybe_changed)
	if scene_changed.is_connected(_on_scene_changed_for_surfaces):
		scene_changed.disconnect(_on_scene_changed_for_surfaces)
	var inspector: EditorInspector = EditorInterface.get_inspector()
	if inspector.property_edited.is_connected(_on_inspector_property_edited):
		inspector.property_edited.disconnect(_on_inspector_property_edited)
	if _surface_dock != null:
		remove_dock(_surface_dock)
		_surface_dock.queue_free()
		_surface_dock = null
		_surface_panel = null


func _on_surfaces_maybe_changed() -> void:
	if _surface_panel != null:
		_surface_panel.call("refresh")


func _on_scene_changed_for_surfaces(_root: Node) -> void:
	_on_surfaces_maybe_changed()


## Picking a style from the Level's own dropdown should move the dock's "in use" marker too.
func _on_inspector_property_edited(property: String) -> void:
	if property == "wall_surface_id" or property == "floor_surface_id":
		if _surface_panel != null:
			_surface_panel.call("queue_refresh")

#endregion


#region canvas input

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _brush_on:
		return _brush_input(event)
	if _enemy_on:
		return _enemy_input(event)
	if _door_on:
		return _door_input(event)
	return _edge_input(event)


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


#region wall edges

## The wall whose edges can be dragged: exactly one Wall selected, and no tool switched on (every tool
## wants the left mouse button for itself).
func _edited_wall() -> Wall:
	if _brush_on or _enemy_on or _door_on:
		return null
	var nodes: Array = EditorInterface.get_selection().get_selected_nodes()
	if nodes.size() != 1:
		return null
	var wall := nodes[0] as Wall
	if wall == null or not wall.is_inside_tree():
		return null
	return wall


func _on_selection_changed() -> void:
	_cancel_edge_drag()
	_edge_hover = -1
	update_overlays()


## Grabbing and dragging an edge. Everything that is not on an edge is handed back to the editor, so
## selecting, moving the wall by its body and box-selecting all keep working with a wall selected.
func _edge_input(event: InputEvent) -> bool:
	var wall: Wall = _edited_wall()
	if wall == null:
		if _edge_hover != -1:
			_edge_hover = -1
			update_overlays()
		return false

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		_last_event_position = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var edge: int = _edge_under_mouse(wall)
				if edge == -1:
					return false
				_begin_edge_drag(wall, edge)
				return true
			if _edge_drag != -1:
				_commit_edge_drag()
				return true
			return false
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _edge_drag != -1:
			_cancel_edge_drag()
			return true
		return false

	if event is InputEventMouseMotion:
		_last_event_position = (event as InputEventMouseMotion).position
		if _edge_drag != -1:
			_update_edge_drag()
			return true
		var hover: int = _edge_under_mouse(wall)
		if hover != _edge_hover:
			_edge_hover = hover
			update_overlays()
		return false

	if event is InputEventKey:
		var key: InputEventKey = event
		if _edge_drag != -1 and key.pressed and key.keycode == KEY_ESCAPE:
			_cancel_edge_drag()
			return true
		# Pressing or releasing Ctrl mid-drag switches between one edge and both, without waiting for
		# the mouse to move.
		if _edge_drag != -1 and key.keycode == KEY_CTRL:
			_update_edge_drag()
			return true
	return false


func _edge_under_mouse(wall: Wall) -> int:
	if _edge_overlay == null or not is_instance_valid(_edge_overlay):
		return -1
	return WALL_EDGES.pick(wall.world_rect(), _world_to_overlay(),
		_edge_overlay.get_local_mouse_position(), EDGE_HANDLE_GRAB, EDGE_LINE_GRAB)


## World space to the overlay's pixels: the edited scene's own canvas transform, then the editor's pan
## and zoom. The editor's 2D viewport has no camera; it applies the view through
## `global_canvas_transform`, so `canvas_transform` alone ignores the view entirely (that drew the
## handles at raw world coordinates, pinned to one spot on screen, and made them impossible to click).
func _world_to_overlay() -> Transform2D:
	var viewport: SubViewport = EditorInterface.get_editor_viewport_2d()
	if viewport == null:
		return Transform2D.IDENTITY
	return viewport.global_canvas_transform * viewport.canvas_transform


## The mouse in world space, read through the same overlay and transform the handles are drawn with.
func _edge_cursor_world() -> Vector2:
	if _edge_overlay == null or not is_instance_valid(_edge_overlay):
		return _cursor_world()
	return _world_to_overlay().affine_inverse() * _edge_overlay.get_local_mouse_position()


func _begin_edge_drag(wall: Wall, edge: int) -> void:
	_edge_wall = wall
	_edge_drag = edge
	_edge_start_rect = wall.world_rect()
	_edge_start_position = wall.position
	update_overlays()


## Live: the wall follows the mouse while dragging, so what you see is the real geometry (the level
## rebuilds its surfaces to match). The undo step is only made on release.
func _update_edge_drag() -> void:
	if _edge_wall == null or not is_instance_valid(_edge_wall):
		_edge_drag = -1
		return
	var coordinate: float = WALL_EDGES.axis_coordinate(_edge_drag, _snap_point(_edge_cursor_world()))
	var rect: Rect2 = WALL_EDGES.dragged(_edge_start_rect, _edge_drag, coordinate,
		Input.is_key_pressed(KEY_CTRL), SNAP * 0.5)
	_apply_wall_rect(_edge_wall, rect)
	update_overlays()


func _commit_edge_drag() -> void:
	var wall: Wall = _edge_wall
	var start_size: Vector2 = _edge_start_rect.size
	var start_position: Vector2 = _edge_start_position
	_edge_drag = -1
	_edge_wall = null
	if wall == null or not is_instance_valid(wall):
		return
	if wall.size == start_size and wall.position == start_position:
		update_overlays()
		return
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Resize wall")
	undo.add_do_property(wall, "size", wall.size)
	undo.add_do_property(wall, "position", wall.position)
	undo.add_undo_property(wall, "size", start_size)
	undo.add_undo_property(wall, "position", start_position)
	undo.commit_action()
	update_overlays()


## Puts the wall back where the drag found it, without touching the undo history.
func _cancel_edge_drag() -> void:
	if _edge_drag != -1 and _edge_wall != null and is_instance_valid(_edge_wall):
		_edge_wall.size = _edge_start_rect.size
		_edge_wall.position = _edge_start_position
	_edge_drag = -1
	_edge_wall = null
	update_overlays()


## A wall is its centre plus its size, so a new rectangle is both. Size first: setting it rebuilds the
## wall's shapes, and the position move after it is then a plain transform change.
func _apply_wall_rect(wall: Wall, rect: Rect2) -> void:
	wall.size = rect.size
	wall.global_position = rect.get_center()


## The handles, drawn over the 2D viewport, through the same transform the mouse is tested against.
func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	_edge_overlay = overlay
	var wall: Wall = _edited_wall()
	if wall == null:
		return
	var to_overlay: Transform2D = _world_to_overlay()

	var rect: Rect2 = wall.world_rect()
	var active: int = _edge_drag if _edge_drag != -1 else _edge_hover
	for edge: int in [0, 1, 2, 3]:
		var ends: PackedVector2Array = WALL_EDGES.segment(rect, edge)
		var hot: bool = edge == active
		overlay.draw_line(to_overlay * ends[0], to_overlay * ends[1],
			EDGE_COLOR if hot else Color(EDGE_COLOR, 0.45), 3.0 if hot else 1.5)
		var centre: Vector2 = to_overlay * WALL_EDGES.handle(rect, edge)
		var half: float = EDGE_HANDLE_SIZE * (0.65 if hot else 0.5)
		var square := Rect2(centre - Vector2.ONE * half, Vector2.ONE * half * 2.0)
		overlay.draw_rect(square, EDGE_COLOR if hot else Color(0.1, 0.1, 0.12, 0.9))
		overlay.draw_rect(square, EDGE_COLOR, false, 1.5)

	if _edge_drag != -1:
		# The size as it will be saved, next to the cursor, so a wall can be dragged to an exact length.
		var mode: String = "  (both edges)" if Input.is_key_pressed(KEY_CTRL) else ""
		overlay.draw_string(ThemeDB.fallback_font,
			to_overlay * WALL_EDGES.handle(rect, _edge_drag) + Vector2(14.0, -10.0),
			"%d x %d%s" % [roundi(rect.size.x), roundi(rect.size.y), mode],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, EDGE_COLOR)

#endregion


#region door tool

func _on_door_toggled(on: bool) -> void:
	_door_on = on
	if not on:
		_door_dragging = false
		return
	# One left-mouse tool at a time.
	if _brush_button != null and _brush_button.button_pressed:
		_brush_button.button_pressed = false
	if _enemy_button != null and _enemy_button.button_pressed:
		_enemy_button.button_pressed = false


## Click where the doorway is, drag along the wall, release. The drag direction decides whether
## the leaf lies horizontally or vertically, which is the only thing about a door that has to
## match the wall it sits in.
func _door_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		_last_event_position = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_door_drag_start = _snap_point(_cursor_world())
				_door_dragging = true
			elif _door_dragging:
				_door_dragging = false
				_place_door(_door_drag_start, _door_rotation(_cursor_world()))
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _door_dragging:
			_door_dragging = false
			return true
		return false

	if event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and key.keycode == KEY_ESCAPE and _door_dragging:
			_door_dragging = false
			return true

	return false


## 0 puts the leaf along X (a gap in a north-south wall), PI/2 along Y (a gap in an east-west
## wall). A click with no drag builds the first.
func _door_rotation(at: Vector2) -> float:
	var delta: Vector2 = at - _door_drag_start
	if delta.length() < 8.0:
		return 0.0
	return 0.0 if absf(delta.x) >= absf(delta.y) else PI * 0.5


func _place_door(at: Vector2, rotation: float) -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null:
		return
	var door: Door = DOOR_SCENE.instantiate() as Door
	if door == null:
		return
	door.name = _unique_child_name(root, "Door")
	door.starts_locked = _door_lock != null and _door_lock.button_pressed
	door.position = at
	door.rotation = rotation
	_add_door(root, door)
	_focus_node(door)


## Doors live in the level's "Doors" container, and the container is created if the level does
## not have one yet -- a new level should not need to be set up by hand before a tool works.
##
## Door and container go into a *single* undo step, so one Ctrl+Z takes back both the door and the
## container it brought with it, rather than leaving an empty node behind.
func _add_door(root: Node, door: Door) -> void:
	var container: Node = root.find_child("Doors", true, false)
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Place door")
	if container == null:
		var fresh := Node2D.new()
		fresh.name = "Doors"
		undo.add_do_method(root, "add_child", fresh, true)
		undo.add_do_method(fresh, "set_owner", root)
		undo.add_undo_method(root, "remove_child", fresh)
		undo.add_do_reference(fresh)
		container = fresh
	undo.add_do_method(container, "add_child", door, true)
	undo.add_do_method(door, "set_owner", root)
	undo.add_undo_method(container, "remove_child", door)
	undo.add_do_reference(door)
	undo.commit_action()


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
	return (node is Wall or node is Enemy or node is Pickup or node is ExitZone
		or node is Lamp or node is NavigationRegion2D)


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


#region navmesh

## Bakes a navigation mesh for the open level from its Wall nodes.
##
## One click, no hand-drawn polygons: `NavmeshBaker` points the polygon at the level's
## static colliders as obstacles and gives it a single outline around everything, so
## the walkable area falls out of the geometry itself. Re-run it whenever the walls
## change -- the linter reports a mesh that no longer matches the level.
func bake_navmesh() -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null:
		print_rich("[b]Navmesh[/b]: no scene open.")
		return
	var walls: Array[Wall] = _walls_under(root)
	if walls.is_empty():
		push_warning("Navmesh: this level has no Wall nodes to bake from.")
		return

	var region: NavigationRegion2D = root.find_child("Nav", true, false) as NavigationRegion2D
	var creating: bool = region == null
	if creating:
		region = NavigationRegion2D.new()
		region.name = "Nav"

	# Bake into a fresh polygon, so the undo step is a plain swap between the old mesh
	# and the new one.
	var polygon := NavigationPolygon.new()
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Bake navmesh")
	if creating:
		undo.add_do_method(root, "add_child", region, true)
		undo.add_do_method(region, "set_owner", root)
		undo.add_undo_method(root, "remove_child", region)
		undo.add_do_reference(region)
	elif region.navigation_polygon != null:
		undo.add_undo_property(region, "navigation_polygon",
			region.navigation_polygon.duplicate(true))
	undo.add_do_property(region, "navigation_polygon", polygon)
	undo.commit_action()

	_report_navmesh(NavmeshBaker.bake(region, walls))


func _report_navmesh(report: Dictionary) -> void:
	var polygons: int = int(report["polygons"])
	print_rich("[b]Navmesh[/b] - baked from %d walls into %d convex polygon(s)." % [
		int(report["walls"]), polygons])
	if polygons == 0:
		push_warning("Navmesh: baking produced no polygons, so enemies will steer directly "
			+ "instead. Check that the level's geometry is made of Wall nodes.")
	else:
		print("  Re-bake after moving walls; the linter says when the mesh is stale.")


func _walls_under(root: Node) -> Array[Wall]:
	var out: Array[Wall] = []
	for child: Node in root.get_children():
		var wall := child as Wall
		if wall != null:
			out.append(wall)
		out.append_array(_walls_under(child))
	return out

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

	# The chain lives in one table, so checking only the open level cannot see a level that is not in
	# it, a duplicate, or a path that has been renamed.
	var campaign_problems: Array[String] = LevelLint.campaign()
	for problem: String in campaign_problems:
		print_rich("  [color=salmon]campaign:[/color] %s" % problem)
		push_warning("Campaign: %s" % problem)

	var problems: Array = report["problems"]
	if problems.is_empty() and campaign_problems.is_empty():
		print_rich("  [color=lightgreen]clean[/color]")
		return
	for problem: String in problems:
		print_rich("  [color=salmon]problem:[/color] %s" % problem)
		push_warning("Level lint: %s" % problem)
	for line: String in report["map"]:
		print("  " + line + "   ('#' wall, '.' walkable, ' ' sealed off)")

#endregion
