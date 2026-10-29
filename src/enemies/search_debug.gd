class_name SearchDebugOverlay
extends Node2D
## Draws one enemy's search in world space, unshaded so it is readable in the dark.
##
## Kept separate from `Enemy._draw` for exactly that reason: the enemy's own canvas item is lit by
## the fog (that is how enemies stay invisible until your light reaches them), and a search drawn
## there is invisible in the dark -- which is where searches happen.
##
## Drawn in world space rather than as HUD text because "is it looking in the right place" is a
## question about geography.

var last_known: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var budget: float = 0.0
var near_radius: float = 0.0
var searched: Array[Vector2] = []
var active: bool = false


func _ready() -> void:
	material = FxDirector.unshaded_material()
	z_index = Layers.Z_FX


func show_search(known: Vector2, sought: Vector2, area: float, minimum: float,
		visited: Array[Vector2]) -> void:
	last_known = known
	target = sought
	budget = area
	near_radius = minimum
	searched = visited
	active = true
	queue_redraw()


func clear() -> void:
	active = false
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var area := Color(1.0, 0.85, 0.35, 0.30)
	var trail := Color(1.0, 0.45, 0.35, 0.85)
	var sought := Color(1.0, 0.92, 0.55, 0.90)
	var crossed := Color(0.62, 0.72, 0.85, 0.45)

	# How far the player could have got, and the minimum the search always covers.
	draw_arc(to_local(last_known), budget, 0.0, TAU, 64, area, 2.0)
	if not is_equal_approx(near_radius, budget):
		draw_arc(to_local(last_known), near_radius, 0.0, TAU, 48, Color(area, 0.16), 1.0)

	# Where the trail ends, where the enemy is heading, and everything already crossed off.
	var here := Vector2.ZERO
	var there: Vector2 = to_local(target)
	draw_line(here, there, sought, 2.0)
	draw_circle(there, 6.0, sought)
	draw_circle(to_local(last_known), 7.0, trail)

	for point: Vector2 in searched:
		var centre: Vector2 = to_local(point)
		draw_line(centre - Vector2(4.0, 4.0), centre + Vector2(4.0, 4.0), crossed, 1.0)
		draw_line(centre - Vector2(4.0, -4.0), centre + Vector2(4.0, -4.0), crossed, 1.0)
