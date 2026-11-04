class_name AbilityLibrary
extends RefCounted
## Every ability in the game, defined in code, in the same shape as `WeaponLibrary`:
## one builder per ability, all balance in one place, referenced elsewhere by name.

const ORDER: Array[String] = ["fire_wall", "fire_tempest", "lightning_bolt"]

static var _cache: Dictionary = {}


static func ids() -> Array[String]:
	return ORDER.duplicate()


static func by_id(id: String) -> AbilityResource:
	if _cache.has(id):
		return _cache[id]

	var ability: AbilityResource = null
	match id:
		"fire_tempest":
			ability = _build_fire_tempest()
		"lightning_bolt":
			ability = _build_lightning_bolt()
		_:
			# Unknown ids get the default rather than null: a null here used to travel
			# into callers and error out far from the mistake.
			ability = _build_fire_wall()

	_cache[id] = ability
	return ability


## A wall of fire at the cursor: the only ability that changes the level. It blocks sight
## both ways without blocking movement, so it cuts a line of sight and burns whoever follows.
static func _build_fire_wall() -> AbilityResource:
	var a := AbilityResource.new()
	a.id = &"fire_wall"
	a.display_name = "Fire Wall"
	a.description = "A burning barrier. Blocks sight both ways; enemies who cross it burn."
	a.targeting = AbilityResource.Targeting.POINT
	a.cooldown = 5.0
	a.damage = 13.0
	a.tick_interval = 0.4
	a.duration = 6.0
	a.max_range = 380.0
	a.requires_clear_space = true
	a.placement_radius = 52.0
	a.area_size = Vector2(176.0, 40.0)
	a.color = Color(1.0, 0.55, 0.18)
	a.effect = FireWall
	a.sfx = &"cast_fire"
	a.noise_radius = 850.0
	a.shake = 0.25
	a.damage_per_level = 0.22
	a.area_per_level = 0.22
	a.cooldown_per_level = 0.12
	return a


## A localised explosion at the cursor: all of its damage in one or two hits, so being
## inside it is what hurts, not lingering.
static func _build_fire_tempest() -> AbilityResource:
	var a := AbilityResource.new()
	a.id = &"fire_tempest"
	a.display_name = "Fire Tempest"
	a.description = "A short, violent blast where you point."
	a.targeting = AbilityResource.Targeting.POINT
	a.cooldown = 7.0
	a.damage = 32.0
	a.tick_interval = 0.25
	a.duration = 0.5
	a.max_range = 480.0
	a.requires_clear_space = false
	a.area_radius = 104.0
	a.color = Color(1.0, 0.65, 0.2)
	a.effect = FireTempest
	a.sfx = &"cast_explosion"
	a.noise_radius = 1150.0
	a.shake = 0.55
	a.damage_per_level = 0.28
	a.area_per_level = 0.14
	a.cooldown_per_level = 0.1
	return a


## A bolt fired from the caster towards the cursor: the only DIRECTION ability, so it is
## what proves the targeting split is worth having.
static func _build_lightning_bolt() -> AbilityResource:
	var a := AbilityResource.new()
	a.id = &"lightning_bolt"
	a.display_name = "Lightning Bolt"
	a.description = "A fast bolt of lightning."
	a.targeting = AbilityResource.Targeting.DIRECTION
	a.cooldown = 2.5
	a.damage = 18.0
	a.max_range = 620.0
	a.projectile_speed = 1900.0
	a.projectile_range = 720.0
	a.color = Color(0.7, 0.85, 1.0)
	a.effect = LightningBolt
	a.sfx = &"cast_lightning"
	a.noise_radius = 700.0
	a.shake = 0.16
	a.damage_per_level = 0.2
	a.cooldown_per_level = 0.14
	return a
