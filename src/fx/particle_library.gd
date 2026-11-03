class_name ParticleLibrary
extends RefCounted
## Every particle look in the game, defined in code, in the same shape as `WeaponLibrary` and
## `AbilityLibrary`: one builder per preset, all numbers in one place, referenced elsewhere by id.
##
## Presets describe *one* emitter. A rich effect is several presets layered on the same spot -- a fire
## is flames, embers, smoke and a bed of coals -- which is also what makes the pieces reusable: a torch
## wants the flames and the embers but no coals, an explosion wants the embers as a burst.
##
## The textures are generated here, like `VisionTextures` does for lights: no image assets to import.

const DOT_SIZE: int = 32

static var _cache: Dictionary = {}
static var _soft_dot: ImageTexture = null
static var _flame_tongue: ImageTexture = null
static var _fade_out: Gradient = null


static func by_id(id: String) -> ParticlePreset:
	if _cache.has(id):
		return _cache[id]
	var preset: ParticlePreset = null
	match id:
		"flames":
			preset = _flames()
		"embers":
			preset = _embers()
		"smoke":
			preset = _smoke()
		"coals":
			preset = _coals()
		"ignite":
			preset = _ignite()
		_:
			push_warning("ParticleLibrary: unknown preset '%s'; using 'embers'." % id)
			preset = _embers()
	_cache[id] = preset
	return preset


#region fire

## The body of a fire: flame tongues that rise, point the way they move, and burn out from
## white-yellow to dark red. Additive, so where many overlap the heart of the fire goes bright on its
## own. Little initial speed and a strong lift: a flame does not fly, it climbs.
static func _flames() -> ParticlePreset:
	var p := ParticlePreset.new()
	p.amount = 110
	p.lifetime = 0.6
	p.lifetime_randomness = 0.4
	p.preprocess = 0.5
	p.shape = ParticlePreset.Shape.BOX
	p.direction = Vector2.UP
	p.direction_in_world = true
	p.spread = 14.0
	p.speed_min = 12.0
	p.speed_max = 30.0
	p.gravity = Vector2(0.0, -110.0)
	p.damping_min = 0.0
	p.damping_max = 3.0
	p.tangential_min = -6.0
	p.tangential_max = 6.0
	p.texture = flame_tongue()
	p.align_to_motion = true
	p.size_min = 16.0
	p.size_max = 26.0
	p.size_curve = _curve([Vector2(0.0, 0.55), Vector2(0.25, 1.0), Vector2(1.0, 0.25)])
	p.colors = _gradient([
		[0.0, Color(1.0, 0.95, 0.75, 0.0)],
		[0.1, Color(1.0, 0.86, 0.5, 0.75)],
		[0.4, Color(1.0, 0.48, 0.1, 0.55)],
		[0.75, Color(0.7, 0.15, 0.03, 0.25)],
		[1.0, Color(0.25, 0.03, 0.02, 0.0)],
	])
	p.hue_variation = 0.02
	return p


## Bright specks thrown up out of the fire, living longer and drifting further than the flames do.
static func _embers() -> ParticlePreset:
	var p := ParticlePreset.new()
	p.amount = 22
	p.lifetime = 1.3
	p.lifetime_randomness = 0.5
	p.preprocess = 0.8
	p.shape = ParticlePreset.Shape.BOX
	p.direction = Vector2.UP
	p.spread = 180.0
	p.speed_min = 10.0
	p.speed_max = 45.0
	p.gravity = Vector2(0.0, -55.0)
	p.damping_min = 2.0
	p.damping_max = 6.0
	p.tangential_min = -30.0
	p.tangential_max = 30.0
	p.size_min = 2.5
	p.size_max = 4.5
	p.size_curve = _curve([Vector2(0.0, 1.0), Vector2(1.0, 0.3)])
	p.colors = _gradient([
		[0.0, Color(1.0, 0.92, 0.6, 1.0)],
		[0.5, Color(1.0, 0.55, 0.15, 0.9)],
		[1.0, Color(0.8, 0.2, 0.05, 0.0)],
	])
	p.z_offset = 1
	return p


