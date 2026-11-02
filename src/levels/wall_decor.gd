class_name WallDecor
extends MeshInstance2D
## Rim and ambient occlusion for a level's walls, drawn from the *merged* outline of the wall mass.
##
## A rectangle cannot know whether its edge is a real edge: where two walls meet -- an L, a T, a corner at
## any angle -- the shared boundary is not a boundary of the mass at all, and shading it produces an
## artificial line inside what should read as one solid shape. Merging the polygons first means those
## edges do not exist, so joins, angles and overlaps are correct by construction.
##
## The bands are built as *mitred rings* around each outline rather than as one band per edge. Per-edge
## bands meet at a corner and their alphas add, which reads as a hard-edged darker square at exactly the
## places -- inside corners -- where occlusion is most visible. Rings share their vertices across a
## corner, so the gradient is continuous the whole way round.
##
## Two phases, because their costs differ by orders of magnitude: `setup()` merges and analyses the
## geometry once, and `refresh()` rebuilds only vertex data so marking a wall explored stays cheap.
##
## Visibility stays per wall: each outline *segment* takes the explored state of the wall it belongs to,
## so nothing is revealed that has not been seen.

## Growth used when merging, so walls that merely touch are treated as connected: a shared edge is
## zero-area overlap, which polygon merging does not count as an overlap.
const TOUCH_EPSILON: float = 0.5
## Rings across the occlusion band. Four is enough to read as a gradient at these widths.
const AO_RINGS: int = 4
## Sharp corners produce huge mitres; cap them so a very acute angle does not shoot off across the room.
const MITER_LIMIT: float = 3.0
## How far south a segment has to face before it gets the extra "the face falls away" darkening.
const SOUTH_FACING: float = 0.35

var _walls: Array[Wall] = []
var _outlines: Array[Dictionary] = []
var _style: SurfaceStyle = null


func _ready() -> void:
	# Built here rather than through `FxDirector`: this node exists in the editor too, and autoloads are
	# placeholders there.
	var canvas_material := CanvasItemMaterial.new()
	canvas_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = canvas_material
	z_index = Layers.Z_WALL_EDGE


## Merges the walls and caches, per outline segment, everything the drawing pass needs: its ends, the
## mitred inward direction at each end, the wall that owns it, and whether it faces south.
func setup(walls: Array[Wall], style: SurfaceStyle) -> void:
	_walls = walls
	_style = style
	_outlines.clear()
	if style == null or not style.is_textured():
		refresh()
		return

	for outline: PackedVector2Array in _merged_outlines(walls):
		if outline.size() < 3:
			continue
		var count: int = outline.size()
		# Inward normal of each *edge*, established by asking the walls which side is solid rather than
		# trusting a winding convention -- a convention guessed wrong pointed every band at the floor.
		var edge_inward: Array[Vector2] = []
		for i: int in count:
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i + 1) % count]
			var normal: Vector2 = (b - a).orthogonal().normalized()
			if not _is_solid((a + b) * 0.5 + normal * 2.0):
				normal = -normal
			edge_inward.append(normal)

		# Miter directions at each *vertex*: the bisector of the two edges that meet there, scaled so the
		# offset ring stays a constant distance from both.
		var normals := PackedVector2Array()
		var scales := PackedFloat32Array()
		for i: int in count:
			var previous: Vector2 = edge_inward[(i - 1 + count) % count]
			var following: Vector2 = edge_inward[i]
			var bisector: Vector2 = previous + following
			if bisector.length_squared() < 0.01:
				bisector = following
			bisector = bisector.normalized()
			normals.append(bisector)
			scales.append(minf(1.0 / maxf(0.2, bisector.dot(following)), MITER_LIMIT))

		var owners: Array[Wall] = []
		var south: Array[bool] = []
		for i: int in count:
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i + 1) % count]
			owners.append(_owner_of((a + b) * 0.5, a, b))
			south.append((-edge_inward[i]).y > SOUTH_FACING)

		_outlines.append({
			"points": outline, "normals": normals, "scales": scales,
			"owners": owners, "south": south,
		})
	refresh()


## Rebuilds only the vertex data, so this can run whenever a wall becomes explored.
func refresh() -> void:
	if _style == null or not _style.is_textured():
		mesh = null
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for entry: Dictionary in _outlines:
		_emit(surface, entry)
	mesh = surface.commit()


