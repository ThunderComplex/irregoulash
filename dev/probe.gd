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
	## Does a lamp stop lighting the world for the player when they cannot see it?
	## In vision_test the lamp sits at (-330, -330) behind a divider wall with a
	## doorway at y -120..120, and it is the only light in the scene.
	"lamps": [
		{
			# Same side of the wall as nothing: the divider blocks sight of the lamp,
			# so its pool must go dark.
			"teleport": Vector2(320.0, -200.0),
			"aim": Vector2(-1.0, 0.0),
			"wait": 1.2,
			"shot": "lamp_01_no_line_of_sight",
			"points": {"lamp_pool_blocked": Vector2(-240.0, -300.0)},
		},
		{
			# Round the wall with a clear view of the lamp: the same spot lights up.
			"teleport": Vector2(-120.0, 0.0),
			"aim": Vector2(-1.0, 0.0),
			"wait": 1.2,
			"shot": "lamp_02_line_of_sight",
			"points": {"lamp_pool_lit": Vector2(-240.0, -300.0)},
		},
	],
	## Bake a navmesh at runtime and verify it: that the server knows about it, that
	## enemies pick it up, and that its paths never cross walls.
	"navmesh": [
		{
			"bake_navmesh": true,
			"wait": 0.8,
			"navmesh_report": true,
			"shot": "navmesh_after_bake",
		},
		{
			# Give the periodic check time to notice the mesh, then confirm enemies
			# switched from steering to pathing.
			"wait": 1.0,
			"navmesh_report": true,
		},
		{
			# And that they can actually close in: everyone is told where the player is
			# and given three seconds to path there. Distances in the report should
			# shrink, and nobody should end up inside a wall.
			"alert_all": true,
			"god": true,
			"wait": 3.0,
			"report": true,
			"shot": "navmesh_chase",
		},
	],
	## Lint every level (the same checks the editor plugin's button runs).
	"lint": [
		{
			"wait": 0.3,
			"lint_levels": true,
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


var _probe_region: NavigationRegion2D = null


func _arg(name: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return ""


## `RenderingServer.frame_post_draw` never fires without a renderer (a `--headless`
## run), so wait on a plain frame there instead. Without this, the probe hangs.
func _await_frame() -> void:
	if _is_headless():
		await get_tree().process_frame
		return
	await RenderingServer.frame_post_draw


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


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
	await _await_frame()
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
		# Actions happen *before* the wait, observations after it: a step that says
		# "bake the mesh, wait, then report" has to bake first.
		if step.has("bake_navmesh"):
			_bake_navmesh_runtime()
		if step.has("alert_all"):
			var alerted: Node = GameDirector.current_level
			if alerted != null and alerted.has_method("debug_alert_all"):
				alerted.call("debug_alert_all")

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
		if step.has("lint_levels"):
			_lint_levels()
		if step.has("navmesh_report"):
			_report_navmesh()
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


## Bakes a navigation mesh for the running level at runtime, with the same baker the
## editor's "Bake navmesh" button uses. Nothing is written to the level file: this
## exists so path finding can be verified as part of a probe run.
func _bake_navmesh_runtime() -> void:
	var level: Node = GameDirector.current_level
	if level == null or not is_instance_valid(level):
		print("[probe] no level to bake a navmesh for")
		return
	var walls: Array[Wall] = []
	for node: Node in get_tree().get_nodes_in_group("wall"):
		var wall := node as Wall
		if wall != null and wall.is_inside_tree():
			walls.append(wall)
	if walls.is_empty():
		print("[probe] no walls to bake from")
		return
	_probe_region = NavigationRegion2D.new()
	_probe_region.name = "ProbeNav"
	level.add_child(_probe_region)
	var report: Dictionary = NavmeshBaker.bake(_probe_region, walls)
	print("[probe] baked navmesh from %d walls -> %d polygon(s)" % [
		report["walls"], report["polygons"]])


## Verifies a navmesh: that the server knows about it, that enemies have picked it up,
## and that the paths it hands out actually respect the geometry.
func _report_navmesh() -> void:
	if _probe_region == null or not is_instance_valid(_probe_region):
		print("[probe] no navmesh to report on (bake one first)")
		return
	var map: RID = _probe_region.get_navigation_map()
	var regions: Array = NavigationServer2D.map_get_regions(map)
	print("[probe] navmesh: %d region(s) registered, iteration %d" % [
		regions.size(), NavigationServer2D.map_get_iteration_id(map)])
	if regions.is_empty():
		return

	var enemies: Variant = GameDirector.current_level.get("enemies")
	var using: int = 0
	var total: int = 0
	if enemies != null:
		for entry: Variant in (enemies as Array):
			if not is_instance_valid(entry):
				continue
			var enemy := entry as Enemy
			if enemy == null or enemy.is_dead():
				continue
			total += 1
			if enemy.uses_navmesh():
				using += 1
	print("[probe] enemies pathing: %d/%d" % [using, total])

	var level: Node2D = GameDirector.current_level as Node2D
	var space: PhysicsDirectSpaceState2D = level.get_world_2d().direct_space_state
	# Endpoints are sampled *on* the navmesh, so they are guaranteed to be walkable.
	# Both raw paths and corner-cut ones are tested.
	for optimize: bool in [false, true]:
		var checked: int = 0
		var crossings: int = 0
		for i: int in 12:
			var from: Vector2 = NavigationServer2D.map_get_random_point(map, 1, true)
			var to: Vector2 = NavigationServer2D.map_get_random_point(map, 1, true)
			if from.distance_squared_to(to) < 4096.0:
				continue
			var path: PackedVector2Array = NavigationServer2D.map_get_path(map, from, to, optimize, 1)
			if path.size() < 2:
				continue
			checked += 1
			crossings += _wall_crossings(path, space)
		print("[probe] paths (optimize=%s): %d checked, %d wall crossings" % [
			optimize, checked, crossings])


## How many segments of a polyline pass through a wall.
func _wall_crossings(path: PackedVector2Array, space: PhysicsDirectSpaceState2D) -> int:
	var crossings: int = 0
	for i: int in range(path.size() - 1):
		var from: Vector2 = path[i]
		var to: Vector2 = path[i + 1]
		if from.distance_squared_to(to) < 1.0:
			continue
		var query := PhysicsRayQueryParameters2D.create(from, to, Layers.WORLD)
		query.hit_from_inside = false
		if not space.intersect_ray(query).is_empty():
			crossings += 1
	return crossings


## Lints every level scene. This runs inside a real game run rather than as a
## `--script` tool on purpose: levels reference autoloads, and autoloads do not
## exist in a `--script` run, so every level script would fail to compile and the
## report would be nonsense.
func _lint_levels() -> void:
	var dir := DirAccess.open("res://src/levels")
	if dir == null:
		print("[probe] cannot open the level folder")
		return
	var files: Array[String] = []
	for file: String in dir.get_files():
		if file.begins_with("level_") and file.ends_with(".tscn"):
			files.append("res://src/levels/%s" % file)
	files.sort()

	var failures: int = 0
	for path: String in files:
		var packed := load(path) as PackedScene
		if packed == null:
			print("[probe] %s: cannot load" % path)
			failures += 1
			continue
		# Instantiated but never added to the tree: LevelLint needs no scene tree,
		# so nothing runs just to be checked.
		var root: Node = packed.instantiate()
		var report: Dictionary = LevelLint.run(root)
		print("[probe] %s: %s" % [path.get_file(), report["summary"]])
		for note: String in report["notes"]:
			print("[probe]   note: %s" % note)
		var problems: Array = report["problems"]
		if problems.is_empty():
			print("[probe]   clean")
		else:
			failures += problems.size()
			for problem: String in problems:
				print("[probe]   PROBLEM: %s" % problem)
			for line: String in report["map"]:
				print("[probe]   %s" % line)
		root.free()
	print("[probe] lint: %d level(s) checked, %d problem(s)" % [files.size(), failures])


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
	if _is_headless():
		print("[probe] shot %s SKIPPED (headless runs have no renderer)" % shot_name)
		return
	await _await_frame()
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [SHOT_DIR, shot_name]
	var err: Error = image.save_png(path)
	print("[probe] shot %s -> %s (%dx%d)" % [
		shot_name, error_string(err), image.get_width(), image.get_height(),
	])


func _sample(points: Dictionary) -> void:
	if _is_headless():
		print("[probe] pixel sampling SKIPPED (headless runs have no renderer)")
		return
	await _await_frame()
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
