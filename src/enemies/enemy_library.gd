class_name EnemyLibrary
extends RefCounted
## The enemy roster. Add an archetype by writing a builder and listing it in ORDER.

const ORDER: Array[String] = ["guard", "scout", "heavy"]

static var _cache: Dictionary = {}


static func ids() -> Array[String]:
	return ORDER.duplicate()


static func by_id(id: String) -> EnemyArchetype:
	if _cache.has(id):
		return _cache[id]
	var archetype: EnemyArchetype = null
	match id:
		"scout":
			archetype = _build_scout()
		"heavy":
			archetype = _build_heavy()
		_:
			archetype = _build_guard()
	_cache[id] = archetype
	return archetype


## The baseline: average in every way, drops a pistol sometimes.
static func _build_guard() -> EnemyArchetype:
	var a := EnemyArchetype.new()
	a.id = &"guard"
	a.display_name = "Guard"
	a.max_health = 50.0
	a.radius = 13.0
	a.speed_patrol = 62.0
	a.speed_alert = 132.0
	a.body_color = Color(0.85, 0.40, 0.34)
	a.sight_range = 430.0
	a.sight_fov = 105.0
	a.detect_multiplier = 1.0
	a.damage = 15.0
	a.pellets = 1
	a.fire_interval = 0.22
	a.burst = 3
	a.burst_pause = 0.75
	a.spread_deg = 6.5
	a.fire_range = 520.0
	a.reaction_time = 0.2
	a.preferred_range = 260.0
	a.drop_weapon = "pistol"
	return a


## Fast, fragile, sees further and reacts quicker. The one that catches you.
static func _build_scout() -> EnemyArchetype:
	var a := EnemyArchetype.new()
	a.id = &"scout"
	a.display_name = "Scout"
	a.max_health = 40.0
	a.radius = 11.0
	a.speed_patrol = 84.0
	a.speed_alert = 168.0
	a.body_color = Color(0.95, 0.72, 0.30)
	a.sight_range = 520.0
	a.sight_fov = 120.0
	a.detect_multiplier = 1.5
	a.damage = 11.0
	a.pellets = 1
	a.fire_interval = 0.16
	a.burst = 5
	a.burst_pause = 0.6
	a.spread_deg = 7.0
	a.fire_range = 480.0
	a.reaction_time = 0.3
	a.preferred_range = 220.0
	a.drop_weapon = "smg"
	return a


## Slow, tanky, closes the distance and hits hard with a shotgun.
static func _build_heavy() -> EnemyArchetype:
	var a := EnemyArchetype.new()
	a.id = &"heavy"
	a.display_name = "Heavy"
	a.max_health = 130.0
	a.radius = 17.0
	a.speed_patrol = 46.0
	a.speed_alert = 96.0
	a.body_color = Color(0.55, 0.45, 0.85)
	a.sight_range = 380.0
	a.sight_fov = 95.0
	a.detect_multiplier = 0.8
	a.damage = 10.0
	a.pellets = 5
	a.fire_interval = 0.5
	a.burst = 1
	a.burst_pause = 1.35
	a.spread_deg = 11.0
	a.fire_range = 340.0
	a.reaction_time = 0.55
	a.preferred_range = 170.0
	a.drop_weapon = "shotgun"
	return a
