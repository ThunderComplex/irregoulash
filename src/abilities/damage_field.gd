class_name DamageField
extends Node2D
## A patch of world that damages whatever is inside it, on a timer.
##
## One component carries both area abilities: the fire wall is a rectangle with a long
## life and a slow tick, the fire tempest is a circle with one or two big hits. Damage
## goes through the same `take_hit()` interface bullets use, so kill credit and the
## stale-source handling come along for free.
##
## It can also be solid, sight-blocking and shadow-casting. The fire wall is the last two:
## it hides each side from the other without stopping anyone walking through it.

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
## Solid to everything, like a wall. Nothing uses it right now: a solid fire burns nobody,
## because nobody can get into it.
var blocks_movement: bool = false
## Hides what is behind it from enemies' sight rays (`Layers.SIGHT_ONLY`), without stopping
## movement or bullets. Pair it with `blocks_light`, which does the same for the player.
var blocks_sight: bool = false
var blocks_light: bool = false
var alpha: float = 0.55
## The flat placeholder shape. Effects that draw themselves (the fire wall's particles) turn it off;
## the collision, occluder and damage do not depend on it.
var show_visual: bool = true
## Rectangles only: block light and sight along the long centre line instead of across the whole
## shape. A filled occluder shadows its own inside, so the ground under a fire wall went pitch black;
## a spine still stops light crossing it, and leaves each half lit from its own side. The sight body
## follows the same line, so the player and the enemies see exactly as far into the fire as each
## other.
var occlude_spine: bool = false

var _tick_left: float = 0.0
var _visual: Polygon2D = null


func _ready() -> void:
	z_index = Layers.Z_PICKUP
	if show_visual:
		_build_visual()
	if blocks_movement:
		_build_body("Solid", Layers.WORLD, make_shape())
	elif blocks_sight:
		_build_body("SightBlocker", Layers.SIGHT_ONLY, _blocker_shape())
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
		# Tell the victim where the caster is *before* the hit lands. `take_hit` guesses the attacker
		# from the hit direction, which suits a bullet (it points back at the shooter) but not a field,
		# whose direction only points away from its own centre: the guess landed somewhere past the
		# middle of the fire, and an unaware enemy went off to search a spot nobody had been -- often
		# another enemy's patrol point. Already alerted, `take_hit` skips its guess.
		var caster := valid_source() as Node2D
		if caster != null and collider.has_method("alert_from"):
			collider.alert_from(caster.global_position)
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


## A static body in the field's footprint. On `WORLD` it is a wall (it already blocks sight, as
## walls do); on `SIGHT_ONLY` it only stops sight rays.
func _build_body(body_name: String, layer: int, shape: Shape2D) -> void:
	var body := StaticBody2D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	var collider := CollisionShape2D.new()
	collider.name = "Collision"
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


## The shape that blocks sight: the whole field, or just its spine (see `occlude_spine`).
func _blocker_shape() -> Shape2D:
	if radius <= 0.0 and occlude_spine:
		var spine := RectangleShape2D.new()
		spine.size = Vector2(size.x, 2.0)
		return spine
	return make_shape()


func _build_occluder() -> void:
	var occluder := LightOccluder2D.new()
	occluder.name = "Occluder"
	var polygon := OccluderPolygon2D.new()
	if radius > 0.0:
		polygon.polygon = Shapes.circle(radius, 20)
	elif occlude_spine:
		polygon.polygon = Shapes.rect(Vector2(size.x, 8.0))
	else:
		polygon.polygon = Shapes.rect(size)
	polygon.closed = true
	occluder.occluder = polygon
	# Mask 1 is what the vision rig and the lamps use.
	occluder.occluder_light_mask = 1
	add_child(occluder)
