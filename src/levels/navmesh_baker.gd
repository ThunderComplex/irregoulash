class_name NavmeshBaker
extends RefCounted
## Bakes a navigation mesh for a level straight from its `Wall` nodes.
##
## Deliberately plain code with no editor dependency, so the same logic runs from the
## editor plugin's "Bake navmesh" button, from a headless script, and from the probe
## that verifies the result.
##
## How it works: the polygon gets ONE outline covering the whole level, and the walls
## are subtracted as obstacles by the baker itself (they are `StaticBody2D` colliders,
## which `PARSED_GEOMETRY_STATIC_COLLIDERS` picks up). So authoring never involves
## drawing navigation polygons by hand -- place walls, click Bake.
##
## The wall geometry is hashed into the region's metadata, so the linter can tell when
## a mesh no longer matches the level it was baked from.

## A little larger than the player (14) and the enemies (11..17), so paths keep
## clearance from walls instead of hugging them.
const AGENT_RADIUS: float = 18.0
const CELL_SIZE: float = 1.0
const BORDER_SIZE: float = 0.0
## How far outside the geometry the walkable outline is placed. The border walls are
## solid, so this only has to enclose them.
const OUTLINE_MARGIN: float = 96.0
const HASH_META: StringName = &"navmesh_hash"
## The group every `Wall` puts itself in; the bake reads its obstacles from it.
const SOURCE_GROUP: StringName = &"wall"


## Bakes `region` in place and returns a small report:
## { "polygons": int, "outlines": int, "walls": int }.
static func bake(region: NavigationRegion2D, walls: Array[Wall]) -> Dictionary:
	var polygon: NavigationPolygon = region.navigation_polygon
	if polygon == null:
		polygon = NavigationPolygon.new()
		region.navigation_polygon = polygon
	configure(polygon, walls)
	# Synchronous: the caller wants to report real numbers straight away, and a level's
	# geometry is small enough that this costs milliseconds.
	region.bake_navigation_polygon(false)
	region.set_meta(HASH_META, geometry_hash(walls))
	return {
		"polygons": polygon.get_polygon_count(),
		"outlines": polygon.get_outline_count(),
		"walls": walls.size(),
	}


## Points the polygon at the level's walls, and gives it its outline.
##
## The walls are named by *group* rather than by "everything under the root": the
## `Wall` scene puts itself in the "wall" group, which is the same set the editor and
## the linter see, and it makes the source of the bake independent of where in the tree
## the parser starts looking.
static func configure(polygon: NavigationPolygon, walls: Array[Wall]) -> void:
	polygon.clear_outlines()
	polygon.set_parsed_geometry_type(NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS)
	polygon.set_source_geometry_mode(NavigationPolygon.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN)
	polygon.set_source_geometry_group_name(SOURCE_GROUP)
	polygon.set_agent_radius(AGENT_RADIUS)
	polygon.set_cell_size(CELL_SIZE)
	polygon.set_border_size(BORDER_SIZE)
	polygon.add_outline(outline_for(walls))


## One rectangle enclosing everything, grown a little. Walls inside it become holes.
static func outline_for(walls: Array[Wall]) -> PackedVector2Array:
	var bounds: Rect2 = bounds_of(walls).grow(OUTLINE_MARGIN)
	return PackedVector2Array([
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
	])


static func bounds_of(walls: Array[Wall]) -> Rect2:
	var rect := Rect2()
	var first: bool = true
	for wall: Wall in walls:
		if not is_instance_valid(wall):
			continue
		rect = wall.world_rect() if first else rect.merge(wall.world_rect())
		first = false
	return rect


## True when the mesh no longer matches the walls it was baked from (walls moved, were
## added, or were deleted). Always true for a region that has never been baked.
static func is_stale(region: NavigationRegion2D, walls: Array[Wall]) -> bool:
	if region == null or not region.has_meta(HASH_META):
		return true
	return int(region.get_meta(HASH_META)) != geometry_hash(walls)


## Stable fingerprint of the walls: sorted, so tree order cannot change it.
static func geometry_hash(walls: Array[Wall]) -> int:
	var rects: Array[Rect2] = []
	for wall: Wall in walls:
		if is_instance_valid(wall):
			rects.append(wall.world_rect())
	rects.sort_custom(func(a: Rect2, b: Rect2) -> bool:
		if not is_equal_approx(a.position.y, b.position.y):
			return a.position.y < b.position.y
		return a.position.x < b.position.x)
	return hash(rects)
