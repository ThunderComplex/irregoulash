extends Node
## All "juice" in one place: screen shake, muzzle flashes, sparks, blood, tracers,
## impact flashes.
##
## Every effect is built from plain nodes and animated by hand in `_process`.
## No scenes, no particle resource properties to get wrong, and combat feedback
## still works in the dark because the effects are drawn unshaded -- muzzle
## flashes and blood being visible in the black is a deliberate feature: it is
## how you track a fight you cannot fully see.
##
## Richer, longer-lived effects (fire, and whatever comes after it) are particle
## emitters instead, described by `ParticlePreset`s from `ParticleLibrary`: see
## `emitter()`, `burst()` and `stop_emitter()` below.

var _camera: Camera2D = null
var _world: Node2D = null
var _shake: float = 0.0
var _effects: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

const Z_FX: int = 60


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()


## The level's camera, so shake can be applied to it.
func register_camera(camera: Camera2D) -> void:
	_camera = camera
	if _camera != null:
		_camera.offset = Vector2.ZERO


## Container node that spawned effects live in, so they die with the level.
func set_world(world: Node2D) -> void:
	_world = world


## `amount` is 0..1 of trauma; it decays automatically.
func shake(amount: float) -> void:
	_shake = minf(1.0, _shake + amount)


func _process(delta: float) -> void:
	_update_shake(delta)
	_update_effects(delta)


func _update_shake(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - Tuning.shake_decay * delta * _shake - Tuning.shake_decay * 0.35 * delta)
	if _camera == null or not is_instance_valid(_camera):
		# The level that owned this camera is gone.
		_camera = null
		return
	if _shake <= 0.0:
		_camera.offset = _camera.offset.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))
		return
	var strength: float = Tuning.shake_max_offset * _shake * _shake
	_camera.offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * strength


func _container() -> Node2D:
	if _world != null and is_instance_valid(_world):
		return _world
	return get_tree().current_scene as Node2D


#region effect spawning

## Bright cone of light + sprite at the muzzle. Also briefly lights up the
## shooter, which is exactly how you spot an enemy firing from the dark.
func muzzle_flash(position: Vector2, aim: Vector2, color: Color, radius: float = 150.0) -> void:
	var parent: Node2D = _container()
	if parent == null:
		return

	var light := PointLight2D.new()
	light.texture = VisionTextures.radial()
	light.texture_scale = radius * 2.0 / float(VisionTextures.SIZE)
	light.color = color
	light.energy = 1.15
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.z_index = Z_FX
	parent.add_child(light)
	light.global_position = position
	_effects.append({
		"node": light, "vel": Vector2.ZERO, "life": 0.09, "max_life": 0.09,
		"drag": 1.0, "mode": "light", "from_energy": 1.15, "from_alpha": 1.0,
	})

	var flash := Polygon2D.new()
	flash.polygon = PackedVector2Array([
		Vector2(0.0, -7.0), Vector2(34.0, 0.0), Vector2(0.0, 7.0),
	])
	flash.color = color
	flash.material = _additive_material()
	flash.rotation = aim.angle()
	flash.z_index = Z_FX + 1
	parent.add_child(flash)
	flash.global_position = position
	_effects.append({
		"node": flash, "vel": Vector2.ZERO, "life": 0.06, "max_life": 0.06,
		"drag": 1.0, "mode": "fade", "from_energy": 1.0, "from_alpha": 1.0,
	})


## Sparks flying away from a surface, plus a brief unshaded flash so hits are
## readable even in pitch darkness.
func impact(position: Vector2, normal: Vector2, color: Color, count: int = 7) -> void:
	spark_burst(position, normal, count, color, 210.0, 0.28)
	flash_light(position, color, 0.7, 68.0, 0.07)


