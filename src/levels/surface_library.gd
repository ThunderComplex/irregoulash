class_name SurfaceLibrary
extends RefCounted
## Every surface look in the game, looked up by id.
##
## Unlike `WeaponLibrary` and `EnemyLibrary` the styles are not built in code: a look is judged by eye,
## so each one is a `SurfaceStyle` resource in `DIRECTORY`, edited in the inspector with the level
## updating live (see the Surfaces dock in `addons/level_tools`). The file name is the id, and the
## dropdowns on `Level` are filled from this folder, so adding a style is saving a file -- nothing to
## register anywhere.
##
## "plain" is the one style that is not a file: it is the flat-colour default, and what any unknown id
## falls back to, so it must exist even with the folder empty.

const DIRECTORY: String = "res://src/levels/surfaces/"
const PLAIN: String = "plain"

static var _styles: Dictionary = {}
static var _scanned: bool = false
static var _plain_style: SurfaceStyle = null


static func by_id(id: String) -> SurfaceStyle:
	_scan()
	if _styles.has(id):
		return _styles[id]
	# Unknown ids get the flat default rather than null: a typo should look plain, not crash.
	return _plain()


## Ids offered for walls, "plain" first.
static func wall_ids() -> Array[String]:
	return ids(SurfaceStyle.Kind.WALL)


## Ids offered for floors, "plain" first.
static func floor_ids() -> Array[String]:
	return ids(SurfaceStyle.Kind.FLOOR)


static func ids(kind: SurfaceStyle.Kind) -> Array[String]:
	_scan()
	var out: Array[String] = []
	for id: String in _styles:
		var style: SurfaceStyle = _styles[id]
		if style.kind == kind:
			out.append(id)
	out.sort()
	out.push_front(PLAIN)
	return out


## Where the style with this id lives (or would live).
static func path_for(id: String) -> String:
	return DIRECTORY.path_join(id + ".tres")


## Forgets the folder listing, so the next lookup sees files added, renamed or removed since. The
## resources themselves stay in Godot's resource cache, so anything already holding a style keeps the
## same instance.
static func invalidate() -> void:
	_styles.clear()
	_scanned = false


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	_styles.clear()
	if not DirAccess.dir_exists_absolute(DIRECTORY):
		return
	# `ResourceLoader.list_directory` rather than `DirAccess`: in an exported game the files are remapped,
	# and only the resource loader knows them by their original names.
	for file: String in ResourceLoader.list_directory(DIRECTORY):
		if file.ends_with("/") or not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var id: String = file.get_basename()
		if id == PLAIN:
			push_warning("SurfaceLibrary: '%s' is reserved for the flat default; ignoring %s."
				% [PLAIN, file])
			continue
		var style := load(DIRECTORY.path_join(file)) as SurfaceStyle
		if style == null:
			push_warning("SurfaceLibrary: %s is not a SurfaceStyle." % file)
			continue
		style.id = StringName(id)
		_styles[id] = style


## The pre-surfaces look: a flat colour per wall, no texture, no floor. Default so that existing
## levels are untouched.
static func _plain() -> SurfaceStyle:
	if _plain_style == null:
		_plain_style = SurfaceStyle.new()
		_plain_style.id = StringName(PLAIN)
		_plain_style.display_name = "Plain"
		_plain_style.albedo = null
	return _plain_style
