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
## Enclosed free space smaller than this many square pixels is a sliver left by `TOUCH_EPSILON`, not a room.
const MIN_ROOM_AREA: float = 64.0
## Rings across the occlusion band. Four is enough to read as a gradient at these widths.
const AO_RINGS: int = 4
## Sharp corners produce huge mitres; cap them so a very acute angle does not shoot off across the room.
const MITER_LIMIT: float = 3.0
## How far south a segment has to face before it gets the extra "the face falls away" darkening.
const SOUTH_FACING: float = 0.35
## How far outside the outline the lighting mask is read, in world pixels. On the outline itself a wall
## reads its own shadow.
const REVEAL_PROBE: float = 10.0
## Size of the spatial bucket used to find the nearest outline segment.
const GRID_CELL: float = 96.0
## How many buckets outwards the search may go before giving up.
const GRID_SEARCH_RINGS: int = 4

## Multiplies the decoration by the same lighting mask the wall fill uses, so rim and occlusion appear
## exactly where the wall they belong to is lit.
const DECOR_SHADER: Shader = preload("res://src/levels/wall_decor.gdshader")

var _walls: Array[Wall] = []
var _outlines: Array[Dictionary] = []
var _style: SurfaceStyle = null
var _material: ShaderMaterial = null
## The lighting mask, sampled on the CPU so decoration appears where the wall around it is lit.
var _reveal: RevealMask = null
var _reveal_image: Image = null
## Where the player was when the mask was last read. A wall is lit by the space on the player's side of
## it, so every sample needs the player's position; caching it per update avoids a lookup per vertex.
var _player_position: Vector2 = Vector2.ZERO
var _has_player: bool = false
## Outline segments bucketed by position, so `_nearest_segment` stays cheap on a dense level.
var _segment_grid: Dictionary = {}
## How many segments `setup` has bucketed; each entry's `id`, so a segment spanning several cells is
## recognised as one.
var _segment_count: int = 0


## `sample_lighting_near`, precomputed for a fixed set of points (the wall fill's vertices).
##
## Everything about a lookup except the player's position and the mask's pixels is fixed while the walls
## do not move: which outline segments are near a point, the closest spot on each, which way is into the
## wall, and which mask pixel that spot is read from. Working it out once per wall setup leaves a lookup
## costing a dot product per candidate and a byte read, instead of a grid search through dictionaries.
class LightingCache:
	extends RefCounted
	## Per point, where its candidates start in the arrays below; one extra entry at the end.
	var offsets := PackedInt32Array()
	## Per candidate, nearest first: the closest spot on the segment, and the segment's inward normal.
	var closest := PackedVector2Array()
	var inward := PackedVector2Array()
	## Per candidate, the byte in the mask image its lighting is read from, or -1 outside the mask.
	## Depends on the mask's rect and size, so it is rebuilt when those change.
	var pixel := PackedInt32Array()
	var pixel_layout: Array = []

	func point_count() -> int:
		return offsets.size() - 1


func _ready() -> void:
	# Built here rather than through `FxDirector`: this node exists in the editor too, and autoloads are
	# placeholders there. The shader is unshaded in its own `render_mode`, so no CanvasItemMaterial is
	# needed on top of it.
	_material = ShaderMaterial.new()
	_material.shader = DECOR_SHADER
	material = _material
	z_index = Layers.Z_WALL_EDGE


## Gives the decoration the level's lighting mask. Called by `Level` once the mask exists.
##
## The mask is sampled on the CPU, once per segment, rather than in the shader: a decoration fragment sits
## *on* the outline, so it suffers the wall's own shadow, and the per-segment `inward` direction is the one
## thing the shader does not have. Sampling just outside the outline, where the lighting is real, is easy
## here and impossible there.
func use_reveal(mask: RevealMask) -> void:
	_reveal = mask
	_cache_player()
	refresh()


## Re-reads the mask and rebuilds, so decoration follows the lighting at the mask's own update rate.
func sync_reveal() -> void:
	_cache_player()
	refresh()


