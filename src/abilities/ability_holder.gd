class_name AbilityHolder
extends Node2D
## The player's abilities: slots, cooldowns, and casting.
##
## It owns everything abilities have in common and *nothing* about what any of them do.
## The effect spawned by `AbilityResource.effect` knows that. Adding a fourth ability is
## a library entry plus one small effect script, with no change in here -- which is the
## only reason the weapon analogy stays worth having.

const MAX_SLOTS: int = 2

signal ability_gained(slot: AbilitySlot, index: int)
signal cast_refused(index: int, reason: String)

var slots: Array[AbilitySlot] = []
## When finite, overrides the mouse cursor as the casting target. Only the dev probe sets
## this, so scripted casts are deterministic.
var debug_target: Vector2 = Vector2.INF

var _player: Player = null


func _ready() -> void:
	_player = get_parent() as Player


func _physics_process(delta: float) -> void:
	# Cooldowns tick per slot, so casting one ability never locks out the other.
	for slot: AbilitySlot in slots:
		slot.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not _can_act():
		return
	if event.is_action_pressed(&"ability_1"):
		use_ability(0)
	elif event.is_action_pressed(&"ability_2"):
		use_ability(1)


func _can_act() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _player.is_dead():
		return false
	return not GameDirector.is_paused()


#region casting

## Casts the ability in `index`, or explains why it will not. Returns whether it happened.
##
## This is the whole of the "abilities all differ" problem, and it is deliberately
## identical for every ability: resolve the target, check it, spawn the effect, let the
## effect say whether it accepted, and only then charge the cooldown.
func use_ability(index: int) -> bool:
	if not _can_act():
		return false
	var slot: AbilitySlot = slot_at(index)
	if slot == null or slot.data == null:
		return false

	if not slot.is_ready():
		cast_refused.emit(index, "not ready")
		return false

	var data: AbilityResource = slot.data
	var target: Vector2 = resolve_target(data)
	if data.targeting != AbilityResource.Targeting.SELF:
		if not AbilityCasting.can_place(_player, target, data):
			# Refused before anything is spent: the player is not charged a cooldown for
			# a wall of fire that has nowhere to stand.
			AudioDirector.play(&"cast_refused", -6.0)
			GameDirector.announce_message("%s: no room there" % data.display_name.to_upper(),
				Color(1.0, 0.6, 0.5))
			cast_refused.emit(index, "no room")
			return false

	var effect: AbilityEffect = _spawn_effect(data)
	if effect == null:
		return false
	if not effect.begin(_player, target, slot):
		effect.queue_free()
		cast_refused.emit(index, "refused")
		return false

	slot.start_cooldown()
	AudioDirector.play_at(data.sfx, target, -4.0)
	FxDirector.shake(data.shake)
	# Noisy, like everything else that hurts people here: abilities must not be a silent
	# way to fight, and enemies already investigate noise.
	GameDirector.make_noise(target, data.noise_radius, _player)
	return true


## The cursor position clamped to the ability's reach. SELF abilities target the caster.
func resolve_target(data: AbilityResource) -> Vector2:
	if data.targeting == AbilityResource.Targeting.SELF:
		return _player.global_position
	var cursor: Vector2 = debug_target if debug_target.is_finite() else get_global_mouse_position()
	return AbilityCasting.clamped_target(_player.global_position, cursor, data.max_range)


func _spawn_effect(data: AbilityResource) -> AbilityEffect:
	if data.effect == null:
		push_warning("Ability '%s' has no effect script." % data.id)
		return null
	var effect := data.effect.new() as AbilityEffect
	if effect == null:
		push_warning("Ability '%s' does not extend AbilityEffect." % data.id)
		return null
	# Spawned into the level, so it is cleaned up with the level.
	GameDirector.spawn_parent().add_child(effect)
	return effect

#endregion


#region inventory

## Gives the player an ability. Returns false when it is already carried *or* when both
## slots are full; the caller is expected to leave the pickup where it is rather than
## quietly consuming it.
func add_ability(id: String) -> bool:
	var data: AbilityResource = AbilityLibrary.by_id(id)
	if data == null:
		return false
	if has_ability(String(data.id)):
		return false
	if slots.size() >= MAX_SLOTS:
		return false
	slots.append(AbilitySlot.new(data))
	ability_gained.emit(slots.back(), slots.size() - 1)
	return true


func has_ability(id: String) -> bool:
	for slot: AbilitySlot in slots:
		if slot.data != null and slot.data.id == StringName(id):
			return true
	return false


func slot_at(index: int) -> AbilitySlot:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


## Debug hook, mirroring WeaponHolder.grant_all().
func grant_all() -> void:
	for id: String in AbilityLibrary.ids():
		add_ability(id)

#endregion
