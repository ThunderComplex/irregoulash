class_name MenuList
extends Control
## A vertical list of menu buttons, laid out in the same 1280x720 reference frame as the rest of
## the UI and scaled to the window, so it is the same size at any resolution.
##
## Keyboard navigation is not reimplemented here: it comes free from Control focus. The first
## enabled button grabs focus, the arrow keys are built-in `ui_*` actions, and Enter/Space
## activates whatever is focused. The mouse works as well, and `activate()` exists for the dev
## probe, which cannot synthesise a reliable click on a Control.
##
## Disabled items are greyed out *and* unfocusable, so the keyboard cannot walk into a dead end.

signal activated(id: StringName)

const ROW_HEIGHT: float = 48.0
const ROW_GAP: float = 8.0

var _scale: float = 1.0
var _columns: int = 1
var _buttons: Array[Button] = []
var _ids: Array[StringName] = []


## `rect` is in reference units; the list occupies that rectangle on screen. `columns` above 1
## lays the items out as a grid, which is how four buttons fit in a title screen whose text
## already fills the frame. Size the rectangle as rows * ROW_HEIGHT: the items divide it evenly.
func configure(rect: Rect2, scale: float, columns: int = 1) -> void:
	_scale = maxf(0.1, scale)
	_columns = maxi(1, columns)
	position = rect.position * _scale
	size = rect.size * _scale
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func add_item(id: StringName, text: String, enabled: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER if _columns > 1 else HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", _font(19))
	_apply_theme(button, enabled)
	button.pressed.connect(_on_pressed.bind(id))
	add_child(button)
	_buttons.append(button)
	_ids.append(id)
	# Laid out on every add, so the caller never has to know the final count.
	layout()
	return button


## Divides the rectangle evenly between the items: one column is a plain vertical list, more are
## a grid. Called on every add, so the caller never has to know the final count.
func layout() -> void:
	var count: int = _buttons.size()
	if count == 0:
		return
	var columns: int = maxi(1, mini(_columns, count))
	var rows: int = int(ceil(float(count) / float(columns)))
	var cell: Vector2 = Vector2(size.x / float(columns), size.y / float(rows))
	for i: int in count:
		_buttons[i].position = Vector2(
			cell.x * float(i % columns) + ROW_GAP * 0.5 * _scale,
			cell.y * float(i / columns) + ROW_GAP * 0.5 * _scale)
		_buttons[i].size = Vector2(cell.x - ROW_GAP * _scale, cell.y - ROW_GAP * _scale)


## Re-label or enable/disable an existing item, so a menu can reflect a change without being
## rebuilt (and without losing focus).
func set_item(id: StringName, text: String, enabled: bool) -> void:
	var button := button_for(id)
	if button == null:
		return
	button.text = text
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE


## Focus the first enabled item, so the menu is immediately usable from the keyboard.
func focus_first() -> void:
	for button: Button in _buttons:
		if not button.disabled:
			button.grab_focus()
			return


## Whether this item currently holds keyboard focus. (Not called `has_focus`: that is a native
## `Control` method, and overriding it with a different signature is an error.)
func item_has_focus(id: StringName) -> bool:
	var button := button_for(id)
	if button == null:
		return false
	return get_viewport().gui_get_focus_owner() == button


## Focus a particular item, so a menu can open on its most likely choice (Enter should resume a
## paused game, not open the settings). Falls back to the first enabled item.
func focus_item(id: StringName) -> void:
	var button := button_for(id)
	if button != null and not button.disabled:
		button.grab_focus()
		return
	focus_first()


func activate(id: StringName) -> bool:
	var index: int = _ids.find(id)
	if index < 0 or _buttons[index].disabled:
		return false
	_on_pressed(id)
	return true


func item_count() -> int:
	return _buttons.size()


## The button for an id, so a test can click the thing a player would click.
func button_for(id: StringName) -> Button:
	var index: int = _ids.find(id)
	if index < 0:
		return null
	return _buttons[index]


func item_ids() -> Array[StringName]:
	return _ids.duplicate()


func item_text(index: int) -> String:
	if index < 0 or index >= _buttons.size():
		return ""
	return _buttons[index].text


func item_enabled(index: int) -> bool:
	if index < 0 or index >= _buttons.size():
		return false
	return not _buttons[index].disabled


func _on_pressed(id: StringName) -> void:
	AudioDirector.play(&"ui_click", -6.0)
	activated.emit(id)


func _font(font_size: int) -> int:
	return maxi(1, int(round(float(font_size) * _scale)))


## Flat, dark buttons to match the rest of the code-drawn UI instead of the engine's default
## theme, which would make the title screen look like a prototype.
func _apply_theme(button: Button, enabled: bool) -> void:
	var font: Color = Color(0.86, 0.91, 0.97) if enabled else Color(0.44, 0.48, 0.55)
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.94, 0.75))
	button.add_theme_color_override("font_focus_color", Color(0.95, 0.98, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.4, 0.43, 0.5))
	button.add_theme_stylebox_override("normal", _style(Color(0.09, 0.10, 0.13, 0.92),
		Color(0.22, 0.26, 0.33)))
	button.add_theme_stylebox_override("hover", _style(Color(0.16, 0.19, 0.25, 0.96),
		Color(0.45, 0.52, 0.65)))
	button.add_theme_stylebox_override("pressed", _style(Color(0.20, 0.24, 0.30, 1.0),
		Color(0.60, 0.70, 0.85)))
	button.add_theme_stylebox_override("focus", _style(Color(0.14, 0.17, 0.22, 0.98),
		Color(0.72, 0.84, 1.0)))
	button.add_theme_stylebox_override("disabled", _style(Color(0.07, 0.075, 0.09, 0.70),
		Color(0.16, 0.18, 0.22)))


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(maxi(1, int(round(2.0 * _scale))))
	style.set_corner_radius_all(maxi(1, int(round(3.0 * _scale))))
	style.content_margin_left = 16.0 * _scale
	style.content_margin_right = 16.0 * _scale
	style.content_margin_top = 6.0 * _scale
	style.content_margin_bottom = 6.0 * _scale
	return style