## Remembers where the player is, once per mask update, so the many samples a rebuild makes do not each
## ask the game director.
func _cache_player() -> void:
	# This runs in the editor too, where the autoloads are placeholder objects that cannot be called.
	if Engine.is_editor_hint():
		_has_player = false
		return
	var player := GameDirector.valid_player()
	_has_player = player != null and is_instance_valid(player)
	if _has_player:
		_player_position = player.global_position


## Merges the walls and caches, per outline segment, everything the drawing pass needs: its ends, the
## mitred inward direction at each end, the wall that owns it, and whether it faces south.
func setup(walls: Array[Wall], style: SurfaceStyle) -> void:
	_walls = walls
	_style = style
	_outlines.clear()
	# Cleared here, not only filled: the level sets this up more than once (on load, then again when the
	# mask's first frame arrives, and on every wall edit in the editor), and every segment used to be
	# bucketed again on top of the last time -- each lighting lookup searched every segment twice.
	_segment_grid.clear()
	_segment_count = 0
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
			var wall_owner: Wall = _owner_of((a + b) * 0.5, a, b)
			owners.append(wall_owner)
			south.append((-edge_inward[i]).y > SOUTH_FACING)
			# Cache the segment per owning wall: `WallFill` asks each of its vertices for the nearest one,
			# and restricting the search to the wall's own outline keeps that cheap.
			# Bucket the segment by every grid cell its bounding box touches, so the nearest-outline query
			# is a handful of comparisons rather than a scan of the whole silhouette.
			var entry := {"a": a, "b": b, "inward": edge_inward[i], "id": _segment_count}
			_segment_count += 1
			var low := Vector2i(int(floor(minf(a.x, b.x) / GRID_CELL)),
				int(floor(minf(a.y, b.y) / GRID_CELL)))
			var high := Vector2i(int(floor(maxf(a.x, b.x) / GRID_CELL)),
				int(floor(maxf(a.y, b.y) / GRID_CELL)))
			for gx: int in range(low.x, high.x + 1):
				for gy: int in range(low.y, high.y + 1):
					var key := Vector2i(gx, gy)
					var bucket: Array = _segment_grid.get(key, [])
					bucket.append(entry)
					_segment_grid[key] = bucket

		_outlines.append({
			"points": outline, "normals": normals, "scales": scales,
			"owners": owners, "south": south,
		})
	refresh()


## Rebuilds the vertex data from the cached outlines and the current lighting mask. It runs at the mask's
## update rate, so it is kept to per-segment work; per-vertex sampling is left to `WallFill`.
func refresh() -> void:
	if _style == null or not _style.is_textured():
		mesh = null
		return
	# The mask's own copy: `texture.get_image()` would be a second GPU read-back every refresh.
	_reveal_image = _reveal.image if _reveal != null else null
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for entry: Dictionary in _outlines:
		_emit(surface, entry)
	mesh = surface.commit()


## How lit the wall is at `point`, judged by the nearest piece of the whole silhouette that faces the
## player.
##
## This is the single definition of "how lit is the wall here": the decoration samples it per segment, and
## `WallFill` samples it per vertex, so the two cannot disagree. The sample is taken a step *outside* that
## edge, because the mask on top of a wall is the wall's own shadow.
func sample_lighting_near(point: Vector2) -> float:
	# Nearest piece of the *whole* silhouette, not of the wall the caller belongs to. Restricting it per
	# wall is what made joins seam: on one side of a join the nearest edge of wall A was sampled, on the
	# other the nearest edge of wall B, and the two disagreed across a boundary that is not an edge at all.
	#
	# Of the edges facing the player, though: a wall is lit by the space you look at it from. Without
	# that, a 64px-thick wall is only lit for the ~20px nearest its lit edge and black for the rest,
	# because the vertices there are nearest the far edge and sample the space behind the wall.
	var entry: Dictionary = _nearest_segment(point, true)
	if entry.is_empty():
		entry = _nearest_segment(point, false)
	if entry.is_empty():
		return 0.0
	var a: Vector2 = entry["a"]
	var b: Vector2 = entry["b"]
	var along: Vector2 = b - a
	var length_squared: float = along.length_squared()
	var t: float = 0.0 if length_squared < 0.0001 else clampf(
		(point - a).dot(along) / length_squared, 0.0, 1.0)
	return _lit_outside(a + along * t, entry["inward"])