func spark_burst(position: Vector2, direction: Vector2, count: int, color: Color,
		speed: float = 220.0, life: float = 0.3) -> void:
	var parent: Node2D = _container()
	if parent == null:
		return
	var base: float = direction.angle()
	for i: int in count:
		var spark := Polygon2D.new()
		var s: float = _rng.randf_range(1.6, 3.4)
		spark.polygon = PackedVector2Array([
			Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s),
		])
		spark.color = color
		spark.material = _additive_material()
		spark.z_index = Z_FX
		parent.add_child(spark)
		spark.global_position = position
		var angle: float = base + _rng.randf_range(-0.9, 0.9)
		var l: float = life * _rng.randf_range(0.6, 1.3)
		_effects.append({
			"node": spark,
			"vel": Vector2.from_angle(angle) * speed * _rng.randf_range(0.4, 1.4),
			"life": l, "max_life": l, "drag": 0.02, "mode": "shrink",
			"from_energy": 1.0, "from_alpha": 1.0,
		})


## Blood: a few heavy droplets that leave marks behind.
func blood(position: Vector2, direction: Vector2, parent_hint: Node2D = null) -> void:
	var parent: Node2D = parent_hint if parent_hint != null else _container()
	if parent == null:
		return
	var base: float = direction.angle()
	for i: int in 5:
		var drop := Polygon2D.new()
		var s: float = _rng.randf_range(1.8, 3.6)
		drop.polygon = PackedVector2Array([
			Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s),
		])
		drop.color = Color(0.62, 0.06, 0.09)
		drop.z_index = Z_FX - 1
		parent.add_child(drop)
		drop.global_position = position
		var l: float = _rng.randf_range(0.25, 0.5)
		_effects.append({
			"node": drop,
			"vel": Vector2.from_angle(base + _rng.randf_range(-0.7, 0.7)) * _rng.randf_range(60.0, 230.0),
			"life": l, "max_life": l, "drag": 0.05, "mode": "fade",
			"from_energy": 1.0, "from_alpha": 1.0,
			"stain": true,
		})


## A bullet trail.
func tracer(from: Vector2, to: Vector2, color: Color, width: float = 1.6) -> void:
	var parent: Node2D = _container()
	if parent == null:
		return
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = width
	line.default_color = color
	line.material = _additive_material()
	line.z_index = Z_FX + 1
	parent.add_child(line)
	_effects.append({
		"node": line, "vel": Vector2.ZERO, "life": 0.05, "max_life": 0.05,
		"drag": 1.0, "mode": "fade", "from_energy": 1.0, "from_alpha": 1.0,
	})


## Free-standing coloured light (explosions, pickups, death flashes).
func flash_light(position: Vector2, color: Color, energy: float, radius: float,
		duration: float, offset_from: Node2D = null) -> void:
	var parent: Node2D = _container()
	if parent == null:
		return
	var light := PointLight2D.new()
	light.texture = VisionTextures.radial()
	light.texture_scale = radius * 2.0 / float(VisionTextures.SIZE)
	light.color = color
	light.energy = energy
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.z_index = Z_FX
	if offset_from != null:
		offset_from.add_child(light)
		light.position = position
	else:
		parent.add_child(light)
		light.global_position = position
	_effects.append({
		"node": light, "vel": Vector2.ZERO, "life": duration, "max_life": duration,
		"drag": 1.0, "mode": "light", "from_energy": energy, "from_alpha": 1.0,
	})


## Pulsing marker ring, used to draw the eye to pickups and exits.
func pulse_ring(parent: Node2D, color: Color, radius: float) -> Node2D:
	var ring := Polygon2D.new()
	var points := PackedVector2Array()
	var segments: int = 28
	for i: int in segments:
		var a: float = TAU * float(i) / float(segments)
		points.append(Vector2.from_angle(a) * radius)
	ring.polygon = points
	ring.color = color
	ring.material = _additive_material()
	ring.z_index = Z_FX - 2
	parent.add_child(ring)
	return ring

#endregion


#region particles

