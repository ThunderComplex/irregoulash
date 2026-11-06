class_name CharacterLook
extends Resource
## The art for one character, drawn as two top-down layers: legs that turn with movement and play a walk
## cycle, and a torso (head, arms and weapon included) that turns with the aim. `CharacterRig` draws it.
##
## A look is a `.tres` file in `CharacterRig.LOOK_DIRECTORY`, named after who wears it -- `player.tres`, an
## enemy archetype's id such as `guard.tres`, or `enemy.tres` as the default every enemy falls back to.
## Nothing registers it: save the file and the next run uses it. A character with no file gets a
## placeholder drawn in code, so art can arrive one character at a time.
##
## Everything is authored facing right (+X), at `art_scale` times the size it appears in the world, with
## the hips -- the point the character turns about -- where `legs_pivot` and `torso_pivot` say.
## docs/CHARACTER_ART.md has the full checklist.

@export_group("Legs")
## The walk cycle as one horizontal strip of equal frames. Frame 0 doubles as standing still, so draw
## it with the feet together.
@export var legs_sheet: Texture2D = null
@export_range(1, 32) var legs_frames: int = 8
## World pixels walked per full cycle. The cycle is driven by distance, not time, so feet do not slide
## whatever the speed: if they look like they skate, raise this; if they look like they shuffle, lower it.
@export var stride: float = 56.0
## The hips, in pixels of one frame, measured from its top-left corner. (-1, -1) means the middle.
@export var legs_pivot: Vector2 = Vector2(-1.0, -1.0)

@export_group("Torso")
## Head, shoulders, arms and the default weapon pose.
@export var torso: Texture2D = null
## Per-weapon torsos, keyed by weapon id ("pistol", "smg", "shotgun"). A weapon without one uses
## `torso`.
@export var torso_by_weapon: Dictionary[String, Texture2D] = {}
## The hips, in pixels of the torso image, from its top-left corner. (-1, -1) means the middle.
@export var torso_pivot: Vector2 = Vector2(-1.0, -1.0)
## How far the torso sways side to side over a stride, in world pixels. A little of it sells the weight
## of a step without a single extra frame; 0 turns it off.
@export var sway: float = 1.0

@export_group("Rules")
## Authored size over world size. 0.25 means drawn four times larger than it appears, which keeps
## smooth art crisp when it is rotated and when the camera zooms in.
@export var art_scale: float = 0.25
## When aim and movement are further apart than this, the legs face the other way and walk backwards
## instead of twisting round under the body.
@export_range(60.0, 180.0, 1.0) var backpedal_degrees: float = 100.0


func torso_for(weapon_id: String) -> Texture2D:
	return torso_by_weapon.get(weapon_id, torso)


#region placeholder

## Stand-in art, drawn in code for characters that have no look file yet. It follows every rule real
## art follows -- facing right, `art_scale` 0.25, hips in the middle, frame 0 standing -- so it is also a
## working example of the format.
static var _placeholders: Dictionary = {}


static func placeholder(radius: float, tint: Color) -> CharacterLook:
	var key: String = "%.1f/%s" % [radius, tint.to_html()]
	if _placeholders.has(key):
		return _placeholders[key]
	var look := CharacterLook.new()
	look.art_scale = 0.25
	look.legs_frames = 8
	look.stride = radius * 4.0
	# Authored at 4x: a texel is a quarter of a world pixel.
	var px: float = 1.0 / look.art_scale
	var size: int = int(ceil(radius * 3.2 * px))
	look.legs_sheet = _draw_legs(size, radius * px, look.legs_frames, tint)
	look.torso = _draw_torso(size, radius * px, tint)
	_placeholders[key] = look
	return look


## Two feet, swinging past each other over the cycle. Frame 0 has them side by side.
static func _draw_legs(size: int, r: float, frames: int, tint: Color) -> ImageTexture:
	var image := Image.create(size * frames, size, false, Image.FORMAT_RGBA8)
	var shoe := tint.darkened(0.65)
	var centre := Vector2(size, size) * 0.5
	for frame: int in frames:
		var swing: float = sin(TAU * float(frame) / float(frames)) * r * 0.6
		var origin := Vector2(float(frame * size), 0.0)
		for side: float in [-1.0, 1.0]:
			var foot: Vector2 = origin + centre + Vector2(swing * side, r * 0.42 * side)
			_ellipse(image, foot, Vector2(r * 0.42, r * 0.22), shoe.darkened(0.4), 3.0)
			_ellipse(image, foot, Vector2(r * 0.42, r * 0.22), shoe, 0.0)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Shoulders across the body, a head, and a weapon held forward in the right hand.
static func _draw_torso(size: int, r: float, tint: Color) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size, size) * 0.5
	var outline := tint.darkened(0.6)
	var gun := Rect2(centre + Vector2(r * 0.2, r * 0.18), Vector2(r * 1.25, r * 0.26))
	_rect(image, gun.grow(3.0), outline)
	_rect(image, gun, Color(0.30, 0.32, 0.36))
	_ellipse(image, centre, Vector2(r * 0.55, r), outline, 4.0)
	_ellipse(image, centre, Vector2(r * 0.55, r), tint, 0.0)
	var head: Vector2 = centre + Vector2(r * 0.12, 0.0)
	_ellipse(image, head, Vector2(r * 0.42, r * 0.42), outline, 3.0)
	_ellipse(image, head, Vector2(r * 0.42, r * 0.42), tint.lightened(0.3), 0.0)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## A filled ellipse, `grow` texels bigger than `radii`, with an anti-aliased edge, drawn over what is
## there.
static func _ellipse(image: Image, centre: Vector2, radii: Vector2, color: Color, grow: float) -> void:
	var rx: float = radii.x + grow
	var ry: float = radii.y + grow
	for y: int in range(maxi(0, int(centre.y - ry) - 1), mini(image.get_height(), int(centre.y + ry) + 2)):
		for x: int in range(maxi(0, int(centre.x - rx) - 1), mini(image.get_width(), int(centre.x + rx) + 2)):
			var d := Vector2((float(x) + 0.5 - centre.x) / rx, (float(y) + 0.5 - centre.y) / ry)
			# Distance to the edge in texels, roughly, for a one-texel soft edge.
			var coverage: float = clampf((1.0 - d.length()) * minf(rx, ry) + 0.5, 0.0, 1.0)
			_blend(image, x, y, color, coverage)


static func _rect(image: Image, rect: Rect2, color: Color) -> void:
	for y: int in range(maxi(0, int(rect.position.y) - 1), mini(image.get_height(), int(rect.end.y) + 2)):
		for x: int in range(maxi(0, int(rect.position.x) - 1), mini(image.get_width(), int(rect.end.x) + 2)):
			var px: float = float(x) + 0.5
			var py: float = float(y) + 0.5
			var inside: float = minf(minf(px - rect.position.x, rect.end.x - px),
				minf(py - rect.position.y, rect.end.y - py))
			_blend(image, x, y, color, clampf(inside + 0.5, 0.0, 1.0))


static func _blend(image: Image, x: int, y: int, color: Color, coverage: float) -> void:
	if coverage <= 0.0:
		return
	var under: Color = image.get_pixel(x, y)
	var over := Color(color.r, color.g, color.b, color.a * coverage)
	image.set_pixel(x, y, under.blend(over))

#endregion
