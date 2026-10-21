extends Node
## Dev-only harness. Runs a scripted scenario, takes screenshots and prints
## numeric diagnostics, then quits. Inert during a normal run.
##
## Usage:
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 \
##       res://dev/vision_test.tscn -- --probe=vision
##
## Screenshots land in res://dev/shots/. The printed RGB values are the honest
## measurement: they tell you whether an area is *actually* pitch black rather
## than merely dark.

const SHOT_DIR: String = "res://dev/shots"

const SCENARIOS: Dictionary = {
	"vision": [
		{
			"teleport": Vector2(-320.0, 0.0),
			"aim": Vector2.RIGHT,
			"wait": 0.8,
			"shot": "vision_01_aim_right_through_doorway",
			"points": {
				"floor_at_feet": Vector2(-300.0, 0.0),
				"floor_through_door": Vector2(-90.0, 0.0),
				"divider_wall_lit": Vector2(-13.0, -30.0),
				"wall_blocked_area": Vector2(0.0, -300.0),
				"room_beyond_wall": Vector2(300.0, -300.0),
				"pillar": Vector2(340.0, 300.0),
			},
		},
		{
			"teleport": Vector2(-320.0, 0.0),
			"aim": Vector2(0.35, -0.94),
			"wait": 0.5,
			"shot": "vision_02_aim_wall_blocks",
			"points": {
				"divider_wall_lit": Vector2(-13.0, -30.0),
				"behind_divider": Vector2(120.0, -260.0),
			},
		},
		{
			"teleport": Vector2(400.0, 0.0),
			"aim": Vector2(-1.0, 0.15),
			"wait": 0.5,
			"shot": "vision_03_lamp_visible_from_dark",
			"points": {
				"lamp_area": Vector2(-330.0, -330.0),
				"dark_corner": Vector2(600.0, -450.0),
			},
		},
	],
	"memory": [
		{
			"teleport": Vector2(-320.0, 0.0),
			"aim": Vector2.RIGHT,
			"wait": 1.0,
			"walls": true,
		},
		{
			"teleport": Vector2(-320.0, -380.0),
			"aim": Vector2.RIGHT,
			"wait": 1.0,
			"walls": true,
		},
		{
			"teleport": Vector2(300.0, -380.0),
			"aim": Vector2.RIGHT,
			"wait": 1.0,
			"walls": true,
		},
		{
			"teleport": Vector2(420.0, 300.0),
			"aim": Vector2(0.0, -1.0),
			"wait": 1.0,
			"walls": true,
		},
		{
			# Walk back and face away from everything: the explored map should
			# still be readable, and nothing else should be.
			"teleport": Vector2(-320.0, 0.0),
			"aim": Vector2(-1.0, 0.0),
			"wait": 0.6,
			"shot": "memory_01_explored_map",
			"points": {
				"explored_divider": Vector2(0.0, -310.0),
				"unexplored_pillar": Vector2(340.0, 300.0),
				"unexplored_floor": Vector2(-500.0, 200.0),
			},
		},
	],
	## Whole-level view: brighten the fog and pull the camera back, so the layout
	## of a generated level can be checked without playing it.
	"map": [
		{
			"center": true,
			"reveal": true,
			"zoom": 0.36,
			"aim": Vector2(0.0, -1.0),
			"wait": 1.6,
			"shot": "map",
			"walls": true,
			"report": true,
		},
	],
	## Walk into the level, shoot at things, and report what happened.
	"combat": [
		{
			"teleport": Vector2(224.0, 620.0),
			"aim": Vector2.RIGHT,
			"wait": 0.5,
			"report": true,
			"shot": "combat_00_before",
			"keys_press": ["move_right"],
			"hold": 1.2,
		},
		{
			"keys_release": ["move_right"],
			"wait": 0.4,
			"report": true,
		},
		{
			"teleport": Vector2(224.0, 900.0),
			"aim_at_enemy": true,
			"wait": 0.6,
			"report": true,
			"shot": "combat_01_aimed_at_enemy",
		},
		{
			"fire_for": 3.0,
			"aim_at_enemy": true,
			"report": true,
			"shot": "combat_02_firing",
		},
		{
			"wait": 1.2,
			"report": true,
			"shot": "combat_03_aftermath",
		},
	],
	## Stand in the open in front of several enemies and do not fight back.
	"death": [
		{
			"center": true,
			"reveal": true,
			"zoom": 0.7,
			"wait": 16.0,
			"report": true,
			"shot": "death_overlay",
		},
	],
	## Level chaining: walk into the exit, land in the next level with the gear
	## you were carrying, then win.
	"flow": [
		{
			"give_all": true,
			"wait": 0.4,
			"report": true,
		},
		{
			"teleport_to_exit": true,
			"wait": 2.6,
			"report": true,
			"shot": "flow_01_next_level",
		},
		{
			"teleport_to_exit": true,
			"wait": 2.2,
			"report": true,
			"shot": "flow_02_win",
		},
	],
	## The project's main scene, which the probe is normally too late for.
	"title": [
		{
			"wait": 1.0,
			"shot": "title_screen",
		},
	],
	## What pressing Enter on the title screen does, end to end.
	"start": [
		{
			"call_start_run": true,
			"wait": 2.5,
			"report": true,
			"shot": "start_run_level_01",
		},
	],
	"debug": [
		{
			"reveal": true,
			"debug_info": true,
			"wait": 1.2,
			"report": true,
			"shot": "debug_overlay",
		},
	],
	## Does the drawn nose agree with the direction the enemy is really looking?
	"facing": [
		{
			"god": true,
			"reveal": true,
			"wait": 1.0,
			"facing_report": true,
		},
		{
			"wait": 2.5,
			"facing_report": true,
			"shot": "facing_during_alert",
		},
		{
			"wait": 2.0,
			"facing_report": true,
		},
	],
	## Deliberately creates the conditions for stale references: enemies die while
	## their own bullets are still in flight, and those bullets then hit the player.
	"stress": [
		{
			"center": true,
			"reveal": true,
			"debug_info": true,
			"god": true,
			"wait": 0.4,
		},
		{
			"spawn_enemies": 3,
			"wait": 1.4,
			"report": true,
		},
		{
			"fire_for": 22.0,
			"aim_at_enemy": true,
			"report": true,
			"shot": "stress_after_firefight",
		},
		{
			"wait": 1.5,
			"report": true,
		},
	],
}


