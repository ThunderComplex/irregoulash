class_name LevelLint
extends RefCounted
## Static checks for the mistakes that make a level unplayable or un-finishable.
##
## Deliberately plain code: it needs no editor and no scene tree, so it can run
## from the editor plugin, from a dev script, or from a test. Feed it an
## instantiated level node and it reports what is wrong.
##
## Approximate by design: reachability is a flood fill on a coarse grid, so a gap
## narrower than `CELL` will read as passable even though the player (a 28px
## circle) might not fit through it.

## Rasterisation step for the reachability check. Smaller is slower and stricter.
const CELL: float = 32.0
## How far outside the geometry the flood fill is allowed to spread.
const MARGIN: float = 320.0


## Returns { "problems": Array[String], "notes": Array[String], "summary": String }.
static func run(root: Node) -> Dictionary:
	var problems: Array[String] = []
	var notes: Array[String] = []

	var walls: Array[Wall] = []
	var enemies: Array[Enemy] = []
	var pickups: Array[Pickup] = []
	var exits: Array[ExitZone] = []
	var routes: Array[PatrolRoute] = []
	var lamps: int = 0
	for node: Node in _descendants(root):
		if node is Wall:
			walls.append(node)
		elif node is Enemy:
			enemies.append(node)
		elif node is Pickup:
			pickups.append(node)
		elif node is ExitZone:
			exits.append(node)
		elif node is PatrolRoute:
			routes.append(node)
		elif node is Lamp:
			lamps += 1

	# --- the two things a level cannot do without
	var spawn_marker: Marker2D = null
	for node: Node in _descendants(root):
		var marker := node as Marker2D
		if marker != null and marker.name == "PlayerSpawn":
			spawn_marker = marker
			break
	var spawn: Vector2 = spawn_marker.global_position if spawn_marker != null else Vector2.ZERO
	if spawn_marker == null:
		problems.append("no PlayerSpawn marker: the player will start at the origin")
	if exits.is_empty():
		problems.append("no ExitZone: this level cannot be finished")

	# --- exits that go nowhere
	var level_next: Variant = root.get("next_level")
	for exit: ExitZone in exits:
		if exit.is_final:
			continue
		if exit.next_level == null and level_next == null:
			problems.append("exit '%s' is not final and no next level is set (on the exit or the level)" % exit.name)

	# --- patrol routes
	for route: PatrolRoute in routes:
		if route.points().size() < 2:
			problems.append("patrol route '%s' has fewer than 2 waypoints" % route.name)
	for enemy: Enemy in enemies:
		if enemy.patrol_route == NodePath():
			continue
		var target: Node = enemy.get_node_or_null(enemy.patrol_route)
		if target == null:
			problems.append("enemy '%s' has a patrol_route that does not resolve" % enemy.name)
		elif not target is PatrolRoute:
			problems.append("enemy '%s' patrols '%s', which is not a PatrolRoute" % [enemy.name, target.name])

	# --- content buried inside geometry
	var placements: Array = []
	if spawn_marker != null:
		placements.append({"label": "PlayerSpawn", "position": spawn})
	for enemy: Enemy in enemies:
		placements.append({"label": "enemy '%s'" % enemy.name, "position": enemy.global_position})
	for pickup: Pickup in pickups:
		placements.append({"label": "pickup '%s'" % pickup.name, "position": pickup.global_position})
	for exit: ExitZone in exits:
		placements.append({"label": "exit '%s'" % exit.name, "position": exit.global_position})
	for entry: Dictionary in placements:
		for wall: Wall in walls:
			if wall.world_rect().has_point(entry["position"]):
				problems.append("%s is inside wall '%s'" % [entry["label"], wall.name])
				break

	# --- can the player actually get to the objectives
	var blocked: Dictionary = {}
	var reachable: Dictionary = {}
	if spawn_marker != null and not exits.is_empty():
		blocked = blocked_cells(walls)
		reachable = flood_fill(spawn, walls, blocked)
		var unreachable: Array[String] = []
		var targets: Array = []
		for exit: ExitZone in exits:
			targets.append({"label": "exit '%s'" % exit.name, "position": exit.global_position})
		for pickup: Pickup in pickups:
			targets.append({"label": "pickup '%s'" % pickup.name, "position": pickup.global_position})
		for entry: Dictionary in targets:
			if _is_inside_a_wall(entry["position"], walls):
				continue
			if not _is_reachable_towards(entry["position"], reachable):
				unreachable.append(entry["label"])
		if not unreachable.is_empty():
			problems.append("the player cannot walk to: %s" % ", ".join(unreachable))

	# --- gentle nudges, not errors
	for route: PatrolRoute in routes:
		if route.users().is_empty():
			notes.append("patrol route '%s' is not used by any enemy" % route.name)
	if lamps == 0:
		notes.append("no lamps: the level will be almost entirely dark")

	return {
		"problems": problems,
		"notes": notes,
		"summary": "%d walls, %d enemies, %d pickups, %d exits, %d lamps, %d routes" % [
			walls.size(), enemies.size(), pickups.size(), exits.size(), lamps, routes.size(),
		],
		# Included only when something is wrong: a picture of which ground the player
		# can actually walk to is the fastest way to understand a "cannot walk to"
		# report.
		"map": describe_grid(walls, blocked, reachable) if not problems.is_empty() else [],
	}


