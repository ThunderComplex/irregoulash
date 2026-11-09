class_name SettingsMenu
extends Control
## The settings menu. Opened from the title screen and from the pause overlay.
##
## Changes apply and persist the moment they are made -- there is no Apply button to forget,
## and no way to lose a change by backing out. Escape closes it.
##
## The settings are grouped on tabs (`TAB_NAMES`). Each is a page of rows, and a pad can reach all of it:
## moving along the tabs switches page, and the first row leads back up to its own tab.
##
## "Controls" swaps the panel for the rebinding list (`GameInput` owns the bindings themselves); Esc
## there returns here rather than closing everything.
##
## Built in code like the HUD, and laid out in the coordinates of a 1280x720 frame scaled
## to fit the window, so it is complete and legible at any resolution. The footer reports
## the real window size, which is also the quickest way to *see* that the rest of the game
## coped with the change.

signal settings_closed();

const REFERENCE: Vector2 = Vector2(1280.0, 720.0)
const PANEL_SIZE: Vector2 = Vector2(620.0, 510.0)
## The rebinding list is long, and scrolls, so it gets a taller panel of its own.
const CONTROLS_PANEL_SIZE: Vector2 = Vector2(620.0, 648.0)
## Width of the number field beside the frame rate slider.
const FPS_FIELD_WIDTH: float = 96.0
const ROW_LEFT: float = 44.0
const CONTROL_WIDTH: float = 300.0
const ROW_RIGHT: float = 44.0
const ROW_TOP: float = 150.0
const ROW_HEIGHT: float = 54.0
## The most rows any tab has; the buttons sit below that many.
const MAX_ROWS: int = 4
const TAB_NAMES: Array[String] = ["Display", "Audio", "Gameplay"]
const TAB_TOP: float = 84.0
const TAB_HEIGHT: float = 40.0
const TAB_GAP: float = 8.0
const TAB_DISPLAY: int = 0
const TAB_AUDIO: int = 1
const TAB_GAMEPLAY: int = 2
const LABEL_COLOR: Color = Color(0.72, 0.8, 0.9)
const LABEL_INERT_COLOR: Color = Color(0.5, 0.55, 0.62)

var _scale: float = 1.0
## Set when the window changed size. The rebuild happens in `_process`, not in the signal: a resolution
## change is chosen from this menu, so the resize signal fires from inside the resolution OptionButton's
## own `item_selected` emission -- and freeing that button there is the "freed while a signal is being
## emitted from it" error.
var _resize_pending: bool = false
var _panel: Control = null
## Which tab is showing. Kept across a rebuild, because changing the resolution rebuilds the menu.
var _current_tab: int = TAB_DISPLAY
var _tabs: Array[Button] = []
## Parallel to `_tabs`: the rows of each.
var _pages: Array[Control] = []
var _tab_marker: ColorRect = null
var _mode_button: OptionButton = null
var _resolution_button: OptionButton = null
var _vsync_button: CheckButton = null
var _aim_line_button: CheckButton = null
var _aim_assist_button: CheckButton = null
var _aim_assist_slider: HSlider = null
var _aim_assist_label: Label = null
## The frame rate cap: a slider whose last notch past `FPS_CAP_MAX` means "unlimited", and a field to
## type an exact number into.
var _fps_slider: HSlider = null
var _fps_field: LineEdit = null
var _fps_label: Label = null
var _master_slider: HSlider = null
var _music_slider: HSlider = null
var _sfx_slider: HSlider = null
var _master_label: Label = null
var _music_label: Label = null
var _sfx_label: Label = null
var _footer: Label = null
## Parallel to the resolution OptionButton's items.
var _resolution_sizes: Array[Vector2i] = []

## The rebinding panel, built on demand. Null while the normal settings rows are showing.
var _controls_panel: Control = null
## Action id -> the button showing (and changing) its binding.
var _binding_buttons: Dictionary = {}
## The action waiting for a key press, or "" when nothing is being captured.
var _capture_action: String = ""
var _controls_status: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Usable while the game is paused, which is the point of it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scale = _compute_scale()
	_build()
	_sync()
	_focus_tab_for_pad()
	get_viewport().size_changed.connect(_on_viewport_resized)
	Settings.changed.connect(_sync)
	GameInput.bindings_changed.connect(_refresh_bindings)


