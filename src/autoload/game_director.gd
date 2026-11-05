extends Node
## Run state, level flow, and the debug toggles.
##
## This is the only node that knows about the *sequence* of levels. Individual
## levels only know "what comes next" (via their export), so adding a level never
## requires touching this file.

signal run_started()
signal level_started(level: Node)
signal game_over(reason: String)
signal game_won()
signal announce(text: String, color: Color)
signal reveal_changed(revealed: bool)
## Anything that makes a sound the AI could hear (gunshots, dashes, footsteps). `type` is a
## `NoiseKind.Type`: what the sound means, which is what decides how enemies react to it.
signal noise_made(position: Vector2, radius: float, source: Node, type: NoiseKind.Type)

const TITLE_SCENE: String = "res://src/ui/title_screen.tscn"
const FIRST_LEVEL: String = "res://src/levels/level_campaign_01.tscn"

var current_level: Node = null
var player: Node2D = null

var run_active: bool = false
var run_time: float = 0.0
var kills: int = 0
var shots_fired: int = 0
var enemies_alerted: int = 0
var levels_cleared: int = 0
## Guards against reporting a win or a death twice. Deliberately NOT tied to
## `run_active`: launching a level directly from the editor should still show the
## death and victory screens.
var _outcome_reported: bool = false

var god_mode: bool = false
var noclip: bool = false
var debug_info: bool = false
var reveal: bool = false
## Weapons carried between levels. Each level spawns a fresh player, so the
## loadout is snapshotted on exit and restored on entry.
var carried_loadout: Array = []
## Keys carried between levels, for the same reason. Any key opens any locked door.
var carried_keys: int = 0

var _slowmo: bool = false


func _ready() -> void:
	# Must keep running while the tree is paused, so pause can be un-paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_maybe_spawn_dev_probe()


## Dev-only: `-- --probe=<scenario>` attaches the screenshot/probe harness to
## whatever scene is running. Inert otherwise.
func _maybe_spawn_dev_probe() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe"):
			var script := load("res://dev/probe.gd") as GDScript
			if script == null:
				return
			var probe: Node = script.new()
			probe.name = "DevProbe"
			get_tree().root.add_child.call_deferred(probe)
			return


func _process(delta: float) -> void:
	if run_active and not get_tree().paused:
		run_time += delta


#region flow

func start_run() -> void:
	# A new game forgets the checkpoint, so Continue cannot offer the run that was just
	# abandoned. The first level records a fresh one as soon as it loads.
	Progress.clear()
	run_active = true
	run_time = 0.0
	kills = 0
	shots_fired = 0
	enemies_alerted = 0
	levels_cleared = 0
	_outcome_reported = false
	carried_loadout = []
	carried_keys = 0
	god_mode = false
	noclip = false
	reveal = false
	debug_info = false
	run_started.emit()
	load_level(FIRST_LEVEL)


## Resume the recorded checkpoint: the level that was being played, with the loadout that was
## being carried. Falls back to a new run when there is nothing to continue from, so the
## button can never leave the player staring at the title screen.
func continue_run() -> void:
	if not Progress.has_progress():
		start_run()
		return
	var path: String = Progress.level_path
	run_active = true
	# Counters start over: this is a fresh attempt at that level, not a replay of the run.
	run_time = 0.0
	kills = 0
	shots_fired = 0
	enemies_alerted = 0
	levels_cleared = 0
	_outcome_reported = false
	god_mode = false
	noclip = false
	reveal = false
	debug_info = false
	# Copied, so continuing twice cannot alias the same array.
	carried_loadout = Progress.loadout.duplicate(true)
	carried_keys = Progress.carried_keys
	run_started.emit()
	load_level(path)


func load_level(path: String) -> void:
	get_tree().paused = false
	_set_slowmo(false)
	_outcome_reported = false
	if not ResourceLoader.exists(path):
		push_error("GameDirector: level scene not found: %s" % path)
		go_to_title()
		return
	# Deferred: exits call this from a physics callback, and swapping scenes in
	# the middle of one is not allowed.
	get_tree().call_deferred("change_scene_to_file", path)


func go_to_title() -> void:
	run_active = false
	run_time = 0.0
	get_tree().paused = false
	_set_slowmo(false)
	_outcome_reported = false
	# Deferred for the same reason as load_level: this can be reached from input
	# handling, and swapping scenes mid-callback leaves callers holding freed nodes.
	get_tree().call_deferred("change_scene_to_file", TITLE_SCENE)


func restart_level() -> void:
	get_tree().paused = false
	_set_slowmo(false)
	get_tree().reload_current_scene()


## Retry the level after dying, keeping the run going (friendlier while tuning).
func retry_level() -> void:
	run_active = true
	restart_level()


## Called by `Level._ready()`, so nothing else has to know when a level began.
func on_level_ready(level: Node) -> void:
	current_level = level
	player = null
	# Where the checkpoint starts from. `record()` ignores levels that were launched directly
	# from the editor, because those are not part of a run.
	Progress.record()
	level_started.emit(level)


func set_player(p: Node2D) -> void:
	player = p


