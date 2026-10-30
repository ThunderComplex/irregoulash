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

## The player's own checkpoint, saved before a test that clears or writes it, and put back
## afterwards. A dev tool must never eat a save.
var _progress_existed: bool = false
var _progress_backup: PackedByteArray = PackedByteArray()

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
	## Exercises the *real* input path for firing: an automatic weapon, trigger held
	## through Input.action_press, so the polled `is_action_pressed` branch runs. This is
	## what catches a wrong action name, which would otherwise fail silently.
	"input": [
		{
			"give_all": true,
			"select_weapon": 1,
			"wait": 0.4,
			"report": true,
		},
		{
			"fire_for": 1.5,
			"fire_mode": "hold",
			"report": true,
			"shot": "input_held_trigger",
		},
	],
	## Resolution independence, with numbers and with pictures. The window is resized while
	## the game is running, which is what the settings menu does, and a constant amount of
	## world must stay visible at every size and aspect.
	"presentation": [
		{
			"center": true,
			"wait": 0.5,
			"presentation": true,
			"shot": "presentation_00_1280x720",
		},
		{
			"window_size": Vector2i(1920, 1080),
			"wait": 0.6,
			"presentation": true,
			"shot": "presentation_01_1920x1080",
		},
		{
			"window_size": Vector2i(1024, 768),
			"wait": 0.6,
			"presentation": true,
			"shot": "presentation_02_1024x768_4x3",
		},
		{
			"window_size": Vector2i(1280, 800),
			"wait": 0.6,
			"presentation": true,
			"shot": "presentation_03_1280x800_16x10",
		},
		{
			"window_size": Vector2i(1600, 600),
			"wait": 0.6,
			"presentation": true,
			"shot": "presentation_04_1600x600_ultrawide",
		},
		{
			# The HUD at a large size and a narrow one, with the debug readout on so the
			# layout can be judged rather than guessed at.
			"window_size": Vector2i(2560, 1440),
			"debug_info": true,
			"wait": 0.6,
			"presentation": true,
			"shot": "presentation_05_2560x1440_debug",
		},
		{
			"window_size": Vector2i(800, 600),
			"wait": 0.6,
			"presentation": true,
			"shot": "presentation_06_800x600_debug",
		},
	],
	## Doors, from every direction: the player working one, a key being spent on a lock, dashing
	## an unlocked door apart, dashing a locked one for nothing, and an enemy opening a door and
	## shutting it behind itself.
	"doors": [
		{
			# A shut door blocks light, movement and enemy sight. God mode: the door tests make
			# noise, which legitimately draws enemies, and a test should not end in a firefight.
			"god": true,
			"add_keys": 2,
			"spawn_door": {"at": Vector2(520.0, 544.0), "locked": false, "rotation": 0.0},
			"wait": 0.3,
			"door_report": true,
			"report": true,
			"shot": "doors_00_closed",
		},
		{
			# Standing beside it, working it: opens, sight opens, the swing makes a noise.
			"teleport": Vector2(520.0, 500.0),
			"clear_noise": true,
			"interact_door": true,
			"wait": 0.5,
			"door_report": true,
			"noise_report": true,
			"shot": "doors_01_open",
		},
		{
			# And shut again from the same spot.
			"interact_door": true,
			"wait": 0.5,
			"door_report": true,
		},
		{
			# Open it, then stand *in* the doorway and try to shut it: the leaf bounces off the
			# player, the door stays open, and nothing is announced. Gamefeel over text.
			"interact_door": true,
			"wait": 0.5,
		},
		{
			"teleport": Vector2(520.0, 544.0),
			"clear_announce": true,
			"interact_door": true,
			"wait": 0.5,
			"door_report": true,
			"announce_report": true,
			"noise_report": true,
		},
		{
			# A locked door, with keys in hand: nothing happens until it is tried.
			"spawn_door": {"at": Vector2(640.0, 640.0), "locked": true, "rotation": 0.0},
			"teleport": Vector2(640.0, 596.0),
			"wait": 0.3,
			"door_report": true,
			"report": true,
		},
		{
			# One key spent, and it opens.
			"interact_door": true,
			"wait": 0.5,
			"door_report": true,
			"report": true,
		},
		{
			# A second locked door, dashed into: loud, stays shut, no key spent.
			"spawn_door": {"at": Vector2(640.0, 900.0), "locked": true, "rotation": 0.0},
			"teleport": Vector2(640.0, 1010.0),
			"clear_noise": true,
			"wait": 0.2,
			"door_report": true,
		},
		{
			"dash_at_door": true,
			"wait": 0.6,
			"door_report": true,
			"report": true,
			"noise_report": true,
		},
		{
			# An unlocked door, dashed into: smashed permanently.
			"spawn_door": {"at": Vector2(900.0, 640.0), "locked": false, "rotation": 0.0},
			"teleport": Vector2(900.0, 750.0),
			"clear_noise": true,
			"wait": 0.2,
		},
		{
			"dash_at_door": true,
			"wait": 0.6,
			"door_report": true,
			"report": true,
			"noise_report": true,
			"shot": "doors_02_smashed",
		},
		{
			# The no-nudge test: a shut door whose *open* leaf will land exactly on the player.
			# Opening it must swing the leaf over them and leave them standing where they were.
			"spawn_door": {"at": Vector2(980.0, 544.0), "locked": false, "rotation": 0.0},
			"teleport": Vector2(932.0, 600.0),
			"wait": 0.3,
			"report": true,
		},
		{
			"interact_door": true,
			"wait": 0.7,
			"report": true,
			"door_report": true,
		},
		{
			# Step clear of the leaf: the exemption is dropped, so a settled door blocks the player
			# like any other wall again.
			"teleport": Vector2(932.0, 760.0),
			"wait": 0.4,
			"door_report": true,
		},
		{
			# And standing *against* a settled leaf must not exempt the player: otherwise walking
			# into an open door would phase through it instead of being stopped.
			"teleport": Vector2(932.0, 654.0),
			"wait": 0.4,
			"door_report": true,
		},
		{
			# An enemy opens a shut door in its way, then shuts it once it is past.
			"enemy_door_test": true,
			"wait": 0.4,
			"door_report": true,
		},
	],
	## The same question asked of a level as it stands: does its own baked navmesh route through its
	## doors? Run this against the level being authored.
	"doorway_level": [
		{
			"wait": 0.6,
			"doorway_report": true,
		},
		{
			# Then bake it here and ask again: proves that re-baking is the fix, rather than leaving
			# the author to find out.
			"bake_navmesh": true,
			"wait": 0.6,
			"doorway_report": true,
		},
	],
	## The surface lab: the look of walls and floor, photographed from a few fixed viewpoints so two runs
	## can be compared. Run this against `dev/surface_lab.tscn`.
	"surface_lab": [
		{
			"god": true,
			"wait": 0.8,
			"surface_report": true,
			"shot": "surfaces_01_overview",
		},
		{
			# Close to the long wall, lit by the lamp between it and its neighbour: tiling and rim.
			"teleport": Vector2(700, 320),
			"aim": Vector2(0, -1),
			"wait": 0.6,
			"shot": "surfaces_02_long_wall",
		},
		{
			# A corner and a thick block: the rim and inner shadow on four sides, and at a join.
			"teleport": Vector2(400, 250),
			"aim": Vector2(-1, 0.2),
			"wait": 0.6,
			"shot": "surfaces_03_block_and_corner",
		},
		{
			# The stub, alone in a light pool: one and a half tiles, so the tiling is obvious if it is
			# going to be.
			"teleport": Vector2(1120, 700),
			"aim": Vector2(0, -1),
			"wait": 0.6,
			"shot": "surfaces_04_stub",
		},
		{
			# Floor only, under a lamp.
			"teleport": Vector2(820, 760),
			"aim": Vector2(0, -1),
			"wait": 0.6,
			"shot": "surfaces_05_floor_pool",
		},
		{
			# The same view in flat colour: if the walls are equally dark here, the darkness is lighting,
			# not the shader.
			"teleport": Vector2(700, 320),
			"aim": Vector2(0, -1),
			"set_wall_surface": "plain",
			"wait": 0.6,
			"shot": "surfaces_06_plain_compare",
		},
		{
			"set_wall_surface": "wood",
			"wait": 0.2,
		},
	],
	## An open door's leaf is solid and unknown to the navmesh: can an enemy walk around it?
	"door_avoid": [
		{
			"god": true,
			"wait": 0.4,
		},
		{
			"door_avoid_test": true,
			"wait": 0.2,
		},
	],
	## Fuzz the search: over hundreds of picks, none may be inside a wall or off the mesh.
	"search_targets": [
		{
			"god": true,
			"wait": 0.4,
		},
		{
			"search_target_test": true,
			"wait": 0.2,
		},
	],
	## A door in a walled doorway, locked then unlocked: can the mesh and an actual enemy get through?
	"doorway": [
		{
			"god": true,
			"wait": 0.4,
		},
		{
			"doorway_test": true,
			"wait": 0.3,
		},
	],
	## Bullets must not go through a wall you are standing against.
	"point_blank": [
		{
			"god": true,
			"give_all": true,
			"wait": 0.4,
		},
		{
			"point_blank_test": true,
			"wait": 0.3,
		},
	],
	## The search, measured. Runs the tier-0 checks and then leaves a searcher framed for the debug
	## view, so the picture and the numbers come from the same behaviour.
	"search": [
		{
			"god": true,
			"wait": 0.4,
		},
		{
			"search_tests": true,
			"wait": 0.3,
			"search_report": true,
		},
		{
			"debug_info": true,
			"wait": 1.0,
			"search_report": true,
			"shot": "search_debug",
		},
	],
	## Loot. Kill a shotgun-carrying enemy while standing on its corpse: the drop has to have a
	## collision shape on the right layers, and walking over it has to actually collect it.
	"loot": [
		{
			"wait": 0.5,
			"report": true,
			"loot_report": true,
		},
		{
			"loot_kill": true,
			"wait": 1.2,
			"loot_report": true,
			"report": true,
		},
	],
	## Both menus, end to end: what they offer, what is greyed out, that a *paused* menu still
	## answers the mouse, and that Continue brings back the level and the loadout. It runs from
	## the title screen, because a run has to be started the way a player starts one.
	"menus": [
		{
			# A fresh install has nothing to resume, and the button has to say so.
			"backup_progress": true,
			"clear_progress": true,
			"wait": 0.3,
			"progress_report": true,
			"menu_report": true,
			"shot": "menu_00_title_continue_disabled",
		},
		{
			"menu_activate": "settings",
			"wait": 0.5,
			"menu_report": true,
			"shot": "menu_01_title_settings",
		},
		{
			"close_menus": true,
			"wait": 0.3,
			"menu_report": true,
		},
		{
			"menu_activate": "new_game",
			"wait": 1.6,
			"scene_report": true,
			"progress_report": true,
		},
		{
			"give_all": true,
			"wait": 0.4,
			"report": true,
		},
		{
			# Pausing refreshes the checkpoint with the live loadout, which is the whole point.
			"toggle_pause": true,
			"wait": 0.6,
			"progress_report": true,
			"menu_report": true,
			"shot": "menu_02_pause",
		},
		{
			# A real click through the GUI, on a paused tree.
			"menu_click": "settings",
			"wait": 0.6,
			"menu_report": true,
			"shot": "menu_03_pause_settings",
		},
		{
			"close_menus": true,
			"wait": 0.4,
			"menu_report": true,
		},
		{
			"menu_activate": "quit_to_menu",
			"wait": 1.8,
			"scene_report": true,
			"progress_report": true,
			"menu_report": true,
			"shot": "menu_04_title_with_progress",
		},
		{
			# The reported bug, exactly: with a checkpoint available, pressing Space on the title
			# screen started a new game and threw the run away. Space now activates whatever is
			# focused, and the loadout proves which path ran -- a new game would have the pistol
			# alone, only Continue has all three weapons.
			"press_space": true,
			"wait": 1.8,
			"scene_report": true,
			"report": true,
		},
		{
			# And put the player's own checkpoint and settings back: a dev tool must not leave
			# test-made saves behind.
			"settings_roundtrip": true,
			"restore_progress": true,
			"wait": 0.2,
			"progress_report": true,
		},
	],
	## The title screen and the settings menu at three window sizes, since both lay
	## themselves out in code and neither may assume 1280x720 any more.
	"title_layout": [
		{
			"wait": 0.6,
			"presentation": true,
			"shot": "title_00_1280x720",
		},
		{
			"window_size": Vector2i(1920, 1080),
			"wait": 0.6,
			"shot": "title_01_1920x1080",
		},
		{
			"window_size": Vector2i(1024, 768),
			"wait": 0.6,
			"shot": "title_02_1024x768_4x3",
		},
		{
			"open_settings": true,
			"wait": 0.6,
			"presentation": true,
			"shot": "title_03_settings_menu",
		},
		{
			"window_size": Vector2i(1920, 1080),
			"wait": 0.6,
			"shot": "title_04_settings_large",
		},
	],
	## Abilities: the holder has one cast path, and these three abilities have to do three
	## different things through it. Damage is read off the enemies; the fire wall's
	## solidity and shadow-casting are read off the effect it leaves behind.
	"abilities": [
		{
			"set_abilities": ["fire_tempest", "lightning_bolt"],
			"wait": 0.4,
			"report": true,
		},
		{
			"teleport": Vector2(224.0, 900.0),
			"aim_at_enemy": true,
			"wait": 0.4,
			"report": true,
		},
		{
			# DIRECTION targeting: a bolt towards the nearest enemy.
			"cast_ability": 1,
			"ability_target_at_enemy": true,
			"wait": 1.2,
			"report": true,
		},
		{
			# POINT targeting with no placement rules: a blast centred on that enemy.
			"cast_ability": 0,
			"ability_target_at_enemy": true,
			"wait": 1.0,
			"report": true,
		},
		{
			"set_abilities": ["fire_wall"],
			# Inside geometry: refused before anything is spent, so the cooldown stays 0.
			"cast_ability": 0,
			"ability_target": Vector2(32.0, 500.0),
			"wait": 0.7,
			"report": true,
			"ability_effects": true,
		},
		{
			# In the open: spawned, and it is solid and shadow-casting.
			"cast_ability": 0,
			"ability_target": Vector2(224.0, 620.0),
			"wait": 0.6,
			"report": true,
			"ability_effects": true,
		},
		{
			# Again immediately: refused by the cooldown.
			"cast_ability": 0,
			"ability_target": Vector2(224.0, 620.0),
			"wait": 0.4,
			"report": true,
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


## Godot's built-in actions the game relies on, checked alongside our own.
const BUILT_IN_ACTIONS: Array[StringName] = [&"ui_accept"]


## Confirms the runtime input map has every action the game polls, and that a press
## registers. Action names are StringName literals throughout the code now, so this is
## the check that catches a typo in one of them -- an unknown action name fails
## silently at runtime, it does not raise an error.
func _input_summary() -> String:
	var missing: Array[String] = []
	var checked: int = 0
	for key: Variant in _declared_actions():
		checked += 1
		if not InputMap.has_action(key):
			missing.append(String(key))

	# The held-press path is what automatic weapons poll, so prove it works.
	Input.action_press(&"fire")
	var registers: bool = Input.is_action_pressed(&"fire")
	Input.action_release(&"fire")

	return "%d/%d actions bound%s | synthetic press registers=%s" % [
		checked - missing.size(), checked,
		"" if missing.is_empty() else "   MISSING: " + ", ".join(missing),
		registers]


func _declared_actions() -> Array:
	var out: Array = []
	for key: Variant in GameInput.KEY_BINDINGS:
		out.append(key)
	for key: Variant in GameInput.MOUSE_BINDINGS:
		out.append(key)
	for key: Variant in BUILT_IN_ACTIONS:
		out.append(key)
	return out


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


## The resolution-independence claim in numbers. Whatever the window size, a constant
## amount of world must be visible and the HUD must scale with the window; if either of
## those drifts, this line shows it immediately.
func _report_presentation() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom: Vector2 = Vector2.ONE
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null:
		# Named "Camera" in the player scene; fall back to any Camera2D under the player.
		var camera := player.get_node_or_null("Camera") as Camera2D
		if camera == null:
			for node: Node in _all_nodes(player):
				var found := node as Camera2D
				if found != null:
					camera = found
					break
		if camera != null:
			zoom = camera.zoom
	var hud: HUD = null
	for node: Node in _all_nodes(get_tree().root):
		var candidate := node as HUD
		if candidate != null:
			hud = candidate
			break
	print("[probe] window %dx%d  desktop %s  zoom %.3f  visible world %.0fx%.0f  hud scale %.3f" % [
		int(viewport_size.x), int(viewport_size.y), str(DisplayServer.screen_get_size()),
		zoom.x, viewport_size.x / maxf(0.001, zoom.x), viewport_size.y / maxf(0.001, zoom.y),
		hud.ui_scale() if hud != null else -1.0,
	])
	# Full-screen overlay controls have to size themselves to the window. A zero-sized one
	# still draws its children, so it fails silently and half off-screen -- worth reporting.
	if hud != null:
		var overlay := hud.get_node_or_null("Root/Overlay") as Control
		if overlay != null:
			print("[probe]   hud overlay rect %s" % str(overlay.get_global_rect()))
	_report_settings_menu()


func _report_settings_menu() -> void:
	var found: int = 0
	for node: Node in _all_nodes(get_tree().root):
		var menu := node as SettingsMenu
		if menu == null:
			continue
		found += 1
		print("[probe]   settings menu rect %s  (visible rect %s)  embedded=%s" % [
			str(menu.get_global_rect()), str(menu.get_viewport_rect()),
			Engine.is_embedded_in_editor(),
		])
	if found == 0:
		print("[probe]   no settings menu open")


## Settings persistence, with the player's own file left exactly as it was found: the test
## writes, reloads, then puts the original bytes back (or removes the file if the probe
## created it) and *reports* whether the file is really gone.
##
## The reporting matters. Leaving a file behind is a nasty side effect, because it also
## stores a resolution adopted from whatever window the probe happened to use -- and an
## earlier version of this test did exactly that, by calling a `set_*` setter (which saves)
## after the cleanup.
func _report_settings_roundtrip() -> void:
	var path: String = GameSettings.PATH
	var existed: bool = FileAccess.file_exists(path)
	var backup: PackedByteArray = PackedByteArray()
	if existed:
		backup = FileAccess.get_file_as_bytes(path)
	var master_before: float = Settings.master_volume_db
	var sfx_before: float = Settings.sfx_volume_db

	Settings.set_master_volume_db(-7.25)
	Settings.set_sfx_volume_db(-23.5)
	# Forget the in-memory values and read them back off disk, which is what a restart does.
	Settings.master_volume_db = 0.0
	Settings.sfx_volume_db = 0.0
	Settings.load_settings()
	print("[probe] settings round-trip master=%s sfx=%s (read back %.2f / %.2f)" % [
		is_equal_approx(Settings.master_volume_db, -7.25),
		is_equal_approx(Settings.sfx_volume_db, -23.5),
		Settings.master_volume_db, Settings.sfx_volume_db,
	])

	# Undo, bytes first, and only direct field writes after that: a `set_*` call would save
	# the file again and undo the cleanup.
	if existed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(backup)
			file.close()
	else:
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove("settings.cfg")
	Settings.master_volume_db = master_before
	Settings.sfx_volume_db = sfx_before
	Settings.apply()
	print("[probe] settings file after restore: exists=%s (existed before the test: %s)" % [
		FileAccess.file_exists(path), existed,
	])


#region doorway

## Reproduces a walled doorway with a door in it, unlocks it the way a player does, and then asks
## two questions: does the navmesh still offer a route through the gap, and does an actual enemy walk
## it. Kept separate from `point_blank` because this is about pathing, not shooting.
func _doorway_test() -> void:
	var level: Node = GameDirector.current_level
	var player := GameDirector.valid_player()
	if level == null or player == null:
		print("[probe] doorway: no level or player")
		return

	# A horizontal wall with a 96px gap, filled by a locked door: the shape a level author builds.
	var gap_centre := Vector2(648.0, 1200.0)
	var left := _spawn_test_wall(Vector2(500.0, 1200.0), Vector2(200.0, 32.0))
	var right := _spawn_test_wall(Vector2(796.0, 1200.0), Vector2(200.0, 32.0))
	var door := _spawn_test_door(gap_centre, true, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_bake_navmesh_runtime()
	await _wait_seconds(0.4)

	var above := gap_centre + Vector2(0.0, -120.0)
	var below := gap_centre + Vector2(0.0, 120.0)
	var probe_map: RID = _probe_region.get_navigation_map() if _probe_region != null else RID()
	# The same predicate the linter uses, so a green here and a green lint mean the same thing.
	print("[probe] doorway: lint agrees the doorway is connected: %s" % LevelLint.disconnected_doorways(
		_probe_region, [door] as Array[Door]).is_empty())
	print("[probe] doorway: navmesh route across a locked door: %s" % _route_through(above, below,
		gap_centre, probe_map))

	# The player unlocks it with a key, which is the moment the report says pathing dies.
	player.keys = 1
	player.global_position = gap_centre + Vector2(0.0, -70.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.interact_nearby()
	await _wait_seconds(0.4)
	print("[probe] doorway after unlocking: door=%s locked=%s keys=%d" % [
		_door_state_name(door.state), door.locked, player.keys,
	])
	print("[probe] doorway: navmesh route across the unlocked door: %s" % _route_through(above, below,
		gap_centre, probe_map))

	# And an enemy actually walking it, which is the version that matters.
	player.global_position = Vector2(288.0, 1560.0)
	var walker := _spawn_test_enemy(above)
	await get_tree().physics_frame
	await get_tree().physics_frame
	walker.call("_enter_search")
	walker.last_known = below
	walker.set("_search_target", below)
	var crossed: bool = false
	var elapsed: float = 0.0
	while elapsed < 4.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if walker.global_position.y > gap_centre.y + 24.0:
			crossed = true
			break
	print("[probe] doorway: enemy walked through the unlocked door: %s (at %s, %.1fs)" % [
		crossed, str(Vector2i(walker.global_position)), elapsed,
	])

	walker.queue_free()
	door.queue_free()
	left.queue_free()
	right.queue_free()
	if _probe_region != null and is_instance_valid(_probe_region):
		_probe_region.queue_free()
		_probe_region = null


## For every door in the level: does the level's *own baked* navmesh offer a route through it?
##
## Doors are deliberately not bake geometry, so a doorway should always be connected in the mesh. If
## it is not, the mesh is stale or the doorway is too narrow for the agent, and the symptom is
## "enemies will not come through this door" -- which is invisible, because the mesh is.
func _report_doorway_routes() -> void:
	var level: Node = GameDirector.current_level
	if level == null:
		print("[probe]   no level")
		return
	var region: NavigationRegion2D = null
	for node: Node in _all_nodes(level):
		var candidate := node as NavigationRegion2D
		if candidate != null:
			region = candidate
			break

	var doors: Array[Door] = []
	for node: Node in _all_nodes(level):
		var door := node as Door
		if door != null:
			doors.append(door)
	if doors.is_empty():
		print("[probe]   this level has no doors")
		return
	for door: Door in doors:
		print("[probe]   door %s (parent %s, locked=%s) size %s" % [
			door.name, door.get_parent().name if door.get_parent() != null else "-",
			door.starts_locked, str(door.size),
		])

	# The same predicate the linter uses, so a green probe and a green lint mean the same thing.
	if region != null:
		print("[probe]   level mesh '%s': %s" % [
			region.name, _describe_gaps(LevelLint.disconnected_doorways(region, doors)),
		])
	if _probe_region != null and is_instance_valid(_probe_region):
		print("[probe]   after a fresh bake: %s" % _describe_gaps(
			LevelLint.disconnected_doorways(_probe_region, doors)))


func _describe_gaps(blocked: Array[String]) -> String:
	return "every doorway is connected" if blocked.is_empty() else "%d not connected: %s" % [
		blocked.size(), " | ".join(blocked),
	]


func _spawn_test_wall(at: Vector2, size: Vector2) -> Wall:
	var level: Node = GameDirector.current_level
	var wall := (load("res://src/levels/wall.tscn") as PackedScene).instantiate() as Wall
	wall.size = size
	level.add_child(wall)
	wall.global_position = at
	return wall


## "through", "around", or "none": does the navmesh route from `from` to `to` pass through the
## doorway at `gap`, or does it go the long way?
func _route_through(from: Vector2, to: Vector2, gap: Vector2, map: RID) -> String:
	if not map.is_valid():
		return "no map"
	var path: PackedVector2Array = NavigationServer2D.map_get_path(map, from, to, true)
	if path.is_empty():
		return "none"
	var crosses: bool = false
	for point: Vector2 in path:
		if absf(point.x - gap.x) < 60.0 and absf(point.y - gap.y) < 40.0:
			crosses = true
			break
	var length: float = 0.0
	for i: int in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return "through (%.0f px)" % length if crosses else "around (%.0f px)" % length


#endregion


#region point blank

## Shooting with your back to a wall, which is where bullets used to go through it.
##
## A muzzle sits ahead of its shooter, so standing flush against a wall puts the muzzle *inside* the
## wall; a raycast ignores any shape containing its origin, so the round flew out the far side. This
## reproduces the report exactly: player against a wall, enemy on the other side, one shot.
func _point_blank_test() -> void:
	var level: Node = GameDirector.current_level
	var player := GameDirector.valid_player()
	if level == null or player == null:
		print("[probe] point blank: no level or player")
		return

	# A fresh wall and a fresh target, so nothing in the level can be blamed for the result.
	var wall := (load("res://src/levels/wall.tscn") as PackedScene).instantiate() as Wall
	wall.size = Vector2(64.0, 400.0)
	level.add_child(wall)
	wall.global_position = Vector2(600.0, 700.0)
	var target := _spawn_test_enemy(Vector2(700.0, 700.0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var holder := player.weapons as WeaponHolder
	var hp_before: float = target.health.current

	# Flush against the wall's left face (x = 568), aiming straight through it at the enemy beyond.
	player.global_position = Vector2(568.0 - Tuning.player_radius, 700.0)
	player.debug_aim = Vector2.RIGHT
	await get_tree().physics_frame
	await get_tree().physics_frame
	var muzzle: Vector2 = player.muzzle_position()
	print("[probe] player at x=%.0f, wall face x=568, muzzle x=%.0f (inside the wall: %s)" % [
		player.global_position.x, muzzle.x, wall.world_rect().has_point(muzzle),
	])
	if holder != null:
		holder.debug_fire_once()
	await _wait_seconds(0.6)
	print("[probe] point-blank shot into a wall: enemy hp %.0f -> %.0f (expected unchanged)" % [
		hp_before, target.health.current,
	])

	# A shut door: same layer, same story, and the case the report mentioned alongside walls.
	var door := _spawn_test_door(Vector2(700.0, 1000.0), false, 0.0)
	var behind_door := _spawn_test_enemy(Vector2(700.0, 1090.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.global_position = Vector2(700.0, 984.0 - Tuning.player_radius)
	player.debug_aim = Vector2.DOWN
	await get_tree().physics_frame
	await get_tree().physics_frame
	var door_hp: float = behind_door.health.current
	if holder != null:
		holder.debug_fire_once()
	await _wait_seconds(0.6)
	print("[probe] point-blank shot into a shut door: enemy hp %.0f -> %.0f (expected unchanged)" % [
		door_hp, behind_door.health.current,
	])
	door.queue_free()
	behind_door.queue_free()

	# The same shot with a clear line must still land, or the fix has broken shooting. Fired past the
	# end of the wall, so the only thing between the two is open floor.
	player.global_position = Vector2(700.0, 960.0)
	player.debug_aim = Vector2.UP
	await get_tree().physics_frame
	await get_tree().physics_frame
	var open_before: float = target.health.current
	if holder != null:
		holder.debug_fire_once()
	await _wait_seconds(0.6)
	print("[probe] same shot with a clear line: enemy hp %.0f -> %.0f (expected a hit)" % [
		open_before, target.health.current,
	])

	wall.queue_free()
	target.queue_free()


#endregion


#region search

## A spare enemy, held in a state that stands still, so a test can drive it deliberately.
func _spawn_test_enemy(at: Vector2) -> Enemy:
	var level: Node = GameDirector.current_level
	var enemy := (load("res://src/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	level.add_child(enemy)
	enemy.global_position = at
	# Registered with the level the same way `debug_spawn_enemy` does, so it shows up in the debug
	# readout and counts as alive.
	var list: Variant = level.get("enemies")
	if list is Array:
		(list as Array).append(enemy)
	enemy.state = Enemy.State.RETURN
	enemy.returns_to_post = false
	# A post it can never reach, so it does not wander off while a test measures it.
	enemy.post = Vector2(99999.0, 99999.0)
	return enemy


func _report_search() -> void:
	var level: Node = GameDirector.current_level
	if level == null:
		return
	var found: int = 0
	for node: Node in _all_nodes(level):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead():
			continue
		found += 1
		var heading: Vector2 = enemy.last_seen_heading
		# The budget only means anything while searching: a patrolling enemy has no last-seen time.
		var budget: String = "%.0f" % enemy.search_budget() if enemy.state == Enemy.State.SEARCH else "-"
		print("[probe]   %s %s  last_known %s  target %s  budget %s  visited %d  heading %s" % [
			enemy.archetype_id, Enemy.STATE_NAMES[enemy.state], str(Vector2i(enemy.last_known)),
			str(Vector2i(enemy.get("_search_target"))), budget,
			(enemy.get("_searched") as Dictionary).size(),
			str(Vector2i(heading)) if heading != Vector2.ZERO else "-",
		])
	if found == 0:
		print("[probe]   no enemies")


## Can an enemy get past an *open* door? Its leaf is solid and stands in the room, and the navmesh has
## never heard of it, so the straight path runs through the leaf. This is the reported bug: the enemy
## walked into the open door and stopped.
func _door_avoid_test() -> void:
	var level: Node = GameDirector.current_level
	var player := GameDirector.valid_player()
	if level == null or player == null:
		print("[probe] door avoid: no level or player")
		return

	# A door in a walled doorway, which is where "can't get around it" actually bites: there is a wall on
	# one side, so the enemy cannot simply slide past the leaf's free end.
	var left := _spawn_test_wall(Vector2(500.0, 1200.0), Vector2(200.0, 32.0))
	var right := _spawn_test_wall(Vector2(796.0, 1200.0), Vector2(200.0, 32.0))
	var door := _spawn_test_door(Vector2(648.0, 1200.0), false, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_bake_navmesh_runtime()
	await _wait_seconds(0.8)

	# Flush against the door: the leaf's top edge is y=1184, so this is within interact range.
	player.global_position = Vector2(648.0, 1184.0 - Tuning.player_radius)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var opened: bool = player.interact_nearby()
	player.global_position = Vector2(288.0, 1560.0)
	await _wait_seconds(0.5)
	print("[probe] door avoid: opened=%s, door=%s; its leaf juts into the gap on one side" % [
		opened, _door_state_name(door.state),
	])

	# Walk from above the wall to below it on the *hinge* side, so the straight line through the doorway
	# runs into the leaf rather than through the clear half of the gap. That is the case where the enemy
	# has to realise it must go around.
	var subject := _spawn_test_enemy(Vector2(604.0, 1080.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	subject.call("_enter_search")
	subject.last_known = Vector2(604.0, 1340.0)
	subject.set("_search_target", Vector2(604.0, 1340.0))

	var passed: bool = false
	var elapsed: float = 0.0
	while elapsed < 8.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if subject.global_position.y > 1300.0:
			passed = true
			break
	print("[probe] door avoid: enemy got through the doorway past the open leaf: %s  (at %s, %.1fs)" % [
		passed, str(Vector2i(subject.global_position)), elapsed,
	])

	if _probe_region != null and is_instance_valid(_probe_region):
		_probe_region.queue_free()
		_probe_region = null
	left.queue_free()
	right.queue_free()

	subject.queue_free()
	door.queue_free()


## Does the walk ever ask for somewhere an enemy cannot stand? Fuzzed over many picks, because the
## failure is intermittent: it depends on where the rings happen to fall relative to the walls.
func _search_target_test() -> void:
	var level: Node = GameDirector.current_level
	if level == null:
		print("[probe] search targets: no level")
		return
	# This level has no baked mesh of its own, and the whole point is what the *mesh* says, so bake one
	# for the test. The agent picks it up within its nav-check interval.
	_bake_navmesh_runtime()
	await _wait_seconds(0.8)

	var subject := _spawn_test_enemy(Vector2(520.0, 700.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	subject.last_seen_heading = Vector2.RIGHT
	# A wide budget, so the rings reach plenty of wall.
	subject.set("_last_seen", float(subject.get("_time")) - 8.0)
	subject.call("_enter_search")

	var walls: Array[Wall] = []
	for node: Node in _all_nodes(level):
		var wall := node as Wall
		if wall != null:
			walls.append(wall)
	var map: RID = subject.agent.get_navigation_map() if subject.agent != null else RID()

	var picks: int = 0
	var in_wall: int = 0
	var off_mesh: int = 0
	for i: int in 400:
		subject.call("_pick_search_target")
		var target: Vector2 = subject.get("_search_target")
		picks += 1
		for wall: Wall in walls:
			if wall.world_rect().has_point(target):
				in_wall += 1
				break
		if map.is_valid():
			var closest: Vector2 = NavigationServer2D.map_get_closest_point(map, target)
			if closest.distance_to(target) > 8.0:
				off_mesh += 1
	print("[probe] search targets over %d picks: inside a wall=%d  off the mesh=%d  (both must be 0)" % [
		picks, in_wall, off_mesh,
	])

	# Control: how many ring candidates sit inside a wall *and* within 40px of the mesh, which is
	# exactly what the old "a path ends within 40px" rule accepted. Non-zero means this geometry does
	# reproduce the reported bug, so the zero above is a fix rather than a test that cannot fail.
	var would_accept: int = 0
	for ring: int in range(1, 8):
		var radius: float = Enemy.SEARCH_STEP * float(ring)
		for i: int in 24:
			var point: Vector2 = subject.last_known + Vector2.from_angle(
				TAU * float(i) / 24.0) * radius
			var inside: bool = false
			for wall: Wall in walls:
				if wall.world_rect().has_point(point):
					inside = true
					break
			if not inside or not map.is_valid():
				continue
			var closest: Vector2 = NavigationServer2D.map_get_closest_point(map, point)
			if closest.distance_to(point) <= 40.0:
				would_accept += 1
	print("[probe]   control: wall points the old 40px rule would have accepted: %d" % would_accept)
	subject.queue_free()


## The tier-0 search, measured rather than eyeballed: how wide it is, which way it looks, whether its
## targets are actually walkable, whether it follows the player through a shut door, and what it does
## at a locked one. Leaves the last subject searching near the player, so the debug view can be
## photographed.
func _search_tests() -> void:
	var level: Node = GameDirector.current_level
	var player := GameDirector.valid_player()
	if level == null or player == null:
		print("[probe] search: no level or player")
		return
	# Clear the field first. This scenario is about what one searcher does, and a firefight next door
	# fills the air with noise that keeps re-alerting the subject through `_on_noise`.
	var existing: Variant = level.get("enemies")
	if existing is Array:
		for entry: Variant in (existing as Array):
			var other := entry as Enemy
			if other != null and is_instance_valid(other):
				other.queue_free()
	await get_tree().physics_frame
	# Park the player away and point their light away, so nothing here is interrupted by being seen.
	var home: Vector2 = player.global_position
	player.global_position = Vector2(288.0, 1560.0)
	player.debug_aim = Vector2.DOWN
	await get_tree().physics_frame

	var subject := _spawn_test_enemy(Vector2(520.0, 760.0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	# --- how far it is willing to look, as the trail goes cold
	var now: float = float(subject.get("_time"))
	for age: float in [1.0, 8.0, 20.0]:
		subject.set("_last_seen", now - age)
		print("[probe] search budget after %.0fs: %.0f px" % [age, subject.search_budget()])

	# --- which way it looks first
	subject.last_known = subject.global_position
	subject.last_seen_heading = Vector2.UP
	subject.set("_searched", {})
	subject.set("_search_ring", 1)
	subject.call("_pick_search_target")
	var target: Vector2 = subject.get("_search_target")
	var to_target: Vector2 = target - subject.last_known
	var off_heading: float = absf(rad_to_deg(wrapf(Vector2.UP.angle_to(to_target), -PI, PI)))
	print("[probe] first target %.0f px away, %.0f deg off the player's last heading" % [
		to_target.length(), off_heading,
	])

	# --- targets it cannot walk to are skipped
	print("[probe] walkable: open floor=%s  inside a wall=%s" % [
		subject.call("_can_walk_to", subject.global_position + Vector2(80.0, 0.0)),
		subject.call("_can_walk_to", Vector2(32.0, 500.0)),
	])

	# --- a shut door between it and the trail must be opened and walked through
	var shut_door := _spawn_test_door(Vector2(520.0, 700.0), false, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	subject.last_known = Vector2(520.0, 620.0)
	subject.last_seen_heading = Vector2.UP
	subject.call("_enter_search")
	# Sampling matters: a lone door stands in open floor, so "it got past the door" could mean it
	# walked around it. Passing *through the door's own footprint* while it is open is the claim.
	var followed: Dictionary = await _watch_search(subject, shut_door, 1.8)
	print("[probe] shut door: opened=%s  passed through the doorway=%s  state=%s" % [
		followed["opened"], followed["through"], Enemy.STATE_NAMES[subject.state],
	])

	# --- a locked door: rattled, kept closed, and the search carries on elsewhere
	var locked_door := _spawn_test_door(Vector2(760.0, 700.0), true, 0.0)
	var blocked := _spawn_test_enemy(Vector2(760.0, 760.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	blocked.last_known = Vector2(760.0, 620.0)
	blocked.last_seen_heading = Vector2.UP
	blocked.call("_enter_search")
	var start: Vector2 = blocked.global_position
	await _wait_seconds(1.8)
	print("[probe] locked door: door=%s  state=%s  moved %.0f px  visited %d" % [
		_door_state_name(locked_door.state), Enemy.STATE_NAMES[blocked.state],
		blocked.global_position.distance_to(start),
		(blocked.get("_searched") as Dictionary).size(),
	])

	# --- a swinging door must not shove an enemy standing where the leaf lands
	var push_door := _spawn_test_door(Vector2(1040.0, 700.0), false, 0.0)
	var pushed := _spawn_test_enemy(Vector2(992.0, 756.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var before: Vector2 = pushed.global_position
	push_door.open_for_enemy(pushed)
	await _wait_seconds(0.8)
	print("[probe] door swung onto an enemy: moved %.1f px (expected 0)" % [
		pushed.global_position.distance_to(before),
	])

	# Clean up everything except the last subject, then frame it for the screenshot.
	shut_door.queue_free()
	locked_door.queue_free()
	push_door.queue_free()
	pushed.queue_free()
	blocked.queue_free()
	# Frame the debug view: the player stands *behind* the searcher so it keeps searching instead of
	# spotting them, and the camera therefore has the search in shot.
	# South of the camera, not north of it: the player sits above centre on screen, so a search
	# placed "ahead" of them lands outside the frame.
	player.global_position = Vector2(760.0, 900.0)
	player.debug_aim = Vector2.UP
	subject.global_position = Vector2(760.0, 1000.0)
	subject.last_known = Vector2(760.0, 1180.0)
	subject.last_seen_heading = Vector2.DOWN
	subject.call("_enter_search")
	# Awareness is a separate meter: left at 1.0 from the tests above, the next perception tick would
	# put the subject straight back into ALERT and there would be nothing to photograph.
	subject.awareness = 0.0
	await get_tree().physics_frame


## Watch an enemy for `seconds` and report whether the door it was heading for ever opened, and
## whether the enemy ever occupied the doorway itself. The second is the one that proves it followed
## the player through rather than walking around a door standing on open floor.
func _watch_search(enemy: Enemy, door: Door, seconds: float) -> Dictionary:
	var opened: bool = false
	var through: bool = false
	var elapsed: float = 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if not is_instance_valid(door) or not is_instance_valid(enemy):
			break
		if door.state == Door.State.OPEN:
			opened = true
		if door.contains_point(enemy.global_position):
			through = true
	return {"opened": opened, "through": through}


func _wait_seconds(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0

#endregion


#region surfaces

## What the level's surface dropdowns actually resolved to, and whether each wall got a real material.
## A style that fails to apply leaves flat colour behind, which is easy to mistake for "the look I
## picked" in a dark screenshot.
func _report_surfaces() -> void:
	var level: Node = GameDirector.current_level
	if level == null:
		print("[probe]   no level")
		return
	var wall_id: String = String(level.get("wall_surface_id"))
	var floor_id: String = String(level.get("floor_surface_id"))
	print("[probe]   level surfaces: walls='%s' floor='%s'" % [wall_id, floor_id])
	var floor_node := level.get_node_or_null("Floor") as Polygon2D
	print("[probe]   floor node: %s" % ("none" if floor_node == null else
		"visible=%s tiled=%s" % [floor_node.visible, floor_node.material is ShaderMaterial]))
	var textured: int = 0
	var flat: int = 0
	for node: Node in _all_nodes(level):
		var wall := node as Wall
		if wall == null:
			continue
		var body := wall.get_node_or_null("Body") as Polygon2D
		if body != null and body.material is ShaderMaterial:
			textured += 1
		else:
			flat += 1
	print("[probe]   walls: %d textured, %d flat" % [textured, flat])
	# One wall's material in detail: a style that silently fails to reach the shader looks exactly like
	# a style nobody picked.
	for node: Node in _all_nodes(level):
		var wall := node as Wall
		if wall == null:
			continue
		var body := wall.get_node_or_null("Body") as Polygon2D
		if body == null or not (body.material is ShaderMaterial):
			continue
		var material := body.material as ShaderMaterial
		print("[probe]   sample wall '%s': shader=%s tint=%s tile=%s size=%s body_color=%s" % [
			wall.name, material.shader.resource_path.get_file(),
			str(material.get_shader_parameter("tint")),
			str(material.get_shader_parameter("tile_world")),
			str(material.get_shader_parameter("size_world")),
			str(body.color),
		])
		break

#endregion


#region doors

## Puts a door in the level at `player + offset`, rotated `rotation` radians. Runtime-only, so
## the door behaviour can be tested without editing a level file.
func _spawn_test_door(at: Vector2, locked: bool, rotation: float) -> Door:
	var player := GameDirector.valid_player()
	if player == null:
		print("[probe] door: no player")
		return null
	var parent: Node = GameDirector.spawn_parent()
	var door := (load("res://src/levels/door.tscn") as PackedScene).instantiate() as Door
	door.starts_locked = locked
	door.rotation = rotation
	door.name = "TestDoor%d" % _door_counter
	_door_counter += 1
	parent.add_child(door)
	door.global_position = at
	print("[probe] spawned door at %s locked=%s rotation=%.0f deg" % [
		str(Vector2i(door.global_position)), locked, rad_to_deg(rotation)])
	return door


func _report_doors() -> void:
	var level: Node = GameDirector.current_level
	if level == null:
		return
	var player := GameDirector.valid_player()
	var found: int = 0
	for node: Node in _all_nodes(level):
		var door := node as Door
		if door == null:
			continue
		found += 1
		var collision := door.find_child("Collision", true, false) as CollisionShape2D
		var occluder := door.find_child("Occluder", true, false) as LightOccluder2D
		# The leaf itself is always solid and always shadows: it is a physical object in the room,
		# open or shut. What changes with the state is whether the *doorway* is clear, and which layer
		# the leaf is on: WORLD stops everything, DOOR stops everything except enemy movement.
		var solid := door.find_child("Solid", true, false) as StaticBody2D
		var layer_text: String = "0"
		if solid != null:
			layer_text = "WORLD" if solid.collision_layer == Layers.WORLD else "DOOR"
		var blocked: bool = door.is_shut()
		var shadow: bool = occluder != null and occluder.occluder_light_mask != 0
		var sight: String = "clear" if _sight_clear_through(door) else "blocked"
		var leaf_sight: String = "clear" if _sight_clear_across_leaf(door) else "blocked"
		# The hinge is the leaf's own origin; the free edge is the far end of the panel. If the
		# hinge moves when the door opens, the leaf is spinning about its centre instead of
		# swinging from its edge, which is exactly the bug this line exists to catch.
		var leaf := door.get_node_or_null("Leaf") as Node2D
		var hinge: Vector2 = leaf.global_position if leaf != null else door.global_position
		var free: Vector2 = leaf.to_global(Vector2(door.size.x, 0.0)) if leaf != null else hinge
		# Exempt actors are the ones this leaf may swing over instead of shoving. Naming the player
		# separately keeps the "no nudge" assertion readable.
		var exempt_list: Variant = door.get("_exempt")
		var exempt_count: int = (exempt_list as Array).size() if exempt_list is Array else 0
		var player_exempt: bool = exempt_list is Array and player != null \
			and (exempt_list as Array).has(player)
		print("[probe]   door %s state=%s locked=%s layer=%s doorway=%s shadows=%s sight=%s exempt=%d player_exempt=%s dist=%d" % [
			door.name, _door_state_name(door.state), door.locked, layer_text,
			"blocked" if blocked else "clear", shadow, sight,
			exempt_count, player_exempt,
			int(door.global_position.distance_to(player.global_position)) if player != null else -1,
		])
		print("[probe]     hinge %s (%.0f px from centre)  free edge %s  leaf sight=%s" % [
			str(Vector2i(hinge)), hinge.distance_to(door.global_position), str(Vector2i(free)),
			leaf_sight,
		])
	if found == 0:
		print("[probe]   no doors in the level")
	# The player must still collide with an open leaf, even though enemies do not.
	if player != null:
		print("[probe]   player collides with door leaves: %s  (mask %d, DOOR bit %d)" % [
			(player.collision_mask & Layers.DOOR) != 0, player.collision_mask, Layers.DOOR,
		])
	# A smashed door is removed from the level, not left lying in the doorway.
	if _dashed_door_name != "":
		var still_there: bool = false
		for node: Node in _all_nodes(level):
			if String(node.name) == _dashed_door_name:
				still_there = true
				break
		print("[probe]   dashed door '%s' still in the level: %s" % [
			_dashed_door_name, still_there,
		])


func _door_state_name(state: Door.State) -> String:
	match state:
		Door.State.OPEN:
			return "OPEN"
		Door.State.BROKEN:
			return "BROKEN"
		_:
			return "CLOSED"


## Whether an enemy standing on one side of the door could see a point on the other side. This is
## the raycast `Enemy._can_see` uses, so it answers the gameplay question rather than a proxy.
func _sight_clear_through(door: Door) -> bool:
	var space: PhysicsDirectSpaceState2D = door.get_world_2d().direct_space_state
	if space == null:
		return true
	# Across the doorway, i.e. through the leaf's thickness: that is the line of sight a shut door
	# is supposed to take away.
	var axis: Vector2 = Vector2.UP.rotated(door.rotation)
	var from: Vector2 = door.global_position - axis * 120.0
	var to: Vector2 = door.global_position + axis * 120.0
	var query := PhysicsRayQueryParameters2D.create(from, to, Layers.SOLID)
	query.hit_from_inside = false
	return space.intersect_ray(query).is_empty()


## Whether the leaf itself still blocks sight where it currently is. Cast across the panel's
## thickness, so it is the same test whether the door is shut (leaf in the doorway) or open (leaf in
## the room). This is the "you can hide behind an open door" property.
func _sight_clear_across_leaf(door: Door) -> bool:
	var leaf := door.get_node_or_null("Leaf") as Node2D
	if leaf == null:
		return true
	var space: PhysicsDirectSpaceState2D = door.get_world_2d().direct_space_state
	if space == null:
		return true
	# Middle of the panel, and the leaf's own up axis is its thickness when shut.
	var centre: Vector2 = leaf.to_global(Vector2(door.size.x * 0.5, 0.0))
	var normal: Vector2 = Vector2.DOWN.rotated(leaf.global_rotation)
	# Sight blockers, not movement blockers: an open leaf is see-through-proof but not walk-proof, which
	# is exactly the asymmetry `Layers.DOOR` exists for.
	var query := PhysicsRayQueryParameters2D.create(centre - normal * 60.0, centre + normal * 60.0,
		Layers.SIGHT_BLOCKERS)
	query.hit_from_inside = false
	return space.intersect_ray(query).is_empty()


func _add_test_keys(count: int) -> void:
	var player := GameDirector.valid_player()
	if player == null:
		return
	player.add_key(count)
	print("[probe] player now carries %d key(s)" % player.keys)


## Self-contained: spawns its own door and enemy, so it cannot be thrown off by whatever earlier
## steps did to the level. Waits a physics frame first: a body created this frame is not visible
## to `intersect_point` until the server has ticked, which made the first version of this test
## report "closed" no matter what.
func _enemy_open_test() -> void:
	var player := GameDirector.valid_player()
	if player == null:
		print("[probe] enemy door test: no player")
		return
	var door := _spawn_test_door(player.global_position + Vector2(0.0, -180.0), false, 0.0)
	if door == null:
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	var level: Node = GameDirector.current_level
	var enemy := (load("res://src/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	level.add_child(enemy)
	await get_tree().physics_frame
	# Approaching through the doorway (across the leaf's thickness), which is what `_handle_doors`
	# looks for: a shut door just ahead of its own velocity.
	enemy.global_position = door.global_position - Vector2(0.0, 46.0).rotated(door.rotation)
	enemy.velocity = Vector2(0.0, 120.0).rotated(door.rotation)
	enemy.call("_handle_doors")
	print("[probe] enemy walked at the door: state=%s (expected OPEN)" % _door_state_name(door.state))
	# Once clearly past, it shuts the door behind itself.
	enemy.global_position = door.global_position + Vector2(0.0, 150.0).rotated(door.rotation)
	door.close_if_enemy_clear(enemy)
	print("[probe] enemy moved on: state=%s (expected CLOSED)" % _door_state_name(door.state))
	enemy.queue_free()
	door.queue_free()


## The shut door nearest the player: what a dash test should be aimed at.
func _nearest_shut_door() -> Door:
	var player := GameDirector.valid_player()
	var level: Node = GameDirector.current_level
	if level == null or player == null:
		return null
	var best: Door = null
	var best_distance: float = INF
	for node: Node in _all_nodes(level):
		var door := node as Door
		if door == null or not door.is_shut():
			continue
		var distance: float = door.surface_distance(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = door
	return best


func _dash_at_newest_door() -> void:
	var player := GameDirector.valid_player()
	var door := _nearest_shut_door()
	if player == null or door == null:
		print("[probe] dash: no shut door near the player")
		return
	# Stand back from the door and dash straight into it, so the hit comes from a real
	# `move_and_slide` collision rather than from calling smash() directly.
	var towards: Vector2 = (door.global_position - player.global_position)
	if towards.length() < 1.0:
		towards = Vector2.RIGHT.rotated(door.rotation)
	player.debug_dash(towards.normalized())
	_dashed_door_name = String(door.name)
	print("[probe] dashing at the door '%s' from %d px away" % [
		_dashed_door_name, int(towards.length()),
	])


## Records every noise broadcast, so tests can assert on how loud an action was. In order: the
## radius and whether it was heard at the door.
var _noise_log: Array[Dictionary] = []
var _noise_connected: bool = false
## Names test doors TestDoor0, TestDoor1... so a report reads like a test, not like a dump.
var _door_counter: int = 0
## The last door a dash was aimed at, by name: a smash removes it, so the name is the only handle
## that outlives it.
var _dashed_door_name: String = ""
## Announcements, so a test can assert that an action is *silent* rather than merely harmless.
var _announce_log: Array[String] = []
var _announce_connected: bool = false


func _connect_noise_log() -> void:
	if _noise_connected:
		return
	GameDirector.noise_made.connect(_on_noise_made)
	_noise_connected = true


func _on_noise_made(position: Vector2, radius: float, _source: Node) -> void:
	_noise_log.append({"position": position, "radius": radius})
	if _noise_log.size() > 40:
		_noise_log.remove_at(0)


func _connect_announce_log() -> void:
	if _announce_connected:
		return
	GameDirector.announce.connect(_on_announce)
	_announce_connected = true


func _on_announce(text: String, _color: Color) -> void:
	_announce_log.append(text)
	if _announce_log.size() > 20:
		_announce_log.remove_at(0)


func _report_announce() -> void:
	if _announce_log.is_empty():
		print("[probe]   announced: nothing")
		return
	print("[probe]   announced: %s" % " / ".join(_announce_log))


func _report_noise(tail: int = 8) -> void:
	if _noise_log.is_empty():
		print("[probe]   no noise recorded")
		return
	var start: int = maxi(0, _noise_log.size() - tail)
	for i: int in range(start, _noise_log.size()):
		var entry: Dictionary = _noise_log[i]
		print("[probe]   noise #%d radius %.0f at %s" % [
			i, entry["radius"], str(Vector2i(entry["position"])),
		])

#endregion


#region menus

func _menu_lists() -> Array[MenuList]:
	var out: Array[MenuList] = []
	for node: Node in _all_nodes(get_tree().root):
		var menu := node as MenuList
		if menu != null and menu.is_visible_in_tree():
			out.append(menu)
	return out


## What the menus offer and where focus is. An open menu with no focused item cannot be driven
## from the keyboard at all, which is invisible in a screenshot.
func _report_menus() -> void:
	var menus: Array[MenuList] = _menu_lists()
	var settings_menus: Array[SettingsMenu] = []
	for node: Node in _all_nodes(get_tree().root):
		var settings := node as SettingsMenu
		if settings != null:
			settings_menus.append(settings)
	if menus.is_empty() and settings_menus.is_empty():
		print("[probe]   no menu open")
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	var focus_text: String = "-"
	if focus is Button:
		focus_text = (focus as Button).text
	for menu: MenuList in menus:
		var parts: Array[String] = []
		for i: int in menu.item_count():
			parts.append("%s%s" % [
				menu.item_text(i), "" if menu.item_enabled(i) else " (disabled)",
			])
		print("[probe]   menu [%s]  focused=%s" % [" | ".join(parts), focus_text])
	for settings: SettingsMenu in settings_menus:
		print("[probe]   settings menu (rect %s)" % str(settings.get_global_rect()))


## Programmatic activation: reliable, but it bypasses the GUI, so it does not prove a menu is
## clickable. `_click_menu_item` is the one that proves that.
func _activate_menu_item(id: String) -> void:
	for menu: MenuList in _menu_lists():
		if menu.activate(StringName(id)):
			print("[probe] activated menu item '%s'" % id)
			return
	print("[probe] menu item '%s' not found, or disabled" % id)


## A synthetic click, which goes through the viewport's GUI hit-testing and only then reaches
## the button. Worth testing explicitly: a paused SceneTree is exactly the situation where
## Controls stop responding to the mouse.
func _click_menu_item(id: String) -> void:
	var target: Button = null
	for menu: MenuList in _menu_lists():
		var button := menu.button_for(StringName(id))
		if button != null and not button.disabled:
			target = button
			break
	if target == null:
		print("[probe] cannot click '%s': no such enabled item" % id)
		return
	var centre: Vector2 = target.get_global_rect().get_center()
	_send_mouse(centre, true)
	_send_mouse(centre, false)
	print("[probe] clicked '%s' at %s" % [id, str(centre)])


## A real key event. `Input.action_press` only ticks the input state and never reaches a
## focused Control, so it cannot test a menu activated by Space or Enter.
func _send_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _send_mouse(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)


func _close_settings_menus() -> void:
	var closed: int = 0
	for node: Node in _all_nodes(get_tree().root):
		var menu := node as SettingsMenu
		if menu != null:
			menu.close()
			closed += 1
	print("[probe] closed %d settings menu(s)" % closed)


func _backup_progress() -> void:
	_progress_existed = Progress.file_exists()
	_progress_backup = PackedByteArray()
	if _progress_existed:
		_progress_backup = FileAccess.get_file_as_bytes(GameProgress.PATH)
	print("[probe] progress backed up (existed: %s)" % _progress_existed)


## Puts the checkpoint back exactly as it was found, and reports whether the file really is
## gone again. Reporting it matters: a silent failure here leaves a test-made save behind.
func _restore_progress() -> void:
	if _progress_existed:
		var file := FileAccess.open(GameProgress.PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_progress_backup)
			file.close()
		Progress.load_progress()
	else:
		Progress.clear()
	print("[probe] progress file after restore: exists=%s (existed before: %s)" % [
		Progress.file_exists(), _progress_existed,
	])


## Every pickup in the level, with the thing that decides whether it can be collected at all: a
## collision shape and the pickup/player layers. Loot that renders but has `shape=false` is the
## exact failure this test exists to catch.
func _report_pickups() -> void:
	var level: Node = GameDirector.current_level
	if level == null or not is_instance_valid(level):
		print("[probe]   no level")
		return
	var player := GameDirector.valid_player()
	var found: int = 0
	for node: Node in _all_nodes(level):
		var pickup := node as Pickup
		if pickup == null:
			continue
		found += 1
		var collision := pickup.get_node_or_null("Collision") as CollisionShape2D
		var shape_ok: bool = collision != null and collision.shape != null
		var distance: int = int(pickup.global_position.distance_to(player.global_position)) \
			if player != null else -1
		var drop: String = pickup.weapon_id if pickup.kind == "weapon" else "-"
		print("[probe]   pickup kind=%s drop=%s shape=%s layer=%d mask=%d dist=%d" % [
			pickup.kind, drop, shape_ok, pickup.collision_layer, pickup.collision_mask, distance,
		])
	if found == 0:
		print("[probe]   no pickups left in the level")


## Kill an enemy that drops a weapon, while standing where the loot will land. A shotgun is
## preferred: the player does not start with one, so "the shotgun is in the slots" proves a real
## pickup rather than an ammo top-up.
func _loot_kill() -> void:
	var level: Node = GameDirector.current_level
	if level == null or not is_instance_valid(level):
		print("[probe] loot: no level")
		return
	var player := GameDirector.valid_player()
	if player == null:
		print("[probe] loot: no player")
		return
	var list: Variant = level.get("enemies")
	if list == null:
		print("[probe] loot: level has no enemy list")
		return
	var target: Enemy = null
	for entry: Variant in (list as Array):
		var enemy := entry as Enemy
		if enemy == null or enemy.is_dead():
			continue
		var drop: String = String(enemy.archetype.drop_weapon)
		if drop.is_empty():
			continue
		# Keep looking for a shotgun; otherwise take the first dropper.
		if target == null or drop == "shotgun":
			target = enemy
		if drop == "shotgun":
			break
	if target == null:
		print("[probe] loot: no enemy in this level drops a weapon")
		return
	print("[probe] loot: killing %s which drops '%s'" % [
		target.archetype_id, target.archetype.drop_weapon])
	player.global_position = target.global_position
	target.take_hit(1000.0, player, target.global_position, Vector2.RIGHT, 0.0)


func _report_progress() -> void:
	print("[probe] progress: has=%s file=%s level=%s title='%s' loadout_slots=%d" % [
		Progress.has_progress(), Progress.file_exists(), Progress.level_path,
		Progress.level_title, Progress.loadout.size(),
	])


func _report_scene() -> void:
	var scene: Node = get_tree().current_scene
	print("[probe] current scene: %s" % (scene.scene_file_path if scene != null else "(none)"))

#endregion


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
	_connect_noise_log()
	_connect_announce_log()
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
			if step.has("select_weapon"):
				var holder = player.weapons
				if holder != null:
					holder.select(int(step["select_weapon"]))
			if step.has("set_abilities"):
				var ability_holder = player.abilities
				if ability_holder != null:
					ability_holder.slots.clear()
					for ability_id: String in step["set_abilities"]:
						ability_holder.add_ability(ability_id)
			if step.has("ability_target") or step.has("ability_target_at_enemy"):
				# Scripted casts need a deterministic target, since the real one is
				# wherever the mouse happens to be.
				var aimed_holder = player.abilities
				if aimed_holder != null:
					if step.has("ability_target"):
						aimed_holder.debug_target = step["ability_target"]
					else:
						var aim_target: Enemy = _nearest_enemy(player.global_position)
						if aim_target != null:
							aimed_holder.debug_target = aim_target.global_position
			else:
				var plain_holder = player.abilities
				if plain_holder != null:
					plain_holder.debug_target = Vector2.INF
			if step.has("cast_ability"):
				var casting_holder = player.abilities
				if casting_holder != null:
					var cast: bool = casting_holder.use_ability(int(step["cast_ability"]))
					print("[probe] cast ability %d -> %s" % [int(step["cast_ability"]), cast])
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
		if step.has("window_size"):
			# Resizing at runtime is the honest test: everything has to adapt while the game
			# is already running, which is exactly what the settings menu does.
			var size: Vector2i = step["window_size"]
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(size)
		if step.has("open_settings"):
			var title: Node = get_tree().current_scene
			if title != null and title.has_method("open_settings"):
				title.call("open_settings")
		if step.has("toggle_pause") and bool(step["toggle_pause"]):
			GameDirector.toggle_pause()
		# (`press_settings` used to live here. The settings keybind is gone, so there is nothing
		# to press: both menus open settings through `MenuList` now.)
		if step.has("settings_roundtrip"):
			_report_settings_roundtrip()
		# Backed up first: the clear below would otherwise destroy a real player's checkpoint.
		if step.has("backup_progress"):
			_backup_progress()
		if step.has("loot_kill"):
			_loot_kill()
		if step.has("search_tests"):
			await _search_tests()
		if step.has("point_blank_test"):
			await _point_blank_test()
		if step.has("doorway_test"):
			await _doorway_test()
		if step.has("door_avoid_test"):
			await _door_avoid_test()
		if step.has("search_target_test"):
			await _search_target_test()
		if step.has("clear_noise"):
			_noise_log.clear()
		if step.has("clear_announce"):
			_announce_log.clear()
		if step.has("spawn_door"):
			var spec: Dictionary = step["spawn_door"]
			_spawn_test_door(spec.get("at", Vector2.ZERO), bool(spec.get("locked", false)),
				float(spec.get("rotation", 0.0)))
		if step.has("add_keys"):
			_add_test_keys(int(step["add_keys"]))
		if step.has("interact_door"):
			var who := GameDirector.valid_player()
			if who != null:
				print("[probe] interact -> %s" % who.interact_nearby())
		if step.has("dash_at_door"):
			_dash_at_newest_door()
		if step.has("enemy_door_test"):
			await _enemy_open_test()
		if step.has("clear_progress"):
			Progress.clear()
			print("[probe] progress cleared (file still exists: %s)" % Progress.file_exists())
		if step.has("restore_progress"):
			_restore_progress()
		if step.has("menu_activate"):
			_activate_menu_item(String(step["menu_activate"]))
		if step.has("menu_click"):
			_click_menu_item(String(step["menu_click"]))
			# A synthesised click needs a frame to travel through the GUI before it lands.
			await get_tree().process_frame
			await get_tree().process_frame
		if step.has("press_space"):
			# Space on the title screen, on reflex: activates whatever is focused.
			_send_key(KEY_SPACE, true)
			await get_tree().process_frame
			_send_key(KEY_SPACE, false)
			await get_tree().process_frame
			await get_tree().process_frame
			print("[probe] pressed Space (activates the focused menu item)")
		if step.has("close_menus"):
			_close_settings_menus()
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
				Input.action_press(&"fire")
				await get_tree().create_timer(duration).timeout
				Input.action_release(&"fire")
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
		if step.has("ability_effects"):
			_report_ability_effects()
		if step.has("presentation"):
			_report_presentation()
		if step.has("settings_menu_report"):
			_report_settings_menu()
		if step.has("menu_report"):
			_report_menus()
		if step.has("progress_report"):
			_report_progress()
		if step.has("loot_report"):
			_report_pickups()
		if step.has("door_report"):
			_report_doors()
		if step.has("search_report"):
			_report_search()
		if step.has("surface_report"):
			_report_surfaces()
		if step.has("set_wall_surface"):
			var lit_level := GameDirector.current_level
			if lit_level != null:
				lit_level.set("wall_surface_id", String(step["set_wall_surface"]))
				print("[probe] wall surface -> '%s'" % step["set_wall_surface"])
		if step.has("doorway_report"):
			_report_doorway_routes()
		if step.has("noise_report"):
			_report_noise()
		if step.has("announce_report"):
			_report_announce()
		if step.has("scene_report"):
			_report_scene()
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
	var abilities = player.abilities
	if abilities != null:
		if abilities.slots.is_empty():
			print("[probe]   no abilities")
		for i: int in abilities.slots.size():
			var ability_slot = abilities.slots[i]
			print("[probe]   ability %d  %-14s cooldown %.1f/%.1f  level %d" % [
				i, ability_slot.data.id, ability_slot.cooldown_left, ability_slot.cooldown(),
				ability_slot.level,
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
	var key_count: int = 0
	var who := GameDirector.valid_player()
	if who != null:
		key_count = who.keys
	print("[probe] kills %d  shots %d  alerts %d  keys %d" % [
		GameDirector.kills, GameDirector.shots_fired, GameDirector.enemies_alerted, key_count,
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


## Lists the ability effects alive in the level and what they are made of. A fire wall
## should report a solid body and a light occluder; a tempest neither.
func _report_ability_effects() -> void:
	var parent: Node = GameDirector.spawn_parent()
	if parent == null:
		return
	var found: int = 0
	for node: Node in _all_nodes(parent):
		var effect := node as AbilityEffect
		if effect == null:
			continue
		found += 1
		print("[probe]   effect %-18s solid=%s occludes=%s field=%s  life_left=%.2f" % [
			effect.get_script().resource_path.get_file(),
			effect.find_child("Solid", true, false) != null,
			effect.find_child("Occluder", true, false) != null,
			effect.find_child("Field", true, false) != null,
			effect.remaining_fraction(),
		])
	if found == 0:
		print("[probe]   no ability effects alive")


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