func _process(_delta: float) -> void:
	if _resize_pending:
		_resize_pending = false
		_rebuild()
	# Every frame: picking up a pad rebuilds the title screen behind this menu, which takes focus back.
	_focus_tab_for_pad()
	if _footer == null:
		return
	var settings_size: Vector2i = Vector2i(get_viewport().get_visible_rect().size)
	if Engine.is_embedded_in_editor():
		# The editor's embedded game window only supports windowed mode, so a window mode or
		# resolution change here would fail with an engine error. Say that rather than letting
		# the player press a button that cannot work. Run the game un-embedded (or export it)
		# to use these two rows for real.
		_footer.text = "window %d x %d\nembedded in the editor: window mode and resolution are fixed" % [
			settings_size.x, settings_size.y,
		]
		_footer.text += "\n[ ESC ] close, changes are saved as you make them"
		return
	_footer.text = "window %d x %d     [ ESC ] close, changes are saved as you make them" % [
		settings_size.x, settings_size.y,
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		# Esc backs out one level: capture, then the controls list, then the menu itself.
		if _controls_panel != null:
			_close_controls()
		else:
			close()


func close() -> void:
	settings_closed.emit()
	AudioDirector.play(&"ui_click", -6.0)
	queue_free()


func _compute_scale() -> float:
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return 1.0
	return clampf(minf(viewport.x / REFERENCE.x, viewport.y / REFERENCE.y), 0.35, 4.0)


func _on_viewport_resized() -> void:
	# Any size change, not only a scale change: the panel is centred from the viewport, so a width-only
	# resize still moves it. Deferred, for the reason `_resize_pending` explains.
	_resize_pending = true


func _rebuild() -> void:
	_scale = _compute_scale()
	_close_controls()
	_panel.free()
	_panel = null
	_build()
	_sync()
	_focus_tab_for_pad()


#region building

func _build() -> void:
	var viewport: Vector2 = get_viewport().get_visible_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.88)
	# Positioned explicitly from the viewport rather than with anchors: an overlay Control
	# parented to another Control does not reliably inherit its rect, and half-off-screen
	# menus are a bad way to find that out.
	dim.position = Vector2.ZERO
	dim.size = viewport
	# Swallows clicks, so nothing behind the menu reacts while it is open.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Control.new()
	_panel.name = "Panel"
	_panel.position = (viewport - PANEL_SIZE * _scale) * 0.5
	_panel.size = PANEL_SIZE * _scale
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_rect(_panel, Vector2(-3.0, -3.0), PANEL_SIZE + Vector2(6.0, 6.0), Color(0.16, 0.19, 0.24))
	_rect(_panel, Vector2.ZERO, PANEL_SIZE, Color(0.055, 0.065, 0.085, 0.98))
	_label(Vector2(ROW_LEFT, 34.0), "SETTINGS", 30, Color(0.92, 0.96, 1.0))
	_build_tabs()

	_mode_button = OptionButton.new()
	_mode_button.add_item("Windowed", GameSettings.WindowMode.WINDOWED)
	_mode_button.add_item("Fullscreen (borderless)", GameSettings.WindowMode.BORDERLESS)
	_mode_button.add_item("Fullscreen (exclusive)", GameSettings.WindowMode.EXCLUSIVE)
	_mode_button.item_selected.connect(_on_mode_selected)
	_add_row("Window mode", _mode_button, 0, TAB_DISPLAY)

	_resolution_button = OptionButton.new()
	_resolution_sizes = Settings.resolution_options()
	var desktop: Vector2i = DisplayServer.screen_get_size()
	for i: int in _resolution_sizes.size():
		var res_size: Vector2i = _resolution_sizes[i]
		var text: String = "%d x %d" % [res_size.x, res_size.y]
		if res_size == desktop:
			text += "   (desktop)"
		_resolution_button.add_item(text, i)
	_resolution_button.item_selected.connect(_on_resolution_selected)
	_add_row("Resolution", _resolution_button, 1, TAB_DISPLAY)

	_vsync_button = CheckButton.new()
	_vsync_button.text = "on"
	_vsync_button.toggled.connect(_on_vsync_toggled)
	_add_row("Vertical sync", _vsync_button, 2, TAB_DISPLAY)

	_fps_label = _add_row("Frame rate cap", _build_fps_control(), 3, TAB_DISPLAY)

	_master_slider = _slider()
	_master_label = _add_row("Master volume", _master_slider, 0, TAB_AUDIO)
	_master_slider.value_changed.connect(_on_master_changed)

	_music_slider = _slider()
	_music_label = _add_row("Music", _music_slider, 1, TAB_AUDIO)
	_music_slider.value_changed.connect(_on_music_changed)

	_sfx_slider = _slider()
	_sfx_label = _add_row("Sound effects", _sfx_slider, 2, TAB_AUDIO)
	_sfx_slider.value_changed.connect(_on_sfx_changed)

	_aim_line_button = CheckButton.new()
	_aim_line_button.tooltip_text = "A line along your next shot, with a crosshair where it would hit."
	_aim_line_button.toggled.connect(func(pressed: bool) -> void: Settings.set_aim_line(pressed))
	_add_row("Aim line", _aim_line_button, 0, TAB_GAMEPLAY)

	_aim_assist_button = CheckButton.new()
	_aim_assist_button.tooltip_text = "Pulls right-stick aim onto a visible enemy you are already pointing near."
	_aim_assist_button.toggled.connect(func(pressed: bool) -> void: Settings.set_aim_assist(pressed))
	_add_row("Gamepad aim assist", _aim_assist_button, 1, TAB_GAMEPLAY)

	_aim_assist_slider = _slider()
	_aim_assist_slider.min_value = GameSettings.AIM_ASSIST_STRENGTH_MIN * 100.0
	_aim_assist_slider.step = 5.0
	_aim_assist_slider.tooltip_text = "How hard aim is pulled, and from how far off the enemy."
	_aim_assist_label = _add_row("Assist strength", _aim_assist_slider, 2, TAB_GAMEPLAY)
	_aim_assist_slider.value_changed.connect(_on_aim_assist_strength_changed)

	_link_tab(TAB_DISPLAY, _mode_button)
	_link_tab(TAB_AUDIO, _master_slider)
	_link_tab(TAB_GAMEPLAY, _aim_line_button)
	_seal_fps_row()
	for tab: Button in _tabs:
		_seal(tab, [SIDE_TOP])
	_seal(_tabs[0], [SIDE_LEFT])
	_seal(_tabs[-1], [SIDE_RIGHT])
	_select_tab(_current_tab)

	# --- buttons. `y` is kept unscaled because every use below multiplies by `_scale`.
	var y: float = ROW_TOP + float(MAX_ROWS) * ROW_HEIGHT + 12.0
	var controls := Button.new()
	controls.text = "Controls"
	controls.position = Vector2(ROW_LEFT, y) * _scale
	controls.size = Vector2(150.0, 38.0) * _scale
	controls.add_theme_font_size_override("font_size", _font(17))
	controls.pressed.connect(_open_controls)
	_panel.add_child(controls)

	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.position = Vector2(ROW_LEFT + 162.0, y) * _scale
	reset.size = Vector2(210.0, 38.0) * _scale
	reset.add_theme_font_size_override("font_size", _font(17))
	reset.pressed.connect(_on_reset_pressed)
	_panel.add_child(reset)

	var done := Button.new()
	done.text = "Done"
	done.position = Vector2(PANEL_SIZE.x - ROW_RIGHT - 150.0, y) * _scale
	done.size = Vector2(150.0, 38.0) * _scale
	done.add_theme_font_size_override("font_size", _font(17))
	done.pressed.connect(close)
	_panel.add_child(done)
	_seal(controls, [SIDE_LEFT, SIDE_BOTTOM])
	_seal(reset, [SIDE_BOTTOM])
	_seal(done, [SIDE_RIGHT, SIDE_BOTTOM])

	# All the space between the buttons and the panel's bottom edge, with the text sitting at the bottom of
	# it: one line normally, three when embedded in the editor (the two fixed rows get a line explaining
	# them, and the close hint moves to its own). A fixed two-line box let the third line hang out of the
	# panel.
	var footer_top: float = y + 38.0 + 8.0
	_footer = _label(Vector2(0.0, footer_top), "", 15, Color(0.55, 0.62, 0.72))
	_footer.size = Vector2(PANEL_SIZE.x, PANEL_SIZE.y - 12.0 - footer_top) * _scale
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM


