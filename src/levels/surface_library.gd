class_name SurfaceLibrary
extends RefCounted
## Every surface look in the game, defined in code, in the same shape as `WeaponLibrary` and
## `EnemyLibrary`: one builder per style, all numbers in one place, referenced elsewhere by id.
##
## The ids here and the `@export_enum` lists on `Level` must agree. Adding a style is: a builder here,
## add its id to the enum, done -- the wall brush and every existing wall pick it up automatically
## because the look is chosen per level, not per wall.

const WALL_IDS: Array[String] = ["plain", "wood"]
const FLOOR_IDS: Array[String] = ["plain", "wood_floor"]

const WOOD_TEXTURE: String = "res://assets/textures/wall_1.png"

static var _cache: Dictionary = {}


static func by_id(id: String) -> SurfaceStyle:
	if _cache.has(id):
		return _cache[id]
	var style: SurfaceStyle = null
	match id:
		"wood":
			style = _wood()
		"wood_floor":
			style = _wood_floor()
		_:
			# Unknown ids get the flat default rather than null: a typo should look plain, not crash.
			style = _plain()
	_cache[id] = style
	return style


## The pre-surfaces look: a flat colour per wall, no texture, no floor. Default so that existing
## levels are untouched.
static func _plain() -> SurfaceStyle:
	var s := SurfaceStyle.new()
	s.id = &"plain"
	s.display_name = "Plain"
	s.albedo = null
	return s


## Warm wood grain, for the lab and for testing the tiling. The texture is authored at 256 and tiled at
## 64 world pixels, so at the game's fixed world scale one tile is about 8% of the screen height.
static func _wood() -> SurfaceStyle:
	var s := SurfaceStyle.new()
	s.id = &"wood"
	s.display_name = "Wood"
	s.albedo = load(WOOD_TEXTURE) as Texture2D
	s.tile_world = Vector2(64.0, 64.0)
	# Bright *over* white on purpose. A wall top is shadowed by its own light occluder -- a rectangle's
	# interior is always behind one of its own edges from any light outside it -- so a lit wall receives
	# roughly a third of what a lit floor does at the same distance. Measured on the lab scene: floor
	# (57,39,17) against wall (18,15,11). Boosting the style's tint is how a wall ends up reading as
	# brightly as the ground beside it; the alternative would be to stop wall tops receiving light at
	# all, which would break the whole "your light reveals the room" idea.
	s.tint = Color(0.38, 0.30, 0.20)
	s.rim_ao_width = 14.0
	s.rim_ao_strength = 0.34
	s.base_band = 0.34
	s.base_strength = 0.46
	s.breakup_amount = 0.25
	s.breakup_scale = 0.21
	s.memory_color = Color(0.24, 0.20, 0.15)
	s.rim_color = Color(0.76, 0.66, 0.50)
	return s


## The same grain used as a floor: much larger tiles, much darker, and none of the edge shading (a floor
## has no rim and does not drop away at its edges).
static func _wood_floor() -> SurfaceStyle:
	var s := SurfaceStyle.new()
	s.id = &"wood_floor"
	s.display_name = "Wood Floor"
	s.albedo = load(WOOD_TEXTURE) as Texture2D
	s.tile_world = Vector2(160.0, 160.0)
	s.tint = Color(0.30, 0.26, 0.22)
	# A floor has no edge to be thick at, so none of the edge treatment applies.
	s.rim_width = 0.0
	s.rim_boost = 0.0
	s.rim_ao_width = 0.0
	s.rim_ao_strength = 0.0
	s.base_band = 0.0
	s.base_strength = 0.0
	s.breakup_amount = 0.5
	s.breakup_scale = 0.17
	s.memory_color = Color(0.12, 0.10, 0.08)
	s.rim_color = Color(0.30, 0.26, 0.22)
	return s
