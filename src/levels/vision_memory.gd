class_name VisionMemory
extends Node
## Remembers level geometry the player has already seen.
##
## Walks the walls in the level a few at a time, asks the player's vision rig
## "can I actually see this wall?" (a real raycast, not a distance guess), and
## asks the wall to reveal its faint memory copy once the answer is yes.
##
## This is what keeps pitch-black fog playable: you cannot see what is ahead of
## you, but the map you have already explored stays readable. Enemies have no
## memory copy, so they never show up here.
##
## Put one of these in every level (the Level base scene does it for you).

## How often to re-test unexplored geometry. Cheap; not worth doing every frame.
@export var sample_interval: float = 0.12
## How many unexplored walls may be raycast per tick (nearest first).
@export var max_checks_per_tick: int = 24
## Walls need the player to actually look at them, but a long wall whose centre is
## hidden can still be partly visible, so several points along it are tested.
@export var sample_points_per_wall: int = 3

var _timer: float = 0.0
var _walls: Array[Wall] = []


func _ready() -> void:
	for node: Node in get_tree().get_nodes_in_group("wall"):
		if node is Wall:
			_walls.append(node)


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = sample_interval

	var player: Node2D = GameDirector.player
	if player == null or not is_instance_valid(player):
		return
	var rig: VisionRig = player.get_node_or_null("Vision") as VisionRig
	if rig == null:
		return

	var candidates: Array[Wall] = []
	for wall: Wall in _walls:
		if is_instance_valid(wall) and not wall.is_explored():
			candidates.append(wall)
	if candidates.is_empty():
		return

	var origin: Vector2 = player.global_position
	candidates.sort_custom(func(a: Wall, b: Wall) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))

	var budget: int = mini(max_checks_per_tick, candidates.size())
	for i: int in budget:
		var wall: Wall = candidates[i]
		if _wall_is_visible(rig, wall):
			wall.mark_explored()


func _wall_is_visible(rig: VisionRig, wall: Wall) -> bool:
	var wall_size: Vector2 = wall.size
	var center: Vector2 = wall.global_position
	var offsets: Array[Vector2] = [Vector2.ZERO]
	var along: float = maxf(0.0, (maxf(wall_size.x, wall_size.y) * 0.5) - 16.0)
	if wall_size.x >= wall_size.y:
		offsets.append(Vector2(-along, 0.0))
		offsets.append(Vector2(along, 0.0))
	else:
		offsets.append(Vector2(0.0, -along))
		offsets.append(Vector2(0.0, along))

	var checks: int = clampi(sample_points_per_wall, 1, offsets.size())
	for i: int in checks:
		if rig.can_see_body(center + offsets[i], wall):
			return true
	return false


## Forget everything (used when a level restarts from scratch).
func reset() -> void:
	for wall: Wall in _walls:
		if is_instance_valid(wall):
			wall.reset_memory()