## The tab strip, and an empty page for each tab.
func _build_tabs() -> void:
	_tabs.clear()
	_pages.clear()
	var count: float = float(TAB_NAMES.size())
	var width: float = (PANEL_SIZE.x - ROW_LEFT - ROW_RIGHT - TAB_GAP * (count - 1.0)) / count
	for i: int in TAB_NAMES.size():
		var tab := Button.new()
		tab.text = TAB_NAMES[i]
		tab.toggle_mode = true
		tab.position = Vector2(ROW_LEFT + float(i) * (width + TAB_GAP), TAB_TOP) * _scale
		tab.size = Vector2(width, TAB_HEIGHT) * _scale
		tab.add_theme_font_size_override("font_size", _font(18))
		for state: String in ["font_color", "font_hover_color", "font_focus_color"]:
			tab.add_theme_color_override(state, Color(0.55, 0.62, 0.72))
		for state: String in ["font_pressed_color", "font_hover_pressed_color"]:
			tab.add_theme_color_override(state, Color(0.92, 0.96, 1.0))
		tab.pressed.connect(_select_tab.bind(i))
		# Moving along the tabs with a pad switches page, with no extra press.
		tab.focus_entered.connect(_select_tab.bind(i))
		_panel.add_child(tab)
		_tabs.append(tab)

		var page := Control.new()
		page.name = "Page%s" % TAB_NAMES[i]
		page.size = _panel.size
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(page)
		_pages.append(page)
	_tab_marker = _rect(_panel, Vector2.ZERO, Vector2(width, 3.0), Color(0.55, 0.72, 0.95))


