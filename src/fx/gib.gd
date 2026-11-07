class_name Gib
extends RigidBody2D
## A piece of a character thrown around when it dies: a chunk cut from its body art, or a leg.
##
## Top-down, so there is no gravity: a gib is flung outwards, slides and spins against heavy damping, and
## bounces off walls and doors. It collides with nothing else and nothing collides with it, so it never
## blocks a bullet, a line of sight or anyone's movement. While it slides it bleeds, leaving a smear of
## blood decals that thins as it runs dry and a splat where it stops; then it freezes, and costs nothing.

## Distance a gib travels between blood stamps, and the speed below which it stops leaving them.
const TRAIL_SPACING: float = 9.0
const TRAIL_MIN_SPEED: float = 45.0
## Below these it counts as at rest.
const REST_SPEED: float = 6.0
const REST_SPIN: float = 0.6
 
## Roughly how big the piece is, in world pixels: it scales the blood it leaves.
var size: float = 6.0
## How much it still bleeds, 1 down to a floor: trails are heaviest right after the explosion.
var _bleed: float = 1.0
var _last_stamp: Vector2 = Vector2.ZERO


## A chunk of a texture, cut out by `polygon` (local, already scaled) with `uv` in texture pixels.
static func from_polygon(texture: Texture2D, polygon: PackedVector2Array, uv: PackedVector2Array,
		art_scale: float, art_material: Material, radius: float) -> Gib:
	var gib := Gib.new()
	var shape := Polygon2D.new()
	shape.texture = texture
	shape.polygon = polygon
	shape.uv = uv
	shape.scale = Vector2.ONE * art_scale
	shape.material = art_material
	gib.add_child(shape)
	gib._setup(radius)
	return gib


## A whole sprite as one piece (a leg), drawn the way `source` draws it now.
static func from_sprite(source: Sprite2D, radius: float) -> Gib:
	var gib := Gib.new()
	var copy := Sprite2D.new()
	copy.texture = source.texture
	copy.offset = source.offset
	copy.scale = source.scale
	copy.material = source.material
	gib.add_child(copy)
	gib._setup(radius)
	return gib


func _setup(radius: float) -> void:
	size = radius
	gravity_scale = 0.0
	linear_damp = 3.2
	angular_damp = 2.6
	collision_layer = 0
	collision_mask = Layers.SOLID | Layers.DOOR
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	var surface := PhysicsMaterial.new()
	surface.bounce = 0.35
	surface.friction = 0.6
	physics_material_override = surface
	var collider := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = maxf(2.5, radius)
	collider.shape = circle
	add_child(collider)
	# On the floor: under everyone standing, over the blood it leaves.
	z_as_relative = false
	z_index = Layers.Z_PICKUP - 1


## Sends the piece off: `velocity` in world pixels per second, `spin` in radians per second.
func launch(velocity: Vector2, spin: float) -> void:
	linear_velocity = velocity
	angular_velocity = spin
	_last_stamp = global_position


func _physics_process(_delta: float) -> void:
	if freeze:
		return
	var speed: float = linear_velocity.length()
	if speed > TRAIL_MIN_SPEED and global_position.distance_to(_last_stamp) >= TRAIL_SPACING:
		_last_stamp = global_position
		# A smear drawn out along the slide, fatter the faster it goes.
		FxDirector.blood_decal(global_position, maxf(1.5, size * lerpf(0.55, 0.95,
			minf(speed / 400.0, 1.0)) * _bleed), false, linear_velocity)
		_bleed = maxf(0.35, _bleed * 0.92)
	if speed < REST_SPEED and absf(angular_velocity) < REST_SPIN:
		# Where it came to rest, it bled most.
		FxDirector.blood_decal(global_position, size * 0.9 * _bleed, true)
		freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		freeze = true
		set_physics_process(false)
