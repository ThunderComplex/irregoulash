class_name Enemy
extends CharacterBody2D
## A line-of-sight-driven enemy with a layered alertness state machine.
##
##   PATROL     walk the route (or wander near the post), or stand and scan
##   SUSPICIOUS heard/glanced something: stop, turn towards it, look
##   ALERT      knows where you are: close in, shoot in bursts, shout for friends
##   SEARCH     lost you: sweep the area around where you were last seen
##   RETURN     give up and walk back to the post
##
## Awareness is a meter (0..1), not a boolean, and it fills faster when you are
## closer, when the enemy sees you, and -- importantly -- when *you* shine your
## own vision cone on them. That last one is the whole point of the mechanic:
## looking at something makes it notice you.

signal died(enemy: Enemy)

enum State { PATROL, SUSPICIOUS, ALERT, SEARCH, RETURN }

const STATE_NAMES: Array[String] = ["PATROL", "SUSPICIOUS", "ALERT", "SEARCH", "RETURN"]
## Perception raycasts run on this slower clock.
const PERCEPTION_DT: float = 0.15

@export_enum("guard", "scout", "heavy") var archetype_id: String = "guard"
## Node whose Marker2D children are this enemy's patrol route. Routes live in the
## level (not under the enemy) so they stay put and can be shared.
@export var patrol_route: NodePath = NodePath("")
## Seconds to stand still at each patrol point.
@export var patrol_dwell: float = 1.6
## Used when the enemy has no PatrolPoints children.
@export var wander_radius: float = 130.0
@export var wander_pause: Vector2 = Vector2(1.5, 3.5)
## How far from the last known position the search wanders.
@export var search_radius: float = 260.0
## If false, the enemy stands its ground instead of returning to its post.
@export var returns_to_post: bool = true

var archetype: EnemyArchetype
var health: Health
var visual: Node2D

var state: int = State.PATROL
var awareness: float = 0.0
var post: Vector2 = Vector2.ZERO
var last_known: Vector2 = Vector2.ZERO

var _facing: float = 0.0
var _look_at_angle: float = 0.0
var _time: float = 0.0
var _last_seen: float = -999.0
var _perception_cd: float = 0.0
var _dead: bool = false

var _patrol_points: PackedVector2Array = []
var _patrol_index: int = 0
var _dwell: float = 0.0
var _scan: float = 0.0
var _scan_center: float = 0.0

var _wander_target: Vector2 = Vector2.ZERO
var _wander_cd: float = 0.0

var _suspicion_pos: Vector2 = Vector2.ZERO
var _suspicion_timer: float = 0.0

var _search_target: Vector2 = Vector2.ZERO
var _search_timer: float = 0.0

var _react_timer: float = 0.0
var _fire_cd: float = 0.0
var _burst_left: int = 0
var _pause_cd: float = 0.0

var _footstep_accum: float = 0.0


func _ready() -> void:
	add_to_group("enemy")
	archetype = EnemyLibrary.by_id(archetype_id)
	health = get_node_or_null("Health") as Health
	visual = get_node_or_null("Visual") as Node2D

	if health != null:
		health.configure(archetype.max_health)
		health.died.connect(_on_died)
		health.damaged.connect(_on_damaged)

	_build_collision()
	_build_art()
	_collect_patrol_points()

	post = global_position
	_wander_target = post
	last_known = post
	# The rotation authored on the instance is the enemy's starting facing. Fold it
	# into `_facing` and zero the node: `Visual.rotation` is driven from `_facing`
	# (which is in global space), so leaving the authored rotation on the root would
	# apply it twice and the drawn nose would no longer point where the enemy looks.
	_facing = wrapf(rotation, -PI, PI)
	_look_at_angle = _facing
	rotation = 0.0
	_update_facing(0.0)
	GameDirector.noise_made.connect(_on_noise)


func is_dead() -> bool:
	return _dead


## The direction this enemy is actually looking (its vision shape points this way),
## in radians, in global space. Public because the debug tools and the probe use it.
func facing_angle() -> float:
	return _facing


#region main loop