func _select_tab(index: int) -> void:
	if index != _current_tab:
		AudioDirector.play(&"ui_click", -6.0)
	_current_tab = index
	for i: int in _tabs.size():
		_tabs[i].set_pressed_no_signal(i == index)
		_pages[i].visible = i == index
	_tab_marker.position = _tabs[index].position + Vector2(0.0, _tabs[index].size.y)


## A tab and the first row of its page lead to each other. Left to the engine, up from a row would land
## on whichever tab was nearest, and switch page.
func _link_tab(index: int, first_row: Control) -> void:
	var tab: Button = _tabs[index]
	tab.focus_neighbor_bottom = tab.get_path_to(first_row)
	first_row.focus_neighbor_top = first_row.get_path_to(tab)


## With a pad there is no pointer, so something has to hold focus before anything can be pressed.
func _focus_tab_for_pad() -> void:
	if not GameInput.using_gamepad() or _controls_panel != null or _tabs.is_empty():
		return
	# The menu behind this one holds focus when it opens, so "somebody has focus" is not enough.
	var owner_: Control = get_viewport().gui_get_focus_owner()
	if owner_ == null or not is_ancestor_of(owner_):
		_tabs[_current_tab].grab_focus()


## Stops focus at `control`'s edge on each of `sides`. The menu that opened this one is still on screen
## behind it, and left to itself a pad's d-pad would walk out onto its buttons.
func _seal(control: Control, sides: Array[Side]) -> void:
	for side: Side in sides:
		control.set_focus_neighbor(side, control.get_path_to(control))


