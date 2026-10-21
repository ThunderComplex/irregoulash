class_name VisionRig
extends Node2D
## The player's eyes.
##
## Two lights do all the work:
##   * `NearSight`  - a short omnidirectional ring ("something is right next to me")
##   * `AimPivot/ConeSight` - the long aim cone, rotated at the mouse
##
## Both cast shadows against `LightOccluder2D`s, and the level keeps the rest of
## the canvas pitch black with a `CanvasModulate`. Anything the lights do not
## reach is therefore *actually* invisible, not merely dark.
##
## The same rig is also the authority on "can the player see point X?", which
## both the enemy AI (was I lit up?) and the explored-geometry memory use.

var near_sight: PointLight2D = null
var cone_sight: PointLight2D = null
var aim_pivot: Node2D = null

var near_radius: float = 100.0
var far_range: float = 600.0
var far_degrees: float = 80.0

var _aim: Vector2 = Vector2.RIGHT
var _enabled: bool = true


func _ready() -> void:
	near_sight = get_node_or_null("NearSight") as PointLight2D
	aim_pivot = get_node_or_null("AimPivot") as Node2D
	cone_sight = get_node_or_null("AimPivot/ConeSight") as PointLight2D
	configure()


func configure() -> void:
	near_radius = Tuning.sight_near_radius
	far_range = Tuning.sight_far_range
	far_degrees = Tuning.sight_far_degrees

	if near_sight != null:
		near_sight.texture = VisionTextures.radial()
		near_sight.texture_scale = near_radius * 2.0 / float(VisionTextures.SIZE)
		near_sight.energy = Tuning.sight_near_energy
		near_sight.color = Color(1.0, 0.96, 0.9)
		near_sight.shadow_enabled = true
		near_sight.blend_mode = Light2D.BLEND_MODE_ADD

	if cone_sight != null:
		cone_sight.texture = VisionTextures.cone(far_degrees)
		cone_sight.texture_scale = far_range * 2.0 / float(VisionTextures.SIZE)
		cone_sight.energy = Tuning.sight_far_energy
		cone_sight.color = Color(1.0, 0.97, 0.92)
		cone_sight.shadow_enabled = true
		cone_sight.blend_mode = Light2D.BLEND_MODE_ADD


func aim_at(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	_aim = direction.normalized()
	if aim_pivot != null:
		aim_pivot.rotation = _aim.angle()


func aim_direction() -> Vector2:
	return _aim


func set_enabled(on: bool) -> void:
	_enabled = on
	if near_sight != null:
		near_sight.visible = on
	if cone_sight != null:
		cone_sight.visible = on


## Cheap test: inside the near ring, or inside the cone?
func in_vision_shape(point: Vector2) -> bool:
	var offset: Vector2 = point - global_position
	var distance: float = offset.length()
	if distance <= near_radius:
		return true
	if distance > far_range:
		return false
	return absf(offset.angle_to(_aim)) <= deg_to_rad(far_degrees * 0.5)


## Full test: inside the vision shape AND not behind a wall.
func can_see_point(point: Vector2, blocker_mask: int = Layers.SOLID) -> bool:
	if not _enabled:
		return false
	var from: Vector2 = global_position
	var offset: Vector2 = point - from
	if offset.length_squared() < 1.0:
		return true
	if not in_vision_shape(point):
		return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(from, point, blocker_mask)
	query.hit_from_inside = false
	var hit: Dictionary = space.intersect_ray(query)
	return hit.is_empty()


## Same as `can_see_point`, but a hit on `body` itself counts as visible. Used for
## "have I seen this wall?" checks, where the sample point sits inside the wall.
func can_see_body(point: Vector2, body: CollisionObject2D, blocker_mask: int = Layers.SOLID) -> bool:
	if not _enabled:
		return false
	if not in_vision_shape(point):
		return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(global_position, point, blocker_mask)
	query.hit_from_inside = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == body
