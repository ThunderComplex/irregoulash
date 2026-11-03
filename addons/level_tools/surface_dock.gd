@tool
extends VBoxContainer
## The Surfaces dock: every wall and floor style in `SurfaceLibrary.DIRECTORY`, with a thumbnail.
##
##   * click a style          -> edit it in the inspector; the open level restyles live as you drag
##   * double-click / "Use"   -> make the open level use it (undoable)
##   * "New wall" / "New floor" -> a fresh style file, named from the box, using the texture selected
##                               in the FileSystem dock; it is applied to the open level straight away
##   * "Duplicate"            -> a copy of the selected style, to try a variation without losing the
##                               original
##
## Styles are ordinary `.tres` files, so they can also be made, renamed and deleted in the FileSystem
## dock; this dock just notices.

const THUMB: int = 40

var undo: EditorUndoRedoManager = null

var _walls: ItemList = null
var _floors: ItemList = null
var _name_edit: LineEdit = null
var _status: Label = null
var _use_button: Button = null
var _duplicate_button: Button = null
var _save_button: Button = null

## What the dropdowns on `Level` offered last time, so the level is only told to rebuild its inspector
## when that actually changes (the file system signal fires on every save).
var _last_ids: Array = []
var _refresh_queued: bool = false


func _init() -> void:
	name = "Surfaces"
	custom_minimum_size = Vector2(200.0, 0.0)

	_walls = _add_list("Wall styles")
	_floors = _add_list("Floor styles")

	var actions := HBoxContainer.new()
	add_child(actions)
	_use_button = _add_button(actions, "Use in level", "Make the open level use the selected style.",
		_on_use_pressed)
	_save_button = _add_button(actions, "Save", "Save the selected style's file now. (Saving the scene "
		+ "also saves styles you have edited.)", _on_save_pressed)

	add_child(HSeparator.new())

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "new style name, e.g. brick_wall"
	_name_edit.tooltip_text = ("The file name, and so the id levels refer to it by. Lowercase with "
		+ "underscores; anything else is converted.")
	add_child(_name_edit)

	var create := HBoxContainer.new()
	add_child(create)
	var texture_hint: String = ("\nUses the texture selected in the FileSystem dock, if any; otherwise "
		+ "drop one onto 'Albedo' in the inspector afterwards.")
	_add_button(create, "New wall", "Create a wall style." + texture_hint,
		_on_new_pressed.bind(SurfaceStyle.Kind.WALL))
	_add_button(create, "New floor", "Create a floor style (no edge shading)." + texture_hint,
		_on_new_pressed.bind(SurfaceStyle.Kind.FLOOR))
	_duplicate_button = _add_button(create, "Duplicate",
		"Copy the selected style under the name above.", _on_duplicate_pressed)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1.0, 1.0, 1.0, 0.7)
	add_child(_status)


func _ready() -> void:
	refresh()


#region building

func _add_list(title: String) -> ItemList:
	var label := Label.new()
	label.text = title
	add_child(label)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0.0, 120.0)
	list.fixed_icon_size = Vector2i(THUMB, THUMB)
	list.item_selected.connect(_on_item_selected.bind(list))
	list.item_activated.connect(_on_item_activated.bind(list))
	add_child(list)
	return list


