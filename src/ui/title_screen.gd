extends Control
## Title screen. Also the project's main scene, so the game always starts here.
##
## Doubles as the "how do I play this" screen: the control list is generated from the live input map, so
## it cannot drift out of date and cannot lie after a rebind.
##
## The layout below is written in the coordinates of a 1280x720 frame and scaled to fit the
## window, so the same screen works on a small window and on a 4K monitor. It is rebuilt on
## resize rather than nudged, because a rebuild is cheap and cannot half-apply.

## The frame the layout is written for.
const REFERENCE: Vector2 = Vector2(1280.0, 720.0)
## How much of that frame the two columns occupy, used to work out the margins.
const CONTENT_WIDTH: float = 1160.0

var _scale: float = 1.0
## Top-left of the reference frame in screen pixels. The frame is centred, so an unusual
## aspect ratio gets even bands around the content rather than everything hugging a corner.
var _origin: Vector2 = Vector2.ZERO
var _resize_pending: bool = false
var _main_menu: MenuList = null
var _settings_menu: Control = null
var _level_select: Control = null

var _bg_image = preload("res://art/cover.png")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_compute_layout()
	_build()
	get_viewport().size_changed.connect(_on_viewport_resized)
	Progress.changed.connect(_refresh_continue)
	GameInput.device_changed.connect(_on_device_changed)
	# Returning from a practice run lands here, with the picker already open: the loop is
	# pick -> play -> pick, not pick -> play -> menu.
	if GameDirector.open_level_select_pending:
		GameDirector.open_level_select_pending = false
		open_level_select()


## The controls table is written for the device in hand, so switching between pad and keyboard rebuilds
## it. Deferred through the same flag the resize path uses: a rebuild during input dispatch would free
## the buttons mid-event.
func _on_device_changed(_gamepad: bool) -> void:
	_resize_pending = true


## Keeps Continue honest if the checkpoint changes while the title is up, so the button can
## never disagree with what is actually on disk.
func _refresh_continue() -> void:
	if _main_menu == null or not is_instance_valid(_main_menu):
		return
	var had_focus: bool = _main_menu.item_has_focus(&"continue")
	var enabled: bool = Progress.has_progress()
	_main_menu.set_item(&"continue", Progress.continue_label(), enabled)
	# Finishing the game unlocks the picker, and it stays unlocked across new games.
	_main_menu.set_item(&"level_select", "LEVEL SELECT", Progress.finished)
	# Disabling the focused Control drops focus entirely, which would leave the keyboard with
	# nothing to activate. Move it to New Game rather than leaving the menu dead.
	if had_focus and not enabled:
		_main_menu.focus_item(&"new_game")


func _process(_delta: float) -> void:
	if _resize_pending:
		_resize_pending = false
		rebuild()


## There is deliberately no `_unhandled_input` here any more: every action is a button, so
## nothing else can shadow the focused one. In particular, a stray `ui_accept` handler would
## fight the menu, activating "New Game" while the player had Continue selected.
func _on_menu_item(id: StringName) -> void:
	match id:
		&"new_game":
			GameDirector.start_run()
		&"continue":
			GameDirector.continue_run()
		&"level_select":
			open_level_select()
		&"settings":
			open_settings()
		&"quit":
			get_tree().quit()


## Opens the level picker. Public so the dev probe can open it, and so the title can reopen it when a
## practice run ends.
func open_level_select() -> void:
	if _level_select != null and is_instance_valid(_level_select):
		return
	if not Progress.finished:
		return
	_level_select = LevelSelect.new()
	_level_select.closed.connect(_on_level_select_closed)
	add_child(_level_select)


func _on_level_select_closed() -> void:
	_level_select = null
	if _main_menu != null and is_instance_valid(_main_menu):
		_main_menu.focus_item(&"level_select")


## Opens the settings menu over the title. Public so the dev probe can open it too.
func open_settings() -> void:
	if _settings_menu != null and is_instance_valid(_settings_menu):
		return
	_settings_menu = SettingsMenu.new()

	if not _settings_menu.settings_closed.is_connected(rebuild):
		_settings_menu.settings_closed.connect(rebuild)
	
	add_child(_settings_menu)


func _compute_layout() -> void:
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return
	# Fit rather than scale-by-height: a 4:3 or 5:4 window is narrower than 16:9, and a
	# height-only scale would push the second column off the right edge.
	_scale = clampf(minf(viewport.x / REFERENCE.x, viewport.y / REFERENCE.y), 0.35, 4.0)
	_origin = (viewport - REFERENCE * _scale) * 0.5


