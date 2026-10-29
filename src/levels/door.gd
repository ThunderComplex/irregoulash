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

enum State {CLOSED, OPEN, BROKEN}

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
## The visible panel, kept separate from the leaf's collider and occluder so rebuilding the art (on
## unlock or resize) cannot delete the physics.
var _art: Node2D = null
var _solid: StaticBody2D = null
var _collision: CollisionShape2D = null
var _occluder: LightOccluder2D = null
var _polygon: OccluderPolygon2D = null
var _tween: Tween = null
## The enemy that opened this door and still intends to shut it behind itself.
var _closer: Node = null
## True while the leaf is between two angles.
var _swinging: bool = false
## Actors currently given a collision exception against this leaf.
var _exempt: Array[Node] = []
## Actors a swing ended on top of. Distinguishes "the door swung into you, so it must not hold you"
## from "you walked into the door", which must stay solid.
var _swung_into: Array[Node] = []


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
		# Standing in the doorway: the leaf tries to shut, meets them, and swings back. The
		# animation says it better than a message does, and nothing is spent or changed.
		bounce()
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
	# Drop the physics this instant, so the dash that broke the door is not stopped dead by a leaf
	# that is already on its way out of the level.
	_solid.process_mode = Node.PROCESS_MODE_DISABLED
	_solid.collision_layer = 0
	AudioDirector.play_at(&"door_smash", global_position, -2.0)
	FxDirector.shake(0.3)
	# A burst of splinters where the door was, and then nothing: the doorway is left empty, because
	# the door is gone from the level rather than lying in it.
	FxDirector.spark_burst(global_position, Vector2.UP, 14, Color(0.78, 0.6, 0.38), 190.0, 0.45)
	FxDirector.flash_light(global_position, Color(0.95, 0.8, 0.5), 0.7, 130.0, 0.18)
	GameDirector.make_noise(global_position, Tuning.noise_door_smash, by)
	GameDirector.announce_message("DOOR SMASHED", Color(0.95, 0.85, 0.6))
	changed.emit()
	queue_free()


## Enemies call this when a shut door is in their way. Quiet compared to the player wrenching it
## open, but not silent: an enemy opening a door tells you roughly where it is.
func open_for_enemy(by: Node) -> bool:
	if state != State.CLOSED or locked:
		return false
	_closer = by
	_set_shut(false, by, true)
	return true


