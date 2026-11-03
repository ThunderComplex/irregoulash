class_name ParticlePreset
extends Resource
## One particle emitter's look and motion, as data.
##
## A preset says what the particles do; `FxDirector` decides where they live. The same "flames" preset
## can line a fire wall, ring an explosion or sit on a torch, because the things that differ between
## those uses -- the emission area, how many particles, the colour -- are adapted per use with the
## `with_*` methods, which return a copy and leave the shared preset alone:
##
##     FxDirector.emitter(ParticleLibrary.by_id("flames").with_box(size * 0.5).with_amount(90), self)
##
## Presets are built in code by `ParticleLibrary`, like every other piece of tuning here, but they are
## ordinary resources: save one as a `.tres` to tune it in the inspector.
##
## Everything is drawn unshaded, because an effect you cannot see in the dark does not exist here.

enum Shape { POINT, CIRCLE, BOX }
enum Blend { ADD, MIX }

@export_group("Emission")
@export var amount: int = 16
@export var lifetime: float = 0.6
@export_range(0.0, 1.0, 0.01) var lifetime_randomness: float = 0.3
## A one-shot emitter fires `amount` particles once and is freed by `FxDirector` when they are gone.
@export var one_shot: bool = false
## 0 spreads emission over the lifetime (a steady stream), 1 emits everything at once (a burst).
@export_range(0.0, 1.0, 0.01) var explosiveness: float = 0.0
## Seconds simulated up front, so a continuous effect appears already burning instead of ramping up.
@export var preprocess: float = 0.0
@export var shape: Shape = Shape.POINT
## For `CIRCLE`.
@export var radius: float = 8.0
## For `BOX`: half the box's size, in the emitter's own (rotated) space.
@export var extents: Vector2 = Vector2(8.0, 8.0)

@export_group("Motion")
## In the emitter's space, so it turns with whatever the emitter is attached to -- unless
## `direction_in_world` is set.
@export var direction: Vector2 = Vector2.UP
## Read `direction` in world space instead, fixed when the emitter is created: flames leave a wall
## cast at any angle heading up the screen, while the emission box still follows the wall.
@export var direction_in_world: bool = false
@export_range(0.0, 180.0, 0.5) var spread: float = 45.0
@export var speed_min: float = 20.0
@export var speed_max: float = 60.0
## In *world* space (emitters simulate in world space), so "up" stays up on screen however the emitter
## is rotated. That is what makes flames rise off a wall cast at any angle.
@export var gravity: Vector2 = Vector2.ZERO
@export var damping_min: float = 0.0
@export var damping_max: float = 0.0
## Sideways push along the particle's path; a little of it makes smoke and embers drift and curl.
@export var tangential_min: float = 0.0
@export var tangential_max: float = 0.0
@export var spin_min: float = 0.0
@export var spin_max: float = 0.0
## Turn each particle so its texture's +Y points along its motion. Needed for anything with a shape,
## like a flame tongue, which has to point the way it is rising.
@export var align_to_motion: bool = false

@export_group("Look")
## Null uses `ParticleLibrary.soft_dot()`.
@export var texture: Texture2D = null
## Particle size in world pixels, measured across the texture's width (a tall texture stays tall).
@export var size_min: float = 6.0
@export var size_max: float = 10.0
## Size over the particle's life, multiplied with the size above. Null keeps it constant.
@export var size_curve: Curve = null
## Colour over life, alpha included. Null is plain white fading out.
@export var colors: Gradient = null
@export_range(0.0, 1.0, 0.01) var hue_variation: float = 0.0
@export var blend: Blend = Blend.ADD
## Added to `Layers.Z_FX`.
@export var z_offset: int = 0


#region per-use adaptation

## A copy emitting from a box with these half-extents.
func with_box(half_size: Vector2) -> ParticlePreset:
	var copy := duplicate() as ParticlePreset
	copy.shape = Shape.BOX
	copy.extents = half_size
	return copy


## A copy emitting from a circle of this radius.
func with_circle(circle_radius: float) -> ParticlePreset:
	var copy := duplicate() as ParticlePreset
	copy.shape = Shape.CIRCLE
	copy.radius = circle_radius
	return copy


func with_amount(count: int) -> ParticlePreset:
	var copy := duplicate() as ParticlePreset
	copy.amount = maxi(1, count)
	return copy


## A copy whose colours are multiplied by `tint`: one fire preset, many coloured fires.
func tinted(tint: Color) -> ParticlePreset:
	var copy := duplicate() as ParticlePreset
	var source: Gradient = colors if colors != null else ParticleLibrary.fade_out()
	copy.colors = source.duplicate() as Gradient
	for i: int in copy.colors.get_point_count():
		copy.colors.set_color(i, copy.colors.get_color(i) * tint)
	return copy

#endregion


## Configures a CPU particle node from this preset. CPU rather than GPU particles: effects here are a
## few hundred particles at most, and CPU particles cost no shader compile the first time one appears
## mid-fight.
func apply_to(node: CPUParticles2D) -> void:
	node.amount = maxi(1, amount)
	node.lifetime = maxf(0.01, lifetime)
	node.lifetime_randomness = lifetime_randomness
	node.one_shot = one_shot
	node.explosiveness = explosiveness
	node.preprocess = preprocess
	node.local_coords = false
	match shape:
		Shape.CIRCLE:
			node.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			node.emission_sphere_radius = radius
		Shape.BOX:
			node.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			node.emission_rect_extents = extents
		_:
			node.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT

	node.direction = direction
	node.spread = spread
	node.initial_velocity_min = speed_min
	node.initial_velocity_max = speed_max
	node.gravity = gravity
	node.damping_min = damping_min
	node.damping_max = damping_max
	node.tangential_accel_min = tangential_min
	node.tangential_accel_max = tangential_max
	node.angular_velocity_min = spin_min
	node.angular_velocity_max = spin_max
	node.particle_flag_align_y = align_to_motion
	node.angle_min = 0.0
	node.angle_max = 360.0 if (spin_min != 0.0 or spin_max != 0.0) else 0.0

	node.texture = texture if texture != null else ParticleLibrary.soft_dot()
	var texture_size: float = maxf(1.0, float(node.texture.get_width()))
	node.scale_amount_min = size_min / texture_size
	node.scale_amount_max = size_max / texture_size
	node.scale_amount_curve = size_curve
	node.color_ramp = colors if colors != null else ParticleLibrary.fade_out()
	node.hue_variation_min = -hue_variation
	node.hue_variation_max = hue_variation

	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material.blend_mode = (CanvasItemMaterial.BLEND_MODE_ADD if blend == Blend.ADD
		else CanvasItemMaterial.BLEND_MODE_MIX)
	node.material = material
	node.z_index = Layers.Z_FX + z_offset
	node.z_as_relative = false


## The longest a particle from this preset can live, for freeing an emitter once it falls quiet.
## `lifetime_randomness` only ever shortens a particle's life, so this is just `lifetime`.
func max_lifetime() -> float:
	return lifetime