## Builds the cache for `points`. The candidates for a point are every segment `_nearest_segment` could
## pick for it -- all of those in its block of grid cells -- sorted by distance, so the first one facing
## the player is the one it would have returned, and the first of all is its fallback.
func lighting_cache(points: PackedVector2Array) -> LightingCache:
	var cache := LightingCache.new()
	cache.offsets.resize(points.size() + 1)
	# Every point in a grid cell has the same block of cells around it, so the segments in that block are
	# gathered once per cell, not once per point.
	var near_cell: Dictionary = {}
	for index: int in points.size():
		cache.offsets[index] = cache.closest.size()
		var point: Vector2 = points[index]
		var cell := Vector2i(int(floor(point.x / GRID_CELL)), int(floor(point.y / GRID_CELL)))
		if not near_cell.has(cell):
			near_cell[cell] = _segments_around(cell)
		var found: Array[Array] = []
		for entry: Dictionary in (near_cell[cell] as Array):
			var a: Vector2 = entry["a"]
			var along: Vector2 = (entry["b"] as Vector2) - a
			var length_squared: float = along.length_squared()
			var t: float = 0.0 if length_squared < 0.0001 else clampf(
				(point - a).dot(along) / length_squared, 0.0, 1.0)
			var closest: Vector2 = a + along * t
			found.append([closest.distance_squared_to(point), found.size(), closest, entry["inward"]])
		found.sort_custom(func(left: Array, right: Array) -> bool:
			return left[0] < right[0] or (left[0] == right[0] and left[1] < right[1]))
		for candidate: Array in found:
			cache.closest.append(candidate[2])
			cache.inward.append(candidate[3])
	cache.offsets[points.size()] = cache.closest.size()
	return cache


## Whether there is a mask frame to light from. Without one every point reads fully lit, so a lighting
## cache would never be consulted -- which is always the case in the editor, where the mask is not
## photographed.
func has_lighting() -> bool:
	return _reveal != null and _reveal_image != null


## Every segment in the block of cells `_nearest_segment` searches around `cell`, each once, in the order
## it first meets them: ring by ring, outwards. Equally near segments keep that order when sorted, which
## matters because ties are real -- a vertex on a wall's corner is exactly as close to both edges that
## meet there, and the two read the lighting from different sides.
func _segments_around(cell: Vector2i) -> Array[Dictionary]:
	var seen: Dictionary = {}
	var out: Array[Dictionary] = []
	for ring: int in range(0, GRID_SEARCH_RINGS + 1):
		for x: int in range(cell.x - ring, cell.x + ring + 1):
			for y: int in range(cell.y - ring, cell.y + ring + 1):
				var bucket: Variant = _segment_grid.get(Vector2i(x, y))
				if not (bucket is Array):
					continue
				for entry: Dictionary in (bucket as Array):
					if seen.has(entry["id"]):
						continue
					seen[entry["id"]] = true
					out.append(entry)
	return out


## Fills `out` (one value per point of `cache`) with how lit each point is: the same answer as
## `sample_lighting_near`, from the cache and the mask's current frame.
func sample_cached(cache: LightingCache, out: PackedFloat32Array) -> void:
	var count: int = cache.point_count()
	out.resize(count)
	if _reveal == null or _reveal_image == null or _reveal.world_rect.size.x <= 0.0 \
			or _reveal.world_rect.size.y <= 0.0:
		out.fill(1.0)
		return
	var bytes_per_pixel: int = _bytes_per_pixel(_reveal_image.get_format())
	if bytes_per_pixel == 0:
		# A format this does not read directly: fall back to the slow, general path.
		for index: int in count:
			out[index] = _cached_choice_slow(cache, index)
		return
	_ensure_pixels(cache, bytes_per_pixel)
	var data: PackedByteArray = _reveal_image.get_data()
	var player: Vector2 = _player_position
	var facing: bool = _has_player
	var offsets: PackedInt32Array = cache.offsets
	var closest: PackedVector2Array = cache.closest
	var inward: PackedVector2Array = cache.inward
	var pixel: PackedInt32Array = cache.pixel
	for index: int in count:
		var start: int = offsets[index]
		var end: int = offsets[index + 1]
		if start == end:
			out[index] = 0.0
			continue
		var chosen: int = start
		if facing:
			for candidate: int in range(start, end):
				if (player - closest[candidate]).dot(inward[candidate]) < 0.0:
					chosen = candidate
					break
		var at: int = pixel[chosen]
		out[index] = 0.0 if at < 0 else float(data[at]) / 255.0