func _add_button(parent: Control, text: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

#endregion


#region refresh

## Rebuilds both lists, re-reading the styles folder first when `rescan` is set. Called when the file
## system changes, when the edited scene changes, and when a style is edited (a kind or name change
## moves or renames an entry, but adds no file, so that one skips the rescan).
func refresh(rescan: bool = true) -> void:
	if rescan:
		SurfaceLibrary.invalidate()
	var level: Level = _level()
	var selected: String = _selected_id()
	_fill(_walls, SurfaceLibrary.wall_ids(), level.wall_surface_id if level != null else "", selected)
	_fill(_floors, SurfaceLibrary.floor_ids(), level.floor_surface_id if level != null else "", selected)
	_update_buttons()

	var ids: Array = [SurfaceLibrary.wall_ids(), SurfaceLibrary.floor_ids()]
	if ids != _last_ids:
		_last_ids = ids
		if level != null:
			level.surfaces_changed()


## A style edit can fire every frame while a slider is dragged; rebuild the lists once per frame at most.
func queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	(func() -> void:
		_refresh_queued = false
		refresh(false)).call_deferred()


func _fill(list: ItemList, ids: Array[String], in_use: String, selected: String) -> void:
	list.clear()
	for id: String in ids:
		var style: SurfaceStyle = SurfaceLibrary.by_id(id)
		var text: String = style.display_name
		if text.to_snake_case() != id:
			text += "  (%s)" % id
		if id == in_use:
			text += "  - in use"
		var index: int = list.add_item(text, style.albedo)
		list.set_item_metadata(index, id)
		list.set_item_tooltip(index, SurfaceLibrary.path_for(id) if id != SurfaceLibrary.PLAIN
			else "Flat colour, no texture. Built in, so it has no file.")
		if id == selected:
			list.select(index)
		if not style.changed.is_connected(queue_refresh):
			style.changed.connect(queue_refresh)

#endregion


#region selection

func _on_item_selected(index: int, list: ItemList) -> void:
	# One selection across both lists, so the buttons always mean one style.
	var other: ItemList = _floors if list == _walls else _walls
	other.deselect_all()
	_update_buttons()
	var id: String = list.get_item_metadata(index)
	if id == SurfaceLibrary.PLAIN:
		_say("Plain is the built-in flat colour; there is nothing to edit. Duplicate a textured style, "
			+ "or make a new one, to start a look.")
		return
	EditorInterface.edit_resource(SurfaceLibrary.by_id(id))
	_say("Editing '%s'. Changes show in the open level as you make them." % id)


func _on_item_activated(index: int, list: ItemList) -> void:
	list.select(index)
	_apply(String(list.get_item_metadata(index)), list == _floors)


## The selected style's id, or "" for none.
func _selected_id() -> String:
	for list: ItemList in [_walls, _floors]:
		if list == null:
			continue
		var picked: PackedInt32Array = list.get_selected_items()
		if not picked.is_empty():
			return String(list.get_item_metadata(picked[0]))
	return ""


func _selected_is_floor() -> bool:
	return _floors != null and not _floors.get_selected_items().is_empty()


func _update_buttons() -> void:
	var id: String = _selected_id()
	_use_button.disabled = id == "" or _level() == null
	_save_button.disabled = id == "" or id == SurfaceLibrary.PLAIN
	_duplicate_button.disabled = id == "" or id == SurfaceLibrary.PLAIN

#endregion


#region actions

func _on_use_pressed() -> void:
	var id: String = _selected_id()
	if id != "":
		_apply(id, _selected_is_floor())


## Points the open level's wall or floor dropdown at a style, through the undo history.
func _apply(id: String, is_floor: bool) -> void:
	var level: Level = _level()
	if level == null:
		_say("Open a level scene first: styles are chosen per level.")
		return
	var property: String = "floor_surface_id" if is_floor else "wall_surface_id"
	var before: String = level.get(property)
	if before == id:
		return
	undo.create_action("Use surface '%s'" % id)
	undo.add_do_property(level, property, id)
	undo.add_undo_property(level, property, before)
	undo.add_do_method(self, "refresh")
	undo.add_undo_method(self, "refresh")
	undo.commit_action()
	_say("%s now uses '%s' for its %s." % [level.name, id, "floor" if is_floor else "walls"])


func _on_save_pressed() -> void:
	var id: String = _selected_id()
	if id == "" or id == SurfaceLibrary.PLAIN:
		return
	var style: SurfaceStyle = SurfaceLibrary.by_id(id)
	var error: Error = ResourceSaver.save(style, SurfaceLibrary.path_for(id))
	_say("Saved %s." % SurfaceLibrary.path_for(id) if error == OK
		else "Could not save %s (error %d)." % [SurfaceLibrary.path_for(id), error])


func _on_new_pressed(kind: SurfaceStyle.Kind) -> void:
	var style := SurfaceStyle.new()
	style.kind = kind
	style.albedo = _texture_from_file_system()
	if kind == SurfaceStyle.Kind.FLOOR:
		# Larger and darker than a wall, and with no edge: the floor is lit, the wall top is not.
		style.clear_edges()
		style.tile_world = Vector2(96.0, 96.0)
		style.tint = Color(0.5, 0.5, 0.5)
	_create(style, "new_floor" if kind == SurfaceStyle.Kind.FLOOR else "new_wall")


func _on_duplicate_pressed() -> void:
	var source: String = _selected_id()
	if source == "" or source == SurfaceLibrary.PLAIN:
		return
	_create(SurfaceLibrary.by_id(source).duplicate() as SurfaceStyle, source + "_copy")


## Saves a new style under the name in the box (or a free fallback name), selects it in the inspector
## and puts it on the open level, so the very next thing you see is the new look in place.
func _create(style: SurfaceStyle, fallback: String) -> void:
	var id: String = _clean_id(_name_edit.text)
	if id == "":
		id = _free_id(fallback)
	if id == SurfaceLibrary.PLAIN:
		_say("'plain' is the built-in flat colour; pick another name.")
		return
	var path: String = SurfaceLibrary.path_for(id)
	if FileAccess.file_exists(path):
		_say("%s already exists; pick another name." % path)
		return

	style.display_name = id.capitalize()
	DirAccess.make_dir_recursive_absolute(SurfaceLibrary.DIRECTORY)
	var error: Error = ResourceSaver.save(style, path)
	if error != OK:
		_say("Could not save %s (error %d)." % [path, error])
		return
	EditorInterface.get_resource_filesystem().update_file(path)
	_name_edit.clear()

	refresh()
	var saved: SurfaceStyle = SurfaceLibrary.by_id(id)
	EditorInterface.edit_resource(saved)
	_apply(id, saved.kind == SurfaceStyle.Kind.FLOOR)
	_select(id)
	var note: String = "" if saved.albedo != null else (" It has no texture yet: drop one onto "
		+ "'Albedo' in the inspector.")
	_say("Created %s.%s" % [path, note])


func _select(id: String) -> void:
	for list: ItemList in [_walls, _floors]:
		list.deselect_all()
		for index: int in list.item_count:
			if String(list.get_item_metadata(index)) == id:
				list.select(index)
				list.ensure_current_is_visible()
	_update_buttons()


## "Brick Wall #2" -> "brick_wall_2": ids are file names and appear in scene files, so keep them plain.
func _clean_id(text: String) -> String:
	var runs := RegEx.create_from_string("[^a-z0-9]+")
	return runs.sub(text.strip_edges().to_lower(), "_", true).trim_prefix("_").trim_suffix("_")


func _free_id(base: String) -> String:
	if not FileAccess.file_exists(SurfaceLibrary.path_for(base)):
		return base
	var n: int = 2
	while FileAccess.file_exists(SurfaceLibrary.path_for("%s_%d" % [base, n])):
		n += 1
	return "%s_%d" % [base, n]


## The first texture selected in the FileSystem dock, so "select the png, press New wall" is the whole
## workflow for a new look.
func _texture_from_file_system() -> Texture2D:
	for path: String in EditorInterface.get_selected_paths():
		if ResourceLoader.exists(path, "Texture2D"):
			return load(path) as Texture2D
	return null

#endregion


func _level() -> Level:
	return EditorInterface.get_edited_scene_root() as Level


func _say(text: String) -> void:
	if _status != null:
		_status.text = text
