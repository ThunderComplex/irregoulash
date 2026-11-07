class_name CharacterRig
extends Node2D
## Draws a character from a `CharacterLook`, seen from straight above, and keeps it moving:
##
##   * two legs, drawn from one leg image, hang from the hips and face where the character is going. A
##     stride is drawn by stretching each leg forward or back from its hip -- from above, that is what a
##     swinging leg looks like -- driven by distance walked, so the feet never slide;
##   * the body faces where the character aims, swaying a little with each step;
##   * the held weapon, from the weapon's own art, sits in the body's hands;
##   * when aim and movement point far enough apart, the legs turn round and walk backwards, so a
##     character backing away while aiming reads as backpedalling, not as legs twisted round.
##
## Movement and aim are independent in this game (WASD moves along the screen, the mouse aims), which is
## why legs and body are separate: no single sprite can face two ways.
##
## The owner calls `update` every frame with its velocity and aim angle. The parts are placed in global
## space, so it does not matter whether the node the rig hangs under is rotated (enemies rotate theirs).

const LOOK_DIRECTORY: String = "res://assets/characters/"
## Weapon art, by convention: `weapon_<id>.png`. A weapon with no file is simply not drawn.
const WEAPON_DIRECTORY: String = "res://assets/weapons/"
## Where along a weapon the hands hold it, as a fraction of its drawn length from the back.
const WEAPON_GRIP: float = 0.3
## Below this speed a character is standing, not walking.
const WALK_SPEED: float = 12.0
## How quickly the legs swing round to a new heading, per second. Snappy, but not instant, so a sudden
## reversal reads as a turn.
const LEG_TURN_RATE: float = 14.0
## How quickly a stride grows when setting off and settles when stopping, per second.
const STRIDE_EASE: float = 6.0

var look: CharacterLook = null

var _legs: Node2D = null
var _leg_sprites: Array[Sprite2D] = []
var _body: Sprite2D = null
var _weapon_sprite: Sprite2D = null
var _weapon_texture: Texture2D = null
## How far through the stride the legs are, 0..1.
var _phase: float = 0.0
var _legs_angle: float = 0.0
## 0 standing, 1 in full stride; eased so starting and stopping do not snap the legs.
var _stride_strength: float = 0.0
## Whether `update` has run yet: the first one places the legs instead of swinging them round from 0.
var _placed: bool = false

static var _weapon_textures: Dictionary = {}


## The look file for the first of `ids` that has one, or null.
static func find_look(ids: Array[String]) -> CharacterLook:
	for id: String in ids:
		var path: String = LOOK_DIRECTORY.path_join(id + ".tres")
		if ResourceLoader.exists(path):
			var found := load(path) as CharacterLook
			if found != null:
				return found
			push_warning("CharacterRig: %s is not a CharacterLook." % path)
	return null


