class_name FireWall
extends AbilityEffect
## A wall of fire: the ability that also changes the level, because it blocks movement
## and light. Cast across a corridor it cuts a line of sight as much as it blocks a path,
## which is the tactical point of it.
##
## The look is four `ParticleLibrary` presets layered over the damage field's footprint --
## coals on the ground, flames, smoke, embers -- plus a flickering light on each side. The
## wall occludes light along its centre line only (see `DamageField.occlude_spine`), so each
## light brightens its own side, the ground under the fire stays visible, and nothing is
## seen through it.

## The footprint the presets' particle counts are tuned for (the unupgraded fire wall).
const REFERENCE_AREA: float = 176.0 * 40.0
## Where each glow light sits, as a fraction of the half-thickness out from the centre line: inside
## the fire, so it lights the ground it burns on as well as the room beside it.
const GLOW_OFFSET: float = 0.5
const GLOW_ENERGY: float = 1.75

var _field: DamageField = null
var _emitters: Array[CPUParticles2D] = []
var _glows: Array[PointLight2D] = []
## Seconds before the end at which the fire stops feeding itself, so it burns down instead of
## blinking out. The flames' lifetime: the last of them die as the effect does.
var _burn_down: float = 0.0
var _t: float = 0.0


func begin(caster: Node2D, target: Vector2, slot: AbilitySlot) -> bool:
	var data: AbilityResource = slot.data
	if not AbilityCasting.can_place(caster, target, data):
		return false

	global_position = target
	# Set across the cast direction, so it reads as a barrier between you and whatever
	# you were pointing at rather than as an arbitrary band.
	var to_target: Vector2 = target - caster.global_position
	if to_target.length_squared() > 1.0:
		rotation = to_target.angle() + PI * 0.5

	_field = DamageField.new()
	_field.name = "Field"
	_field.damage = slot.damage()
	_field.tick_interval = data.tick_interval
	_field.size = data.area_size * slot.area_scale()
	_field.hits_mask = Layers.ENEMY
	_field.source = caster
	_field.color = data.color
	_field.blocks_movement = true
	_field.blocks_light = true
	_field.show_visual = false
	_field.occlude_spine = true
	add_child(_field)

	lifetime = data.duration
	_build_fire(_field.size)
	_build_glow(_field.size, data.color)
	var ignite: ParticlePreset = ParticleLibrary.by_id("ignite")
	# The burst's direction is what turns its box, so pass the wall's own "up" to line the two up.
	FxDirector.burst(ignite.with_box(_field.size * 0.5).with_amount(_scaled(ignite.amount, _field.size)),
		target, Vector2.from_angle(rotation - PI * 0.5))
	FxDirector.flash_light(target, data.color, 1.1, 170.0, 0.25)
	return true


func _build_fire(size: Vector2) -> void:
	var half: Vector2 = size * 0.5
	# Coals cover the whole footprint; flames, smoke and embers come from slightly inside it, so the
	# fire's silhouette stays within the solid area rather than spilling past where it blocks you.
	var inner: Vector2 = half * Vector2(0.92, 0.7)
	_add_emitter("coals", half, size)
	_add_emitter("flames", inner, size)
	_add_emitter("smoke", inner, size)
	_add_emitter("embers", inner, size)
	_burn_down = ParticleLibrary.by_id("flames").max_lifetime()


func _add_emitter(preset_id: String, half: Vector2, size: Vector2) -> void:
	var base: ParticlePreset = ParticleLibrary.by_id(preset_id)
	var preset: ParticlePreset = base.with_box(half).with_amount(_scaled(base.amount, size))
	var node: CPUParticles2D = FxDirector.emitter(preset, self)
	if node != null:
		_emitters.append(node)


## Particle counts follow the area, so an upgraded (bigger) wall is as dense as the first one.
func _scaled(base_amount: int, size: Vector2) -> int:
	return maxi(1, roundi(float(base_amount) * size.x * size.y / REFERENCE_AREA))


func _build_glow(size: Vector2, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		var light := PointLight2D.new()
		light.name = "Glow"
		light.texture = VisionTextures.radial()
		light.texture_scale = size.x * 1.6 / float(VisionTextures.SIZE)
		light.color = color
		light.energy = GLOW_ENERGY
		light.blend_mode = Light2D.BLEND_MODE_ADD
		# Shadows on, like every other light here: without them the glow would leak through walls into
		# the next room. The fire's own spine occluder is what keeps each light to one side of it.
		light.shadow_enabled = true
		light.z_index = Layers.Z_ACTOR
		light.position = Vector2(0.0, side * size.y * 0.5 * GLOW_OFFSET)
		add_child(light)
		_glows.append(light)


func _tick(delta: float) -> void:
	if _field == null:
		return
	_t += delta
	var left: float = lifetime * remaining_fraction()
	if left <= _burn_down and not _emitters.is_empty():
		for node: CPUParticles2D in _emitters:
			FxDirector.stop_emitter(node)
		_emitters.clear()

	# Two sines at unrelated rates flicker without visibly looping; the two sides are out of step so
	# the light does not pulse as one block.
	var fade: float = clampf(left / maxf(0.01, _burn_down), 0.0, 1.0)
	for i: int in _glows.size():
		var phase: float = _t + float(i) * 1.7
		var flicker: float = 0.82 + 0.1 * sin(phase * 13.0) + 0.08 * sin(phase * 7.3 + 1.1)
		_glows[i].energy = GLOW_ENERGY * flicker * fade
