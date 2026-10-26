class_name AbilityCasting
extends RefCounted
## The aiming rules every ability shares, in one place so a cast and any aiming feedback
## cannot disagree about where an ability will land.
##
## Deliberately pure functions over a cursor position rather than reading the mouse, so
## they can be reasoned about and tested without a viewport.

## Where a POINT ability lands for a given cursor position: at the cursor, pulled back to
## `max_range` if that is further than the ability can reach.
static func clamped_target(caster_position: Vector2, cursor: Vector2, max_range: float) -> Vector2:
	var offset: Vector2 = cursor - caster_position
	if max_range <= 0.0 or offset.length() <= max_range:
		return cursor
	return caster_position + offset.normalized() * max_range


## Whether a POINT ability may be placed at `point`.
##
## Only abilities that ask for room (a wall of fire) are refused, and they are refused
## rather than placed inside geometry -- which is also what the "that cast was refused"
## feedback keys off.
static func can_place(caster: Node2D, point: Vector2, data: AbilityResource) -> bool:
	if not data.requires_clear_space:
		return true
	var space: PhysicsDirectSpaceState2D = caster.get_world_2d().direct_space_state
	if space == null:
		return true
	var shape := CircleShape2D.new()
	shape.radius = data.placement_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = Layers.SOLID
	query.collide_with_areas = false
	return space.intersect_shape(query, 1).is_empty()
