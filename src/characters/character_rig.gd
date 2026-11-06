class_name CharacterRig
extends Node2D
## Draws a character as two top-down layers from a `CharacterLook`, and keeps them moving:
##
##   * the legs turn to face where the character is going and play the walk cycle, advanced by distance
##     walked so the feet never slide, and settle on the standing frame when it stops;
##   * the torso turns to face where it is aiming, swaying a little with each step;
##   * when aim and movement point far enough apart, the legs turn round and walk the cycle backwards,
##     so a character backing away while aiming reads as backpedalling, not as legs twisted round.
##
## Movement and aim are independent in this game (WASD moves along the screen, the mouse aims), which is
## why a character is two layers and not one: no single sprite can face two ways.
##
## The owner calls `update` every frame with its velocity and aim angle. The layers are set in global
## space, so it does not matter whether the node the rig hangs under is rotated (enemies rotate theirs).

const LOOK_DIRECTORY: String = "res://assets/characters/"
## Below this speed a character is standing, not walking.
const WALK_SPEED: float = 12.0
## How quickly the legs swing round to a new heading, per second. Snappy, but not instant, so a sudden
## reversal reads as a turn.
const LEG_TURN_RATE: float = 14.0

var look: CharacterLook = null

var _legs: Sprite2D = null
var _torso: Sprite2D = null
## How far through the walk cycle the legs are, 0..1.
var _phase: float = 0.0
var _legs_angle: float = 0.0
var _weapon: String = ""
var _sway_strength: float = 0.0
## Whether `update` has run yet: the first one places the legs instead of swinging them round from 0.
var _placed: bool = false


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


## Builds the layers from `chosen`, or from a placeholder sized and coloured for this character when
## there is no look file for it yet.
func setup(chosen: CharacterLook, radius: float, tint: Color) -> void:
	look = chosen if chosen != null else CharacterLook.placeholder(radius, tint)
	# Art is authored larger than it is shown, so it is drawn through its mipmaps: shrinking a texture to
	# a quarter of its size without them shimmers as the character moves and turns.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _legs == null:
		_legs = Sprite2D.new()
		_legs.name = "Legs"
		_legs.z_index = Layers.Z_ACTOR
		add_child(_legs)
	if _torso == null:
		_torso = Sprite2D.new()
		_torso.name = "Torso"
		# Above the legs, and above the rest of the character's own art.
		_torso.z_index = Layers.Z_ACTOR + 1
		add_child(_torso)
	_legs.texture = look.legs_sheet
	_legs.hframes = maxi(1, look.legs_frames)
	_legs.frame = 0
	_legs.scale = Vector2.ONE * look.art_scale
	_legs.offset = _centre_offset(_frame_size(look.legs_sheet, _legs.hframes), look.legs_pivot)
	_apply_torso()


func set_weapon(weapon_id: String) -> void:
	if weapon_id == _weapon:
		return
	_weapon = weapon_id
	_apply_torso()


## Call every frame. `velocity` in world pixels per second, `aim_angle` in radians, global.
func update(delta: float, velocity: Vector2, aim_angle: float) -> void:
	if look == null:
		return
	var speed: float = velocity.length()
	var walking: bool = speed > WALK_SPEED
	var heading: float = aim_angle
	var direction: float = 1.0
	if walking:
		heading = velocity.angle()
		if absf(angle_difference(aim_angle, heading)) > deg_to_rad(look.backpedal_degrees):
			heading += PI
			direction = -1.0
		_phase = fposmod(_phase + direction * speed * delta / maxf(1.0, look.stride), 1.0)
	else:
		# Standing: frame 0 is the feet-together pose, and the feet turn to sit under the aim.
		_phase = 0.0
	if _placed:
		_legs_angle = lerp_angle(_legs_angle, heading, clampf(delta * LEG_TURN_RATE, 0.0, 1.0))
	else:
		_legs_angle = heading
		_placed = true

	var frames: int = maxi(1, look.legs_frames)
	_legs.frame = int(_phase * float(frames)) % frames
	_legs.global_rotation = _legs_angle

	# The sway fades in and out rather than snapping, so stopping mid-stride does not jolt the torso.
	_sway_strength = move_toward(_sway_strength, 1.0 if walking else 0.0, delta * 6.0)
	var side: Vector2 = Vector2.from_angle(aim_angle + PI * 0.5)
	_torso.global_rotation = aim_angle
	_torso.global_position = global_position + side * sin(_phase * TAU) * look.sway * _sway_strength


func _apply_torso() -> void:
	if _torso == null or look == null:
		return
	var texture: Texture2D = look.torso_for(_weapon)
	_torso.texture = texture
	_torso.scale = Vector2.ONE * look.art_scale
	_torso.offset = _centre_offset(_frame_size(texture, 1), look.torso_pivot)


static func _frame_size(texture: Texture2D, frames: int) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return Vector2(float(texture.get_width()) / float(maxi(1, frames)), float(texture.get_height()))


## A Sprite2D is drawn about the middle of its frame; this moves the drawing so `pivot` (in frame
## pixels, from the top-left; negative for "the middle") lands on the node's origin instead.
static func _centre_offset(frame_size: Vector2, pivot: Vector2) -> Vector2:
	if pivot.x < 0.0 or pivot.y < 0.0:
		return Vector2.ZERO
	return frame_size * 0.5 - pivot
