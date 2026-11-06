class_name CharacterLook
extends Resource
## The art for one character, seen from straight above: a body (head, shoulders and arms) that turns with
## the aim, and one leg that `CharacterRig` draws twice and walks in code. The held weapon is drawn from
## the weapon's own art (`CharacterRig.WEAPON_DIRECTORY`), placed in the body's hands.
##
## A look is a `.tres` file in `CharacterRig.LOOK_DIRECTORY`, named after who wears it -- `player.tres`, an
## enemy archetype's id such as `guard.tres`, or `enemy.tres` as the default every enemy falls back to.
## Nothing registers it: save the file and the next run uses it. A character with no file gets a
## placeholder drawn in code, so art can arrive one character at a time.
##
## Everything is drawn facing right (+X), at 1 / `art_scale` times the size it appears in the world.
## docs/CHARACTER_ART.md has the full checklist.

@export_group("Body")
## Head, shoulders and arms.
@export var body: Texture2D = null
## The hips -- the point the body turns about -- in body pixels from the top-left. (-1, -1) is the middle.
@export var body_pivot: Vector2 = Vector2(-1.0, -1.0)
## Where the hands are, in body pixels from the top-left: the held weapon's grip is put here. (-1, -1)
## means the character holds nothing visible.
@export var hands: Vector2 = Vector2(-1.0, -1.0)
## How far the body sways side to side over a stride, in world pixels. A little sells the weight of a
## step; 0 turns it off.
@export var sway: float = 1.0
## The held weapon's size relative to the body: weapon art is drawn at the same scale as the body, and
## this resizes it without redrawing it.
@export_range(0.1, 2.0, 0.01) var weapon_scale: float = 1.0

@export_group("Legs")
## One leg seen from above: hip end on the left, toe pointing right. Drawn twice, once per side.
@export var leg: Texture2D = null
## The hip joint, in leg pixels from the top-left: the point the leg hangs from. (-1, -1) means the middle
## of the left end of the drawing, which suits a leg drawn with its hip at the left.
@export var leg_hip: Vector2 = Vector2(-1.0, -1.0)
## World pixels between the two hips.
@export var stance_width: float = 10.0
## World pixels walked per full stride (both legs). Driven by distance, not time, so feet do not slide:
## if they look like they skate, raise it; if they look like they shuffle, lower it.
@export var stride: float = 60.0
## How far a leg reaches at the front and back of a stride, as a fraction of its drawn length. From
## above, a leg swinging forward looks like it stretches forward from the hip; one behind, backward.
@export_range(0.0, 1.5, 0.01) var reach: float = 0.9
## How far the legs reach forward when standing still, as the same fraction.
@export_range(0.0, 1.0, 0.01) var rest_reach: float = 0.3

@export_group("Rules")
## World size over drawn size. 0.2 means the art is drawn five times larger than it appears, which keeps
## smooth art crisp when it is rotated and when the camera zooms in.
@export var art_scale: float = 0.2
## When aim and movement are further apart than this, the legs face the other way and walk backwards
## instead of twisting round under the body.
@export_range(60.0, 180.0, 1.0) var backpedal_degrees: float = 100.0


## The hip, in leg pixels, with the default resolved.
func leg_hip_point() -> Vector2:
	if leg_hip.x >= 0.0 and leg_hip.y >= 0.0:
		return leg_hip
	if leg == null:
		return Vector2.ZERO
	var used: Rect2i = _used_rect(leg)
	# The middle of the round end: half the leg's thickness in from its left edge.
	return Vector2(float(used.position.x) + float(used.size.y) * 0.5, float(used.get_center().y))


func body_pivot_point() -> Vector2:
	if body_pivot.x >= 0.0 and body_pivot.y >= 0.0:
		return body_pivot
	return Vector2(body.get_size()) * 0.5 if body != null else Vector2.ZERO


func has_hands() -> bool:
	return hands.x >= 0.0 and hands.y >= 0.0


## The drawn part of a texture: everything that is not fully transparent. Cached, because reading the
## image back is not free.
static var _used_rects: Dictionary = {}


static func _used_rect(texture: Texture2D) -> Rect2i:
	if _used_rects.has(texture):
		return _used_rects[texture]
	var image: Image = texture.get_image()
	var rect := Rect2i(Vector2i.ZERO, texture.get_size())
	if image != null:
		if image.is_compressed():
			image.decompress()
		rect = image.get_used_rect()
	_used_rects[texture] = rect
	return rect