func _physics_process(delta: float) -> void:
	if _dead:
		velocity = Vector2.ZERO
		return
	_time += delta
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_pause_cd = maxf(0.0, _pause_cd - delta)
	_react_timer = maxf(0.0, _react_timer - delta)
	_perception_cd -= delta
	if _perception_cd <= 0.0:
		_perception_cd = PERCEPTION_DT
		_perception_tick(PERCEPTION_DT)

	match state:
		State.PATROL:
			_tick_patrol(delta)
		State.SUSPICIOUS:
			_tick_suspicious(delta)
		State.ALERT:
			_tick_alert(delta)
		State.SEARCH:
			_tick_search(delta)
		State.RETURN:
			_tick_return(delta)

	move_and_slide()
	_update_facing(delta)
	_update_footsteps(delta)


## Perception runs on its own slower clock: it is a real raycast, no need to do
## it 60 times a second.
func _perception_tick(dt: float) -> void:
	var player := GameDirector.valid_player()
	if player == null or player.is_dead():
		awareness = maxf(0.0, awareness - Tuning.awareness_decay * dt * 2.0)
		if state == State.ALERT:
			_enter_search()
		return

	var to_player: Vector2 = player.global_position - global_position
	var distance: float = to_player.length()
	if _can_see(player.global_position):
		_last_seen = _time
		last_known = player.global_position
		var closeness: float = 1.0 - clampf(
			(distance - 60.0) / maxf(1.0, archetype.sight_range - 60.0), 0.0, 1.0)
		var gain: float = lerpf(Tuning.awareness_gain_far, Tuning.awareness_gain_close, closeness)
		if GameDirector.player_sees(global_position):
			# Standing in the player's own light makes you much easier to notice.
			gain *= Tuning.awareness_lit_multiplier
		awareness = minf(1.0, awareness + gain * dt * archetype.detect_multiplier)
	else:
		awareness = maxf(0.0, awareness - Tuning.awareness_decay * dt)

	if awareness >= Tuning.awareness_alert and state != State.ALERT:
		_enter_alert(player.global_position)
	elif awareness >= Tuning.awareness_suspicious and (state == State.PATROL or state == State.RETURN):
		_enter_suspicious(player.global_position)


func _can_see(point: Vector2) -> bool:
	var to_point: Vector2 = point - global_position
	var distance: float = to_point.length()
	if distance > archetype.sight_range:
		return false
	if distance > 30.0 and state != State.ALERT:
		var half_fov: float = deg_to_rad(archetype.sight_fov * 0.5)
		if absf(wrapf(_facing - to_point.angle(), -PI, PI)) > half_fov:
			return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(global_position, point, Layers.SOLID)
	query.hit_from_inside = false
	var hit: Dictionary = space.intersect_ray(query)
	return hit.is_empty()

#endregion


#region states

func _tick_patrol(delta: float) -> void:
	if _patrol_points.is_empty():
		_tick_wander(delta)
		return

	if _dwell > 0.0:
		_dwell -= delta
		_scan_idle(delta)
		_brake(delta)
		return

	var target: Vector2 = _patrol_points[_patrol_index]
	if global_position.distance_to(target) < 18.0:
		_dwell = patrol_dwell
		_patrol_index = (_patrol_index + 1) % _patrol_points.size()
		return
	_move_toward(target, archetype.speed_patrol, delta)


func _tick_wander(delta: float) -> void:
	_wander_cd -= delta
	if _wander_cd <= 0.0 or global_position.distance_to(_wander_target) < 16.0:
		if wander_radius <= 1.0:
			_scan_idle(delta)
			_brake(delta)
			return
		_wander_target = post + Vector2.from_angle(randf() * TAU) * randf_range(20.0, wander_radius)
		_wander_cd = randf_range(wander_pause.x, wander_pause.y)
	_move_toward(_wander_target, archetype.speed_patrol * 0.85, delta)


func _tick_suspicious(delta: float) -> void:
	_suspicion_timer -= delta
	_look_at_angle = (_suspicion_pos - global_position).angle()
	_brake(delta)
	if _suspicion_timer <= 0.0:
		if awareness >= Tuning.awareness_alert:
			_enter_alert(_suspicion_pos)
		else:
			_enter_return()


func _tick_alert(delta: float) -> void:
	var player := GameDirector.valid_player()
	if player == null or player.is_dead():
		_enter_search()
		return

	if _can_see(player.global_position):
		last_known = player.global_position
		_last_seen = _time

	if _time - _last_seen > Tuning.alert_lost_sight_grace:
		_enter_search()
		return

	var distance: float = global_position.distance_to(last_known)
	var desired_speed: float = archetype.speed_alert
	if distance > archetype.preferred_range:
		_move_toward(last_known, desired_speed, delta)
	else:
		# Hold the angle at a comfortable shooting distance instead of hugging.
		_brake(delta)
	_look_at_angle = (last_known - global_position).angle()

	if _can_shoot(player.global_position):
		_shoot_at(player.global_position)