func _on_viewport_resized() -> void:
	_resize_pending = true


## Rebuilds everything except an open overlay, which stays put. The main menu *is* rebuilt, so it is
## never the node left holding stale coordinates.
func rebuild() -> void:
	for child: Node in get_children():
		if child == _settings_menu or child == _level_select:
			continue
		child.free()
	_compute_layout()
	_build()
	# `_build()` appends the background and the menu, so a kept overlay would end up *under* them:
	# sibling order is draw order, and the background is opaque. Raise whatever was open to the top.
	for overlay: Control in [_settings_menu, _level_select]:
		if overlay != null and is_instance_valid(overlay):
			move_child(overlay, get_child_count() - 1)


func _build() -> void:
	# The background and the beam are sized from the viewport explicitly: a Control inside
	# another Control is not automatically given its parent's rect, and relying on that is
	# what put the settings panel half off-screen once already.
	var viewport: Vector2 = get_viewport().get_visible_rect().size

	var bg := TextureRect.new()
	bg.texture = _bg_image
	bg.position = Vector2.ZERO
	bg.size = viewport
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	add_child(bg)

	# Testers quote this in feedback; see `BuildInfo`.
	_label(Vector2(1000.0, 24.0), Vector2(256.0, 24.0), BuildInfo.version_text(), 14,
		Color(0.45, 0.5, 0.58), HORIZONTAL_ALIGNMENT_RIGHT)

	# Generated from the live input map, so a rebind cannot leave this text lying about what the keys do.
	_controls_block(Vector2(84.0, 196.0))

	# --- main menu: a grid of buttons across the bottom, which is the only free space on this screen;
	# the control list and the "what to try" text both run down to just above it. Three columns rather
	# than two because the level select adds a fifth entry after the campaign is finished.
	_main_menu = MenuList.new()
	_main_menu.configure(Rect2(400.0, 620.0, 840.0, 2.0 * MenuList.ROW_HEIGHT), _scale, 3, _origin)
	_main_menu.add_item(&"new_game", "NEW GAME")
	_main_menu.add_item(&"continue", Progress.continue_label(), Progress.has_progress())
	_main_menu.add_item(&"level_select", "LEVEL SELECT", Progress.finished)
	_main_menu.add_item(&"settings", "SETTINGS")
	_main_menu.add_item(&"quit", "QUIT")
	_main_menu.activated.connect(_on_menu_item)
	add_child(_main_menu)
	# Opens on Continue when there is something to continue, because pressing Space on reflex is
	# what a returning player does -- and with New Game focused that reflex threw the run away.
	# `focus_item` falls back to the first enabled item, so a fresh install still lands on New
	# Game. Focus is only set here, not in `_refresh_continue`, so it never moves under the
	# player's hands if the checkpoint changes while the title is up.
	_main_menu.focus_item(&"continue")


## Reference frame -> screen pixels.
func _to_screen(point: Vector2) -> Vector2:
	return _origin + point * _scale


## The controls block: two aligned columns generated from the live input map, so a rebind cannot leave
## this screen lying about the keys. A grid rather than space-padded text, because the default font is
## proportional and padded columns never line up.
func _controls_block(position_: Vector2) -> void:
	var box := VBoxContainer.new()
	box.position = _to_screen(position_)
	box.custom_minimum_size = Vector2(520.0, 0.0) * _scale
	box.add_theme_constant_override("separation", maxi(1, int(round(12.0 * _scale))))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", maxi(1, int(round(20.0 * _scale))))
	grid.add_theme_constant_override("v_separation", maxi(1, int(round(1.0 * _scale))))
	box.add_child(grid)
	for row: Array in GameInput.title_rows():
		grid.add_child(_block_label(String(row[0]), 17, Color(1.0, 1.0, 1.0, 1.0)))
		grid.add_child(_block_label(String(row[1]), 17, Color(1.0, 1.0, 1.0, 1.0)))

	# The pickup hint used to sit here. The menu now needs the bottom of the frame, and pickups are
	# explained by walking over one.
	if OS.is_debug_build():
		var debug := _block_label("Debug: " + GameInput.debug_short_text(), 14,
			Color(0.45, 0.5, 0.58))
		debug.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(debug)


func _block_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", maxi(1, int(round(float(font_size) * _scale))))
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _label(position_: Vector2, label_size: Vector2, text: String, font_size: int, color: Color,
		halign: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = _to_screen(position_)
	label.size = label_size * _scale
	label.add_theme_font_size_override("font_size", maxi(1, int(round(float(font_size) * _scale))))
	label.horizontal_alignment = halign as HorizontalAlignment
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
