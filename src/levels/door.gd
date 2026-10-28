@tool
class_name Door
extends Node2D
## A door in a wall: it blocks movement, bullets and light while shut, and stops blocking all
## three when it is open. In a game about line of sight that makes every door a decision --
## open it and the room (and you) become visible, shut it and the line of sight is gone.
##
## States are `open`, `locked` and `broken`, and broken is permanent. Dashing into an unlocked
## door smashes it; dashing into a locked one only makes noise, and never opens it. Locked doors
## consume one key from the player, and any key opens any door.
##
## The node builds everything it needs (collider, occluder, leaf, hinge) in `_ready` rather than
## relying on the scene carrying them, so a door created in code is as complete as one placed by
## hand. That lesson came from enemy loot, which was spawned as a bare script instance and could
## never be picked up.
##
## Deliberately NOT a `Wall` and not in the `wall` group: the navmesh bake reads that group, and
## doors have to be passable in the baked mesh or enemies could never path through a doorway.

signal changed()

enum State { CLOSED, OPEN, BROKEN }

## Footprint of the closed door, in pixels. The leaf's long axis is local X, so a door filling a
## gap in a north-south wall is rotated 90 degrees.
@export var size: Vector2 = Vector2(96.0, 32.0):
	set(value):
		size = value
		# Never rebuild in the editor: these are runtime nodes, and creating them there would be
		# written into the level file (see dev/check_scene_hygiene.gd).
		if is_inside_tree() and not Engine.is_editor_hint():
			_rebuild_geometry()
		queue_redraw()


## Starts shut and locked: needs a key, and dashing into it does not help.
@export var starts_locked: bool = false:
	set(value):
		starts_locked = value
		queue_redraw()
## Starts open, for doorways that are meant to read as already used.
@export var starts_open: bool = false:
	set(value):
		starts_open = value
		queue_redraw()

var state: State = State.CLOSED
var locked: bool = false

var _leaf: Node2D = null
var _solid: StaticBody2D = null
var _collision: CollisionShape2D = null
var _occluder: LightOccluder2D = null
var _polygon: OccluderPolygon2D = null
var _tween: Tween = null
## The enemy that opened this door and still intends to shut it behind itself.
var _closer: Node = null


func _ready() -> void:
	# Editor: gizmo only. Building nodes here would write them into the level file.
	if Engine.is_editor_hint():
		return
	# Found by group rather than by walking a parent's children: doors may sit under a "Doors"
	# container, a room node, or directly in the level, and interaction should not care which.
	add_to_group(&"door")
	locked = starts_locked
	state = State.OPEN if starts_open else State.CLOSED
	_rebuild_geometry()
	_leaf.rotation = PI * 0.5 if state == State.OPEN else 0.0
	_apply_state()


#region state

func is_shut() -> bool:
	return state == State.CLOSED


## Whether this door currently stops movement (and bullets, and light).
func is_barrier() -> bool:
	return state == State.CLOSED


## Whether it can be opened without a key.
func is_openable() -> bool:
	return not locked


## Player interaction: open a shut door, shut an open one, unlock a locked one with a key.
## Returns whether anything changed.
func interact(by: Node) -> bool:
	if state == State.BROKEN:
		return false
	if state == State.CLOSED:
		if locked:
			if not _consume_key(by):
				_refused(by)
				return false
			locked = false
			_build_leaf_art()
			AudioDirector.play_at(&"door_unlock", global_position, -4.0)
		_set_shut(false, by)
		return true
	if not can_close():
		GameDirector.announce_message("Something is in the doorway", Color(0.9, 0.75, 0.5))
		return false
	_set_shut(true, by)
	return true