## Dark, slow, wide puffs above the flames. Mixed rather than added, so it reads as smoke and can
## dim what is behind it, and kept faint: in pitch darkness heavy smoke would just be a black hole.
static func _smoke() -> ParticlePreset:
	var p := ParticlePreset.new()
	p.amount = 14
	p.lifetime = 1.8
	p.lifetime_randomness = 0.4
	p.preprocess = 1.0
	p.shape = ParticlePreset.Shape.BOX
	p.spread = 180.0
	p.speed_min = 4.0
	p.speed_max = 14.0
	p.gravity = Vector2(0.0, -40.0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.tangential_min = -10.0
	p.tangential_max = 10.0
	p.spin_min = -40.0
	p.spin_max = 40.0
	p.size_min = 26.0
	p.size_max = 44.0
	p.size_curve = _curve([Vector2(0.0, 0.5), Vector2(1.0, 1.2)])
	p.colors = _gradient([
		[0.0, Color(0.16, 0.12, 0.1, 0.0)],
		[0.3, Color(0.16, 0.12, 0.1, 0.22)],
		[1.0, Color(0.08, 0.07, 0.07, 0.0)],
	])
	p.blend = ParticlePreset.Blend.MIX
	p.z_offset = -1
	return p


## Glowing coals that stay where they are: marks the footprint of a fire on the ground, so you can see
## exactly where the flames are solid. Drawn under walls, like anything lying on the floor.
static func _coals() -> ParticlePreset:
	var p := ParticlePreset.new()
	p.amount = 60
	p.lifetime = 1.1
	p.lifetime_randomness = 0.5
	p.preprocess = 0.6
	p.shape = ParticlePreset.Shape.BOX
	p.spread = 180.0
	p.speed_min = 0.0
	p.speed_max = 3.0
	p.size_min = 14.0
	p.size_max = 24.0
	p.size_curve = _curve([Vector2(0.0, 0.6), Vector2(0.4, 1.0), Vector2(1.0, 0.6)])
	p.colors = _gradient([
		[0.0, Color(0.9, 0.25, 0.05, 0.0)],
		[0.4, Color(1.0, 0.4, 0.08, 0.55)],
		[1.0, Color(0.6, 0.1, 0.03, 0.0)],
	])
	p.z_offset = Layers.Z_PICKUP - Layers.Z_FX - 1
	return p


## A one-shot flare as a fire catches: everything at once, thrown outwards, gone in a moment.
static func _ignite() -> ParticlePreset:
	var p := ParticlePreset.new()
	p.amount = 40
	p.lifetime = 0.45
	p.lifetime_randomness = 0.4
	p.one_shot = true
	p.explosiveness = 0.95
	p.shape = ParticlePreset.Shape.BOX
	p.spread = 180.0
	p.speed_min = 60.0
	p.speed_max = 150.0
	p.gravity = Vector2(0.0, -80.0)
	p.damping_min = 120.0
	p.damping_max = 220.0
	p.size_min = 12.0
	p.size_max = 22.0
	p.size_curve = _curve([Vector2(0.0, 1.0), Vector2(1.0, 0.2)])
	p.colors = _gradient([
		[0.0, Color(1.0, 0.95, 0.8, 0.7)],
		[0.4, Color(1.0, 0.6, 0.18, 0.5)],
		[1.0, Color(0.7, 0.15, 0.04, 0.0)],
	])
	p.z_offset = 1
	return p

#endregion


#region shared resources

## A soft round dot, the default particle. Small on purpose: particles are drawn at 2-40 world pixels,
## and a big texture shrunk that far shimmers without mipmaps.
static func soft_dot() -> ImageTexture:
	if _soft_dot == null:
		var image := Image.create(DOT_SIZE, DOT_SIZE, false, Image.FORMAT_RGBA8)
		var center: float = float(DOT_SIZE) * 0.5
		for y: int in DOT_SIZE:
			for x: int in DOT_SIZE:
				var r: float = Vector2(float(x) + 0.5 - center, float(y) + 0.5 - center).length() / center
				var a: float = clampf(1.0 - r, 0.0, 1.0)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a * (3.0 - 2.0 * a)))
		_soft_dot = ImageTexture.create_from_image(image)
	return _soft_dot


## A flame tongue, twice as tall as it is wide: a round, bright base tapering to a soft point. Drawn
## with the point at the *bottom* of the image, because `align_to_motion` lines the texture's +Y up with
## the particle's motion, and a rising flame should point the way it goes.
static func flame_tongue() -> ImageTexture:
	if _flame_tongue == null:
		var width: int = DOT_SIZE
		var height: int = DOT_SIZE * 2
		var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
		for y: int in height:
			# 0 at the round base, 1 at the tip.
			var v: float = (float(y) + 0.5) / float(height)
			var half_width: float
			if v < 0.3:
				var k: float = (0.3 - v) / 0.3
				half_width = sqrt(maxf(0.0, 1.0 - k * k))
			else:
				half_width = pow(1.0 - (v - 0.3) / 0.7, 0.9)
			for x: int in width:
				var u: float = absf((float(x) + 0.5) / float(width) * 2.0 - 1.0)
				var a: float = 0.0
				if half_width > 0.001:
					a = clampf(1.0 - u / half_width, 0.0, 1.0)
				a = a * a * (3.0 - 2.0 * a)
				# Brightest low in the tongue, fading towards the tip.
				a *= lerpf(1.0, 0.35, v)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
		_flame_tongue = ImageTexture.create_from_image(image)
	return _flame_tongue


## White, fading to nothing: the colour ramp of a preset that sets none.
static func fade_out() -> Gradient:
	if _fade_out == null:
		_fade_out = _gradient([[0.0, Color.WHITE], [1.0, Color(1.0, 1.0, 1.0, 0.0)]])
	return _fade_out


static func _gradient(stops: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop: Array in stops:
		offsets.append(float(stop[0]))
		colors.append(stop[1] as Color)
	g.offsets = offsets
	g.colors = colors
	return g


static func _curve(points: Array[Vector2]) -> Curve:
	var c := Curve.new()
	# Room above 1, so a size curve can grow a particle past its starting size.
	c.max_value = 2.0
	for point: Vector2 in points:
		c.add_point(point)
	return c

#endregion
