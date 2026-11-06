class_name GameProgress
extends Node
## The one checkpoint the title screen's Continue button resumes from.
##
## Deliberately not a save system: it remembers the level you were on and what you carried
## (weapons, abilities and keys), and nothing else. No position, no enemy state, no items already
## taken. Continue therefore puts you at the *start* of the level you were in, with the build you
## had when you paused, which is the reassuring half and the cheap half.
##
## Written when a level starts, refreshed whenever the game is paused (the moment before you
## might quit to the menu), and cleared when the run is won.

## Emitted whenever the checkpoint changes, so any menu showing it can stay honest.
signal changed()

const PATH: String = "user://progress.cfg"
const FILE_NAME: String = "progress.cfg"

var level_path: String = ""
var level_title: String = ""
## The same plain-data shape `WeaponHolder.serialize()` produces, so restoring it uses code
## that already exists and is already exercised by the level chain.
var loadout: Array = []
## Abilities are carried the same way, and their upgrade levels with them: a checkpoint that
## dropped them would lose the player's build, not just their position.
var abilities: Array = []
## Keys are inventory, so a checkpoint that forgot them would make a player lose progress.
var carried_keys: int = 0
## Whether this player has ever reached the final exit. Kept across runs: finishing unlocks the level
## select, and finishing again (or starting a new game) must not take that away.
var finished: bool = false


func _ready() -> void:
	load_progress()


## True when there is something worth continuing: a recorded level that still exists. Checking
## the file means renaming or deleting a level greys the button out instead of erroring.
func has_progress() -> bool:
	return level_path != "" and ResourceLoader.exists(level_path)


## Snapshot the run in progress. Called on level entry and on pause.
func record() -> void:
	if not GameDirector.run_active:
		return
	# A level picked from the level select is practice: it must not overwrite the checkpoint of the
	# real run, so a replay can never cost someone their place in the campaign.
	if GameDirector.selected_level_run:
		return
	var level: Node = GameDirector.current_level
	if level == null or not is_instance_valid(level):
		return
	level_path = String(level.scene_file_path)
	var title: Variant = level.get("level_title")
	level_title = String(title) if title != null else ""
	# The live loadout rather than the one snapshotted at the last level exit: pausing is the
	# moment before quitting to the menu, so this is where the save is worth refreshing.
	GameDirector.snapshot_carried()
	loadout = GameDirector.carried_loadout.duplicate(true)
	abilities = GameDirector.carried_abilities.duplicate(true)
	carried_keys = GameDirector.carried_keys
	save()


## Forgets where the run was, keeping the "finished the game" flag. Called when a new game starts and
## when one is won: there is nothing left to continue, but the level select stays unlocked.
func clear_checkpoint() -> void:
	level_path = ""
	level_title = ""
	loadout = []
	abilities = []
	carried_keys = 0
	save()
	changed.emit()


## The final exit: remember that the game was finished, then drop the checkpoint.
func finish_run() -> void:
	finished = true
	clear_checkpoint()


## Forgets everything, including the finished flag. Used by a full wipe (and by tests), not by New Game:
## a new campaign does not take the level select away.
func reset() -> void:
	finished = false
	level_path = ""
	level_title = ""
	loadout = []
	abilities = []
	carried_keys = 0
	remove_file()
	changed.emit()


func remove_file() -> bool:
	var dir := DirAccess.open("user://")
	if dir == null or not dir.file_exists(FILE_NAME):
		return true
	return dir.remove(FILE_NAME) == OK


func file_exists() -> bool:
	return FileAccess.file_exists(PATH)


## Shown on the Continue button: "CONTINUE - THE YARD".
func continue_label() -> String:
	if level_title != "":
		return "CONTINUE   %s" % level_title.to_upper()
	return "CONTINUE"


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "level_path", level_path)
	config.set_value("progress", "level_title", level_title)
	config.set_value("progress", "loadout", loadout)
	config.set_value("progress", "abilities", abilities)
	config.set_value("progress", "carried_keys", carried_keys)
	config.set_value("progress", "finished", finished)
	var error: Error = config.save(PATH)
	if error != OK:
		push_warning("Could not save progress to %s (error %d)." % [PATH, error])
	changed.emit()


func load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	level_path = String(config.get_value("progress", "level_path", ""))
	level_title = String(config.get_value("progress", "level_title", ""))
	# From a config file this comes back as a plain Array of Dictionaries, which is exactly
	# what deserialize() expects.
	var stored: Variant = config.get_value("progress", "loadout", [])
	loadout = stored if stored is Array else []
	# Defaults to empty, so a checkpoint written before abilities were carried still loads.
	var stored_abilities: Variant = config.get_value("progress", "abilities", [])
	abilities = stored_abilities if stored_abilities is Array else []
	carried_keys = int(config.get_value("progress", "carried_keys", 0))
	finished = bool(config.get_value("progress", "finished", false))
	changed.emit()