## The leaf swings most of the way shut, meets whoever is standing in the doorway, and comes back.
## Deliberately not a message: the obstruction is something the player can see, so the animation is
## the feedback and no text is needed. The door's state, collider and occluder are untouched.
func bounce() -> void:
	AudioDirector.play_at(&"door_close", global_position, -12.0)
	GameDirector.make_noise(global_position, Tuning.noise_door_bump, null)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var open_angle: float = PI * 0.5
	_tween = create_tween()
	_tween.tween_property(_leaf, "rotation", open_angle * 0.8, 0.04) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(_leaf, "rotation", open_angle, 0.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(_on_swing_finished)
	_swinging = true


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


## Whether `point` is inside the door's footprint. Exact and instant, unlike a physics query, which
## lags a frame behind anything that moved this frame.
func contains_point(point: Vector2) -> bool:
	var local: Vector2 = to_local(point)
	var half: Vector2 = size * 0.5
	return absf(local.x) <= half.x and absf(local.y) <= half.y


## The door that owns `node`, walking up the parent chain.
##
## The leaf's collider and occluder live *under the leaf* so they swing with it, which means they
## are no longer direct children of the door. Everything that identifies a door from a collider
## goes through here rather than assuming `get_parent()`.
static func from_node(node: Node) -> Door:
	var current: Node = node
	while current != null:
		var door := current as Door
		if door != null:
			return door
		current = current.get_parent()
	return null


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
	# The player is checked by position first, and not only by the shape query below. A collision
	# query reflects the physics server's last step, so a body that moved this frame can be missed
	# -- and a door closing on the player is the one outcome that must never happen. This exact
	# check is also what makes "stand in the doorway and try to shut it" bounce instead.
	var player := GameDirector.valid_player()
	if player != null and contains_point(player.global_position):
		return false
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

## (Re)builds the leaf, its collider and its occluder. Idempotent, so a door resized in the editor
## or created in code ends up identical to one authored in a scene.
##
## The collider and the occluder are children of the *leaf*, offset to the middle of the panel, so
## they follow it through the swing. That is what makes a door an object rather than a hole with a
## state: shut, the leaf fills the doorway; open, the same leaf stands in the room and still stops
## movement, bullets and light -- which is what makes it cover you can hide behind.
func _rebuild_geometry() -> void:
	if _leaf == null:
		_leaf = Node2D.new()
		_leaf.name = "Leaf"
		add_child(_leaf)
	if _art == null:
		_art = Node2D.new()
		_art.name = "Art"
		_leaf.add_child(_art)
	# Where the middle of the panel sits in the leaf's own space.
	var centre := Vector2(size.x * 0.5, 0.0)

	if _solid == null:
		_solid = StaticBody2D.new()
		_solid.name = "Solid"
		# WORLD: stops the player and enemies, catches bullets, and blocks the raycasts that
		# enemy sight and lamp visibility use. One layer, three jobs, all of them wanted.
		_solid.collision_layer = Layers.WORLD
		_solid.collision_mask = 0
		_leaf.add_child(_solid)
	if _collision == null:
		_collision = CollisionShape2D.new()
		_collision.name = "Collision"
		_solid.add_child(_collision)
	var rect := RectangleShape2D.new()
	rect.size = size
	_collision.shape = rect
	_solid.position = centre

	if _occluder == null:
		_occluder = LightOccluder2D.new()
		_occluder.name = "Occluder"
		_polygon = OccluderPolygon2D.new()
		_occluder.occluder = _polygon
		_leaf.add_child(_occluder)
	_polygon.polygon = Shapes.rect(size)
	_polygon.closed = true
	_occluder.position = centre

	_build_leaf_art()


## The leaf: a panel hinged at the door's left edge.
##
## The hinge is the *leaf node's own origin*, moved to the edge, with the panel drawn from 0 to
## `size.x` in the leaf's space. Offsetting the panel inside a leaf left at the door's centre --
## which is what the first version did -- makes it spin like a turnstile about the middle instead
## of swinging from its edge.
func _build_leaf_art() -> void:
	if _leaf == null or _art == null:
		return
	# Only the art: the collider and occluder are siblings of this node and must survive a rebuild
	# (which happens whenever the door is unlocked or resized).
	for child: Node in _art.get_children():
		child.free()

	_leaf.position = Vector2(-size.x * 0.5, 0.0)

	var corners := PackedVector2Array([
		Vector2(0.0, -size.y * 0.5),
		Vector2(size.x, -size.y * 0.5),
		Vector2(size.x, size.y * 0.5),
		Vector2(0.0, size.y * 0.5),
	])

	var panel := Polygon2D.new()
	panel.name = "Panel"
	panel.polygon = corners
	panel.color = Color(0.44, 0.30, 0.34) if locked else Color(0.52, 0.36, 0.22)
	panel.z_index = Layers.Z_WALL
	_art.add_child(panel)

	var edge := Line2D.new()
	edge.name = "Edge"
	edge.points = Shapes.closed_outline(corners)
	edge.width = 2.0
	edge.default_color = Color(0.95, 0.55, 0.6) if locked else Color(0.86, 0.72, 0.5)
	edge.z_index = Layers.Z_WALL_EDGE
	_art.add_child(edge)

	if locked:
		var plate := Polygon2D.new()
		plate.name = "Lock"
		plate.polygon = Shapes.rect(Vector2(10.0, 10.0))
		# Middle of the leaf, not the hinge.
		plate.position = Vector2(size.x * 0.5, 0.0)
		plate.color = Color(1.0, 0.78, 0.3)
		plate.z_index = Layers.Z_WALL_EDGE
		_leaf.add_child(plate)


func _hinge(trans: Tween.TransitionType, angle: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_leaf, "rotation", angle, Tuning.door_open_time) \
		.set_trans(trans).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(_on_swing_finished)
	_swinging = true


func _on_swing_finished() -> void:
	_swinging = false


## The player is never shoved by a door; enemies still are.
##
## A `StaticBody2D` can block or not block, but it cannot "block without pushing", so while the leaf
## is moving -- or while it happens to be sitting on top of the player -- the player is given a
## collision exception against it. The exception is dropped as soon as the leaf has settled and is
## clear, so a settled door blocks the player exactly like a wall does.
##
## The cost is that a swinging leaf passes over the player instead of sweeping them aside. That is
## the right trade: losing control of your own position is far worse than a door being briefly
## intangible, and it is invisible in play. Enemies keep being shoved, which reads as weight.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _solid == null or _leaf == null:
		return
	_prune_swung_into()
	var wanted: Array[Node] = []
	for actor: Node in _nearby_actors():
		var body := actor as Node2D
		if body == null:
			continue
		var covered: bool = _leaf_covers(body.global_position)
		# Only a swing may put someone inside the leaf. Once they are clear, the exemption is gone
		# for good -- otherwise walking into a settled door would quietly turn it intangible and let
		# you through it, which is far worse than a nudge.
		if _swinging and covered:
			if not _swung_into.has(actor):
				_swung_into.append(actor)
		elif not _swinging and not covered:
			_swung_into.erase(actor)
		if _swinging or _swung_into.has(actor):
			wanted.append(actor)

	for actor: Node in _exempt.duplicate():
		if wanted.has(actor):
			continue
		_exempt.erase(actor)
		if is_instance_valid(actor):
			actor.remove_collision_exception_with(_solid)
	for actor: Node in wanted:
		if _exempt.has(actor):
			continue
		_exempt.append(actor)
		actor.add_collision_exception_with(_solid)


## Everyone the leaf could shove: the player, and enemies close enough to matter. Enemies are
## included because a door they opened themselves used to shunt them into a corner they could not
## climb out of -- worse than a door being briefly intangible.
func _nearby_actors() -> Array[Node]:
	var out: Array[Node] = []
	var player := GameDirector.valid_player()
	if player != null:
		out.append(player)
	var range_sq: float = 240.0 * 240.0
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_squared_to(global_position) > range_sq:
			continue
		out.append(enemy)
	return out


func _prune_swung_into() -> void:
	for i: int in range(_swung_into.size() - 1, -1, -1):
		var actor: Node = _swung_into[i]
		if not is_instance_valid(actor):
			_swung_into.remove_at(i)
			_exempt.erase(actor)


## Whether a body would be touching or inside the leaf where it is now. The margin beyond the
## player's radius keeps the exemption from being dropped a pixel early and handing back a nudge.
func _leaf_covers(point: Vector2) -> bool:
	var panel := Rect2(Vector2(0.0, -size.y * 0.5), size)
	return panel.grow(Tuning.player_radius + 4.0).has_point(_leaf.to_local(point))


## Someone tried a locked door. Quiet, but not silent: a rattling handle is a sound.
func rattle(by: Node) -> void:
	AudioDirector.play_at(&"door_locked", global_position, -7.0)
	GameDirector.make_noise(global_position, Tuning.noise_door_locked, by)


func _exit_tree() -> void:
	# Never leave an exception pointing at a door that is about to stop existing.
	for actor: Node in _exempt:
		if is_instance_valid(actor) and _solid != null:
			actor.remove_collision_exception_with(_solid)
	_exempt.clear()
	_swung_into.clear()


## Opens (`shut` false) or closes (`shut` true), with the swing, the sound and the noise.
func _set_shut(shut: bool, by: Node, quiet_sound: bool = false) -> void:
	if state == State.BROKEN:
		return
	state = State.CLOSED if shut else State.OPEN
	if shut:
		_closer = null
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