## Adds a labelled row to a tab's page and returns its label, so a volume row can update its own text.
func _add_row(text: String, control: Control, index: int, tab: int) -> Label:
	var y: float = ROW_TOP + float(index) * ROW_HEIGHT
	var label := _label(Vector2(ROW_LEFT, y), text, 18, LABEL_COLOR, _pages[tab])
	label.size = Vector2(PANEL_SIZE.x - ROW_LEFT - CONTROL_WIDTH - ROW_RIGHT, 32.0) * _scale
	control.position = Vector2(PANEL_SIZE.x - ROW_RIGHT - CONTROL_WIDTH, y) * _scale
	control.size = Vector2(CONTROL_WIDTH, 34.0) * _scale
	if control.has_method("add_theme_font_size_override"):
		control.add_theme_font_size_override("font_size", _font(17))
	_pages[tab].add_child(control)
	_seal(control, [SIDE_LEFT, SIDE_RIGHT])
	return label


## The slider and the number field side by side. The slider's notch past `FPS_CAP_MAX` is "unlimited",
## so the whole range is reachable by dragging alone.
func _build_fps_control() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(round(10.0 * _scale)))
	_fps_slider = HSlider.new()
	_fps_slider.min_value = GameSettings.FPS_CAP_MIN
	_fps_slider.max_value = GameSettings.FPS_CAP_MAX + 1
	_fps_slider.step = 1.0
	_fps_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fps_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fps_slider.value_changed.connect(_on_fps_slider_changed)
	row.add_child(_fps_slider)
	_fps_field = LineEdit.new()
	_fps_field.custom_minimum_size = Vector2(FPS_FIELD_WIDTH, 0.0) * _scale
	_fps_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_field.add_theme_font_size_override("font_size", _font(16))
	_fps_field.text_submitted.connect(_on_fps_field_submitted)
	_fps_field.focus_exited.connect(func() -> void: _on_fps_field_submitted(_fps_field.text))
	row.add_child(_fps_field)
	return row


## The frame rate row is two controls, so its edges are sealed separately once both are in the tree.
func _seal_fps_row() -> void:
	_seal(_fps_slider, [SIDE_LEFT])
	_fps_slider.focus_neighbor_right = _fps_slider.get_path_to(_fps_field)
	_fps_field.focus_neighbor_left = _fps_field.get_path_to(_fps_slider)
	_seal(_fps_field, [SIDE_RIGHT])


func _slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	return slider


func _rect(parent: Control, position_: Vector2, rect_size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = position_ * _scale
	rect.size = rect_size * _scale
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _label(position_: Vector2, text: String, font_size: int, color: Color,
		parent: Control = null) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_ * _scale
	label.add_theme_font_size_override("font_size", _font(font_size))
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else _panel).add_child(label)
	return label


func _font(font_size: int) -> int:
	return maxi(1, int(round(float(font_size) * _scale)))

#endregion


#region state

## Pushes the stored settings into the controls. Also called when anything else changes
## them, so the menu can never show a stale value.
func _sync() -> void:
	if _panel == null:
		return
	_mode_button.select(_mode_button.get_item_index(int(Settings.window_mode)))
	var index: int = _resolution_sizes.find(Settings.resolution)
	_resolution_button.selected = index if index >= 0 else -1
	# Two reasons a row can be inert, and the footer explains whichever applies: a fullscreen
	# mode ignores the resolution, and the editor's embedded game window ignores both.
	var embedded: bool = Engine.is_embedded_in_editor()
	_mode_button.disabled = embedded
	_resolution_button.disabled = embedded or not Settings.resolution_is_relevant()
	_vsync_button.button_pressed = Settings.vsync_enabled
	# The switch's own text says which way it is; it used to read "on" whichever way it was set.
	_vsync_button.text = "on" if Settings.vsync_enabled else "off"
	_aim_line_button.set_pressed_no_signal(Settings.aim_line_enabled)
	_aim_line_button.text = "on" if Settings.aim_line_enabled else "off"
	_sync_aim_assist()
	_sync_fps()
	_master_slider.set_value_no_signal(GameSettings.db_to_slider(Settings.master_volume_db))
	_music_slider.set_value_no_signal(GameSettings.db_to_slider(Settings.music_volume_db))
	_sfx_slider.set_value_no_signal(GameSettings.db_to_slider(Settings.sfx_volume_db))
	_update_volume_labels()