func _tick_search(delta: float) -> void:
	_search_timer -= delta
	if _search_timer <= 0.0:
		_enter_return()
		return
	if global_position.distance_to(_search_target) < 20.0:
		_pick_search_target()
		_dwell = randf_range(0.6, 1.6)
	if _dwell > 0.0:
		_dwell -= delta
		_scan_idle(delta)
		_brake(delta)
		return
	_look_at_angle = (_search_target - global_position).angle()
	_move_toward(_search_target, archetype.speed_patrol * 1.25, delta)


func _tick_return(delta: float) -> void:
	if not returns_to_post:
		_scan_idle(delta)
		_brake(delta)
		if global_position.distance_to(post) < 24.0:
			state = State.PATROL
		return
	if global_position.distance_to(post) < 22.0:
		state = State.PATROL
		awareness = 0.0
		_patrol_index = 0
		return
	_look_at_angle = (post - global_position).angle()
	_move_toward(post, archetype.speed_patrol, delta)


func _enter_suspicious(where: Vector2) -> void:
	state = State.SUSPICIOUS
	_suspicion_pos = where
	_suspicion_timer = Tuning.suspicious_look_time
	last_known = where
	AudioDirector.play_at(&"suspicious", global_position, -11.0)


func _enter_alert(where: Vector2) -> void:
	var was_alert: bool = state == State.ALERT
	state = State.ALERT
	last_known = where
	_last_seen = _time
	awareness = 1.0
	_react_timer = archetype.reaction_time
	_burst_left = archetype.burst
	if was_alert:
		return
	AudioDirector.play_at(&"alert", global_position, -7.0)
	FxDirector.flash_light(global_position, Color(1.0, 0.55, 0.35), 0.9, 130.0, 0.35)
	GameDirector.notify_alert()
	if archetype.shouts:
		_shout()


func _enter_search() -> void:
	if _dead:
		return
	state = State.SEARCH
	_search_timer = Tuning.search_duration
	_dwell = 0.0
	_pick_search_target()
	AudioDirector.play_at(&"lose_player", global_position, -10.0)


func _enter_return() -> void:
	state = State.RETURN
	_dwell = 0.0


## Call friends within earshot and point them at the player.
func _shout() -> void:
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		var other := node as Enemy
		if other == null or other == self or other.is_dead():
			continue
		if other.global_position.distance_to(global_position) > Tuning.shout_radius:
			continue
		other.alert_from(global_position)


func alert_from(where: Vector2) -> void:
	if _dead:
		return
	if state == State.ALERT:
		last_known = where
		return
	awareness = 1.0
	_enter_alert(where)


## A loud noise: gunfire, a dash, footsteps nearby.
func _on_noise(where: Vector2, radius: float, source: Node) -> void:
	if _dead or source == self:
		return
	var distance: float = global_position.distance_to(where)
	if distance > radius:
		return

	var heard: float = 1.0 - clampf(distance / maxf(1.0, radius), 0.0, 1.0)
	if source is Player:
		if _can_see(where):
			_enter_alert(where)
		elif state != State.ALERT and heard > 0.15:
			awareness = minf(1.0, awareness + 0.45 * heard)
			if state == State.PATROL or state == State.RETURN:
				_enter_suspicious(where)
		return

	# Noise from something that is not the player (gunfire of allies, ricochets).
	if state != State.ALERT and heard > 0.4:
		awareness = minf(1.0, awareness + 0.2)
		if state == State.PATROL or state == State.RETURN:
			_enter_suspicious(where)

#endregion


#region combat

func _can_shoot(point: Vector2) -> bool:
	if _react_timer > 0.0 or _fire_cd > 0.0 or _pause_cd > 0.0:
		return false
	if global_position.distance_to(point) > archetype.fire_range:
		return false
	return _can_see(point)


