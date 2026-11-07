@tool
class_name KeyHint
extends Node2D
## A key cap painted on the floor, showing whatever the player has bound to an action, with an optional
## line of text beside it: "[F] Open doors". Pick the action in the inspector; in game the cap shows the
## player's own binding, and the pad button once they pick up a controller, so a rebind can never leave
## a hint lying about the keys.
##
## In the editor it shows the default keyboard binding. Always visible and drawn on the floor, like
## `FloorText`.

const GameInputScript: GDScript = preload("res://src/autoload/game_input.gd")
## Actions not offered in the inspector besides the cheats: the right stick's four directions (aim is
## the mouse on a keyboard).
const HIDDEN_ACTIONS: Array[String] = ["aim_left", "aim_right", "aim_up", "aim_down"]
const CAP_PADDING: Vector2 = Vector2(8.0, 3.0)
## Space between the cap and the text, in units of the font size.
const GAP: float = 0.55

## The action whose key is shown (the list in the inspector is `GameInput.META`).
@export var action: String = "interact":
	set(value):
		action = value
		queue_redraw()
## Shown to the right of the key cap. Empty for the cap alone.
@export var text: String = "":
	set(value):
		text = value
		queue_redraw()
@export_range(6, 96, 1) var font_size: int = 18:
	set(value):
		font_size = value
		queue_redraw()
## The text, the key's name and the cap's border.
@export var color: Color = Color(0.82, 0.86, 0.92, 0.75):
	set(value):
		color = value
		queue_redraw()
## The cap's fill.
@export var cap_color: Color = Color(0.05, 0.06, 0.08, 0.6):
	set(value):
		cap_color = value
		queue_redraw()
@export_range(0, 16, 1) var outline_size: int = 4:
	set(value):
		outline_size = value
		queue_redraw()
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.55):
	set(value):
		outline_color = value
		queue_redraw()


func _validate_property(property: Dictionary) -> void:
	if property.name == "action":
		var names: PackedStringArray = []
		for name_: String in GameInputScript.META:
			if hint_action(name_):
				names.append(name_)
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(names)


static func hint_action(name_: String) -> bool:
	return not GameInputScript.is_debug_action(name_) and not HIDDEN_ACTIONS.has(name_)


func _ready() -> void:
	FloorText.setup_floor_canvas(self)
	if Engine.is_editor_hint():
		return
	GameInput.bindings_changed.connect(queue_redraw)
	GameInput.device_changed.connect(func(_gamepad: bool) -> void: queue_redraw())


## What the cap says right now: the live binding in game, the default keyboard binding in the editor.
func key_text() -> String:
	if not GameInputScript.META.has(action):
		return "?"
	if not Engine.is_editor_hint():
		return GameInput.describe_for_device(action)
	for spec: Variant in GameInputScript.DEFAULT_SPECS.get(action, []):
		var event: InputEvent = GameInputScript.event_from_spec(spec)
		if event is InputEventKey or event is InputEventMouseButton:
			return GameInputScript.describe(event)
	return "?"


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var key: String = key_text()
	var key_width: float = font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var cap_height: float = font.get_height(font_size) + CAP_PADDING.y * 2.0
	# A single letter gets a square cap; "Space" and "LMB" stretch it.
	var cap_width: float = maxf(key_width + CAP_PADDING.x * 2.0, cap_height)
	var gap: float = GAP * float(font_size)
	var text_width: float = 0.0
	if not text.is_empty():
		text_width = gap + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# Cap and text together are centred on the node.
	var cap := Rect2(-(cap_width + text_width) * 0.5, -cap_height * 0.5, cap_width, cap_height)

	var box := StyleBoxFlat.new()
	box.bg_color = cap_color
	box.border_color = color
	box.set_border_width_all(maxi(1, int(round(float(font_size) / 10.0))))
	box.set_corner_radius_all(int(round(cap_height * 0.2)))
	box.anti_aliasing = true
	draw_style_box(box, cap)
	FloorText.draw_centered_lines(self, key, font_size, color, 0, outline_color, cap.get_center())
	if not text.is_empty():
		FloorText.draw_centered_lines(self, text, font_size, color, outline_size, outline_color,
			Vector2(cap.end.x + gap + (text_width - gap) * 0.5, 0.0))
