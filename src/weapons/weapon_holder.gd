class_name WeaponHolder
extends Node2D
## The player's gun hand: firing, magazines, reloading, spread bloom, switching.
##
## It reads the aim direction and muzzle position off its parent `Player`, and
## handles its own input, so the player script stays about moving.

signal shot_fired(at: Vector2)
signal weapon_changed(slot: WeaponSlot, index: int)
signal ammo_changed()

const MAX_SLOTS: int = 3
## Recoil bloom recovers at this many degrees per second.
const RECOIL_RECOVERY: float = 9.0

## Weapon the player starts a level with.
@export var start_weapon: String = "pistol"

var slots: Array[WeaponSlot] = []
var current: int = -1

var _player: Player = null
var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _recoil: float = 0.0


func _ready() -> void:
	_player = get_parent() as Player
	if not start_weapon.is_empty():
		add_weapon(start_weapon, -1, false)


#region queries

func slot() -> WeaponSlot:
	if current < 0 or current >= slots.size():
		return null
	return slots[current]


func current_weapon() -> WeaponResource:
	var s: WeaponSlot = slot()
	return s.data if s != null else null


func is_reloading() -> bool:
	return _reload_left > 0.0


func reload_progress() -> float:
	var s: WeaponSlot = slot()
	if s == null or _reload_left <= 0.0:
		return 0.0
	return 1.0 - clampf(_reload_left / s.reload_time(), 0.0, 1.0)


func recoil_bloom() -> float:
	return _recoil


func total_ammo_of(id: StringName) -> int:
	for s: WeaponSlot in slots:
		if s.data.id == id:
			return s.total_ammo()
	return 0

#endregion


#region input

func _unhandled_input(event: InputEvent) -> void:
	if not _can_act():
		return
	if event.is_action_pressed(&"reload"):
		reload()
	elif event.is_action_pressed(&"switch_next"):
		cycle(1)
	elif event.is_action_pressed(&"switch_prev"):
		cycle(-1)
	elif event.is_action_pressed(&"switch_1"):
		select(0)
	elif event.is_action_pressed(&"switch_2"):
		select(1)
	elif event.is_action_pressed(&"switch_3"):
		select(2)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_recoil = maxf(0.0, _recoil - RECOIL_RECOVERY * delta)

	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()

	if not _can_act():
		return
	var w: WeaponResource = current_weapon()
	if w == null:
		return
	if w.automatic:
		if Input.is_action_pressed(&"fire"):
			try_fire()
	elif Input.is_action_just_pressed(&"fire"):
		try_fire()


func _can_act() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _player.is_dead():
		return false
	return not GameDirector.is_paused()

#endregion


#region firing

func try_fire() -> void:
	if _cooldown > 0.0 or _reload_left > 0.0:
		return
	var s: WeaponSlot = slot()
	if s == null:
		return

	if s.mag <= 0:
		AudioDirector.play(&"dry_fire", -8.0)
		_cooldown = 0.3
		if s.reserve > 0:
			reload()
		return

	var w: WeaponResource = s.data
	s.mag -= 1
	_cooldown = w.cooldown()
	ammo_changed.emit()

	var origin: Vector2 = _player.muzzle_position()
	# Straight out of the barrel (see `Player.shot_direction`).
	var aim: Vector2 = _player.shot_direction()
	var spread: float = s.spread_deg() + _recoil
	var parent: Node = GameDirector.spawn_parent()

	for i: int in w.pellets:
		var angle: float = aim.angle() + deg_to_rad(randf_range(-spread, spread) * 0.5)
		var bullet := Projectile.new()
		bullet.damage = s.damage()
		bullet.hits_mask = Layers.PLAYER_SHOT_HITS
		bullet.shooter = _player
		# bullet.max_distance = w.max_range * randf_range(0.85, 1.15)
		bullet.color = w.color
		bullet.knockback = w.knockback
		bullet.show_orb = false
		parent.add_child(bullet)
		bullet.launch(origin, Vector2.from_angle(angle), w.projectile_speed * randf_range(0.96, 1.04))

	FxDirector.muzzle_flash(origin, aim, w.color, 160.0)
	FxDirector.shake(w.shake)
	AudioDirector.play_at(w.sfx, origin, -3.0)
	GameDirector.make_noise(origin, w.noise(), NoiseKind.Type.GUNSHOT, _player)
	GameDirector.notify_shot_fired()

	_recoil = minf(_recoil + w.recoil_kick, 14.0)
	_player.apply_recoil(-aim * w.knockback * 0.35)
	shot_fired.emit(origin)


func stop() -> void:
	# Nothing held; firing is polled each physics frame.
	pass


## Dev/probe hook: fire one shot, ignoring the trigger.
func debug_fire_once() -> void:
	try_fire()

#endregion


#region reloading

func reload() -> void:
	var s: WeaponSlot = slot()
	if s == null or _reload_left > 0.0:
		return
	if s.reserve <= 0 or s.mag >= s.mag_size():
		return
	_reload_left = s.reload_time()
	AudioDirector.play(&"reload_out", -7.0)


func _finish_reload() -> void:
	var s: WeaponSlot = slot()
	if s == null:
		return
	var need: int = s.mag_size() - s.mag
	var taken: int = mini(need, s.reserve)
	s.mag += taken
	s.reserve -= taken
	AudioDirector.play(&"reload_in", -7.0)
	ammo_changed.emit()

#endregion


#region inventory

