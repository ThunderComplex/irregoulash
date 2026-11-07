@tool
class_name FloorText
extends Node2D
## Text painted on the floor: a sign, a tutorial line, a joke. Place it anywhere in a level (Add Child
## Node > FloorText), type the text in the inspector, rotate and scale it like any node.
##
## It is always visible, lit or not: the level's black fog does not hide it, so it can teach the player
## something before they have seen the room. It sits on the floor -- under pickups, actors and walls --
## so anything standing on it covers it, the way real floor paint would.
##
## See `KeyHint` for a line that shows the key bound to an action.

## The text. Several lines are fine; each is centred on the node.
@export_multiline var text: String = "Text":
	set(value):
		text = value
		queue_redraw()
@export_range(6, 96, 1) var font_size: int = 18:
	set(value):
		font_size = value
		queue_redraw()
## Translucent by default, so it reads as paint on the floor rather than as a HUD element.
@export var color: Color = Color(0.82, 0.86, 0.92, 0.7):
	set(value):
		color = value
		queue_redraw()
## A dark edge around the letters, so the text reads on any floor texture. 0 for none.
@export_range(0, 16, 1) var outline_size: int = 4:
	set(value):
		outline_size = value
		queue_redraw()
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.55):
	set(value):
		outline_color = value
		queue_redraw()


func _ready() -> void:
	setup_floor_canvas(self)


## The draw settings both floor hints share: on the floor's depth, and unaffected by the fog.
static func setup_floor_canvas(item: CanvasItem) -> void:
	item.z_as_relative = false
	# Above decals (blood is painted on the floor too, and should not hide a hint), below pickups and
	# everything that moves.
	item.z_index = Layers.Z_DECAL + 1
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	item.material = unshaded


func _draw() -> void:
	draw_centered_lines(self, text, font_size, color, outline_size, outline_color, Vector2.ZERO)


## Draws `text` line by line, each line centred horizontally on `center.x`, the whole block centred
## vertically on `center.y`.
static func draw_centered_lines(item: CanvasItem, text_: String, size: int, fill: Color, outline: int,
		outline_fill: Color, center: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var lines: PackedStringArray = text_.split("\n")
	var line_height: float = font.get_height(size)
	var top: float = center.y - line_height * float(lines.size()) * 0.5
	for i: int in lines.size():
		var line: String = lines[i]
		var width: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var baseline := Vector2(center.x - width * 0.5, top + line_height * float(i) + font.get_ascent(size))
		if outline > 0:
			item.draw_string_outline(font, baseline, line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline,
				outline_fill)
		item.draw_string(font, baseline, line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)