func _ready() -> void:
	var scenario: String = _arg("--probe")
	if scenario.is_empty():
		queue_free()
		return
	# Pretend a real run started, so stats and the win/death screens behave.
	GameDirector.run_active = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	print("[probe] scenario '%s'" % scenario)
	# Give the running scene (and any level it spawns) time to finish _ready.
	await get_tree().create_timer(0.7).timeout
	await _report_environment()
	await _run(scenario)
	print("[probe] done")
	get_tree().quit()


func _arg(name: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return ""


## Confirms the runtime input map really has what the game polls, including the
## mouse buttons (the one part of the real input path a script cannot press).
func _input_summary() -> String:
	var parts: Array[String] = []
	for action: String in ["fire", "move_up", "reload", "dash", "switch_1"]:
		if not InputMap.has_action(action):
			parts.append("%s=MISSING" % action)
			continue
		var kinds: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				kinds.append("key")
			elif event is InputEventMouseButton:
				kinds.append("mouse%s" % (event as InputEventMouseButton).button_index)
			else:
				kinds.append("other")
		parts.append("%s=%s" % [action, "+".join(kinds)])
	return "  ".join(parts)


func _report_environment() -> void:
	await RenderingServer.frame_post_draw
	# Prove the synthesised audio bank exists and that a sound actually starts.
	AudioDirector.play(&"shot_pistol", -6.0)
	AudioDirector.play_at(&"footstep", Vector2.ZERO, -6.0)
	await get_tree().process_frame
	print("[probe] audio %s" % AudioDirector.debug_summary())
	print("[probe] input %s" % _input_summary())
	var lights: int = 0
	var occluders: int = 0
	var modulate_colors: Array[String] = []
	for node: Node in _all_nodes(get_tree().root):
		if node is Light2D:
			lights += 1
		elif node is LightOccluder2D:
			occluders += 1
		elif node is CanvasModulate:
			modulate_colors.append(str((node as CanvasModulate).color))
	print("[probe] lights=%d occluders=%d canvas_modulate=%s" % [lights, occluders, modulate_colors])
	var player = get_tree().get_first_node_in_group("player")
	if player != null:
		var rig: VisionRig = player.get_node_or_null("Vision") as VisionRig
		if rig != null:
			var near_ok: bool = rig.near_sight != null and rig.near_sight.texture != null
			var cone_ok: bool = rig.cone_sight != null and rig.cone_sight.texture != null
			print("[probe] vision: near_texture=%s cone_texture=%s near_scale=%.3f cone_scale=%.3f" % [
				near_ok, cone_ok,
				rig.near_sight.texture_scale if rig.near_sight != null else -1.0,
				rig.cone_sight.texture_scale if rig.cone_sight != null else -1.0,
			])


func _all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for child: Node in root.get_children():
		out.append_array(_all_nodes(child))
	return out


func _run(scenario: String) -> void:
	var steps: Array = SCENARIOS.get(scenario, [])
	if steps.is_empty():
		print("[probe] no scenario named '%s'" % scenario)
		return
	var player = get_tree().get_first_node_in_group("player")

	for step: Dictionary in steps:
		# Re-fetch: a level transition replaces the player entirely.
		player = get_tree().get_first_node_in_group("player")
		if player != null:
			if step.has("center"):
				player.global_position = _level_center()
			if step.has("teleport"):
				player.global_position = step["teleport"]
			if step.has("teleport_to_exit"):
				var exit := _first_exit()
				if exit != null:
					player.global_position = exit.global_position
			if step.has("give_all"):
				player.debug_give_all_weapons()
			if step.has("aim"):
				player.debug_aim = (step["aim"] as Vector2).normalized()
			if step.has("aim_at_enemy"):
				var target: Enemy = _nearest_enemy(player.global_position)
				if target != null:
					player.debug_aim = (target.global_position - player.global_position).normalized()
			if step.has("zoom"):
				_configure_camera(player, float(step["zoom"]))
		if step.has("reveal"):
			GameDirector.reveal = bool(step["reveal"])
			GameDirector.reveal_changed.emit(GameDirector.reveal)
		if step.has("debug_info"):
			GameDirector.debug_info = bool(step["debug_info"])
		if step.has("call_start_run"):
			GameDirector.start_run()
		if step.has("god"):
			GameDirector.god_mode = bool(step["god"])
		if step.has("spawn_enemies"):
			var level: Node = GameDirector.current_level
			if level != null and level.has_method("debug_spawn_enemy"):
				for i: int in int(step["spawn_enemies"]):
					level.call("debug_spawn_enemy")
		if step.has("keys_press"):
			for action: String in step["keys_press"]:
				Input.action_press(action)

		# Holding is expressed as a longer wait; keeping the naming separate makes
		# the scenarios read better.
		var wait: float = float(step.get("wait", 0.5))
		if step.has("hold"):
			wait = maxf(wait, float(step["hold"]))

		if step.has("fire_for"):
			var duration: float = float(step["fire_for"])
			if String(step.get("fire_mode", "single")) == "hold":
				# Automatic weapons poll is_action_pressed, so a held press works.
				Input.action_press("fire")
				await get_tree().create_timer(duration).timeout
				Input.action_release("fire")
			else:
				# Semi-auto needs a discrete press per shot, which synthetic input
				# cannot reliably fake across the physics-frame boundary, so drive
				# the weapon directly. The real input path is trivial by comparison.
				var holder = player.weapons if player != null else null
				var elapsed: float = 0.0
				while elapsed < duration:
					# Keep the aim on the target: a strafing enemy is not going to
					# stand still for a scripted test.
					if step.has("aim_at_enemy") and player != null:
						var track: Enemy = _nearest_enemy(player.global_position)
						if track != null:
							player.debug_aim = (track.global_position - player.global_position).normalized()
					if holder != null:
						holder.debug_fire_once()
					await get_tree().physics_frame
					elapsed += 1.0 / 60.0
		else:
			await get_tree().create_timer(wait).timeout

		if step.has("keys_release"):
			for action: String in step["keys_release"]:
				Input.action_release(action)
		if step.has("report"):
			_report_state()
		if step.has("facing_report"):
			_report_facing()
		if step.has("shot"):
			await _screenshot(String(step["shot"]))
		if step.has("walls"):
			_report_walls()
		if step.has("points"):
			await _sample(step["points"] as Dictionary)


func _level_center() -> Vector2:
	var level: Node = GameDirector.current_level
	if level != null and level.has_method("level_bounds"):
		return level.level_bounds().get_center()
	return Vector2.ZERO


## The first exit in the level, final or not, for scripted level transitions.
func _first_exit() -> Area2D:
	var level: Node = GameDirector.current_level
	if level == null or not is_instance_valid(level):
		return null
	var list: Variant = level.get("exits")
	if list == null:
		return null
	for entry: Variant in (list as Array):
		if not is_instance_valid(entry):
			continue
		var area := entry as Area2D
		if area != null:
			return area
	return null


func _nearest_enemy(from: Vector2) -> Enemy:
	var level: Node = GameDirector.current_level
	if level == null or not is_instance_valid(level):
		return null
	var list: Variant = level.get("enemies")
	if list == null:
		return null
	var best: Enemy = null
	var best_distance: float = INF
	for entry: Variant in (list as Array):
		if not is_instance_valid(entry):
			continue
		var enemy := entry as Enemy
		if enemy == null or enemy.is_dead():
			continue
		var distance: float = enemy.global_position.distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _configure_camera(player: Node, zoom_value: float) -> void:
	var camera := player.get_node_or_null("Camera") as Camera2D
	if camera == null:
		return
	camera.zoom = Vector2(zoom_value, zoom_value)
	camera.limit_left = -1000000
	camera.limit_top = -1000000
	camera.limit_right = 1000000
	camera.limit_bottom = 1000000
	camera.position_smoothing_enabled = false


func _report_state() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		print("[probe] no player found")
		return
	print("[probe] player pos=(%.0f, %.0f) hp=%.0f dead=%s aim=(%.2f, %.2f)" % [
		player.global_position.x, player.global_position.y, player.health.current,
		player.is_dead(), player.aim_direction.x, player.aim_direction.y,
	])
	var holder = player.weapons
	if holder != null:
		var slot = holder.slot()
		if slot == null:
			print("[probe]   unarmed")
		else:
			print("[probe]   weapon %s  mag %d  reserve %d  slots %d  reloading %s" % [
				slot.data.id, slot.mag, slot.reserve, holder.slots.size(), holder.is_reloading(),
			])
	var level: Node = GameDirector.current_level
	if level != null and level.has_method("alive_enemies"):
		print("[probe]   alive enemies %d" % level.alive_enemies())
		var enemies: Array = level.get("enemies")
		for entry: Variant in enemies:
			if not is_instance_valid(entry):
				continue
			var enemy := entry as Enemy
			if enemy == null or enemy.is_dead():
				continue
			print("[probe]   enemy %s dist %d" % [
				enemy.debug_state(),
				int(enemy.global_position.distance_to(player.global_position)),
			])
	print("[probe] kills %d  shots %d  alerts %d" % [
		GameDirector.kills, GameDirector.shots_fired, GameDirector.enemies_alerted,
	])


## Compares, for every enemy: the direction it is really looking, the direction its
## nose is drawn at, and the direction to the player. The first two must agree.
func _report_facing() -> void:
	var player = get_tree().get_first_node_in_group("player")
	var level: Node = GameDirector.current_level
	if level == null or not is_instance_valid(level):
		return
	var list: Variant = level.get("enemies")
	if list == null:
		return
	print("[probe] facing check, in degrees (nose_err must be ~0):")
	for entry: Variant in (list as Array):
		if not is_instance_valid(entry):
			continue
		var enemy := entry as Enemy
		if enemy == null or enemy.is_dead():
			continue
		var visual := enemy.get_node_or_null("Visual") as Node2D
		var looking: float = rad_to_deg(enemy.facing_angle())
		var drawn: float = rad_to_deg(visual.global_rotation) if visual != null else 999.0
		var to_player: float = rad_to_deg((player.global_position - enemy.global_position).angle()) \
			if player != null else 999.0
		var nose_error: float = absf(wrapf(deg_to_rad(drawn - looking), -PI, PI))
		var aim_error: float = absf(wrapf(deg_to_rad(looking - to_player), -PI, PI))
		print("[probe]   %-6s %-10s looking=%7.1f  nose=%7.1f  nose_err=%6.1f  to_player=%7.1f  aim_err=%6.1f" % [
			enemy.archetype.id, Enemy.STATE_NAMES[enemy.state], looking, drawn,
			rad_to_deg(nose_error), to_player, rad_to_deg(aim_error),
		])


func _report_walls() -> void:
	var total: int = 0
	var explored: int = 0
	for node: Node in get_tree().get_nodes_in_group("wall"):
		var wall: Wall = node as Wall
		if wall == null:
			continue
		total += 1
		if wall.is_explored():
			explored += 1
	print("[probe]   walls explored %d/%d" % [explored, total])


func _screenshot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [SHOT_DIR, shot_name]
	var err: Error = image.save_png(path)
	print("[probe] shot %s -> %s (%dx%d)" % [
		shot_name, error_string(err), image.get_width(), image.get_height(),
	])


func _sample(points: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var scale: float = float(image.get_width()) / maxf(1.0, view_size.x)
	for key: String in points:
		var world: Vector2 = points[key]
		var screen: Vector2 = canvas_transform * world
		var px: int = int(round(screen.x * scale))
		var py: int = int(round(screen.y * scale))
		if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
			print("[probe]   %-22s OFFSCREEN (world %s)" % [key, world])
			continue
		var c: Color = image.get_pixel(px, py)
		print("[probe]   %-22s rgb=(%.3f %.3f %.3f) world=%s" % [key, c.r, c.g, c.b, world])
