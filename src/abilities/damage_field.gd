class_name DamageField
extends Node2D
## A patch of world that damages whatever is inside it, on a timer.
##
## One component carries both area abilities: the fire wall is a rectangle with a long
## life and a slow tick, the fire tempest is a circle with one or two big hits. Damage
## goes through the same `take_hit()` interface bullets use, so kill credit and the
## stale-source handling come along for free.
##
## It can also be solid and shadow-casting, which is what makes the fire wall an
## obstacle rather than just a damage zone.

## Which physics layers this hurts. A player ability hurts enemies.
var hits_mask: int = Layers.ENEMY
var damage: float = 10.0
var tick_interval: float = 0.4
## Rectangle by default; set `radius` above zero for a circle.
var size: Vector2 = Vector2(160.0, 32.0)
var radius: float = 0.0
## Who gets credit and blame. Validated on use, because it can die mid-effect.
var source: Node = null
var color: Color = Color(1.0, 0.55, 0.18)
## A wall of fire is both of these; an explosion is neither.
var blocks_movement: bool = false
var blocks_light: bool = false
var alpha: float = 0.55

var _tick_left: float = 0.0
var _visual: Polygon2D = null


func _ready() -> void:
	z_index = Layers.Z_PICKUP
	_build_visual()
	if blocks_movement:
		_build_collision()
	if blocks_light:
		_build_occluder()
	# Hit straight away: an explosion that waits a tick before hurting feels broken.
	_tick_left = 0.0


func _process(delta: float) -> void:
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = maxf(0.05, tick_interval)
	apply_damage()


## Everything inside the shape takes one hit.
func apply_damage() -> void:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = make_shape()
	# The global transform, not just the position: a fire wall is rotated across the
	# direction it was cast, and the damage has to follow the visual.
	query.transform = global_transform
	query.collision_mask = hits_mask
	query.collide_with_areas = false
	for hit: Dictionary in space.intersect_shape(query, 16):
		var collider: Variant = hit.get("collider")
		if collider == null or not collider.has_method("take_hit"):
			continue
		var target := collider as Node2D
		var at: Vector2 = target.global_position if target != null else global_position
		var away: Vector2 = at - global_position
		if away.length_squared() < 1.0:
			away = Vector2.RIGHT
		collider.take_hit(damage, valid_source(), at, away.normalized(), 0.0)


func valid_source() -> Node:
	return source if is_instance_valid(source) else null


func make_shape() -> Shape2D:
	if radius > 0.0:
		var circle := CircleShape2D.new()
		circle.radius = radius
		return circle
	var rect := RectangleShape2D.new()
	rect.size = size
	return rect


## Fading is driven by the owning effect, so the field itself stays dumb.
func set_alpha(value: float) -> void:
	alpha = clampf(value, 0.0, 1.0)
	if _visual != null:
		_visual.color = Color(color, alpha)


func _build_visual() -> void:
	_visual = Polygon2D.new()
	_visual.name = "Visual"
	_visual.polygon = Shapes.circle(radius, 24) if radius > 0.0 else Shapes.rect(size)
	_visual.color = Color(color, alpha)
	# Unshaded so it is visible in the dark, like every other combat effect here.
	_visual.material = FxDirector.unshaded_material()
	_visual.z_index = Layers.Z_PICKUP
	add_child(_visual)


func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "Solid"
	# WORLD layer, so it stops the player and enemies and catches bullets.
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var collider := CollisionShape2D.new()
	collider.name = "Collision"
	collider.shape = make_shape()
	body.add_child(collider)
	add_child(body)


func _build_occluder() -> void:
	var occluder := LightOccluder2D.new()
	occluder.name = "Occluder"
	var polygon := OccluderPolygon2D.new()
	polygon.polygon = Shapes.circle(radius, 20) if radius > 0.0 else Shapes.rect(size)
	polygon.closed = true
	occluder.occluder = polygon
	# Mask 1 is what the vision rig and the lamps use.
	occluder.occluder_light_mask = 1
	add_child(occluder)