## The art for a weapon id, or null when it has none.
static func weapon_texture(weapon_id: String) -> Texture2D:
	if weapon_id.is_empty():
		return null
	if not _weapon_textures.has(weapon_id):
		var path: String = WEAPON_DIRECTORY.path_join("weapon_%s.png" % weapon_id)
		_weapon_textures[weapon_id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _weapon_textures[weapon_id]


## Builds the parts from `chosen`, or from a placeholder sized and coloured for this character when there
## is no look file for it yet.
func setup(chosen: CharacterLook, radius: float, tint: Color) -> void:
	look = chosen if chosen != null else CharacterLook.placeholder(radius, tint)
	# Art is drawn larger than it is shown, so it is drawn through its mipmaps: shrinking a texture to a
	# fifth of its size without them shimmers as the character moves and turns.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _legs == null:
		_legs = Node2D.new()
		_legs.name = "Legs"
		_legs.z_index = Layers.Z_ACTOR
		add_child(_legs)
		for side: String in ["LeftLeg", "RightLeg"]:
			var sprite := Sprite2D.new()
			sprite.name = side
			_legs.add_child(sprite)
			_leg_sprites.append(sprite)
	if _weapon_sprite == null:
		_weapon_sprite = Sprite2D.new()
		_weapon_sprite.name = "Weapon"
		_weapon_sprite.z_index = Layers.Z_ACTOR + 3
		add_child(_weapon_sprite)
	if _body == null:
		_body = Sprite2D.new()
		_body.name = "Body"
		_body.z_index = Layers.Z_ACTOR + 2
		add_child(_body)

	var hip: Vector2 = look.leg_hip_point()
	for index: int in _leg_sprites.size():
		var sprite: Sprite2D = _leg_sprites[index]
		sprite.texture = look.leg
		sprite.offset = _offset_to(look.leg, hip)
		sprite.position = Vector2(0.0, look.stance_width * (0.5 if index == 1 else -0.5))
		sprite.scale = Vector2(look.rest_reach, 1.0 if index == 0 else -1.0) * look.art_scale
	_body.texture = look.body
	_body.scale = Vector2.ONE * look.art_scale
	_body.offset = _offset_to(look.body, look.body_pivot_point())
	_apply_weapon()


## Recolours the body (see `ColorShift`). Legs and weapon keep their own colours.
func set_body_shift(shift: Vector3) -> void:
	if _body != null:
		_body.material = ColorShift.material(shift)


## Shows `weapon_id`'s art in the hands, or nothing when it has none (or the look has no hands).
func set_weapon(weapon_id: String) -> void:
	_weapon_texture = weapon_texture(weapon_id)
	_apply_weapon()


## Where shots leave the weapon, in world space, for a character at this rig's position aiming at
## `aim_angle`: the front tip of the weapon's art. Null when no weapon is drawn, so the owner can fall
## back to its own idea of where the muzzle is.
func muzzle_position(aim_angle: float) -> Variant:
	if _weapon_texture == null or look == null or not look.has_hands():
		return null
	var used: Rect2i = CharacterLook._used_rect(_weapon_texture)
	var muzzle := Vector2(float(used.end.x), float(used.get_center().y))
	var from_grip: Vector2 = (muzzle - _grip(_weapon_texture)) * look.art_scale * look.weapon_scale
	return global_position + (_hands_local() + from_grip).rotated(aim_angle)


## Call every frame. `velocity` in world pixels per second, `aim_angle` in radians, global.
func update(delta: float, velocity: Vector2, aim_angle: float) -> void:
	if look == null:
		return
	var speed: float = velocity.length()
	var walking: bool = speed > WALK_SPEED
	var heading: float = aim_angle
	if walking:
		heading = velocity.angle()
		var direction: float = 1.0
		if absf(angle_difference(aim_angle, heading)) > deg_to_rad(look.backpedal_degrees):
			heading += PI
			direction = -1.0
		_phase = fposmod(_phase + direction * speed * delta / maxf(1.0, look.stride), 1.0)
	if _placed:
		_legs_angle = lerp_angle(_legs_angle, heading, clampf(delta * LEG_TURN_RATE, 0.0, 1.0))
	else:
		_legs_angle = heading
		_placed = true
	_stride_strength = move_toward(_stride_strength, 1.0 if walking else 0.0, delta * STRIDE_EASE)

	_legs.global_rotation = _legs_angle
	var swing: float = sin(_phase * TAU)
	for index: int in _leg_sprites.size():
		# The legs are half a stride apart: one reaches forward while the other reaches back. A negative
		# reach flips the leg to point backwards from its hip, which is exactly how it looks from above.
		var side: float = 1.0 if index == 0 else -1.0
		var extent: float = lerpf(look.rest_reach, swing * side * look.reach, _stride_strength)
		var sprite: Sprite2D = _leg_sprites[index]
		# The right leg is the left one mirrored across its own length.
		sprite.scale = Vector2(extent, side) * look.art_scale

	var sideways: Vector2 = Vector2.from_angle(aim_angle + PI * 0.5)
	var origin: Vector2 = global_position + sideways * swing * look.sway * _stride_strength
	_body.global_rotation = aim_angle
	_body.global_position = origin
	if _weapon_sprite.visible:
		_weapon_sprite.global_rotation = aim_angle
		_weapon_sprite.global_position = origin + _hands_local().rotated(aim_angle)


#region gibs

## How many chunks the body is cut into when it explodes.
const BODY_CHUNKS: int = 5


## Blows the character apart: the body art cut into chunks, and both legs, each thrown outwards (and
## along `push`, the direction the killing blow travelled) as a `Gib` under `parent`. The rig hides
## itself; the weapon is not thrown, because the gameplay drops it as loot.
func break_apart(push: Vector2, parent: Node) -> Array[Gib]:
	var gibs: Array[Gib] = []
	if look == null or parent == null:
		return gibs
	var pieces: Array[Dictionary] = []
	if _body != null and _body.texture != null:
		pieces.append_array(_body_chunks())
	for sprite: Sprite2D in _leg_sprites:
		if sprite.texture == null:
			continue
		# A leg mid-stride can be drawn foreshortened to nothing; thrown, it is a whole leg.
		var gib := Gib.from_sprite(sprite, look.stance_width * 0.6)
		(gib.get_child(0) as Sprite2D).scale = Vector2(look.art_scale, sprite.scale.y)
		pieces.append({"gib": gib, "at": sprite.global_position, "rotation": sprite.global_rotation})
	var centre: Vector2 = global_position
	var heading: Vector2 = push.normalized() if push.length_squared() > 0.0001 else Vector2.ZERO
	for piece: Dictionary in pieces:
		var gib: Gib = piece["gib"]
		parent.add_child(gib)
		gib.global_position = piece["at"]
		gib.global_rotation = piece["rotation"]
		var outward: Vector2 = (gib.global_position - centre)
		outward = outward.normalized() if outward.length_squared() > 0.01 \
			else Vector2.from_angle(randf() * TAU)
		var direction: Vector2 = (outward + heading * 0.9 + Vector2.from_angle(randf() * TAU) * 0.35) \
			.normalized()
		gib.launch(direction * randf_range(150.0, 360.0), randf_range(-14.0, 14.0))
		gibs.append(gib)
	visible = false
	return gibs


## The body art cut into `BODY_CHUNKS` jagged wedges around the hips, each a `Gib` placed exactly where
## that part of the body was drawn, colour shift and all.
func _body_chunks() -> Array[Dictionary]:
	var texture: Texture2D = _body.texture
	var texture_size := Vector2(texture.get_size())
	var used := Rect2(CharacterLook._used_rect(texture))
	var centre: Vector2 = look.body_pivot_point()
	if not used.has_point(centre):
		centre = used.get_center()

	# The cuts: spokes from the hips to the edge of the drawing, kinked part way along so the chunks look
	# torn rather than sliced. Neighbouring chunks share a spoke, so they fit back together exactly.
	var spokes: Array[Dictionary] = []
	var start: float = randf() * TAU
	for i: int in BODY_CHUNKS:
		var angle: float = start + TAU * (float(i) + randf_range(-0.3, 0.3)) / float(BODY_CHUNKS)
		var edge: Vector2 = _ray_to_rect_edge(centre, Vector2.from_angle(angle), used)
		var kink: Vector2 = centre.lerp(edge, randf_range(0.35, 0.65)) \
			+ Vector2.from_angle(angle + PI * 0.5) * randf_range(-8.0, 8.0)
		spokes.append({"angle": angle, "kink": kink, "edge": edge})
	var corners: Array[Vector2] = [used.position, Vector2(used.end.x, used.position.y), used.end,
		Vector2(used.position.x, used.end.y)]

	var chunks: Array[Dictionary] = []
	for i: int in BODY_CHUNKS:
		var from: Dictionary = spokes[i]
		var to: Dictionary = spokes[(i + 1) % BODY_CHUNKS]
		var span: float = fposmod(float(to["angle"]) - float(from["angle"]), TAU)
		var outline := PackedVector2Array([centre, from["kink"], from["edge"]])
		# The drawing's corners that fall inside this wedge, in order round it.
		var inside: Array[Vector2] = []
		for corner: Vector2 in corners:
			if fposmod((corner - centre).angle() - float(from["angle"]), TAU) < span:
				inside.append(corner)
		inside.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return fposmod((a - centre).angle() - float(from["angle"]), TAU) \
				< fposmod((b - centre).angle() - float(from["angle"]), TAU))
		outline.append_array(PackedVector2Array(inside))
		outline.append(to["edge"])
		outline.append(to["kink"])

		var middle := Vector2.ZERO
		for point: Vector2 in outline:
			middle += point
		middle /= float(outline.size())
		var local := PackedVector2Array()
		for point: Vector2 in outline:
			local.append(point - middle)
		var area: float = absf(_polygon_area(outline))
		var radius: float = sqrt(area / PI) * look.art_scale * 0.55
		var gib := Gib.from_polygon(texture, local, outline, look.art_scale, _body.material, radius)
		var at: Vector2 = _body.global_transform * (middle - texture_size * 0.5 + _body.offset)
		chunks.append({"gib": gib, "at": at, "rotation": _body.global_rotation})
	return chunks