## The mask byte each candidate reads, worked out the way `_lit_outside` finds its pixel. Kept until the
## mask's rect or resolution changes.
func _ensure_pixels(cache: LightingCache, bytes_per_pixel: int) -> void:
	var rect: Rect2 = _reveal.world_rect
	var width: int = _reveal_image.get_width()
	var height: int = _reveal_image.get_height()
	var layout: Array = [rect, width, height, bytes_per_pixel]
	if cache.pixel_layout == layout and cache.pixel.size() == cache.closest.size():
		return
	cache.pixel_layout = layout
	cache.pixel.resize(cache.closest.size())
	for candidate: int in cache.closest.size():
		var point: Vector2 = cache.closest[candidate] - cache.inward[candidate] * REVEAL_PROBE
		var uv: Vector2 = (point - rect.position) / rect.size
		if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
			cache.pixel[candidate] = -1
			continue
		var x: int = clampi(int(uv.x * float(width)), 0, width - 1)
		var y: int = clampi(int(uv.y * float(height)), 0, height - 1)
		cache.pixel[candidate] = (y * width + x) * bytes_per_pixel


## Bytes per pixel for the formats whose first byte is the red channel, 0 for anything else.
static func _bytes_per_pixel(format: Image.Format) -> int:
	match format:
		Image.FORMAT_RGBA8:
			return 4
		Image.FORMAT_RGB8:
			return 3
		Image.FORMAT_R8, Image.FORMAT_L8:
			return 1
	return 0


func _cached_choice_slow(cache: LightingCache, index: int) -> float:
	var start: int = cache.offsets[index]
	var end: int = cache.offsets[index + 1]
	if start == end:
		return 0.0
	var chosen: int = start
	if _has_player:
		for candidate: int in range(start, end):
			if (_player_position - cache.closest[candidate]).dot(cache.inward[candidate]) < 0.0:
				chosen = candidate
				break
	return _lit_outside(cache.closest[chosen], cache.inward[chosen])


## The outline segment closest to `point`, using the spatial grid so a dense maze does not turn every
## vertex into a scan of the whole silhouette. With `facing_player`, only segments whose free side is the
## player's side count.
func _nearest_segment(point: Vector2, facing_player: bool) -> Dictionary:
	var want_facing: bool = facing_player and _has_player
	var cell: Vector2i = Vector2i(int(floor(point.x / GRID_CELL)), int(floor(point.y / GRID_CELL)))
	# Expand outwards until the best candidate found is closer than any cell still unsearched.
	#
	# This used to stop at the first ring that contained *anything*, which is wrong: a segment one cell
	# over can be right next to the point while the point's own cell holds a far-away segment. That is
	# exactly what a wall whose edge sits on a cell boundary gets -- its own edge was missed in favour of
	# the opposite side of the wall, so the whole wall sampled the space behind it and stayed black.
	var best: Dictionary = {}
	var best_distance: float = INF
	for ring: int in range(0, GRID_SEARCH_RINGS + 1):
		for x: int in range(cell.x - ring, cell.x + ring + 1):
			for y: int in range(cell.y - ring, cell.y + ring + 1):
				var bucket: Variant = _segment_grid.get(Vector2i(x, y))
				if not (bucket is Array):
					continue
				for entry: Dictionary in (bucket as Array):
					var a: Vector2 = entry["a"]
					var b: Vector2 = entry["b"]
					var along: Vector2 = b - a
					var length_squared: float = along.length_squared()
					var t: float = 0.0 if length_squared < 0.0001 else clampf(
						(point - a).dot(along) / length_squared, 0.0, 1.0)
					var closest: Vector2 = a + along * t
					if want_facing and (_player_position - closest).dot(entry["inward"]) >= 0.0:
						continue
					var distance: float = closest.distance_squared_to(point)
					if distance < best_distance:
						best_distance = distance
						best = entry
		# The squares searched so far are exact, so the distance to their edge is the closest an
		# unsearched segment could possibly be.
		var reach: float = minf(
			minf(point.x - float(cell.x - ring) * GRID_CELL,
				float(cell.x + ring + 1) * GRID_CELL - point.x),
			minf(point.y - float(cell.y - ring) * GRID_CELL,
				float(cell.y + ring + 1) * GRID_CELL - point.y))
		if not best.is_empty() and best_distance <= reach * reach:
			return best
	return best