func _update_volume_labels() -> void:
	_master_label.text = "Master volume   %d%%" % int(round(_master_slider.value))
	_music_label.text = "Music   %d%%" % int(round(_music_slider.value))
	_sfx_label.text = "Sound effects   %d%%" % int(round(_sfx_slider.value))


## The strength means nothing with the assist off, so the row goes inert, like the frame rate cap.
func _sync_aim_assist() -> void:
	_aim_assist_button.set_pressed_no_signal(Settings.aim_assist_enabled)
	_aim_assist_button.text = "on" if Settings.aim_assist_enabled else "off"
	_aim_assist_slider.set_value_no_signal(Settings.aim_assist_strength * 100.0)
	_aim_assist_slider.editable = Settings.aim_assist_enabled
	_aim_assist_label.text = "Assist strength   %d%%" % int(round(_aim_assist_slider.value))
	_aim_assist_label.modulate = LABEL_COLOR if Settings.aim_assist_enabled else LABEL_INERT_COLOR


func _on_aim_assist_strength_changed(value: float) -> void:
	Settings.set_aim_assist_strength(value / 100.0)


## The cap only applies with vsync off, so the row goes inert while vsync is on, and its label says why.
func _sync_fps() -> void:
	var cap: int = Settings.fps_cap
	var unlimited: bool = cap == GameSettings.FPS_UNLIMITED
	_fps_slider.set_value_no_signal(GameSettings.FPS_CAP_MAX + 1 if unlimited else cap)
	if not _fps_field.has_focus():
		_fps_field.text = "Unlimited" if unlimited else str(cap)
	var active: bool = not Settings.vsync_enabled
	_fps_slider.editable = active
	_fps_field.editable = active
	# Greyed rather than explained in the label, which has no room for it; the tooltip says why.
	_fps_label.modulate = LABEL_COLOR if active else LABEL_INERT_COLOR
	var why: String = "" if active else "
Only applies while vertical sync is off."
	_fps_slider.tooltip_text = "Frames per second the game is held to.%s" % why
	_fps_field.tooltip_text = "Frames per second (%d to %d), or 0 / \"unlimited\" for no cap.%s" % [
		GameSettings.FPS_CAP_MIN, GameSettings.FPS_CAP_MAX, why]


func _on_fps_slider_changed(value: float) -> void:
	var cap: int = int(value)
	Settings.set_fps_cap(GameSettings.FPS_UNLIMITED if cap > GameSettings.FPS_CAP_MAX else cap)
	_sync_fps()


## A typed cap: a number (clamped to the range), or 0, "unlimited" or nothing for no cap. Anything else
## is ignored and the field goes back to the current value.
func _on_fps_field_submitted(text: String) -> void:
	var typed: String = text.strip_edges().to_lower()
	if typed.is_empty() or typed.begins_with("unl") or typed == "0" or typed == "∞":
		Settings.set_fps_cap(GameSettings.FPS_UNLIMITED)
	elif typed.is_valid_int() or typed.is_valid_float():
		Settings.set_fps_cap(int(round(typed.to_float())))
	_fps_field.release_focus()
	_fps_field.text = ""
	_sync_fps()


func _on_mode_selected(index: int) -> void:
	Settings.set_window_mode(_mode_button.get_item_id(index) as GameSettings.WindowMode)


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= _resolution_sizes.size():
		return
	Settings.set_resolution(_resolution_sizes[index])


func _on_vsync_toggled(pressed: bool) -> void:
	Settings.set_vsync(pressed)


func _on_master_changed(value: float) -> void:
	_update_volume_labels()
	Settings.set_master_volume_db(GameSettings.slider_to_db(value))


func _on_music_changed(value: float) -> void:
	_update_volume_labels()
	Settings.set_music_volume_db(GameSettings.slider_to_db(value))