## A continuous emitter attached to `parent`, so it moves and turns with it and is freed with it.
## Particles simulate in world space, so moving the parent leaves a trail rather than dragging the
## whole fire along. Stop it with `stop_emitter()` to let it die down instead of vanishing.
func emitter(preset: ParticlePreset, parent: Node2D, offset: Vector2 = Vector2.ZERO) -> CPUParticles2D:
	if preset == null or parent == null:
		return null
	var node := CPUParticles2D.new()
	node.name = "Particles"
	preset.apply_to(node)
	node.position = offset
	parent.add_child(node)
	if preset.direction_in_world:
		node.direction = preset.direction.rotated(-node.global_rotation)
	node.emitting = true
	return node


## A one-shot burst in the world, freed when its last particle dies. `direction` turns the preset's
## own emission direction (and its box, if it has one), so a burst can spray away from a wall.
func burst(preset: ParticlePreset, position: Vector2, direction: Vector2 = Vector2.UP) -> CPUParticles2D:
	var parent: Node2D = _container()
	if preset == null or parent == null:
		return null
	var node := CPUParticles2D.new()
	node.name = "Burst"
	preset.apply_to(node)
	node.one_shot = true
	parent.add_child(node)
	node.global_position = position
	node.global_rotation = direction.angle() - preset.direction.angle()
	node.emitting = true
	_free_after(node, preset.max_lifetime() + 0.1)
	return node


## Stops new particles and frees the emitter once the ones in flight have burnt out.
func stop_emitter(node: CPUParticles2D) -> void:
	if node == null or not is_instance_valid(node) or not node.emitting:
		return
	node.emitting = false
	_free_after(node, node.lifetime + 0.1)


func _free_after(node: Node, seconds: float) -> void:
	if not is_inside_tree():
		return
	# By id, not by capturing the node: an emitter usually dies with its parent before the timer fires,
	# and a lambda that captured a freed object errors when it runs.
	var id: int = node.get_instance_id()
	var timer: SceneTreeTimer = get_tree().create_timer(seconds, false)
	timer.timeout.connect(func() -> void:
		var still: Node = instance_from_id(id) as Node
		if still != null:
			still.queue_free()
	)

#endregion


func _update_effects(delta: float) -> void:
	for i: int in range(_effects.size() - 1, -1, -1):
		var e: Dictionary = _effects[i]
		var node: Node2D = e["node"]
		if not is_instance_valid(node):
			_effects.remove_at(i)
			continue

		e["life"] = float(e["life"]) - delta
		var life: float = e["life"]
		var max_life: float = maxf(0.001, float(e["max_life"]))
		var t: float = clampf(life / max_life, 0.0, 1.0)

		if life <= 0.0:
			if bool(e.get("stain", false)):
				# Blood stays on the floor for a while as a fading stain.
				var stain := Polygon2D.new()
				stain.polygon = (node as Polygon2D).polygon
				stain.color = Color(0.32, 0.03, 0.05, 0.55)
				stain.global_position = node.global_position
				stain.z_index = -4
				var parent: Node2D = _container()
				if parent != null:
					parent.add_child(stain)
					stain.set_meta("decal", true)
					_decay_decal(stain)
			node.queue_free()
			_effects.remove_at(i)
			continue

		var vel: Vector2 = e["vel"]
		node.position += vel * delta
		var drag: float = float(e["drag"])
		if drag < 1.0:
			e["vel"] = vel * pow(drag, delta * 60.0)

		match String(e["mode"]):
			"light":
				(node as PointLight2D).energy = float(e["from_energy"]) * t
			"fade":
				node.modulate.a = t
			"shrink":
				node.modulate.a = t
				node.scale = Vector2.ONE * lerpf(0.35, 1.0, t)
			_:
				node.modulate.a = t


## Bullet holes / blood stains fade out so a long fight does not turn into soup.
func _decay_decal(stain: Polygon2D) -> void:
	if not is_inside_tree():
		return
	var timer: SceneTreeTimer = get_tree().create_timer(Tuning.decal_lifetime, false)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(stain):
			return
		var tween: Tween = create_tween()
		tween.tween_property(stain, "modulate:a", 0.0, 3.0)
		tween.tween_callback(stain.queue_free)
	)


func _additive_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


## Unshaded so it is visible in the dark (used for hit flashes on entities).
func unshaded_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m
