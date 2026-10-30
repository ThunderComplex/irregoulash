class_name Player
extends CharacterBody2D
## The player character: screen-relative movement, mouse aim, dash, and the
## vision rig that defines what the player is allowed to see.
##
## The weapon holder is looked up by name and used through duck typing, so the
## player still works (unarmed) if you strip the WeaponHolder node out of the
## scene while experimenting.

signal died

@onready var vision: VisionRig = $Vision
@onready var visual: Node2D = $Visual
@onready var health: Health = $Health
@onready var camera: Camera2D = $Camera
@onready var gun_pivot: Node2D = $Visual/GunPivot

var aim_direction: Vector2 = Vector2.RIGHT
var weapons: Node = null
var abilities: Node = null
## When non-zero the mouse is ignored and this direction is used instead. Only
## used by the automated dev probe so scripted tests are deterministic.
var debug_aim: Vector2 = Vector2.ZERO

## Any key opens any locked door. Carried between levels and saved with the checkpoint, because
## losing keys at a level boundary would be a nasty surprise.
var keys: int = 0

var _dead: bool = false
var _dash_time: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_direction: Vector2 = Vector2.RIGHT
var _footstep_accum: float = 0.0
## Doors already smashed during the current dash, so one dash cannot hit the same door twice.
var _dashed_doors: Array[Door] = []


func _ready() -> void:
	add_to_group("player")
	# The player's art and vision rig are driven by the aim angle, which is measured
	# in global space, so the root itself must never carry a rotation.
	rotation = 0.0
	_build_collision()
	_build_art()

	health.configure(Tuning.player_max_health, Tuning.player_hit_invuln)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)

	weapons = get_node_or_null("WeaponHolder")
	if weapons != null and weapons.has_signal("shot_fired"):
		weapons.shot_fired.connect(_on_weapon_shot)

	abilities = get_node_or_null("AbilityHolder")

	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = Tuning.camera_smoothing
	FxDirector.register_camera(camera)
	_update_camera_zoom()
	# The window can be resized, or the display settings changed, at any time.
	get_viewport().size_changed.connect(_update_camera_zoom)

	vision.aim_at(aim_direction)
	GameDirector.set_player(self)


func _process(delta: float) -> void:
	if _dead:
		return
	var mouse: Vector2 = get_global_mouse_position()
	var to_mouse: Vector2 = mouse - global_position
	if debug_aim != Vector2.ZERO:
		aim_direction = debug_aim.normalized()
	elif to_mouse.length_squared() > 1.0:
		aim_direction = to_mouse.normalized()
	vision.aim_at(aim_direction)
	gun_pivot.rotation = aim_direction.angle()
	# Keep the gun the right way up when aiming leftwards.
	gun_pivot.scale.y = -1.0 if absf(aim_direction.angle()) > PI * 0.5 else 1.0

	if GameDirector.god_mode:
		health.current = health.max_health
	_update_camera_offset()
	_update_noclip()


