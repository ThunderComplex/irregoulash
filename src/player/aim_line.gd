class_name AimLine
extends Node2D
## A thin line along the path the next shot will take, and a small crosshair where it would hit.
##
## It is the shot's real path: from the muzzle, along `Player.shot_direction`, stopped by whatever a
## player's bullet stops at (walls, doors, enemies) -- so the line is the shot, not an approximation of
## it. With a gamepad there is no cursor, and this is the aim.
##
## It reaches only as far as the player's vision cone. Further, it would find walls and enemies in the
## dark and give them away; within that range, anything it touches is lit by the player's own sight and
## already visible, so it reveals nothing.
##
## Only the player sees it; it is not a laser sight the enemies can notice. Off with the "Aim line"
## setting.

const COLOR: Color = Color(1.0, 0.18, 0.15)
const WIDTH: float = 1.5
## Opacity of the line where it leaves the gun, and where it ends at full reach: it fades with distance,
## so it guides the eye without drawing a bright stripe across the screen.
const NEAR_ALPHA: float = 0.55
const FAR_ALPHA: float = 0.08
const CROSSHAIR_RADIUS: float = 5.0

var _player: Player = null
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _hit: bool = false
var _reach: float = 1.0


func _ready() -> void:
	_player = get_parent() as Player
	# Drawn in world space, whatever the player does with its own transform.
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = Layers.Z_FX
	# Readable in the dark, like every other combat cue.
	material = FxDirector.unshaded_material()


func _process(_delta: float) -> void:
	visible = _should_show()
	if not visible:
		return
	_reach = maxf(1.0, Tuning.sight_far_range)
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var direction: Vector2 = _player.shot_direction()
	_from = _player.muzzle_position()
	# Pressed against a wall, the muzzle can be inside it; a shot starts at the wall then (see
	# `Projectile._clear_origin`), and so does the line.
	var exclude: Array[RID] = [_player.get_rid()]
	var inward := PhysicsRayQueryParameters2D.create(_player.global_position, _from,
		Layers.PLAYER_SHOT_HITS, exclude)
	var blocked: Dictionary = space.intersect_ray(inward)
	if not blocked.is_empty():
		_from = blocked["position"]
		_to = _from
		_hit = true
		queue_redraw()
		return
	# As far as the vision cone reaches, measured from the player like the cone is.
	var reach_end: Vector2 = _player.global_position + direction * _reach
	var along: float = maxf(0.0, (reach_end - _from).dot(direction))
	var ray := PhysicsRayQueryParameters2D.create(_from, _from + direction * along,
		Layers.PLAYER_SHOT_HITS, exclude)
	var hit: Dictionary = space.intersect_ray(ray)
	_hit = not hit.is_empty()
	_to = hit["position"] if _hit else _from + direction * along
	queue_redraw()


func _should_show() -> bool:
	if _player == null or _player.is_dead() or not Settings.aim_line_enabled:
		return false
	var holder := _player.weapons as WeaponHolder
	return holder != null and holder.slot() != null


func _draw() -> void:
	var far_alpha: float = lerpf(NEAR_ALPHA, FAR_ALPHA,
		clampf(_player.global_position.distance_to(_to) / _reach, 0.0, 1.0))
	draw_polyline_colors(PackedVector2Array([_from, _to]),
		PackedColorArray([Color(COLOR, NEAR_ALPHA), Color(COLOR, far_alpha)]), WIDTH, true)
	if not _hit:
		return
	# A small ring with four ticks: precise, and readable without hiding what it sits on.
	var mark := Color(COLOR, 0.9)
	draw_arc(_to, CROSSHAIR_RADIUS, 0.0, TAU, 16, mark, WIDTH, true)
	for side: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		draw_line(_to + side * (CROSSHAIR_RADIUS + 1.5), _to + side * (CROSSHAIR_RADIUS + 4.5), mark, WIDTH,
			true)
