class_name ColorShift
extends RefCounted
## A change of colour for a character's body, so the same art can look different from enemy to enemy
## and from level to level. Written as a `Vector3`: hue in degrees round the colour wheel, then
## saturation and brightness as multipliers. `Vector3(0, 1, 1)` changes nothing.
##
## Applied to the body only, never to legs or weapons: the weapon is the other half of how an enemy's
## type is read at a glance, and should look the same everywhere.

const SHADER: Shader = preload("res://src/characters/color_shift.gdshader")
const NONE: Vector3 = Vector3(0.0, 1.0, 1.0)

## How far the automatic per-enemy variation reaches. Kept small on purpose: each enemy type has its own
## colour, and they are close on the colour wheel -- measured off the art, the guard sits at 17 degrees,
## the heavy at 21 (told apart by being darker and bigger) and the scout at 39. Hue has the least room, so
## +-5 degrees keeps a guard and a scout at least 12 apart; saturation and brightness carry most of the
## variety. A level-wide shift is the tool for bigger changes, because it moves every type together.
const VARIATION_HUE: float = 5.0
const VARIATION_SATURATION: float = 0.12
const VARIATION_BRIGHTNESS: float = 0.1


## `first` followed by `then`: hues add, saturation and brightness multiply.
static func combine(first: Vector3, then: Vector3) -> Vector3:
	return Vector3(first.x + then.x, first.y * then.y, first.z * then.z)


## A small variation that is always the same for the same `key`, so an enemy looks the same every time
## its level is played, and no colour has to be stored in the level file.
static func variation(key: String) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	return Vector3(
		rng.randf_range(-VARIATION_HUE, VARIATION_HUE),
		1.0 + rng.randf_range(-VARIATION_SATURATION, VARIATION_SATURATION),
		1.0 + rng.randf_range(-VARIATION_BRIGHTNESS, VARIATION_BRIGHTNESS))


## The same change, on one colour: for things that are not sprites, like the editor gizmo and corpses.
static func apply(color: Color, shift: Vector3) -> Color:
	return Color.from_hsv(fposmod(color.h + shift.x / 360.0, 1.0), clampf(color.s * shift.y, 0.0, 1.0),
		color.v * shift.z, color.a)


## A material that applies `shift` to a sprite, or null when there is nothing to change.
static func material(shift: Vector3) -> ShaderMaterial:
	if shift.is_equal_approx(NONE):
		return null
	var out := ShaderMaterial.new()
	out.shader = SHADER
	out.set_shader_parameter("hue_shift", shift.x / 360.0)
	out.set_shader_parameter("saturation", shift.y)
	out.set_shader_parameter("brightness", shift.z)
	return out
