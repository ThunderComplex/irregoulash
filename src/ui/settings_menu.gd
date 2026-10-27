class_name SettingsMenu
extends Control
## The settings menu. Opened from the title screen and from the pause overlay.
##
## Changes apply and persist the moment they are made -- there is no Apply button to forget,
## and no way to lose a change by backing out. Escape closes it.
##
## Built in code like the HUD, and laid out in the coordinates of a 1280x720 frame scaled
## to fit the window, so it is complete and legible at any resolution. The footer reports
## the real window size, which is also the quickest way to *see* that the rest of the game
## coped with the change.

const REFERENCE: Vector2 = Vector2(1280.0, 720.0)
const PANEL_SIZE: Vector2 = Vector2(620.0, 540.0)
const ROW_LEFT: float = 44.0
const CONTROL_WIDTH: float = 300.0
const ROW_RIGHT: float = 44.0
const ROW_TOP: float = 110.0
const ROW_HEIGHT: float = 54.0

var _scale: float = 1.0
var _panel: Control = null
var _mode_button: OptionButton = null
var _resolution_button: OptionButton = null
var _vsync_button: CheckButton = null
var _master_slider: HSlider = null
var _sfx_slider: HSlider = null
var _master_label: Label = null
var _sfx_label: Label = null
var _footer: Label = null
## Parallel to the resolution OptionButton's items.
var _resolution_sizes: Array[Vector2i] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Usable while the game is paused, which is the point of it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scale = _compute_scale()
	_build()
	_sync()
	get_viewport().size_changed.connect(_on_viewport_resized)
	Settings.changed.connect(_sync)


func _process(_delta: float) -> void:
	if _footer == null:
		return
	var size: Vector2i = Vector2i(get_viewport().get_visible_rect().size)
	_footer.text = "window %d x %d     [ ESC ] close, changes are saved as you make them" % [
		size.x, size.y,
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	AudioDirector.play(&"ui_click", -6.0)
	queue_free()


func _compute_scale() -> float:
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return 1.0
	return clampf(minf(viewport.x / REFERENCE.x, viewport.y / REFERENCE.y), 0.35, 4.0)


func _on_viewport_resized() -> void:
	if absf(_compute_scale() - _scale) < 0.001:
		return
	_scale = _compute_scale()
	_rebuild()


func _rebuild() -> void:
	_panel.free()
	_panel = null
	_build()
	_sync()


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

	_mode_button = OptionButton.new()
	_mode_button.add_item("Windowed", GameSettings.WindowMode.WINDOWED)
	_mode_button.add_item("Fullscreen (borderless)", GameSettings.WindowMode.BORDERLESS)
	_mode_button.add_item("Fullscreen (exclusive)", GameSettings.WindowMode.EXCLUSIVE)
	_mode_button.item_selected.connect(_on_mode_selected)
	_add_row("Window mode", _mode_button, 0)

	_resolution_button = OptionButton.new()
	_resolution_sizes = Settings.resolution_options()
	var desktop: Vector2i = DisplayServer.screen_get_size()
	for i: int in _resolution_sizes.size():
		var size: Vector2i = _resolution_sizes[i]
		var text: String = "%d x %d" % [size.x, size.y]
		if size == desktop:
			text += "   (desktop)"
		_resolution_button.add_item(text, i)
	_resolution_button.item_selected.connect(_on_resolution_selected)
	_add_row("Resolution", _resolution_button, 1)

	_vsync_button = CheckButton.new()
	_vsync_button.text = "on"
	_vsync_button.toggled.connect(_on_vsync_toggled)
	_add_row("Vertical sync", _vsync_button, 2)

	_master_slider = _slider()
	_master_label = _add_row("Master volume", _master_slider, 3)
	_master_slider.value_changed.connect(_on_master_changed)

	_sfx_slider = _slider()
	_sfx_label = _add_row("Sound effects", _sfx_slider, 4)
	_sfx_slider.value_changed.connect(_on_sfx_changed)

	# --- buttons. `y` is kept unscaled because every use below multiplies by `_scale`.
	var y: float = ROW_TOP + 5.0 * ROW_HEIGHT + 22.0
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.position = Vector2(ROW_LEFT, ROW_TOP + 5.0 * ROW_HEIGHT + 22.0) * _scale
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

	_footer = _label(Vector2(0.0, PANEL_SIZE.y - 44.0), "", 15, Color(0.55, 0.62, 0.72))
	_footer.size = Vector2(PANEL_SIZE.x, 26.0) * _scale
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Adds a labelled row and returns its label, so a volume row can update its own text.
func _add_row(text: String, control: Control, index: int) -> Label:
	var y: float = ROW_TOP + float(index) * ROW_HEIGHT
	var label := _label(Vector2(ROW_LEFT, y), text, 18, Color(0.72, 0.8, 0.9))
	label.size = Vector2(PANEL_SIZE.x - ROW_LEFT - CONTROL_WIDTH - ROW_RIGHT, 32.0) * _scale
	control.position = Vector2(PANEL_SIZE.x - ROW_RIGHT - CONTROL_WIDTH, y) * _scale
	control.size = Vector2(CONTROL_WIDTH, 34.0) * _scale
	if control.has_method("add_theme_font_size_override"):
		control.add_theme_font_size_override("font_size", _font(17))
	_panel.add_child(control)
	return label


func _slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	return slider


func _rect(parent: Control, position_: Vector2, size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = position_ * _scale
	rect.size = size * _scale
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _label(position_: Vector2, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_ * _scale
	label.add_theme_font_size_override("font_size", _font(font_size))
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(label)
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
	# Fullscreen modes ignore the resolution, so say so rather than showing a control that
	# looks like it does something.
	_resolution_button.disabled = not Settings.resolution_is_relevant()
	_vsync_button.button_pressed = Settings.vsync_enabled
	_master_slider.set_value_no_signal(GameSettings.db_to_slider(Settings.master_volume_db))
	_sfx_slider.set_value_no_signal(GameSettings.db_to_slider(Settings.sfx_volume_db))
	_update_volume_labels()


func _update_volume_labels() -> void:
	_master_label.text = "Master volume   %d%%" % int(round(_master_slider.value))
	_sfx_label.text = "Sound effects   %d%%" % int(round(_sfx_slider.value))


func _on_mode_selected(index: int) -> void:
	Settings.set_window_mode(_mode_button.get_item_id(index))


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= _resolution_sizes.size():
		return
	Settings.set_resolution(_resolution_sizes[index])


func _on_vsync_toggled(pressed: bool) -> void:
	Settings.set_vsync(pressed)


func _on_master_changed(value: float) -> void:
	_update_volume_labels()
	Settings.set_master_volume_db(GameSettings.slider_to_db(value))


func _on_sfx_changed(value: float) -> void:
	_update_volume_labels()
	Settings.set_sfx_volume_db(GameSettings.slider_to_db(value))


func _on_reset_pressed() -> void:
	AudioDirector.play(&"ui_click", -6.0)
	Settings.reset_defaults()

#endregion
