class_name Shapes
extends RefCounted
## Small polygon builders for the geometric placeholder art.

static func circle(radius: float, segments: int = 18) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count: int = maxi(3, segments)
	for i: int in count:
		points.append(Vector2.from_angle(TAU * float(i) / float(count)) * radius)
	return points


static func circle_offset(radius: float, offset: Vector2, segments: int = 18) -> PackedVector2Array:
	var points := circle(radius, segments)
	for i: int in points.size():
		points[i] += offset
	return points


static func rect(size: Vector2) -> PackedVector2Array:
	var h: Vector2 = size * 0.5
	return PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
	])


## Closed outline (first point repeated) for use with Line2D.
static func closed_outline(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out


static func triangle(length: float, width: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(length, 0.0), Vector2(0.0, -width * 0.5), Vector2(0.0, width * 0.5),
	])