func _emit(surface: SurfaceTool, entry: Dictionary) -> void:
	var points: PackedVector2Array = entry["points"]
	var normals: PackedVector2Array = entry["normals"]
	var scales: PackedFloat32Array = entry["scales"]
	var owners: Array = entry["owners"]
	var south: Array = entry["south"]
	var count: int = points.size()

	var occlusion_width: float = _style.rim_ao_width
	var occlusion_strength: float = _style.rim_ao_strength
	if occlusion_width > 0.0 and occlusion_strength > 0.0:
		for i: int in count:
			var owner := owners[i] as Wall
			if owner != null and not owner.is_explored():
				continue
			var strength: float = occlusion_strength
			if bool(south[i]):
				# A south-facing edge is where the wall's face falls away from the camera: extra darkening
				# here is what reads as thickness rather than as a flat cut-out.
				strength *= 1.0 + _style.base_strength
			var a: Vector2 = points[i]
			var b: Vector2 = points[(i + 1) % count]
			var na: Vector2 = normals[i]
			var nb: Vector2 = normals[(i + 1) % count]
			var sa: float = scales[i]
			var sb: float = scales[(i + 1) % count]
			for ring: int in AO_RINGS:
				var t0: float = float(ring) / float(AO_RINGS)
				var t1: float = float(ring + 1) / float(AO_RINGS)
				var dark0 := Color(0.0, 0.0, 0.0, strength * (1.0 - t0))
				var dark1 := Color(0.0, 0.0, 0.0, strength * (1.0 - t1))
				_quad(surface,
					a + na * (occlusion_width * t0 * sa), b + nb * (occlusion_width * t0 * sb),
					b + nb * (occlusion_width * t1 * sb), a + na * (occlusion_width * t1 * sa),
					dark0, dark0, dark1, dark1)

	if _style.rim_width > 0.0 and _style.rim_boost > 0.0:
		var rim := _style.tint.lightened(0.5)
		rim.a = clampf(0.3 + _style.rim_boost, 0.0, 1.0)
		for i: int in count:
			var owner := owners[i] as Wall
			if owner != null and not owner.is_explored():
				continue
			var a: Vector2 = points[i]
			var b: Vector2 = points[(i + 1) % count]
			var na: Vector2 = normals[i] * _style.rim_width * scales[i]
			var nb: Vector2 = normals[(i + 1) % count] * _style.rim_width * scales[(i + 1) % count]
			_quad(surface, a, b, b + nb, a + na, rim, rim, rim, rim)


## `outer_a`-`outer_b` is the edge on the outline; `inner_b`-`inner_a` is the matching edge one step in.
## The two quads share their vertices with the neighbouring segments' quads, which is what keeps the
## gradient continuous around a corner instead of stacking two separate bands on top of each other.
func _quad(surface: SurfaceTool, outer_a: Vector2, outer_b: Vector2, inner_b: Vector2,
		inner_a: Vector2, ca: Color, cb: Color, cb_inner: Color, ca_inner: Color) -> void:
	surface.set_color(ca)
	surface.add_vertex(Vector3(outer_a.x, outer_a.y, 0.0))
	surface.set_color(cb)
	surface.add_vertex(Vector3(outer_b.x, outer_b.y, 0.0))
	surface.set_color(cb_inner)
	surface.add_vertex(Vector3(inner_b.x, inner_b.y, 0.0))

	surface.set_color(ca)
	surface.add_vertex(Vector3(outer_a.x, outer_a.y, 0.0))
	surface.set_color(cb_inner)
	surface.add_vertex(Vector3(inner_b.x, inner_b.y, 0.0))
	surface.set_color(ca_inner)
	surface.add_vertex(Vector3(inner_a.x, inner_a.y, 0.0))


## Is this point inside any wall? The walls are the definition of where the solid is, which is more
## reliable than any winding convention.
func _is_solid(point: Vector2) -> bool:
	for wall: Wall in _walls:
		if wall == null or not is_instance_valid(wall):
			continue
		if not wall.world_rect().grow(4.0).has_point(point):
			continue
		if Geometry2D.is_point_in_polygon(point, wall.world_polygon()):
			return true
	return false


func _owner_of(point: Vector2, a: Vector2, b: Vector2) -> Wall:
	for wall: Wall in _walls:
		if not is_instance_valid(wall):
			continue
		if wall.world_rect().has_point(point):
			return wall
	# A segment exactly on a shared boundary belongs to nobody by the test above; fall back to the nearest
	# wall, which is still the right one for visibility.
	var best: Wall = null
	var best_distance: float = INF
	for wall: Wall in _walls:
		if not is_instance_valid(wall):
			continue
		var distance: float = wall.world_rect().get_center().distance_to((a + b) * 0.5)
		if distance < best_distance:
			best_distance = distance
			best = wall
	return best


#region merging

## Union of every wall's footprint, as outer outlines and hole outlines.
static func _merged_outlines(walls: Array[Wall]) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	for wall: Wall in walls:
		if wall != null and is_instance_valid(wall):
			polygons.append(_grown(wall.world_polygon(), TOUCH_EPSILON))
	if polygons.is_empty():
		return polygons

	# Merge pairs until nothing more can be merged. Runs once per level, not per frame, and wall counts
	# are in the dozens even for a maze of rooms.
	var changed: bool = true
	while changed:
		changed = false
		var i: int = 0
		while i < polygons.size():
			var j: int = i + 1
			while j < polygons.size():
				var merged: Array[PackedVector2Array] = Geometry2D.merge_polygons(polygons[i],
					polygons[j])
				if _is_real_merge(merged, polygons[i], polygons[j]):
					polygons[i] = merged[0]
					for extra: int in range(1, merged.size()):
						polygons.append(merged[extra])
					polygons.remove_at(j)
					changed = true
				else:
					j += 1
			i += 1
	return polygons


## `merge_polygons` hands back the two inputs untouched when they do not overlap, and an outer polygon
## plus hole polygons when one contains the other. Tell those apart so a ring of walls merges instead of
## being treated as separate.
static func _is_real_merge(merged: Array[PackedVector2Array], a: PackedVector2Array,
		b: PackedVector2Array) -> bool:
	if merged.size() != 2:
		return merged.size() == 1
	var first: PackedVector2Array = merged[0]
	var second: PackedVector2Array = merged[1]
	return not ((first == a and second == b) or (first == b and second == a))


## The wall's footprint in world space, grown by `amount` about its centre so touching walls count as
## overlapping.
static func _grown(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var centre := Vector2.ZERO
	for point: Vector2 in points:
		centre += point
	centre /= float(maxi(1, points.size()))
	for point: Vector2 in points:
		out.append(point + (point - centre).normalized() * amount)
	return out

#endregion
