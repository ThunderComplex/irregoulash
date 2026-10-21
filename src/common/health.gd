class_name Health
extends Node
## Hit points, invulnerability window and hit flash. Shared by the player and
## every enemy so damage feels identical everywhere.

signal damaged(amount: float, source: Node, hit_position: Vector2, direction: Vector2)
signal healed(amount: float)
signal died(source: Node)

@export var max_health: float = 100.0
## Seconds of immunity after a hit (player uses this; enemies usually 0).
@export var invuln_time: float = 0.0
## Optional CanvasItem to brighten briefly when hit.
@export var flash_target: NodePath
@export var flash_time: float = 0.09
@export var flash_strength: float = 3.5

var current: float = 0.0
var is_dead: bool = false

var _invuln: float = 0.0
var _flash: float = 0.0
var _flash_item: CanvasItem = null


func _ready() -> void:
	current = max_health
	if flash_target != NodePath():
		_flash_item = get_node_or_null(flash_target) as CanvasItem


func _process(delta: float) -> void:
	if _invuln > 0.0:
		_invuln = maxf(0.0, _invuln - delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		if _flash_item != null:
			var t: float = _flash / maxf(0.001, flash_time)
			_flash_item.modulate = Color(1.0, 1.0, 1.0).lerp(
				Color(flash_strength, flash_strength, flash_strength), t)


## Returns true if the hit actually landed.
##
## `source` is deliberately untyped and validated here. A bullet outlives its
## shooter, so by the time a hit lands the shooter may already be freed -- and a
## freed object cannot be handed to a typed parameter or emitted through a signal.
func take_damage(amount: float, source = null, hit_position: Vector2 = Vector2.ZERO,
		direction: Vector2 = Vector2.ZERO) -> bool:
	if is_dead or _invuln > 0.0:
		return false
	var from: Node = source if is_instance_valid(source) else null
	current -= amount
	_invuln = invuln_time
	_flash = flash_time
	if _flash_item != null:
		_flash_item.modulate = Color(flash_strength, flash_strength, flash_strength)
	damaged.emit(amount, from, hit_position, direction)
	if current <= 0.0:
		current = 0.0
		is_dead = true
		died.emit(from)
	return true


func heal(amount: float) -> void:
	if is_dead:
		return
	current = minf(max_health, current + amount)
	healed.emit(amount)


func fraction() -> float:
	return clampf(current / maxf(1.0, max_health), 0.0, 1.0)


func is_invulnerable() -> bool:
	return _invuln > 0.0


## Set hit points in one call. Using `max_health` directly after `_ready()` would
## leave `current` at the default, which is a nasty way to ship a bug.
func configure(maximum: float, invuln: float = 0.0) -> void:
	max_health = maximum
	invuln_time = invuln
	current = maximum
	is_dead = false