static func cell_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.y / CELL))


## Walkable cells reachable from `from`, as a Dictionary of Vector2i to true.
static func flood_fill(from: Vector2, walls: Array[Wall], blocked: Dictionary = {}) -> Dictionary:
	if blocked.is_empty():
		blocked = blocked_cells(walls)
	var start: Vector2i = cell_of(from)
	var visited: Dictionary = {}
	if blocked.has(start):
		return visited

	var bounds: Rect2 = Rect2(from, Vector2.ZERO)
	for wall: Wall in walls:
		bounds = bounds.merge(wall.world_rect())
	bounds = bounds.grow(MARGIN)
	var lowest: Vector2i = cell_of(bounds.position)
	var highest: Vector2i = cell_of(bounds.end)

	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if next.x < lowest.x or next.y < lowest.y or next.x > highest.x or next.y > highest.y:
				continue
			if visited.has(next) or blocked.has(next):
				continue
			visited[next] = true
			queue.append(next)
	return visited


## Walls rasterised onto the grid, grown by half a cell so narrow gaps do not read
## as passable paths. A cell counts as blocked when its *centre* falls inside a
## grown wall: testing overlap instead would seal any doorway whose free space does
## not happen to line up with the grid.
static func blocked_cells(walls: Array[Wall]) -> Dictionary:
	var blocked: Dictionary = {}
	for wall: Wall in walls:
		var rect: Rect2 = wall.world_rect().grow(CELL * 0.5)
		var first: Vector2i = cell_of(rect.position)
		var last: Vector2i = cell_of(rect.end)
		for y: int in range(first.y, last.y + 1):
			for x: int in range(first.x, last.x + 1):
				var centre := Vector2((float(x) + 0.5) * CELL, (float(y) + 0.5) * CELL)
				if rect.has_point(centre):
					blocked[Vector2i(x, y)] = true
	return blocked


## A target counts as reachable if its own cell, or any of the eight around it, was
## flooded. Without the neighbours, anything standing within half a cell of a wall
## is reported as unreachable, which is almost everything.
static func _is_reachable_towards(point: Vector2, reachable: Dictionary) -> bool:
	var cell: Vector2i = cell_of(point)
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if reachable.has(cell + Vector2i(dx, dy)):
				return true
	return false


## A coarse picture of the lint grid: '#' wall, '.' ground the player can reach,
## ' ' ground they cannot. Returned (not printed) when a level has problems, because
## a "cannot walk to" report is much easier to believe with a map next to it.
static func describe_grid(walls: Array[Wall], blocked: Dictionary, reachable: Dictionary) -> Array[String]:
	if walls.is_empty():
		return []
	var bounds: Rect2 = walls[0].world_rect()
	for wall: Wall in walls:
		bounds = bounds.merge(wall.world_rect())
	bounds = bounds.grow(CELL)
	var step: int = 2
	var lowest: Vector2i = cell_of(bounds.position)
	var highest: Vector2i = cell_of(bounds.end)
	var lines: Array[String] = []
	var y: int = lowest.y
	while y <= highest.y:
		var line: String = ""
		var x: int = lowest.x
		while x <= highest.x:
			if blocked.has(Vector2i(x, y)):
				line += "#"
			elif reachable.has(Vector2i(x, y)):
				line += "."
			else:
				line += " "
			x += step
		lines.append(line)
		y += step
	return lines


static func _is_inside_a_wall(point: Vector2, walls: Array[Wall]) -> bool:
	for wall: Wall in walls:
		if wall.world_rect().has_point(point):
			return true
	return false


static func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out