func _on_sfx_changed(value: float) -> void:
	_update_volume_labels()
	Settings.set_sfx_volume_db(GameSettings.slider_to_db(value))


func _on_reset_pressed() -> void:
	AudioDirector.play(&"ui_click", -6.0)
	Settings.reset_defaults()

#endregion


#region controls

## Swaps the settings for the rebinding list. A second panel rather than another tab: the list is long
## enough to scroll, so it wants a different layout.
func _open_controls() -> void:
	if _controls_panel != null:
		return
	AudioDirector.play(&"ui_click", -6.0)
	_panel.visible = false

	_controls_panel = Control.new()
	_controls_panel.name = "ControlsPanel"
	_controls_panel.position = (get_viewport().get_visible_rect().size - CONTROLS_PANEL_SIZE * _scale) * 0.5
	_controls_panel.size = CONTROLS_PANEL_SIZE * _scale
	_controls_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_controls_panel)

	_rect(_controls_panel, Vector2(-3.0, -3.0), CONTROLS_PANEL_SIZE + Vector2(6.0, 6.0),
		Color(0.16, 0.19, 0.24))
	_rect(_controls_panel, Vector2.ZERO, CONTROLS_PANEL_SIZE, Color(0.055, 0.065, 0.085, 0.98))
	_label(Vector2(ROW_LEFT, 34.0), "CONTROLS", 30, Color(0.92, 0.96, 1.0), _controls_panel)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(ROW_LEFT, 84.0) * _scale
	scroll.size = Vector2(CONTROLS_PANEL_SIZE.x - ROW_LEFT - ROW_RIGHT, CONTROLS_PANEL_SIZE.y - 84.0 - 108.0) * _scale
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_controls_panel.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", _font(6))
	scroll.add_child(list)

	for group: String in GameInput.groups():
		var heading := Label.new()
		heading.text = group.to_upper()
		heading.add_theme_font_size_override("font_size", _font(15))
		heading.modulate = Color(0.55, 0.62, 0.72)
		list.add_child(heading)
		for action: String in GameInput.actions_in(group):
			list.add_child(_binding_row(action))

	_controls_status = _label(Vector2(ROW_LEFT, CONTROLS_PANEL_SIZE.y - 92.0), "", 15,
		Color(0.72, 0.8, 0.9), _controls_panel)
	_controls_status.size = Vector2(CONTROLS_PANEL_SIZE.x - ROW_LEFT - ROW_RIGHT, 24.0) * _scale
	_controls_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var reset_all := Button.new()
	reset_all.text = "Reset all controls"
	reset_all.position = Vector2(ROW_LEFT, CONTROLS_PANEL_SIZE.y - 56.0) * _scale
	reset_all.size = Vector2(210.0, 38.0) * _scale
	reset_all.add_theme_font_size_override("font_size", _font(17))
	reset_all.pressed.connect(_on_reset_controls_pressed)
	_controls_panel.add_child(reset_all)

	var back := Button.new()
	back.text = "Back"
	back.position = Vector2(CONTROLS_PANEL_SIZE.x - ROW_RIGHT - 150.0, CONTROLS_PANEL_SIZE.y - 56.0) * _scale
	back.size = Vector2(150.0, 38.0) * _scale
	back.add_theme_font_size_override("font_size", _font(17))
	back.pressed.connect(_close_controls)
	_controls_panel.add_child(back)
	_seal(reset_all, [SIDE_LEFT, SIDE_BOTTOM])
	_seal(back, [SIDE_RIGHT, SIDE_BOTTOM])
	var first_binding: Button = null
	for key: Variant in _binding_buttons:
		var binding: Button = _binding_buttons[key]
		_seal(binding, [SIDE_LEFT, SIDE_RIGHT])
		if first_binding == null:
			first_binding = binding
	if first_binding != null:
		_seal(first_binding, [SIDE_TOP])
		if GameInput.using_gamepad():
			first_binding.grab_focus()