## Dash impact. An unlocked door is destroyed for good; a locked one only rattles -- louder than
## touching it, quieter than a door coming off its hinges -- and stays shut.
func smash(by: Node) -> void:
	if state == State.BROKEN:
		return
	if locked:
		_refused(by, true)
		return
	state = State.BROKEN
	_closer = null
	_apply_state()
	# The leaf hangs open where the dash threw it.
	_hinge(Tween.TRANS_CUBIC, PI * 0.5)
	_leaf.modulate.a = 0.5
	AudioDirector.play_at(&"door_smash", global_position, -2.0)
	FxDirector.shake(0.3)
	FxDirector.spark_burst(global_position, Vector2.UP, 12, Color(0.9, 0.76, 0.5), 170.0, 0.4)
	GameDirector.make_noise(global_position, Tuning.noise_door_smash, by)
	GameDirector.announce_message("DOOR SMASHED", Color(0.95, 0.85, 0.6))
	changed.emit()


## Enemies call this when a shut door is in their way. Quiet compared to the player wrenching it
## open, but not silent: an enemy opening a door tells you roughly where it is.
func open_for_enemy(by: Node) -> bool:
	if state != State.CLOSED or locked:
		return false
	_closer = by
	_set_shut(false, by, true)
	return true


## Called by the enemy that opened this door once it is clear of the doorway, so doors shut behind
## passing patrols instead of ending up all open by the end of a fight.
func close_if_enemy_clear(by: Node) -> void:
	if state != State.OPEN or _closer != by:
		return
	var body := by as Node2D
	if body == null or not is_instance_valid(body):
		_closer = null
		return
	if global_position.distance_to(body.global_position) < Tuning.door_close_distance:
		return
	if not can_close():
		return
	_closer = null
	_set_shut(true, by, true)


## Distance from `point` to the nearest edge of the door, in pixels (0 if inside it). Measured to
## the surface rather than the centre: a 96-pixel-wide door's centre is 48px from its edge, so a
## player standing against it would read as "far away" by a centre-to-centre measure.
func surface_distance(point: Vector2) -> float:
	var local: Vector2 = to_local(point)
	var half: Vector2 = size * 0.5
	var closest := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
	return maxf(0.0, local.distance_to(closest))


## Whether the doorway is empty enough to shut. Closing a door on top of someone would leave them
## stuck inside its collider.
func can_close() -> bool:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return true
	var shape := RectangleShape2D.new()
	shape.size = size * 0.9
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = Layers.PLAYER | Layers.ENEMY
	query.collide_with_areas = false
	return space.intersect_shape(query, 1).is_empty()

#endregion


#region geometry

## (Re)builds the collider, occluder and leaf. Idempotent, so a door resized in the editor or
## created in code ends up identical to one authored in a scene.
func _rebuild_geometry() -> void:
	if _solid == null:
		_solid = StaticBody2D.new()
		_solid.name = "Solid"
		# WORLD: stops the player and enemies, catches bullets, and blocks the raycasts that
		# enemy sight and lamp visibility use. One layer, three jobs, all of them wanted.
		_solid.collision_layer = Layers.WORLD
		_solid.collision_mask = 0
		add_child(_solid)
	if _collision == null:
		_collision = CollisionShape2D.new()
		_collision.name = "Collision"
		_solid.add_child(_collision)
	var rect := RectangleShape2D.new()
	rect.size = size
	_collision.shape = rect

	if _occluder == null:
		_occluder = LightOccluder2D.new()
		_occluder.name = "Occluder"
		_polygon = OccluderPolygon2D.new()
		_occluder.occluder = _polygon
		add_child(_occluder)
	_polygon.polygon = Shapes.rect(size)
	_polygon.closed = true

	if _leaf == null:
		_leaf = Node2D.new()
		_leaf.name = "Leaf"
		add_child(_leaf)
	_build_leaf_art()


