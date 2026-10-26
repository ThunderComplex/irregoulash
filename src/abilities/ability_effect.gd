class_name AbilityEffect
extends Node2D
## Base for whatever an ability spawns.
##
## One effect per ability, spawned by `AbilityHolder` on a successful cast, parented to
## the level (so it is cleaned up with the level) and left to manage itself.
##
## `begin()` is the only thing the holder calls. Returning false means "that cast was
## illegal", and the holder keeps the cooldown so the player is not charged for it.

## Seconds this effect lives for. 0 means it manages its own lifetime.
var lifetime: float = 0.0

var _age: float = 0.0


## Caster: whoever cast it. Target: the already-clamped, already-validated point.
func begin(_caster: Node2D, _target: Vector2, _slot: AbilitySlot) -> bool:
	return false


func _process(delta: float) -> void:
	_tick(delta)
	if lifetime > 0.0:
		_age += delta
		if _age >= lifetime:
			queue_free()


## Subclass hook: called every frame for as long as the effect lives.
func _tick(_delta: float) -> void:
	pass


## How much of this effect's life is left, 1 down to 0. Handy for fading out.
func remaining_fraction() -> float:
	if lifetime <= 0.0:
		return 1.0
	return clampf((lifetime - _age) / lifetime, 0.0, 1.0)
