class_name AbilityCasting
extends RefCounted
## The aiming rules every ability shares, in one place so a cast and any aiming feedback
## cannot disagree about where an ability will land.
##
## Deliberately pure functions over a cursor position rather than reading the mouse, so
## they can be reasoned about and tested without a viewport.

## How far a blocked POINT ability may be moved to find room, and how finely that is searched.
## Far enough to step out of a wall the cursor is resting on, not so far that the effect lands
## somewhere the player did not mean.
const NUDGE_REACH: float = 96.0
const NUDGE_STEP: float = 12.0
const NUDGE_SAMPLES: int = 16


## Where a POINT ability lands for a given cursor position: at the cursor, pulled back to
## `max_range` if that is further than the ability can reach.
static func clamped_target(caster_position: Vector2, cursor: Vector2, max_range: float) -> Vector2:
	var offset: Vector2 = cursor - caster_position
	if max_range <= 0.0 or offset.length() <= max_range:
		return cursor
	return caster_position + offset.normalized() * max_range


## Whether a POINT ability may be placed at `point`.
##
## Only abilities that ask for room (a wall of fire) can fail this. `placement` uses it to
## find a nearby spot that passes before a cast is refused.
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


## Where a POINT ability actually lands: `point` if it fits there, otherwise the nearest spot within
## `NUDGE_REACH` that does. `Vector2.INF` when nothing nearby fits, and the cast is refused.
##
## Aiming a wall of fire at a doorway mid-fight should not fail because the cursor clipped the frame,
## so a blocked cast is moved rather than refused. A moved spot must also stay within reach and in
## plain view of the caster: nudging is for stepping out of the wall you aimed at, never for slipping
## the effect through it into the next room.
static func placement(caster: Node2D, point: Vector2, data: AbilityResource) -> Vector2:
	if can_place(caster, point, data):
		return point
	var space: PhysicsDirectSpaceState2D = caster.get_world_2d().direct_space_state
	if space == null:
		return Vector2.INF
	var origin: Vector2 = caster.global_position
	var ring: float = NUDGE_STEP
	while ring <= NUDGE_REACH:
		# The nearest ring with any room wins; within it, the spot nearest the caster, which is the
		# open side of whatever wall was in the way.
		var best: Vector2 = Vector2.INF
		var best_distance: float = INF
		for i: int in NUDGE_SAMPLES:
			var candidate: Vector2 = point + Vector2.from_angle(TAU * float(i) / NUDGE_SAMPLES) * ring
			var distance: float = origin.distance_to(candidate)
			if distance >= best_distance:
				continue
			if data.max_range > 0.0 and distance > data.max_range:
				continue
			if not can_place(caster, candidate, data):
				continue
			var ray := PhysicsRayQueryParameters2D.create(origin, candidate, Layers.SOLID)
			if not space.intersect_ray(ray).is_empty():
				continue
			best = candidate
			best_distance = distance
		if best.is_finite():
			return best
		ring += NUDGE_STEP
	return Vector2.INF