func _shoot_at(point: Vector2) -> void:
	var origin: Vector2 = global_position + Vector2.from_angle(_facing) * (archetype.radius + 6.0)
	var direction: Vector2 = (point - origin).normalized()
	var distance: float = origin.distance_to(point)
	var spread: float = archetype.spread_deg + Tuning.enemy_extra_spread * clampf(
		distance / maxf(1.0, archetype.fire_range), 0.0, 1.0)

	var parent: Node = GameDirector.spawn_parent()
	for i: int in archetype.pellets:
		var angle: float = direction.angle() + deg_to_rad(randf_range(-spread, spread) * 0.5)
		var bullet := Projectile.new()
		bullet.damage = archetype.damage
		bullet.hits_mask = Layers.ENEMY_SHOT_HITS
		bullet.shooter = self
		bullet.max_distance = archetype.fire_range * 1.25
		bullet.color = Color(1.0, 0.55, 0.32)
		bullet.knockback = 45.0
		bullet.show_orb = true
		parent.add_child(bullet)
		bullet.launch(origin, Vector2.from_angle(angle), Tuning.enemy_bullet_speed * randf_range(0.95, 1.05))

	FxDirector.muzzle_flash(origin, direction, Color(1.0, 0.6, 0.35), 120.0)
	AudioDirector.play_at(&"shot_enemy", origin, -7.0)
	GameDirector.make_noise(origin, 620.0, self)

	_fire_cd = archetype.fire_interval
	_burst_left -= 1
	if _burst_left <= 0:
		_burst_left = archetype.burst
		_pause_cd = archetype.burst_pause


## Shared "take_hit" interface with the player, so bullets do not care what they
## hit. `source` is untyped on purpose; see `Health.take_damage`.
func take_hit(amount: float, source = null, hit_position: Vector2 = Vector2.ZERO,
		direction: Vector2 = Vector2.ZERO, knockback: float = 0.0) -> void:
	if _dead or health == null:
		return
	if not health.take_damage(amount, source, hit_position, direction):
		return
	velocity += direction * knockback * 0.6
	AudioDirector.play_at(&"enemy_hurt", global_position, -7.0)
	# Being shot at is itself information, even without seeing the shooter.
	awareness = minf(1.0, awareness + 0.55)
	if state != State.ALERT:
		var guess: Vector2 = hit_position - direction * 140.0
		if awareness >= Tuning.awareness_alert:
			_enter_alert(guess)
		elif state == State.PATROL or state == State.RETURN:
			_enter_suspicious(guess)

#endregion


#region movement

func _move_toward(target: Vector2, speed: float, delta: float) -> void:
	var desired: Vector2 = target - global_position
	if desired.length_squared() < 1.0:
		_brake(delta)
		return
	var direction: Vector2 = _avoid(desired.normalized())
	velocity = velocity.move_toward(direction * speed, 900.0 * delta)


func _brake(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 1100.0 * delta)


## Crude but effective obstacle avoidance: probe ahead, and if something is in the
## way, rotate the desired direction until it is clear. Enough for room-and-
## corridor levels, and far cheaper than a navigation mesh to author.
func _avoid(desired: Vector2) -> Vector2:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return desired
	var probe: float = archetype.radius + 24.0
	for offset: float in [0.0, 0.45, -0.45, 0.95, -0.95, 1.5, -1.5]:
		var direction: Vector2 = desired.rotated(offset)
		var query := PhysicsRayQueryParameters2D.create(
			global_position, global_position + direction * probe, Layers.SOLID)
		query.hit_from_inside = false
		if space.intersect_ray(query).is_empty():
			return direction
	return -desired


func _update_facing(delta: float) -> void:
	if velocity.length() > 12.0 and state != State.SUSPICIOUS and state != State.ALERT:
		_look_at_angle = velocity.angle()
		_scan = 0.0
	# Turn rates are per state so that the nose swinging onto you reads as intent.
	var turn_rate: float = 9.0
	if state == State.ALERT:
		turn_rate = 17.0
	elif state == State.SUSPICIOUS:
		turn_rate = 13.0
	_facing = wrapf(lerp_angle(_facing, _look_at_angle, clampf(delta * turn_rate, 0.0, 1.0)),
		-PI, PI)
	if visual != null:
		visual.rotation = _facing


## Idle "looking around" so a standing enemy still sweeps its cone of vision.
func _scan_idle(delta: float) -> void:
	if _scan <= 0.0:
		_scan_center = _facing
	_scan += delta
	_look_at_angle = _scan_center + sin(_scan * 0.9) * 0.6