## How lit the mask says the space just outside this piece of outline is.
##
## Always a step *out* of the wall, never into it: `inward` points into the solid, and the mask on top of
## the wall is the wall's own shadow, so a sample taken inward can only ever read darkness. Stepping
## outward reads the space the wall borders -- which is what lights it.
func _lit_outside(mid: Vector2, inward: Vector2) -> float:
	if _reveal == null or _reveal_image == null:
		return 1.0
	var rect: Rect2 = _reveal.world_rect
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return 1.0
	var point: Vector2 = mid - inward * REVEAL_PROBE
	var uv: Vector2 = (point - rect.position) / rect.size
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return 0.0
	var x: int = clampi(int(uv.x * float(_reveal_image.get_width())), 0, _reveal_image.get_width() - 1)
	var y: int = clampi(int(uv.y * float(_reveal_image.get_height())), 0,
		_reveal_image.get_height() - 1)
	return _reveal_image.get_pixel(x, y).r


func _emit(surface: SurfaceTool, entry: Dictionary) -> void:
	var points: PackedVector2Array = entry["points"]
	var normals: PackedVector2Array = entry["normals"]
	var scales: PackedFloat32Array = entry["scales"]
	# var owners: Array = entry["owners"]
	var south: Array = entry["south"]
	var count: int = points.size()

	var occlusion_width: float = _style.rim_ao_width
	var occlusion_strength: float = _style.rim_ao_strength
	if occlusion_width > 0.0 and occlusion_strength > 0.0:
		for i: int in count:
			var mid: Vector2 = (points[i] + points[(i + 1) % count]) * 0.5
			var lit: float = _lit_outside(mid, normals[i])
			if lit <= 0.01:
				continue
			var strength: float = occlusion_strength * lit
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
			var mid: Vector2 = (points[i] + points[(i + 1) % count]) * 0.5
			var lit: float = _lit_outside(mid, normals[i])
			if lit <= 0.01:
				continue
			var a: Vector2 = points[i]
			var b: Vector2 = points[(i + 1) % count]
			var na: Vector2 = normals[i] * _style.rim_width * scales[i]
			var nb: Vector2 = normals[(i + 1) % count] * _style.rim_width * scales[(i + 1) % count]
			# Rim brightness follows the lighting too, so it does not outline stretches of wall that are
			# in the dark.
			var rim_lit := Color(rim.r, rim.g, rim.b, rim.a * lit)
			_quad(surface, a, b, b + nb, a + na, rim_lit, rim_lit, rim_lit, rim_lit)


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

## Union of every wall's footprint, as outlines: the outer contour of each group of touching walls, plus
## the boundary of every free space enclosed by that group -- the rooms.
##
## The rooms are the part that is easy to lose. `merge_polygons` reports a closed ring of walls as an outer
## contour and a separate hole, and the outer contour on its own is a *filled* shape covering the whole
## level: merging the next wall into it swallows that wall whole, and dropping the hole drops every edge
## that faces into a room. A level whose outer walls closed into a loop came out as a single outline round
## its outside, no wall had an edge to sample light from, and nothing was ever revealed. So the outer
## contour is built per group of walls that actually touch, and the rooms are cut back out of it from the
## walls themselves rather than trusted to the merge.
static func _merged_outlines(walls: Array[Wall]) -> Array[PackedVector2Array]:
	var footprints: Array[PackedVector2Array] = []
	for wall: Wall in walls:
		if wall != null and is_instance_valid(wall):
			footprints.append(_grown(wall.world_polygon(), TOUCH_EPSILON))
	var out: Array[PackedVector2Array] = []
	for group: Array[PackedVector2Array] in _touching_groups(footprints):
		var outer: PackedVector2Array = _outer_contour(group)
		out.append(outer)
		out.append_array(_enclosed_space(outer, group))
	return out


