@tool
extends RefCounted
## The geometry behind the wall edge handles: where the four edges are, which one the mouse is on, and
## what a drag does to the wall. Kept apart from the plugin, and free of editor state, so it can be
## checked headlessly.
##
## Walls are axis-aligned rectangles (`Wall.world_rect()`), so an edge only ever moves along one axis:
## left and right along x, top and bottom along y.

enum Edge { NONE = -1, LEFT, TOP, RIGHT, BOTTOM }


## The two ends of `edge`, in world space.
static func segment(rect: Rect2, edge: int) -> PackedVector2Array:
	var a: Vector2 = rect.position
	var b: Vector2 = rect.end
	match edge:
		Edge.LEFT:
			return PackedVector2Array([a, Vector2(a.x, b.y)])
		Edge.TOP:
			return PackedVector2Array([a, Vector2(b.x, a.y)])
		Edge.RIGHT:
			return PackedVector2Array([Vector2(b.x, a.y), b])
		Edge.BOTTOM:
			return PackedVector2Array([Vector2(a.x, b.y), b])
	return PackedVector2Array()


## Where the handle for `edge` is drawn: the middle of the edge.
static func handle(rect: Rect2, edge: int) -> Vector2:
	var ends: PackedVector2Array = segment(rect, edge)
	return (ends[0] + ends[1]) * 0.5 if ends.size() == 2 else rect.get_center()


## The edge under `mouse`, or `Edge.NONE`. Both are in *viewport* pixels (`to_viewport` is the editor's
## canvas transform), so the grab distance stays the same at every zoom level: grab a handle, or anywhere
## along an edge. Handles win over plain edges, and a closer edge over a further one.
static func pick(rect: Rect2, to_viewport: Transform2D, mouse: Vector2, handle_grab: float,
		edge_grab: float) -> int:
	var best: int = Edge.NONE
	var best_distance: float = INF
	for edge: int in [Edge.LEFT, Edge.TOP, Edge.RIGHT, Edge.BOTTOM]:
		var distance: float = mouse.distance_to(to_viewport * handle(rect, edge))
		if distance <= handle_grab and distance < best_distance:
			best = edge
			best_distance = distance
	if best != Edge.NONE:
		return best
	for edge: int in [Edge.LEFT, Edge.TOP, Edge.RIGHT, Edge.BOTTOM]:
		var ends: PackedVector2Array = segment(rect, edge)
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(mouse,
			to_viewport * ends[0], to_viewport * ends[1])
		var distance: float = mouse.distance_to(closest)
		if distance <= edge_grab and distance < best_distance:
			best = edge
			best_distance = distance
	return best


## `start` with `edge` moved to `coordinate` (a world x for left/right, a world y for top/bottom).
##
## On its own, only that edge moves and the opposite one stays put. With `symmetric`, the opposite edge
## moves the same amount the other way, so the wall grows or shrinks about its centre. Either way the wall
## never gets thinner than `min_size`, and an edge dragged past its opposite stops there rather than
## flipping the wall inside out.
static func dragged(start: Rect2, edge: int, coordinate: float, symmetric: bool,
		min_size: float) -> Rect2:
	var left: float = start.position.x
	var top: float = start.position.y
	var right: float = start.end.x
	var bottom: float = start.end.y
	var centre: Vector2 = start.get_center()
	var half_min: float = min_size * 0.5
	match edge:
		Edge.LEFT:
			if symmetric:
				var half: float = maxf(half_min, centre.x - coordinate)
				left = centre.x - half
				right = centre.x + half
			else:
				left = minf(coordinate, right - min_size)
		Edge.RIGHT:
			if symmetric:
				var half: float = maxf(half_min, coordinate - centre.x)
				left = centre.x - half
				right = centre.x + half
			else:
				right = maxf(coordinate, left + min_size)
		Edge.TOP:
			if symmetric:
				var half: float = maxf(half_min, centre.y - coordinate)
				top = centre.y - half
				bottom = centre.y + half
			else:
				top = minf(coordinate, bottom - min_size)
		Edge.BOTTOM:
			if symmetric:
				var half: float = maxf(half_min, coordinate - centre.y)
				top = centre.y - half
				bottom = centre.y + half
			else:
				bottom = maxf(coordinate, top + min_size)
	return Rect2(left, top, right - left, bottom - top)


## Which world coordinate of the cursor drives `edge`: x for the vertical edges, y for the others.
static func axis_coordinate(edge: int, point: Vector2) -> float:
	return point.x if edge == Edge.LEFT or edge == Edge.RIGHT else point.y