func _physics_process(delta: float) -> void:
	if _dead:
		velocity = Vector2.ZERO
		return

	if _dash_cooldown > 0.0:
		_dash_cooldown -= delta

	var input: Vector2 = GameInput.move_vector()

	if GameDirector.noclip:
		global_position += input * Tuning.player_speed * 3.0 * delta
		velocity = Vector2.ZERO
		return

	if _dash_time > 0.0:
		_dash_time -= delta
		velocity = _dash_direction * Tuning.player_dash_speed
		move_and_slide()
		_smash_doors_hit()
		return

	if input.length() > 0.1 and _dash_cooldown <= 0.0 and Input.is_action_just_pressed(&"dash"):
		_start_dash(input)
		return

	if Input.is_action_just_pressed(&"interact"):
		interact_nearby()

	var target: Vector2 = input * Tuning.player_speed
	var rate: float = Tuning.player_accel if input.length() > 0.1 else Tuning.player_friction
	velocity = velocity.move_toward(target, rate * delta)
	move_and_slide()
	_update_footsteps(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Weapon input (fire, reload, switching) is handled by the WeaponHolder.
	pass


#region movement helpers

func _start_dash(input: Vector2) -> void:
	_dash_time = Tuning.player_dash_time
	_dash_cooldown = Tuning.player_dash_cooldown
	_dash_direction = input.normalized()
	_dashed_doors.clear()
	velocity = _dash_direction * Tuning.player_dash_speed
	AudioDirector.play(&"dash", -3.0)
	GameDirector.make_noise(global_position, Tuning.noise_dash, self)
	FxDirector.spark_burst(global_position - _dash_direction * 10.0, -_dash_direction, 6,
		Color(0.72, 0.82, 1.0), 130.0, 0.22)


## Doors stopped by this frame's dash. `move_and_slide` reports what it collided with, so this
## needs no extra raycast: whatever stopped the dash is what gets hit.
func _smash_doors_hit() -> void:
	for i: int in get_slide_collision_count():
		var collision: KinematicCollision2D = get_slide_collision(i)
		var body: Node = collision.get_collider() as Node
		if body == null:
			continue
		# The collider is nested under the leaf so it swings with it, so the owner is found by
		# walking up rather than by `get_parent()`.
		var door := Door.from_node(body)
		if door == null or _dashed_doors.has(door):
			continue
		_dashed_doors.append(door)
		door.smash(self)


## Work the nearest door within reach. Nearest rather than most-faced: doors sit in doorways the
## player is walking through, so proximity is a better guess than pointer direction.
func interact_nearby() -> bool:
	var door := nearest_door()
	if door == null:
		return false
	return door.interact(self)


## Debug hook for the probe: starts a real dash, so door smashing is exercised through the same
## collision path a player uses.
func debug_dash(direction: Vector2) -> void:
	if direction.length_squared() < 0.01:
		return
	_start_dash(direction)


func nearest_door() -> Door:
	var best: Door = null
	var best_distance: float = Tuning.player_interact_range
	for node: Node in get_tree().get_nodes_in_group(&"door"):
		var door := node as Door
		if door == null or door.state == Door.State.BROKEN:
			continue
		# Distance to the door's surface, not its centre: a wide door's centre is out of reach
		# while you are standing against it.
		var distance: float = door.surface_distance(global_position)
		if distance <= best_distance:
			best_distance = distance
			best = door
	return best


## Called by a door that was opened with a key.
func spend_key() -> bool:
	if keys <= 0:
		return false
	keys -= 1
	GameDirector.carry_keys(keys)
	return true


func add_key(count: int = 1) -> void:
	keys = maxi(0, keys + count)
	GameDirector.carry_keys(keys)


func _update_footsteps(delta: float) -> void:
	var speed: float = velocity.length()
	if speed < 25.0:
		return
	_footstep_accum += delta * (speed / Tuning.player_speed)
	if _footstep_accum < 0.42:
		return
	_footstep_accum = 0.0
	AudioDirector.play_at(&"footstep", global_position, -14.0, randf_range(0.9, 1.1))
	GameDirector.make_noise(global_position, Tuning.noise_footstep, self)


func _update_camera_offset() -> void:
	var distance: float = get_global_mouse_position().distance_to(global_position)
	var amount: float = minf(distance * Tuning.camera_aim_offset, Tuning.camera_aim_offset_max)
	camera.position = aim_direction * amount


## Zooms so that a constant amount of world is visible vertically, whatever the window
## size. This is the whole of "resolution independent" from the world's point of view: the
## vision cone, lamps and enemies cover the same share of the screen on any display, so the
## game does not become easier or darker just because the window is bigger.
##
## The tradeoff is horizontal: a wider aspect ratio shows more world to the sides. That is
## the standard choice for a 2D game (letterboxing an ultrawide monitor is worse), and it
## is worth knowing that a 21:9 player sees a little further sideways than a 16:9 one.
func _update_camera_zoom() -> void:
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	if viewport_height <= 0.0:
		return
	var visible_height: float = maxf(200.0, Tuning.camera_visible_height)
	camera.zoom = Vector2.ONE * (viewport_height / visible_height)


func _update_noclip() -> void:
	var wanted: int = 0 if GameDirector.noclip else Layers.PLAYER
	if collision_layer != wanted:
		collision_layer = wanted


func muzzle_position() -> Vector2:
	return global_position + aim_direction * 20.0


## Knockback from firing; the gun pushes you around a little.
func apply_recoil(impulse: Vector2) -> void:
	velocity += impulse


## Receives a bullet. Exists so projectiles can hit both the player and enemies
## through the same "take_hit" interface. `source` is untyped on purpose; see
## `Health.take_damage`.
func take_hit(amount: float, source = null, hit_position: Vector2 = Vector2.ZERO,
		direction: Vector2 = Vector2.ZERO, _knockback: float = 0.0) -> void:
	health.take_damage(amount, source, hit_position, direction)

#endregion


#region damage

func _on_damaged(_amount: float, _source: Node, hit_position: Vector2, direction: Vector2) -> void:
	FxDirector.shake(0.32)
	FxDirector.blood(hit_position, direction)
	AudioDirector.play(&"hurt", -4.0)


func _on_died(_source: Node) -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	AudioDirector.play_at(&"player_die", global_position)
	FxDirector.shake(0.85)
	FxDirector.blood(global_position, Vector2.RIGHT, visual)
	visual.rotation = aim_direction.angle() + PI * 0.5
	visual.modulate = Color(0.45, 0.4, 0.45)
	vision.set_enabled(false)
	weapons_fire_stop()
	FxDirector.flash_light(global_position, Color(1.0, 0.3, 0.3), 1.2, 220.0, 0.35)
	died.emit()
	GameDirector.notify_player_died()


func weapons_fire_stop() -> void:
	if weapons != null and weapons.has_method("stop"):
		weapons.stop()


func is_dead() -> bool:
	return _dead


func health_fraction() -> float:
	return health.fraction()

#endregion


#region art

func _build_collision() -> void:
	var collision: CollisionShape2D = get_node_or_null("Collision") as CollisionShape2D
	if collision == null:
		return
	var shape := CircleShape2D.new()
	shape.radius = Tuning.player_radius
	collision.shape = shape
	# Guaranteed here rather than trusted to the scene: the player walks into walls and into door
	# leaves, open or shut. Enemies deliberately do *not* collide with an open leaf (see Layers.DOOR).
	collision_layer = Layers.PLAYER
	collision_mask = Layers.SOLID | Layers.DOOR


## Geometric placeholder art, built in code so the scene file stays tiny and the
## whole look can be swapped for sprites later without touching gameplay.
func _build_art() -> void:
	var radius: float = Tuning.player_radius

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = Shapes.circle(radius)
	body.color = Color(0.80, 0.87, 1.0)
	body.z_index = Layers.Z_ACTOR
	visual.add_child(body)

	var outline := Line2D.new()
	outline.name = "Outline"
	outline.points = Shapes.closed_outline(Shapes.circle(radius))
	outline.width = 2.0
	outline.default_color = Color(0.22, 0.30, 0.45)
	outline.z_index = Layers.Z_ACTOR
	visual.add_child(outline)

	_build_gun()


## Placeholder weapon silhouette; the real thing is drawn per weapon later.
func _build_gun() -> void:
	var gun := Polygon2D.new()
	gun.name = "Gun"
	gun.polygon = Shapes.rect(Vector2(22.0, 6.0))
	gun.position = Vector2(11.0, 0.0)
	gun.color = Color(0.35, 0.38, 0.44)
	gun.z_index = Layers.Z_ACTOR + 1
	gun_pivot.add_child(gun)

	var barrel := Polygon2D.new()
	barrel.name = "Barrel"
	barrel.polygon = Shapes.rect(Vector2(9.0, 3.0))
	barrel.position = Vector2(27.0, 0.0)
	barrel.color = Color(0.22, 0.24, 0.28)
	barrel.z_index = Layers.Z_ACTOR + 1
	gun_pivot.add_child(barrel)

#endregion


#region debug / weapons plumbing

func _on_weapon_shot(_muzzle: Vector2) -> void:
	pass


func debug_give_all_weapons() -> void:
	if weapons != null and weapons.has_method("grant_all"):
		weapons.grant_all()

#endregion
