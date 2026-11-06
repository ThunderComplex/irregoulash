class_name AbilitySlot
extends RefCounted
## Runtime state for one carried ability: its upgrade level and its own cooldown.
##
## The cooldown lives per slot, unlike weapons where one gun is equipped and the holder
## tracks a single timer. Without that, casting one ability would lock out the other.

## How many times an ability may be upgraded. Damage grows linearly and cooldown falls to a floor, so a
## cap is what stops a long run from trivialising the game -- and it is why a late crate can be left on
## the floor instead of being spent for nothing.
const MAX_LEVEL: int = 3

var data: AbilityResource
var level: int = 0
## Seconds until this ability may be cast again.
var cooldown_left: float = 0.0


func _init(ability_data: AbilityResource = null) -> void:
	if ability_data != null:
		data = ability_data


func tick(delta: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)


func is_ready() -> bool:
	return cooldown_left <= 0.0


func start_cooldown() -> void:
	cooldown_left = cooldown()


## How far through its cooldown this slot is, for the HUD: 0 = ready, 1 = just cast.
func cooldown_fraction() -> float:
	var total: float = cooldown()
	if total <= 0.0:
		return 0.0
	return clampf(cooldown_left / total, 0.0, 1.0)


## Upgrades make an ability *faster* to cast, with a floor so it never reaches zero.
func cooldown() -> float:
	return maxf(0.4, data.cooldown * (1.0 - data.cooldown_per_level * float(level)))


func damage() -> float:
	return data.damage * (1.0 + data.damage_per_level * float(level))


func area_scale() -> float:
	return 1.0 + data.area_per_level * float(level)


func upgrade() -> bool:
	if level >= MAX_LEVEL:
		return false
	level += 1
	return true