## The player, or null if there is not one or it has been freed (level changes).
## Use this instead of casting `player` directly: casting a freed object errors.
func valid_player() -> Player:
	if player == null or not is_instance_valid(player):
		return null
	return player as Player


func notify_level_cleared() -> void:
	levels_cleared += 1
	snapshot_loadout()
	AudioDirector.play(&"exit")


## Remember what the player is carrying so the next level can restore it.
func snapshot_loadout() -> void:
	if player == null or not is_instance_valid(player):
		return
	var who := valid_player()
	if who != null:
		carried_keys = who.keys
	var holder := player.weapons as WeaponHolder
	if holder == null:
		return
	carried_loadout = holder.serialize()


## Kept in step by the player whenever a key changes hands, so nothing has to remember to
## snapshot before a level change.
func carry_keys(count: int) -> void:
	carried_keys = maxi(0, count)


func notify_player_died() -> void:
	if _outcome_reported:
		return
	_outcome_reported = true
	run_active = false
	AudioDirector.play(&"player_die")
	game_over.emit("You died")


func notify_win() -> void:
	if _outcome_reported:
		return
	_outcome_reported = true
	run_active = false
	# Finished: there is nothing left to continue, so the title screen offers a new game only.
	Progress.clear()
	AudioDirector.play(&"win")
	game_won.emit()


func notify_kill() -> void:
	kills += 1


func notify_shot_fired() -> void:
	shots_fired += 1


func notify_alert() -> void:
	enemies_alerted += 1


func announce_message(text: String, color: Color = Color.WHITE) -> void:
	announce.emit(text, color)


## Broadcast a noise the AI can hear at `position` within `radius`. The type is required, not
## defaulted, so a new sound cannot be added without deciding what it means.
func make_noise(position: Vector2, radius: float, type: NoiseKind.Type, source: Node = null) -> void:
	noise_made.emit(position, radius, source, type)


## Where world objects spawned during play (bullets, corpses, effects) should be
## parented, so they are cleaned up with the level.
func spawn_parent() -> Node:
	if current_level != null and is_instance_valid(current_level):
		return current_level
	return get_tree().current_scene


## Can the player actually see `point` right now? Used by enemies to notice that
## the player's own vision cone is shining on them. One raycast, called a few
## times a second per enemy.
func player_sees(point: Vector2) -> bool:
	var who := valid_player()
	if who == null:
		return false
	var rig: VisionRig = who.get_node_or_null("Vision") as VisionRig
	if rig == null:
		return false
	# Sight-only blockers too: the cone does not shine through a fire wall, so nobody behind one
	# should notice it.
	return rig.can_see_point(point, Layers.SOLID | Layers.SIGHT_ONLY)


func stats_line() -> String:
	return "kills %d   shots %d   alerts %d   time %s" % [
		kills, shots_fired, enemies_alerted, format_time(run_time),
	]


func format_time(seconds: float) -> String:
	var total: int = int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [total / 60, total % 60]

#endregion


#region pause

func set_paused(value: bool) -> void:
	if get_tree().paused == value:
		return
	get_tree().paused = value
	if value:
		# Pausing is the moment before someone quits to the menu, so it is the best possible
		# time to refresh the checkpoint: the level they are on, with what they are carrying.
		Progress.record()


func toggle_pause() -> void:
	set_paused(not get_tree().paused)


func is_paused() -> bool:
	return get_tree().paused

#endregion


#region debug

func _unhandled_input(event: InputEvent) -> void:
	if run_active and event.is_action_pressed(&"pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"debug_god"):
		god_mode = not god_mode
		announce_message("God mode %s" % ("ON" if god_mode else "off"), Color(1, 0.8, 0.3))
	elif event.is_action_pressed(&"debug_noclip"):
		noclip = not noclip
		announce_message("Noclip %s" % ("ON" if noclip else "off"), Color(1, 0.8, 0.3))
	elif event.is_action_pressed(&"debug_info"):
		debug_info = not debug_info
	elif event.is_action_pressed(&"debug_reveal"):
		reveal = not reveal
		reveal_changed.emit(reveal)
		announce_message("Reveal %s" % ("ON" if reveal else "off"), Color(1, 0.8, 0.3))
	elif event.is_action_pressed(&"debug_slowmo"):
		_set_slowmo(not _slowmo)
	elif event.is_action_pressed(&"debug_spawn"):
		_debug_call("debug_spawn_enemy")
	elif event.is_action_pressed(&"debug_alert_all"):
		_debug_call("debug_alert_all")
	elif event.is_action_pressed(&"debug_give"):
		if player != null and player.has_method("debug_give_all_weapons"):
			player.debug_give_all_weapons()
			announce_message("All weapons granted", Color(1, 0.8, 0.3))


func _debug_call(method: String) -> void:
	if current_level != null and current_level.has_method(method):
		current_level.call(method)
	else:
		announce_message("Not available here", Color(1, 0.5, 0.4))


func _set_slowmo(on: bool) -> void:
	_slowmo = on
	Engine.time_scale = 0.25 if on else 1.0

#endregion
