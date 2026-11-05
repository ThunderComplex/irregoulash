class_name WeaponLibrary
extends RefCounted
## Every weapon in the game, defined in code.
##
## Kept in one place (rather than as .tres files scattered around) so balancing a
## weapon means editing one function, and so pickups can reference a weapon by a
## plain name that shows up as a dropdown in the inspector.
##
## Add a weapon: write a `_build_x()` function, add it to ORDER, done.

const ORDER: Array[String] = ["pistol", "smg", "shotgun"]

static var _cache: Dictionary = {}


static func ids() -> Array[String]:
	return ORDER.duplicate()


static func by_id(id: String) -> WeaponResource:
	if _cache.has(id):
		return _cache[id]
	var weapon: WeaponResource = null
	match id:
		"smg":
			weapon = _build_smg()
		"shotgun":
			weapon = _build_shotgun()
		_:
			weapon = _build_pistol()
	_cache[id] = weapon
	return weapon


## Semi-auto, accurate, always useful. The weapon you are issued.
static func _build_pistol() -> WeaponResource:
	var w := WeaponResource.new()
	w.id = &"pistol"
	w.display_name = "PISTOL"
	w.category = "pistol"
	w.damage = 10.0
	w.fire_rate = 5.5
	w.automatic = false
	w.pellets = 1
	w.spread_deg = 1.4
	w.recoil_kick = 0.7
	w.projectile_speed = 1600.0
	w.mag_size = 5
	w.reload_time = 1.3
	w.reserve_max = 40
	w.shake = 0.15
	w.knockback = 60.0
	w.color = Color(1.0, 0.94, 0.68)
	w.sfx = &"shot_pistol"
	w.noise_radius = 700.0
	w.ammo_pickup = 24
	w.silhouette = Vector2(20.0, 5.0)
	w.pickup_color = Color(0.72, 0.8, 0.95)
	return w


## Full auto, cheap per shot, useless past medium range.
static func _build_smg() -> WeaponResource:
	var w := WeaponResource.new()
	w.id = &"smg"
	w.display_name = "SMG"
	w.category = "smg"
	w.damage = 7.0
	w.fire_rate = 12.5
	w.automatic = true
	w.pellets = 1
	w.spread_deg = 4.6
	w.recoil_kick = 0.55
	w.projectile_speed = 1500.0
	w.mag_size = 16
	w.reload_time = 1.7
	w.reserve_max = 96
	w.shake = 0.09
	w.knockback = 26.0
	w.color = Color(1.0, 0.86, 0.5)
	w.sfx = &"shot_smg"
	w.noise_radius = 880.0
	w.ammo_pickup = 60
	w.silhouette = Vector2(24.0, 7.0)
	w.pickup_color = Color(0.95, 0.85, 0.55)
	return w


## Room clearing. Loud, slow, brutally short range, huge knockback.
static func _build_shotgun() -> WeaponResource:
	var w := WeaponResource.new()
	w.id = &"shotgun"
	w.display_name = "SHOTGUN"
	w.category = "shotgun"
	w.damage = 8.5
	w.fire_rate = 1.35
	w.automatic = false
	w.pellets = 7
	w.spread_deg = 14.0
	w.recoil_kick = 9.0
	w.projectile_speed = 1250.0
	w.mag_size = 5
	w.reload_time = 1.7
	w.reserve_max = 80
	w.shake = 0.42
	w.knockback = 300.0
	w.color = Color(1.0, 0.78, 0.45)
	w.sfx = &"shot_shotgun"
	w.noise_radius = 1050.0
	w.ammo_pickup = 16
	w.silhouette = Vector2(26.0, 9.0)
	w.pickup_color = Color(0.95, 0.7, 0.45)
	return w