## Adds a weapon, or ammo for one already carried. Returns true if the weapon was new.
##
## `auto_equip` takes the hand only for a *new* weapon. A top-up for one already carried never does:
## the pickup that switches you to a gun is the one that gives you the gun, and a player who picked
## their weapon deliberately does not want it changed by walking over ammunition.
func add_weapon(id: String, ammo: int = -1, auto_equip: bool = true) -> bool:
	var data: WeaponResource = WeaponLibrary.by_id(id)
	# What is in hand now, so that if this pickup takes its place the reload can be abandoned with it.
	var was_held: WeaponSlot = slot()
	for i: int in slots.size():
		if slots[i].data.id == data.id:
			var held: WeaponSlot = slots[i]
			var amount: int = ammo if ammo >= 0 else held.ammo_pickup_amount() * 2
			held.reserve = mini(data.reserve_max, held.reserve + amount)
			ammo_changed.emit()
			return false

	var fresh := WeaponSlot.new(data)
	if ammo >= 0:
		fresh.reserve = ammo

	if slots.size() >= MAX_SLOTS and current >= 0:
		# Swap out whatever is in hand.
		slots[current] = fresh
	elif slots.size() < MAX_SLOTS:
		slots.append(fresh)
	else:
		slots[0] = fresh

	if current < 0:
		current = 0
	elif auto_equip:
		current = slots.find(fresh)
	if current < 0 or current >= slots.size():
		current = 0
	if slot() != was_held:
		# A reload belongs to the weapon that was in hand. Switching abandons it -- and the timer has to
		# go with the weapon, or the HUD keeps drawing a reload bar for the new gun and `_finish_reload`
		# fills it with rounds it never loaded.
		_reload_left = 0.0
	ammo_changed.emit()
	weapon_changed.emit(slot(), current)
	return true


## Replaces everything the player is carrying (used by a level's start loadout).
func set_loadout(ids: Array) -> void:
	_reload_left = 0.0
	slots.clear()
	current = -1
	for id: Variant in ids:
		add_weapon(String(id), -1, false)
	if slots.is_empty() and not start_weapon.is_empty():
		add_weapon(start_weapon, -1, false)
	if not slots.is_empty():
		current = 0
	ammo_changed.emit()
	weapon_changed.emit(slot(), current)


func select(index: int) -> void:
	if index < 0 or index >= slots.size() or index == current:
		return
	current = index
	_reload_left = 0.0
	_recoil = 0.0
	_cooldown = maxf(_cooldown, 0.12)
	AudioDirector.play(&"ui_click", -12.0)
	weapon_changed.emit(slot(), current)


func cycle(direction: int) -> void:
	if slots.size() <= 1:
		return
	select(wrapi(current + direction, 0, slots.size()))


## Adds ammo to the weapon in hand (creating nothing if the player is unarmed).
func add_ammo(amount: int) -> void:
	var s: WeaponSlot = slot()
	if s == null:
		return
	s.reserve = mini(s.data.reserve_max, s.reserve + amount)
	ammo_changed.emit()


func upgrade_current() -> bool:
	var s: WeaponSlot = slot()
	if s == null:
		return false
	# `upgrade()` refuses at the cap, and refusing here is what leaves the crate on the ground.
	if not s.upgrade():
		return false
	weapon_changed.emit(s, current)
	return true


func grant_all() -> void:
	for id: String in WeaponLibrary.ORDER:
		add_weapon(id, -1, false)
	if current < 0:
		current = 0
	weapon_changed.emit(slot(), current)


## Every weapon at once, fully upgraded, magazine and reserve full. Used by the level select: a
## practice run should be about the level, not about the loadout you happened to have.
func grant_maxed() -> void:
	slots.clear()
	current = -1
	for id: String in WeaponLibrary.ORDER:
		var data: WeaponResource = WeaponLibrary.by_id(id)
		var weapon_slot := WeaponSlot.new(data)
		weapon_slot.level = WeaponSlot.MAX_LEVEL
		weapon_slot.mag = weapon_slot.mag_size()
		weapon_slot.reserve = data.reserve_max
		slots.append(weapon_slot)
	if not slots.is_empty():
		current = 0
	# Nothing carried in, so nothing is being reloaded.
	_reload_left = 0.0
	_recoil = 0.0
	ammo_changed.emit()
	weapon_changed.emit(slot(), current)


## Plain-data snapshot of the loadout, so it can survive a level change.
func serialize() -> Array:
	var out: Array = []
	for s: WeaponSlot in slots:
		out.append({
			"id": String(s.data.id),
			"mag": s.mag,
			"reserve": s.reserve,
			"level": s.level,
		})
	return out


func deserialize(data: Array) -> void:
	# The loadout is being replaced outright, so a reload in flight belongs to a weapon that is about to
	# stop existing. Same rule as a switch: the timer goes with it.
	_reload_left = 0.0
	slots.clear()
	current = -1
	for entry: Variant in data:
		var dict: Dictionary = entry
		var id: String = String(dict.get("id", "pistol"))
		var data_resource: WeaponResource = WeaponLibrary.by_id(id)
		var s := WeaponSlot.new(data_resource)
		s.mag = int(dict.get("mag", data_resource.mag_size))
		s.reserve = int(dict.get("reserve", 0))
		s.level = int(dict.get("level", 0))
		slots.append(s)
	if slots.is_empty() and not start_weapon.is_empty():
		add_weapon(start_weapon, -1, false)
	if not slots.is_empty():
		current = 0
	ammo_changed.emit()
	weapon_changed.emit(slot(), current)

#endregion
