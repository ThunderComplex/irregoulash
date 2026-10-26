class_name FireTempest
extends AbilityEffect
## A localised blast: a short, circular damage field. No placement rules -- an explosion
## is happy to happen against a wall, which is the difference between it and the fire
## wall expressed purely as data.

var _field: DamageField = null


func begin(caster: Node2D, target: Vector2, slot: AbilitySlot) -> bool:
	var data: AbilityResource = slot.data
	global_position = target

	_field = DamageField.new()
	_field.name = "Field"
	_field.damage = slot.damage()
	_field.tick_interval = data.tick_interval
	_field.radius = data.area_radius * slot.area_scale()
	_field.hits_mask = Layers.ENEMY
	_field.source = caster
	_field.color = data.color
	add_child(_field)

	lifetime = data.duration
	FxDirector.flash_light(target, data.color, 1.8, _field.radius * 2.6, 0.3)
	FxDirector.impact(target, Vector2.UP, data.color, 16)
	return true


func _tick(_delta: float) -> void:
	if _field == null:
		return
	_field.set_alpha(lerpf(0.0, 0.6, remaining_fraction()))
