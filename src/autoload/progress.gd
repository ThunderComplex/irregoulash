class_name GameProgress
extends Node
## The one checkpoint the title screen's Continue button resumes from.
##
## Deliberately not a save system: it remembers the level you were on and the loadout you were
## carrying, and nothing else. No position, no enemy state, no items already taken. Continue
## therefore puts you at the *start* of the level you were in, with the weapons you had when
## you paused, which is the reassuring half and the cheap half.
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
## Keys are inventory, so a checkpoint that forgot them would make a player lose progress.
var carried_keys: int = 0


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
	var level: Node = GameDirector.current_level
	if level == null or not is_instance_valid(level):
		return
	level_path = String(level.scene_file_path)
	var title: Variant = level.get("level_title")
	level_title = String(title) if title != null else ""
	# The live loadout rather than the one snapshotted at the last level exit: pausing is the
	# moment before quitting to the menu, so this is where the save is worth refreshing.
	GameDirector.snapshot_loadout()
	loadout = GameDirector.carried_loadout.duplicate(true)
	carried_keys = GameDirector.carried_keys
	save()


## Forgets the checkpoint and removes the file, so a fresh install and a finished run both
## leave nothing behind for Continue to offer.
func clear() -> void:
	level_path = ""
	level_title = ""
	loadout = []
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
	config.set_value("progress", "carried_keys", carried_keys)
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
	carried_keys = int(config.get_value("progress", "carried_keys", 0))
	changed.emit()