## Footprints split into groups that touch, directly or through each other. A wall standing alone in a
## room is its own group, so it keeps its own outline instead of vanishing into the room's surroundings.
static func _touching_groups(footprints: Array[PackedVector2Array]) -> Array[Array]:
	var group_of: Array[int] = []
	for i: int in footprints.size():
		group_of.append(i)
	for i: int in footprints.size():
		for j: int in range(i + 1, footprints.size()):
			if Geometry2D.intersect_polygons(footprints[i], footprints[j]).is_empty():
				continue
			var from: int = group_of[j]
			var to: int = group_of[i]
			if from == to:
				continue
			for k: int in group_of.size():
				if group_of[k] == from:
					group_of[k] = to
	var by_root: Dictionary = {}
	for i: int in footprints.size():
		if not by_root.has(group_of[i]):
			var fresh: Array[PackedVector2Array] = []
			by_root[group_of[i]] = fresh
		(by_root[group_of[i]] as Array[PackedVector2Array]).append(footprints[i])
	var groups: Array[Array] = []
	for root: int in by_root:
		groups.append(by_root[root])
	return groups


## The outside edge of one group of touching footprints. Holes the merge reports are ignored here on
## purpose; `_enclosed_space` finds them properly.
static func _outer_contour(group: Array[PackedVector2Array]) -> PackedVector2Array:
	var outer: PackedVector2Array = group[0]
	var pending: Array[PackedVector2Array] = group.slice(1)
	# A footprint can only be merged once something it touches is already in; keep sweeping until every
	# one has been, or a sweep makes no progress (which a touching group cannot do, but a loop must end).
	var progress: bool = true
	while not pending.is_empty() and progress:
		progress = false
		var i: int = 0
		while i < pending.size():
			var solids: Array[PackedVector2Array] = []
			for piece: PackedVector2Array in Geometry2D.merge_polygons(outer, pending[i]):
				if not Geometry2D.is_polygon_clockwise(piece):
					solids.append(piece)
			if solids.size() == 1:
				outer = solids[0]
				pending.remove_at(i)
				progress = true
			else:
				# Not touching what has been merged so far: the two came back separately.
				i += 1
	return outer


## The free space inside `outer` once every footprint of its group is cut out of it: the rooms the group
## encloses. Empty for a group that encloses nothing, which is almost every group.
static func _enclosed_space(outer: PackedVector2Array,
		group: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var free: Array[PackedVector2Array] = [outer]
	var pending: Array[PackedVector2Array] = group.duplicate()
	var progress: bool = true
	while not pending.is_empty() and progress:
		progress = false
		var i: int = 0
		while i < pending.size():
			var cut: Array[PackedVector2Array] = []
			var punched_hole: bool = false
			for region: PackedVector2Array in free:
				for piece: PackedVector2Array in Geometry2D.clip_polygons(region, pending[i]):
					if Geometry2D.is_polygon_clockwise(piece):
						punched_hole = true
					cut.append(piece)
			if punched_hole:
				# This footprint sits strictly inside a free region, away from everything cut so far, and
				# `clip_polygons` would report it as a hole that the next cut ignores. Cut it once a
				# neighbour has carved the region up to it.
				i += 1
				continue
			free = cut
			pending.remove_at(i)
			progress = true
	# The footprints are grown by `TOUCH_EPSILON`, so cutting them out of their own union leaves hairline
	# slivers along every join. Anything smaller than a wall corner is not a room.
	var rooms: Array[PackedVector2Array] = []
	for region: PackedVector2Array in free:
		if absf(_area(region)) > MIN_ROOM_AREA:
			rooms.append(region)
	return rooms


static func _area(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in points.size():
		total += points[i].cross(points[(i + 1) % points.size()])
	return total * 0.5


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
