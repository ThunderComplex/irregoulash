class_name CampaignLibrary
extends RefCounted
## The campaign, in order: the only place the level chain exists.
##
## Exits do not carry targets any more. `ExitZone` asks its level what comes next, and the answer comes
## from this list, so adding a level is one line here plus the scene -- no per-exit wiring, and nothing
## can point at the wrong neighbour.
##
## Paths rather than `PackedScene` references on purpose: a string list diffs cleanly, matches what the
## checkpoint already stores, and opening one level does not load every other level in the campaign.

## Every level, in play order. The last one's exit ends the run.
const LEVELS: Array[String] = [
	"res://src/levels/level_campaign_01.tscn",
	"res://src/levels/level_campaign_02.tscn",
	"res://src/levels/level_campaign_03.tscn",
	"res://src/levels/level_campaign_04.tscn",
]

## `level_title` per path, read from the scene once. Only menus and level-select need it.
static var _titles: Dictionary = {}


static func paths() -> Array[String]:
	return LEVELS.duplicate()


static func count() -> int:
	return LEVELS.size()


## Where a new run starts.
static func first() -> String:
	return LEVELS[0] if not LEVELS.is_empty() else ""


static func index_of(path: String) -> int:
	return LEVELS.find(path)


## The level after `path`, or "" when it is the last one.
##
## A level that is not in the campaign also gets "": that is what a level being authored and run
## directly from the editor behaves like -- its exit ends the run instead of leading somewhere
## arbitrary. The linter says so when the open level is not registered.
static func next_after(path: String) -> String:
	var index: int = index_of(path)
	if index < 0 or index + 1 >= LEVELS.size():
		return ""
	return LEVELS[index + 1]


## Whether `path` ends the run. Anything not in the campaign does, for the reason above.
static func is_final(path: String) -> bool:
	return next_after(path).is_empty()


## "3 / 12", or "" for a level that is not in the campaign.
static func position_text(path: String) -> String:
	var index: int = index_of(path)
	if index < 0:
		return ""
	return "%d / %d" % [index + 1, LEVELS.size()]


## The level's own `level_title`, read from its scene once and cached.
static func title_of(path: String) -> String:
	if _titles.has(path):
		return String(_titles[path])
	var title: String = ""
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			var root: Node = packed.instantiate()
			var value: Variant = root.get("level_title")
			title = String(value) if value != null else ""
			root.free()
	_titles[path] = title
	return title


## Problems only the whole campaign can see: an empty list, a path that does not exist, or the same
## level twice. Per-level problems are `LevelLint.run`'s job.
static func problems() -> Array[String]:
	var out: Array[String] = []
	if LEVELS.is_empty():
		out.append("the campaign has no levels")
		return out
	var seen: Dictionary = {}
	for path: String in LEVELS:
		if seen.has(path):
			out.append("'%s' appears more than once in the campaign" % path)
		seen[path] = true
		if not ResourceLoader.exists(path):
			out.append("'%s' is in the campaign but does not exist" % path)
	return out