## The leaf: a panel hinged at its left edge, so rotating the parent swings the free edge.
func _build_leaf_art() -> void:
	if _leaf == null:
		return
	for child: Node in _leaf.get_children():
		child.free()

	var corners := PackedVector2Array([
		Vector2(0.0, -size.y * 0.5),
		Vector2(size.x, -size.y * 0.5),
		Vector2(size.x, size.y * 0.5),
		Vector2(0.0, size.y * 0.5),
	])
	var pivot := Vector2(-size.x * 0.5, 0.0)

	var panel := Polygon2D.new()
	panel.name = "Panel"
	panel.polygon = corners
	panel.position = pivot
	panel.color = Color(0.44, 0.30, 0.34) if locked else Color(0.52, 0.36, 0.22)
	panel.z_index = Layers.Z_WALL
	_leaf.add_child(panel)

	var edge := Line2D.new()
	edge.name = "Edge"
	edge.points = Shapes.closed_outline(corners)
	edge.position = pivot
	edge.width = 2.0
	edge.default_color = Color(0.95, 0.55, 0.6) if locked else Color(0.86, 0.72, 0.5)
	edge.z_index = Layers.Z_WALL_EDGE
	_leaf.add_child(edge)

	if locked:
		var plate := Polygon2D.new()
		plate.name = "Lock"
		plate.polygon = Shapes.rect(Vector2(10.0, 10.0))
		plate.position = Vector2(0.0, 0.0)
		plate.color = Color(1.0, 0.78, 0.3)
		plate.z_index = Layers.Z_WALL_EDGE
		_leaf.add_child(plate)


## Pushes `state` into the physical world: a shut door blocks and shadows, an open one does not.
func _apply_state() -> void:
	var shut: bool = state == State.CLOSED
	# Deferred: these are toggled from enemy physics callbacks too, where changing a collision
	# shape mid-step is exactly what Godot forbids.
	_collision.set_deferred("disabled", not shut)
	# `LightOccluder2D` has no enable flag; a zero light mask stops it occluding anything.
	_occluder.occluder_light_mask = 1 if shut else 0


func _hinge(trans: Tween.TransitionType, angle: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_leaf, "rotation", angle, Tuning.door_open_time) \
		.set_trans(trans).set_ease(Tween.EASE_OUT)


## Opens (`shut` false) or closes (`shut` true), with the swing, the sound and the noise.
func _set_shut(shut: bool, by: Node, quiet_sound: bool = false) -> void:
	if state == State.BROKEN:
		return
	state = State.CLOSED if shut else State.OPEN
	if shut:
		_closer = null
	_apply_state()
	_hinge(Tween.TRANS_CUBIC, 0.0 if shut else PI * 0.5)
	var sound: StringName = &"door_close" if shut else &"door_open"
	AudioDirector.play_at(sound, global_position, -9.0 if quiet_sound else -5.0)
	GameDirector.make_noise(global_position, Tuning.noise_door, by)
	changed.emit()


## A key is any key: there is one kind, and opening a locked door eats one.
func _consume_key(by: Node) -> bool:
	if by == null or not is_instance_valid(by):
		return false
	if not by.has_method("spend_key"):
		return false
	return bool(by.spend_key())


func _refused(by: Node, bump: bool = false) -> void:
	AudioDirector.play_at(&"door_locked", global_position, -5.0)
	var radius: float = Tuning.noise_door_locked
	if bump:
		# Dashing at a lock is louder than trying the handle, quieter than a door smashing.
		radius = Tuning.noise_door_smash_locked
		FxDirector.shake(0.12)
	else:
		GameDirector.announce_message("LOCKED - you need a key", Color(0.95, 0.85, 0.5))
	GameDirector.make_noise(global_position, radius, by)

#endregion


#region editor gizmo

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var tint: Color = Color(1.0, 0.78, 0.35) if starts_locked else Color(0.85, 0.75, 0.55)
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, Color(tint, 0.18))
	draw_rect(rect, Color(tint, 0.85), false, 2.0)
	# The hinge end, so the direction the leaf swings is obvious before running the level.
	draw_circle(Vector2(-size.x * 0.5, 0.0), 3.0, Color(tint, 0.95))
	draw_circle(Vector2(size.x * 0.5, 0.0), 2.0, Color(tint, 0.55))
	if starts_locked:
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(-size.x * 0.5, size.y * 0.5 + 14.0), "LOCKED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(tint, 0.95))

#endregion
