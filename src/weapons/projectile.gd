class_name Projectile
extends Node2D
## A bullet.
##
## Movement is a *swept* raycast from last frame's position to this frame's, so a
## 1600 px/s round cannot tunnel through a 40 px wall at 60 fps. The bullet draws
## its own one-frame streak, and fast rounds get no orb (a moving dot at that
## speed just looks like a dashed line).

var velocity: Vector2 = Vector2.RIGHT
var damage: float = 10.0
var hits_mask: int = Layers.PLAYER_SHOT_HITS
var shooter: Node = null
var max_distance: float = 700.0
var color: Color = Color.WHITE
var knockback: float = 0.0
## Draw a visible orb (used for slow enemy rounds so they can be dodged).
var show_orb: bool = false

var _traveled: float = 0.0
var _dead: bool = false
var _trail: Line2D = null


func launch(origin: Vector2, direction: Vector2, speed: float) -> void:
	global_position = origin
	velocity = direction.normalized() * speed


func _ready() -> void:
	z_index = Layers.Z_FX - 5
	add_to_group("projectile")

	_trail = Line2D.new()
	_trail.width = 2.0
	_trail.default_color = color
	_trail.z_index = Layers.Z_FX - 5
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail.material = mat
	_trail.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	add_child(_trail)

	if show_orb:
		var orb := Polygon2D.new()
		orb.polygon = Shapes.circle(3.0, 8)
		orb.color = color
		orb.material = FxDirector.unshaded_material()
		orb.z_index = Layers.Z_FX - 4
		add_child(orb)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	var step: Vector2 = velocity * delta
	var from: Vector2 = global_position
	var to: Vector2 = from + step

	if _trail != null:
		_trail.points = PackedVector2Array([-step, Vector2.ZERO])

	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters2D.create(from, to, hits_mask)
		query.hit_from_inside = false
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			_impact(hit)
			return

	global_position = to
	_traveled += step.length()
	if _traveled >= max_distance:
		_expire()


func _impact(hit: Dictionary) -> void:
	var point: Vector2 = hit.get("position", global_position)
	var normal: Vector2 = hit.get("normal", Vector2.UP)
	var direction: Vector2 = velocity.normalized()
	var collider: Variant = hit.get("collider")

	_dead = true
	if collider != null and collider.has_method("take_hit"):
		# Whoever fired this may have died while the round was in the air.
		var source: Node = shooter if is_instance_valid(shooter) else null
		collider.take_hit(damage, source, point, direction, knockback)
		FxDirector.blood(point, direction)
	else:
		FxDirector.impact(point, normal, color, 6)
		AudioDirector.play_at(&"impact_wall", point, -9.0)
	queue_free()


func _expire() -> void:
	_dead = true
	queue_free()