#region placeholder

## Stand-in art, drawn in code for characters that have no look file yet. It follows every rule real art
## follows -- 256 px canvas, facing right, hips in the middle, the leg's hip on its left -- so it is also a
## working example of the format.
static var _placeholders: Dictionary = {}


static func placeholder(radius: float, tint: Color) -> CharacterLook:
	var key: String = "%.1f/%s" % [radius, tint.to_html()]
	if _placeholders.has(key):
		return _placeholders[key]
	var look := CharacterLook.new()
	look.art_scale = 0.2
	var r: float = radius / look.art_scale
	look.body = _draw_body(r, tint)
	look.hands = Vector2(128.0 + r * 1.3, 128.0 + r * 0.82)
	look.leg = _draw_leg(r, tint)
	look.stance_width = radius * 0.7
	look.stride = radius * 4.3
	_placeholders[key] = look
	return look


## Shoulders across the body, a head, and two arms meeting at the hands, ahead and to the right.
static func _draw_body(r: float, tint: Color) -> ImageTexture:
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var centre := Vector2(128.0, 128.0)
	var hands_offset: Vector2 = centre + Vector2(r * 1.3, r * 0.82)
	var arm := tint.darkened(0.15)
	var outline := tint.darkened(0.6)
	for shoulder: Vector2 in [centre + Vector2(r * 0.1, -r * 0.8), centre + Vector2(r * 0.1, r * 0.8)]:
		_capsule(image, shoulder, hands_offset, r * 0.14 + 3.0, outline)
		_capsule(image, shoulder, hands_offset, r * 0.14, arm)
	_ellipse(image, centre, Vector2(r * 0.55, r), outline, 4.0)
	_ellipse(image, centre, Vector2(r * 0.55, r), tint, 0.0)
	var head: Vector2 = centre + Vector2(r * 0.08, 0.0)
	_ellipse(image, head, Vector2(r * 0.45, r * 0.45), outline, 3.0)
	_ellipse(image, head, Vector2(r * 0.45, r * 0.45), tint.lightened(0.3), 0.0)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## A round hip end on the left, tapering to the toe on the right.
static func _draw_leg(r: float, tint: Color) -> ImageTexture:
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var colour := tint.darkened(0.65)
	var thickness: float = r * 0.28
	var hip := Vector2(128.0 - r * 0.7, 128.0)
	var toe := Vector2(128.0 + r * 0.95, 128.0)
	_capsule(image, hip, toe, thickness * 0.75, colour)
	_ellipse(image, hip, Vector2(thickness, thickness), colour.darkened(0.2), 0.0)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## A filled ellipse, `grow` pixels bigger than `radii`, with a soft one-pixel edge.
static func _ellipse(image: Image, centre: Vector2, radii: Vector2, color: Color, grow: float) -> void:
	var rx: float = radii.x + grow
	var ry: float = radii.y + grow
	for y: int in range(maxi(0, int(centre.y - ry) - 1), mini(image.get_height(), int(centre.y + ry) + 2)):
		for x: int in range(maxi(0, int(centre.x - rx) - 1), mini(image.get_width(), int(centre.x + rx) + 2)):
			var d := Vector2((float(x) + 0.5 - centre.x) / rx, (float(y) + 0.5 - centre.y) / ry)
			_blend(image, x, y, color, clampf((1.0 - d.length()) * minf(rx, ry) + 0.5, 0.0, 1.0))


## A line with round ends, `half_width` either side of the segment `a`..`b`.
static func _capsule(image: Image, a: Vector2, b: Vector2, half_width: float, color: Color) -> void:
	var low := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (half_width + 2.0)
	var high := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (half_width + 2.0)
	for y: int in range(maxi(0, int(low.y)), mini(image.get_height(), int(high.y) + 1)):
		for x: int in range(maxi(0, int(low.x)), mini(image.get_width(), int(high.x) + 1)):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var distance: float = p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
			_blend(image, x, y, color, clampf(half_width - distance + 0.5, 0.0, 1.0))


static func _blend(image: Image, x: int, y: int, color: Color, coverage: float) -> void:
	if coverage <= 0.0:
		return
	var under: Color = image.get_pixel(x, y)
	image.set_pixel(x, y, under.blend(Color(color.r, color.g, color.b, color.a * coverage)))

#endregion
