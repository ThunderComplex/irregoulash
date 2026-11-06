class_name WeaponSlot
extends RefCounted
## Runtime state for one carried weapon: ammo in the magazine, reserve ammo, and
## how many times it has been upgraded.
##
## The `WeaponResource` itself is a shared, read-only template -- upgrades never
## mutate it, so every enemy or pickup can safely point at the same instance.

## How many times a weapon may be upgraded. The cap keeps a long campaign from turning one gun into a
## different game, and lets an upgrade crate be left on the ground instead of being consumed at the cap.
const MAX_LEVEL: int = 3

var data: WeaponResource
var mag: int = 0
var reserve: int = 0
var level: int = 0


func _init(weapon_data: WeaponResource = null) -> void:
	if weapon_data != null:
		data = weapon_data
		mag = data.mag_size
		reserve = data.mag_size * 3


func damage() -> float:
	return data.damage * (1.0 + 0.25 * float(level))


func spread_deg() -> float:
	return maxf(0.15, data.spread_deg * (1.0 - 0.16 * float(level)))


func mag_size() -> int:
	return data.mag_size


func ammo_pickup_amount() -> int:
	return data.ammo_pickup


func reload_time() -> float:
	return maxf(0.15, data.reload_time * (1.0 - 0.08 * float(level)))


## Raises the level by one. Returns false at the cap, so a pickup can be left where it is rather than
## being spent for nothing.
func upgrade() -> bool:
	if level >= MAX_LEVEL:
		return false
	level += 1
	return true


func total_ammo() -> int:
	return mag + reserve