## Where a ray from `origin` (inside `rect`) along `direction` leaves `rect`.
static func _ray_to_rect_edge(origin: Vector2, direction: Vector2, rect: Rect2) -> Vector2:
	var t: float = INF
	if direction.x > 0.0001:
		t = minf(t, (rect.end.x - origin.x) / direction.x)
	elif direction.x < -0.0001:
		t = minf(t, (rect.position.x - origin.x) / direction.x)
	if direction.y > 0.0001:
		t = minf(t, (rect.end.y - origin.y) / direction.y)
	elif direction.y < -0.0001:
		t = minf(t, (rect.position.y - origin.y) / direction.y)
	return origin + direction * (t if is_finite(t) else 0.0)


static func _polygon_area(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in points.size():
		total += points[i].cross(points[(i + 1) % points.size()])
	return total * 0.5

#endregion


func _apply_weapon() -> void:
	if _weapon_sprite == null or look == null:
		return
	_weapon_sprite.visible = _weapon_texture != null and look.has_hands()
	if not _weapon_sprite.visible:
		return
	_weapon_sprite.texture = _weapon_texture
	_weapon_sprite.scale = Vector2.ONE * look.art_scale * look.weapon_scale
	_weapon_sprite.offset = _offset_to(_weapon_texture, _grip(_weapon_texture))


## The hands relative to the hips, in world pixels, before turning to the aim.
func _hands_local() -> Vector2:
	return (look.hands - look.body_pivot_point()) * look.art_scale


## Where a weapon is held, in its own pixels: `WEAPON_GRIP` of the way along its drawn length, on its
## centre line.
static func _grip(texture: Texture2D) -> Vector2:
	var used: Rect2i = CharacterLook._used_rect(texture)
	return Vector2(float(used.position.x) + float(used.size.x) * WEAPON_GRIP, float(used.get_center().y))


## A Sprite2D draws about the middle of its texture; this offset puts `point` (texture pixels from the
## top-left) on the node's origin instead.
static func _offset_to(texture: Texture2D, point: Vector2) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return Vector2(texture.get_size()) * 0.5 - point
