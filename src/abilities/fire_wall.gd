class_name FireWall
extends AbilityEffect
## A wall of fire: the ability that also changes the level, because it blocks movement
## and light. Cast across a corridor it cuts a line of sight as much as it blocks a path,
## which is the tactical point of it.

var _field: DamageField = null


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
	add_child(_field)

	lifetime = data.duration
	FxDirector.flash_light(target, data.color, 1.1, 170.0, 0.25)
	return true


func _tick(_delta: float) -> void:
	if _field == null:
		return
	# Fade over its life instead of vanishing mid-frame.
	_field.set_alpha(lerpf(0.12, 0.55, remaining_fraction()))
