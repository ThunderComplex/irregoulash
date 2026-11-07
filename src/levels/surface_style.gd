@tool
class_name SurfaceStyle
extends Resource
## The look of a flat surface: a wall top, or the floor.
##
## One texture, tiled in world space, plus the shading that makes a rectangle read as a solid object
## from above. Each style is a `.tres` file in `SurfaceLibrary.DIRECTORY`, and its file name is its id:
## adding a look is "New wall style" in the editor's Surfaces dock, no code and no scene editing.
##
## A style with no `albedo` draws a flat colour instead -- which is exactly how levels looked before
## surfaces existed, and is why "plain" is the default: adding this system changes nothing until a
## level asks for a style.
##
## `@tool`, and every property emits `changed`: a level open in the editor listens for that, so dragging
## a slider in the inspector restyles the level on the spot instead of needing a run to check it.

enum Kind { WALL, FLOOR }

## The file name, filled in by `SurfaceLibrary` when the style is loaded. Not saved: a file that is
## renamed cannot end up with an id that disagrees with its name.
var id: StringName = &"plain"

## Which dropdown on `Level` offers this style. Purely for tidiness: nothing stops a level using a wall
## style as its floor in code.
@export var kind: Kind = Kind.WALL:
	set(value):
		kind = value
		emit_changed()
@export var display_name: String = "Plain":
	set(value):
		display_name = value
		emit_changed()
## Null means "flat colour", not "missing texture".
@export var albedo: Texture2D = null:
	set(value):
		albedo = value
		emit_changed()
## World pixels per tile. The texture is never resized; a bigger tile means bigger features.
@export var tile_world: Vector2 = Vector2(64.0, 64.0):
	set(value):
		tile_world = Vector2(maxf(1.0, value.x), maxf(1.0, value.y))
		emit_changed()
## Multiplied with the surface's own colour, so a level can push a style warm or dark without editing
## the art.
##
## Expect a wall to want a much brighter tint than a floor of the same art. A wall top is shadowed by
## its own light occluder -- a rectangle's interior is always behind one of its own edges from any
## light outside it -- so a lit wall receives roughly a third of what a lit floor does at the same
## distance. Boosting the tint is how a wall ends up reading as brightly as the ground beside it.
@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		emit_changed()

## A bright edge, and light falling away just inside it: between them they read as thickness from above,
## more than any texture detail does. Floors have no edge, so leave these at zero for a floor.
@export_group("Edges")
@export_range(0.0, 16.0, 0.5, "or_greater") var rim_width: float = 2.0:
	set(value):
		rim_width = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var rim_boost: float = 0.35:
	set(value):
		rim_boost = value
		emit_changed()
@export_range(0.0, 64.0, 0.5, "or_greater") var rim_ao_width: float = 14.0:
	set(value):
		rim_ao_width = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var rim_ao_strength: float = 0.35:
	set(value):
		rim_ao_strength = value
		emit_changed()
## Fraction of the surface's height darkened at the bottom, faking the drop into a wall's face.
@export_range(0.0, 1.0, 0.01) var base_band: float = 0.3:
	set(value):
		base_band = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var base_strength: float = 0.4:
	set(value):
		base_strength = value
		emit_changed()

## How strongly a second, much larger sample of the same texture is blended in to hide the tiling.
@export_group("Tiling breakup")
@export_range(0.0, 1.0, 0.01) var breakup_amount: float = 0.35:
	set(value):
		breakup_amount = value
		emit_changed()
@export_range(0.0, 1.0, 0.01, "or_greater") var breakup_scale: float = 0.23:
	set(value):
		breakup_scale = value
		emit_changed()


## Doors in a level with this wall style. Drawn lying horizontally, hinge on the left, and stretched
## to each door's size: 384x128 matches the walls' detail for the standard 96x32 door. No texture keeps
## the plain panel. Ignored for floors.
@export_group("Door")
@export var door: Texture2D = null:
	set(value):
		door = value
		emit_changed()


func is_textured() -> bool:
	return albedo != null


## Zeroes the edge treatment, which a floor has no use for: it has no rim and does not drop away.
func clear_edges() -> void:
	rim_width = 0.0
	rim_boost = 0.0
	rim_ao_width = 0.0
	rim_ao_strength = 0.0
	base_band = 0.0
	base_strength = 0.0
