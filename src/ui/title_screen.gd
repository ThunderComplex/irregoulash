extends Control
## Title screen. Also the project's main scene, so the game always starts here.
##
## Doubles as the "how do I play this" screen: the control list is generated from
## GameInput.CONTROLS_TEXT so it cannot drift out of date.
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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_compute_layout()
	_build()
	get_viewport().size_changed.connect(_on_viewport_resized)
	Progress.changed.connect(_refresh_continue)


## Keeps Continue honest if the checkpoint changes while the title is up, so the button can
## never disagree with what is actually on disk.
func _refresh_continue() -> void:
	if _main_menu == null or not is_instance_valid(_main_menu):
		return
	var had_focus: bool = _main_menu.item_has_focus(&"continue")
	var enabled: bool = Progress.has_progress()
	_main_menu.set_item(&"continue", Progress.continue_label(), enabled)
	# Disabling the focused Control drops focus entirely, which would leave the keyboard with
	# nothing to activate. Move it to New Game rather than leaving the menu dead.
	if had_focus and not enabled:
		_main_menu.focus_item(&"new_game")


func _process(_delta: float) -> void:
	if _resize_pending:
		_resize_pending = false
		_rebuild()


## There is deliberately no `_unhandled_input` here any more: every action is a button, so
## nothing else can shadow the focused one. In particular, a stray `ui_accept` handler would
## fight the menu, activating "New Game" while the player had Continue selected.
func _on_menu_item(id: StringName) -> void:
	match id:
		&"new_game":
			GameDirector.start_run()
		&"continue":
			GameDirector.continue_run()
		&"settings":
			open_settings()
		&"quit":
			get_tree().quit()


## Opens the settings menu over the title. Public so the dev probe can open it too.
func open_settings() -> void:
	if _settings_menu != null and is_instance_valid(_settings_menu):
		return
	_settings_menu = SettingsMenu.new()
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


## Rebuilds everything except an open settings menu, which stays put. The main menu *is*
## rebuilt, so it is never the node left holding stale coordinates.
func _rebuild() -> void:
	for child: Node in get_children():
		if child == _settings_menu:
			continue
		child.free()
	_compute_layout()
	_build()


func _build() -> void:
	# The background and the beam are sized from the viewport explicitly: a Control inside
	# another Control is not automatically given its parent's rect, and relying on that is
	# what put the settings panel half off-screen once already.
	var viewport: Vector2 = get_viewport().get_visible_rect().size

	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.04, 0.055, 1.0)
	bg.position = Vector2.ZERO
	bg.size = viewport
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# A dim cone of light, echoing the thing the game is actually about.
	var beam := Polygon2D.new()
	beam.polygon = PackedVector2Array([
		_to_screen(Vector2(40.0, 700.0)),
		_to_screen(Vector2(1420.0, 60.0)),
		_to_screen(Vector2(1420.0, 700.0)),
	])
	beam.color = Color(0.16, 0.18, 0.24, 1.0)
	add_child(beam)

	_label(Vector2(80.0, 90.0), Vector2(1100.0, 80.0), "TOP DOWN SHOOTER", 52,
		Color(0.93, 0.96, 1.0))
	_label(Vector2(84.0, 176.0), Vector2(1100.0, 40.0),
		"in development  --  line of sight is the whole game", 18,
		Color(0.6, 0.68, 0.8))

	_label(Vector2(84.0, 256.0), Vector2(520.0, 340.0), GameInput.CONTROLS_TEXT, 17,
		Color(0.78, 0.84, 0.92))

	_label(Vector2(640.0, 256.0), Vector2(600.0, 300.0),
		"""What to try

- Walk into a dark room and notice how
  the walls you have seen stay faintly
  lit, so you can still find your way.
- Sneak up on a guard. Awareness is a
  meter, not a switch: it fills faster the
  closer you are, and much faster when
  you shine your own light on them.
- Fire a shot and listen: noise pulls
  guards towards you.
- Get out of the light and break line of
  sight, and they will search for you.
- Clear the yard, find the exit, escape.""", 16, Color(0.62, 0.72, 0.84))

	# --- main menu: a 2x2 grid of buttons in the bottom right, which is the only free space on
	# this screen. A single column collided with the control list and its debug keys, both of
	# which are longer than they look, and a row along the bottom collided with them too.
	# Continue knows where the last run got to, and is greyed out rather than hidden when there
	# is nothing to resume.
	_main_menu = MenuList.new()
	_main_menu.configure(Rect2(640.0, 620.0, 560.0, 2.0 * MenuList.ROW_HEIGHT), _scale, 2)
	_main_menu.add_item(&"new_game", "NEW GAME")
	_main_menu.add_item(&"continue", Progress.continue_label(), Progress.has_progress())
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