func _close_controls() -> void:
	_finish_capture()
	if _controls_panel != null:
		_controls_panel.queue_free()
		_controls_panel = null
	_controls_status = null
	_binding_buttons.clear()
	if _panel != null and is_instance_valid(_panel):
		_panel.visible = true
		_focus_tab_for_pad()


## One row: the action's name and a button showing what it is bound to. Pressing the button starts
## capturing the next key or mouse button.
func _binding_row(action: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _font(8))

	var label := Label.new()
	label.text = GameInput.action_label(action)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", _font(17))
	label.modulate = Color(0.78, 0.85, 0.93)
	row.add_child(label)

	var button := Button.new()
	button.custom_minimum_size = Vector2(190.0, 30.0) * _scale
	button.add_theme_font_size_override("font_size", _font(16))
	button.text = GameInput.describe_action(action)
	button.pressed.connect(_on_rebind_pressed.bind(action))
	row.add_child(button)

	_binding_buttons[action] = button
	return row


func _on_rebind_pressed(action: String) -> void:
	if not _capture_action.is_empty():
		return
	AudioDirector.play(&"ui_click", -12.0)
	_capture_action = action
	_status("Press a key or mouse button.   Esc cancels.", Color(0.72, 0.8, 0.9))
	var button: Button = _binding_buttons.get(action)
	if button != null and is_instance_valid(button):
		button.text = "press a key..."


## Capture runs in `_input`, not `_unhandled_input`: a focused Button would otherwise eat Space and
## Enter as "activate", and those are keys the player may legitimately want to bind.
func _input(event: InputEvent) -> void:
	if _capture_action.is_empty():
		return
	if event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return
		get_viewport().set_input_as_handled()
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			_finish_capture()
			_status("", Color(0.72, 0.8, 0.9))
			return
		_try_bind(key)
		return
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		# Release only: the click that opened the capture is still being released.
		if not mouse.pressed:
			return
		get_viewport().set_input_as_handled()
		_try_bind(mouse)
		return
	if event is InputEventJoypadButton:
		var pad_button: InputEventJoypadButton = event
		if not pad_button.pressed:
			return
		get_viewport().set_input_as_handled()
		_try_bind(pad_button)
		return
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		# A stick reports continuously; bind on the first push past the halfway point and ignore the
		# drift on the way back.
		if absf(motion.axis_value) < 0.6:
			return
		get_viewport().set_input_as_handled()
		_try_bind(motion)


func _try_bind(event: InputEvent) -> void:
	var action: String = _capture_action
	var events: Array[InputEvent] = [event]
	if GameInput.is_reserved(event):
		_status("F1-F12 are reserved", Color(0.95, 0.55, 0.45))
		_finish_capture()
		return
	var conflict: String = GameInput.conflict_for(action, events)
	if not conflict.is_empty():
		# Refused rather than accepted: two actions on one key is a bug the player cannot see, and the
		# second one wins silently.
		_status("Already used by %s" % GameInput.action_label(conflict), Color(0.95, 0.55, 0.45))
		_finish_capture()
		return
	GameInput.rebind(action, event)
	_finish_capture()
	_status("", Color(0.72, 0.8, 0.9))


## Ends a capture and puts the button's text back.
func _finish_capture() -> void:
	if _capture_action.is_empty():
		return
	var action: String = _capture_action
	_capture_action = ""
	var button: Button = _binding_buttons.get(action)
	if button != null and is_instance_valid(button):
		button.text = GameInput.describe_action(action)


func _refresh_bindings() -> void:
	for key: Variant in _binding_buttons:
		var button: Button = _binding_buttons[key]
		if is_instance_valid(button):
			button.text = GameInput.describe_action(String(key))


func _status(text: String, color: Color) -> void:
	if _controls_status == null or not is_instance_valid(_controls_status):
		return
	_controls_status.text = text
	_controls_status.modulate = color


func _on_reset_controls_pressed() -> void:
	AudioDirector.play(&"ui_click", -6.0)
	GameInput.reset_all()
	_status("Controls reset to defaults.", Color(0.6, 0.85, 0.6))

#endregion
