class_name VisionTextures
extends RefCounted
## Generates the light textures the vision system needs, in code.
##
## No PNGs, no imports, no assets: an `ImageTexture` is built once from a
## `PackedByteArray` and cached. Change the falloff maths here to change how
## sight "feels" everywhere at once.
##
## Orientation note: a `PointLight2D` draws its texture axis-aligned in the
## node's local space, so a wedge opening toward +X points along the node's
## local +X. The vision rig therefore just rotates the light node at the aim
## angle.

const SIZE: int = 256

static var _radial_cache: ImageTexture = null
static var _cone_cache: Dictionary = {}


## Omnidirectional falloff: bright at the centre, smoothly dark at the rim.
static func radial() -> ImageTexture:
	if _radial_cache == null:
		_radial_cache = _build_radial(SIZE)
	return _radial_cache


## Wedge of `degrees`, pointing along local +X, soft on its edges and falling
## off with distance.
static func cone(degrees: float) -> ImageTexture:
	var key: String = str(int(degrees * 10.0))
	if not _cone_cache.has(key):
		_cone_cache[key] = _build_cone(degrees, SIZE)
	return _cone_cache[key]


static func _build_radial(size: int) -> ImageTexture:
	var data := PackedByteArray()
	data.resize(size * size * 4)
	var center: float = float(size) * 0.5
	for y: int in size:
		for x: int in size:
			var dx: float = float(x) + 0.5 - center
			var dy: float = float(y) + 0.5 - center
			var r: float = sqrt(dx * dx + dy * dy) / center
			var a: float = 0.0
			if r <= 1.0:
				a = pow(1.0 - r, 0.8)
			_write(data, (y * size + x) * 4, a)
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	return ImageTexture.create_from_image(image)


static func _build_cone(degrees: float, size: int) -> ImageTexture:
	var half_angle: float = deg_to_rad(clampf(degrees, 1.0, 359.0) * 0.5)
	var data := PackedByteArray()
	data.resize(size * size * 4)
	var center: float = float(size) * 0.5
	for y: int in size:
		for x: int in size:
			var dx: float = float(x) + 0.5 - center
			var dy: float = float(y) + 0.5 - center
			var r: float = sqrt(dx * dx + dy * dy) / center
			var a: float = 0.0
			if r <= 1.0:
				var angle: float = absf(atan2(dy, dx))
				# 1 in the middle of the wedge, 0 at its edge.
				var angular: float = 1.0 - clampf(angle / half_angle, 0.0, 1.0)
				# Soften the very edges so the cone does not look like a hard triangle.
				angular = smoothstep(0.0, 0.6, angular)
				# Stay at full strength for most of the reach, then fall off at the
				# tip. Lighting is multiplicative, so keeping this near 1.0 is what
				# makes lit surfaces show their real colour instead of a dim smear.
				var radial_fade: float = clampf((1.0 - r) / 0.3, 0.0, 1.0)
				radial_fade = smoothstep(0.0, 1.0, radial_fade)
				a = angular * radial_fade
			_write(data, (y * size + x) * 4, a)
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	return ImageTexture.create_from_image(image)


## Writes intensity into both RGB and A: depending on how the light shader
## samples the texture, either channel alone is enough to define the shape.
static func _write(data: PackedByteArray, index: int, amount: float) -> void:
	var v: int = int(clampf(amount, 0.0, 1.0) * 255.0)
	data[index] = v
	data[index + 1] = v
	data[index + 2] = v
	data[index + 3] = v
