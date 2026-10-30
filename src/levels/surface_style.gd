class_name SurfaceStyle
extends Resource
## The look of a flat surface: a wall top, or the floor.
##
## One texture, tiled in world space, plus the shading that makes a rectangle read as a solid object
## from above. Built in code by `SurfaceLibrary`, like every other piece of balance in this project, so
## adding a look is one function and no scene editing.
##
## A style with no `albedo` draws a flat colour instead -- which is exactly how levels looked before
## surfaces existed, and is why "plain" is the default: adding this system changes nothing until a
## level asks for a style.

@export var id: StringName = &"plain"
@export var display_name: String = "Plain"
## Null means "flat colour", not "missing texture".
@export var albedo: Texture2D = null
## World pixels per tile. The texture is never resized; a bigger tile means bigger features.
@export var tile_world: Vector2 = Vector2(64.0, 64.0)
## Multiplied with the surface's own colour, so a level can push a style warm or dark without editing
## the art.
@export var tint: Color = Color.WHITE

## A bright edge, and light falling away just inside it: between them they read as thickness from above,
## more than any texture detail does.
@export var rim_width: float = 2.0
@export var rim_boost: float = 0.35
@export var rim_ao_width: float = 14.0
@export var rim_ao_strength: float = 0.35
## Fraction of the surface's height darkened at the bottom, faking the drop into a wall's face.
@export var base_band: float = 0.3
@export var base_strength: float = 0.4

## How strongly a second, much larger sample of the same texture is blended in to hide the tiling.
@export var breakup_amount: float = 0.35
@export var breakup_scale: float = 0.23

## Flat colour for the explored-geometry ghost, and for the crisp rim line on walls. Memory must stay a
## silhouette: drawing texture there would be wrong and slower.
@export var memory_color: Color = Color(0.40, 0.44, 0.54)
@export var rim_color: Color = Color(0.62, 0.67, 0.78)


func is_textured() -> bool:
	return albedo != null