func _pick_search_target() -> void:
	_search_target = last_known + Vector2.from_angle(randf() * TAU) * randf_range(30.0, search_radius)


func _update_footsteps(delta: float) -> void:
	var speed: float = velocity.length()
	if speed < 20.0:
		return
	_footstep_accum += delta * (speed / 120.0)
	if _footstep_accum < 0.5:
		return
	_footstep_accum = 0.0
	AudioDirector.play_at(&"footstep", global_position, -15.0, randf_range(0.85, 1.05))
	GameDirector.make_noise(global_position, archetype.footstep_audible_range, self)

#endregion


#region damage / death

func _on_damaged(_amount: float, _source: Node, _hit_position: Vector2, _direction: Vector2) -> void:
	FxDirector.shake(0.12)


func _on_died(source: Node) -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("enemy")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO

	AudioDirector.play_at(&"enemy_die", global_position, -5.0)
	FxDirector.blood(global_position, Vector2.from_angle(_facing))
	FxDirector.shake(0.18)
	_spawn_corpse()
	_drop_loot()
	GameDirector.notify_kill()
	died.emit(self)
	queue_free()


func _spawn_corpse() -> void:
	var parent: Node = GameDirector.spawn_parent()
	if parent == null:
		return
	var corpse := Node2D.new()
	parent.add_child(corpse)
	corpse.global_position = global_position
	corpse.z_index = Layers.Z_PICKUP - 1

	var pool := Polygon2D.new()
	pool.polygon = Shapes.circle(archetype.radius * 1.9, 12)
	pool.color = Color(0.30, 0.04, 0.06, 0.75)
	pool.z_index = Layers.Z_DECAL
	corpse.add_child(pool)

	var body := Polygon2D.new()
	body.polygon = Shapes.circle(archetype.radius, 12)
	body.color = archetype.body_color.darkened(0.55)
	body.position = Vector2(6.0, 4.0)
	body.z_index = Layers.Z_PICKUP - 1
	corpse.add_child(body)


func _drop_loot() -> void:
	if archetype.drop_weapon.is_empty():
		return
	var parent: Node = GameDirector.spawn_parent()
	if parent == null:
		return
	var pickup := Pickup.new()
	pickup.kind = "weapon"
	pickup.weapon_id = archetype.drop_weapon
	parent.add_child(pickup)
	pickup.global_position = global_position + Vector2(0.0, 6.0)

#endregion


#region authoring / art

func _collect_patrol_points() -> void:
	if patrol_route == NodePath():
		return
	var container: Node = get_node_or_null(patrol_route)
	if container == null:
		push_warning("Enemy '%s': patrol_route not found." % name)
		return
	for child: Node in container.get_children():
		var marker := child as Marker2D
		if marker != null:
			_patrol_points.append(marker.global_position)


func _build_collision() -> void:
	var collision: CollisionShape2D = get_node_or_null("Collision") as CollisionShape2D
	if collision == null:
		return
	var shape := CircleShape2D.new()
	shape.radius = archetype.radius
	collision.shape = shape


func _build_art() -> void:
	if visual == null:
		return
	var radius: float = archetype.radius

	var body := Polygon2D.new()
	body.polygon = Shapes.circle(radius)
	body.color = archetype.body_color
	body.z_index = Layers.Z_ACTOR
	visual.add_child(body)

	var outline := Line2D.new()
	outline.points = Shapes.closed_outline(Shapes.circle(radius))
	outline.width = 2.0
	outline.default_color = archetype.body_color.darkened(0.55)
	outline.z_index = Layers.Z_ACTOR
	visual.add_child(outline)

	# A wedge that overlaps the body and sticks out past it, so facing is readable
	# at a glance: this is the only cue the player has for an enemy's vision cone.
	var nose := Polygon2D.new()
	nose.polygon = Shapes.triangle(radius * 1.35, radius * 0.75)
	nose.position = Vector2(radius * 0.35, 0.0)
	nose.color = archetype.body_color.lightened(0.5)
	nose.z_index = Layers.Z_ACTOR
	visual.add_child(nose)


## Used by the debug overlay.
func debug_state() -> String:
	var hp: int = int(health.current) if health != null else 0
	return "%-6s %-10s aw=%.2f hp=%d%s" % [
		archetype.id, STATE_NAMES[state], awareness, hp,
		" (dead)" if _dead else "",
	]

#endregion
