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
## When non-zero the mouse is ignored and this direction is used instead. Only
## used by the automated dev probe so scripted tests are deterministic.
var debug_aim: Vector2 = Vector2.ZERO

var _dead: bool = false
var _dash_time: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_direction: Vector2 = Vector2.RIGHT
var _footstep_accum: float = 0.0


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

	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = Tuning.camera_smoothing
	FxDirector.register_camera(camera)

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
		return

	if input.length() > 0.1 and _dash_cooldown <= 0.0 and Input.is_action_just_pressed("dash"):
		_start_dash(input)
		return

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
	velocity = _dash_direction * Tuning.player_dash_speed
	AudioDirector.play(&"dash", -3.0)
	GameDirector.make_noise(global_position, Tuning.noise_dash, self)
	FxDirector.spark_burst(global_position - _dash_direction * 10.0, -_dash_direction, 6,
		Color(0.72, 0.82, 1.0), 130.0, 0.22)


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

	# Little nose so facing is obvious.
	var nose := Polygon2D.new()
	nose.name = "Nose"
	nose.polygon = Shapes.triangle(9.0, 12.0)
	nose.color = Color(0.55, 0.72, 1.0)
	nose.position = Vector2(radius - 1.0, 0.0)
	nose.z_index = Layers.Z_ACTOR
	visual.add_child(nose)

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
