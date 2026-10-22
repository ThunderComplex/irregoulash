@tool
class_name PatrolRoute
extends Node2D
## A patrol route. Its `Marker2D` children are the waypoints, in tree order.
##
## Everything is drawn in the editor: a dashed path, direction arrows, numbered
## waypoints, and a link line from every enemy in the level that patrols this
## route. That turns "wire up a NodePath and guess whether it worked" into a
## visual job -- if an enemy is not linked to a route, it shows up as a broken
## link on the enemy instead, and if a route is not used by anybody it is obvious
## at a glance.
##
## Enemies opt in through their own `patrol_route` property.
##
## Authoring: drop a PatrolRoute in the level, add two or more Marker2D children,
## drag them into place, then set each enemy's `patrol_route` to this node.

const DASH_LENGTH: float = 7.0

@export var color: Color = Color(0.55, 0.85, 1.0):
	set(value):
		color = value
		queue_redraw()
## Patrol back to the first waypoint when the last one is reached.
@export var loops: bool = true:
	set(value):
		loops = value
		queue_redraw()
## Draw a link from each enemy that patrols this route.
@export var show_users: bool = true:
	set(value):
		show_users = value
		queue_redraw()

var _state_hash: int = 0


func _ready() -> void:
	# Only needs to tick in the editor, to notice waypoints being dragged.
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	var current: int = _state_hash_of()
	if current != _state_hash:
		_state_hash = current
		queue_redraw()


#region data

## Waypoint positions, in this node's local space.
func points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for child: Node in get_children():
		var marker := child as Marker2D
		if marker != null:
			out.append(marker.position)
	return out


## Enemies whose `patrol_route` resolves to this node.
##
## Deliberately does not use the "enemy" group: this has to work on a level that
## has not been added to the scene tree (the linter instantiates levels without
## running them), where `get_tree()` is null. Walking the scene the route belongs
## to also scopes the search to this level, which is the behaviour we want anyway.
func users() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for node: Node in _descendants(_scene_root()):
		var enemy := node as Enemy
		if enemy == null or enemy.patrol_route == NodePath():
			continue
		if enemy.get_node_or_null(enemy.patrol_route) == self:
			out.append(enemy)
	return out


func _scene_root() -> Node:
	var node: Node = self
	while node.get_parent() != null:
		node = node.get_parent()
	return node


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


func _state_hash_of() -> int:
	var parts: Array = [points(), global_position, rotation, color, loops, show_users]
	for enemy: Enemy in users():
		parts.append(enemy.global_position)
	return hash(parts)

#endregion


#region editor drawing

func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	var font: Font = ThemeDB.fallback_font
	var points_in_route: PackedVector2Array = points()

	if show_users:
		_draw_user_links(font, points_in_route)

	if points_in_route.is_empty():
		_draw_upright_text(font, Vector2(-46.0, -8.0), "route needs Marker2D children",
			Color(1.0, 0.62, 0.4, 0.9))
		return
	if points_in_route.size() == 1:
		_draw_upright_text(font, Vector2(-34.0, -18.0), "1 waypoint: add another",
			Color(1.0, 0.62, 0.4, 0.9))

	# The path itself.
	var legs: int = points_in_route.size() if loops else points_in_route.size() - 1
	for i: int in legs:
		var from: Vector2 = points_in_route[i]
		var to: Vector2 = points_in_route[(i + 1) % points_in_route.size()]
		draw_dashed_line(from, to, Color(color, 0.55), 2.0, DASH_LENGTH)
		_draw_arrow((from + to) * 0.5, (to - from).angle())

	# Waypoints, numbered so a route order can be reasoned about.
	for i: int in points_in_route.size():
		var p: Vector2 = points_in_route[i]
		draw_circle(p, 6.0, Color(0.05, 0.06, 0.08, 0.85))
		draw_arc(p, 6.0, 0.0, TAU, 16, Color(color, 0.95), 2.0)
		_draw_upright_text(font, p + Vector2(9.0, -6.0), str(i), Color(color, 0.95))


func _draw_arrow(at: Vector2, angle: float) -> void:
	var size: float = 9.0
	var arrow := PackedVector2Array([
		Vector2(size, 0.0), Vector2(-size * 0.5, -size * 0.55), Vector2(-size * 0.5, size * 0.55),
	])
	for i: int in arrow.size():
		arrow[i] = arrow[i].rotated(angle) + at
	draw_colored_polygon(arrow, Color(color, 0.75))


## A dashed line from each enemy that uses this route to its first waypoint.
func _draw_user_links(font: Font, points_in_route: PackedVector2Array) -> void:
	if points_in_route.is_empty():
		return
	for enemy: Enemy in users():
		var enemy_local: Vector2 = to_local(enemy.global_position)
		draw_dashed_line(enemy_local, points_in_route[0], Color(color, 0.28), 1.0, 5.0)
		_draw_upright_text(font, enemy_local + Vector2(10.0, 16.0), "uses this route",
			Color(color, 0.55))


## Text stays horizontal even when the route node is rotated.
func _draw_upright_text(font: Font, at: Vector2, text: String, tint: Color) -> void:
	var counter: float = global_rotation
	draw_set_transform(Vector2.ZERO, -counter, Vector2.ONE)
	draw_string(font, at.rotated(counter), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

#endregion
