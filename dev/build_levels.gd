extends SceneTree
## DEV TOOL - turns the ASCII maps below into real, editable level scenes.
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://dev/build_levels.gd
##
## The output (.tscn) is an ordinary scene: open it, drag walls around, add
## props, save. This tool only exists so that laying out a new level is as quick
## as sketching it, which is what AGENTS.md asks for ("procgen may be used to
## aide in creating levels" -- the levels themselves are authored, not random).
##
## It lints what it builds: entities stuck inside walls, and anything the player
## cannot reach from the spawn, are both reported. A level that lints clean is
## guaranteed completable.
##
## Note: every uppercase enemy walks patrol route 1. Route 2 and 3 markers are
## generated too (`2`, `3`) but assigning an enemy to them is a one-field edit in
## the editor afterwards (patrol_route on the enemy).

#region legend
##
##   #  wall                      .  / space  floor
##   P  player spawn              1 2 3      patrol route marker (routes 1..3)
##   G  guard, patrols route 1    g  guard, wanders near spawn
##   S  scout, patrols route 1    s  scout, wanders
##   H  heavy, patrols route 1    h  heavy, wanders
##   L  lamp
##   -  pistol pickup   =  smg pickup   +  shotgun pickup
##   A  ammo pickup     %  medkit       U  weapon upgrade crate
##   X  exit (the campaign decides where it leads; the last level's exit ends the run)
##
#endregion

const TILE: float = 64.0
const OUT_DIR: String = "res://src/levels"
const WALL_TINT: String = "Color(0.4, 0.44, 0.54, 1)"
const FLOOR_COLOR: String = "Color(0.13, 0.145, 0.175, 1)"

## Level 1: an open yard with a wall across the middle, blocks for cover, and an
## exit on the far side. Teaches: lamps are landmarks, patrols exist, loud fights
## pull everyone to you.
const MAP_YARD: String = """
########################################
#.....................................#
#..####........................#####..#
#..####....s...................#####..#
#..####........................#####..#
#.....................................#
#.1.......########################...#
#.....................................#
#...P................................#
#..................................A.#
#.....................................#
#...........=........................#
#.............g.......................#
#................L...................#
#.....................................#
#....1................................#
#.....................................#
#.....%..............................#
#..G.................................#
#..####.....................####.....#
#..####.....................####.....#
#.....................................#
#................S...................#
#.....................................#
#....................h................#
#........A......%..................X.#
########################################
"""

## Level 2: a building. Six rooms off a central corridor, two doors into each
## room, three enemies patrolling the corridor. Teaches: doorways are danger,
## the corridor is long and lit, and the upgrade crate is worth the trip.
const MAP_DEPOT: String = """
########################################
#...........#..............#..........#
#...........#..............#..........#
#..L........#..............#......H...#
#...........#..............#......%...#
#...........#..............#..........#
#..U........#........A.....#......X...#
#...........#..............#..........#
#...........#..............#..........#
#...........#........g.....#..........#
#...........#..............#..........#
#...........#..............#..........#
#...........#..............#..........#
#####..##############..############..##
#......................................#
#..s.1......S........G........1.......#
#......................................#
########..################..#####..#####
#...........#..............#..........#
#...........#..............#..........#
#...........#........%.....#......L...#
#...........#..............#..........#
#...........#......s.......#..........#
#...........#..............#..........#
#...........#........A.....#......+...#
#..P........#..............#..........#
#...........#........h.....#..........#
#...........#..............#..........#
#...........#..............#..........#
########################################
"""

const LEVELS: Array = [
	{
		"id": "level_01",
		"node": "Level01",
		"title": "THE YARD",
		"objective": "Get across the yard and find the way out.",
		"map": MAP_YARD,
		"weapons": ["pistol"],
	},
	{
		"id": "level_02",
		"node": "Level02",
		"title": "THE DEPOT",
		"objective": "You are inside the depot. Find the last door out.",
		"map": MAP_DEPOT,
		"weapons": ["pistol"],
	},
]


func _initialize() -> void:
	print("[build_levels] writing %d level(s) to %s" % [LEVELS.size(), OUT_DIR])
	for entry: Dictionary in LEVELS:
		_build_level(entry)
	print("[build_levels] done")
	quit()


func _build_level(entry: Dictionary) -> void:
	var grid: Array = _parse_map(String(entry["map"]), String(entry["id"]))
	var height: int = grid.size()
	var width: int = (grid[0] as Array).size()

	var walls: Array = _merge_walls(grid, width, height)
	var entities: Dictionary = _collect_entities(grid, width, height)

	print("\n=== %s (%dx%d cells, %.0fx%.0f px, %d wall rects)" % [
		entry["id"], width, height, width * TILE, height * TILE, walls.size(),
	])
	_lint(grid, width, height, entities, walls, entry)

	var text: String = _write_scene(entry, width, height, walls, entities)
	var path: String = "%s/%s.tscn" % [OUT_DIR, entry["id"]]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % path)
		return
	file.store_string(text)
	file.close()
	print("  wrote %s (%d bytes)" % [path, text.length()])


#region parsing

## Returns grid[y][x] as a single-character String, padded to the widest row and
## with the outer border forced to wall so a short row can never leak the map.
func _parse_map(text: String, id: String) -> Array:
	var rows: Array = []
	for line: String in text.split("\n"):
		if line.strip_edges().is_empty():
			continue
		rows.append(line)
	if rows.is_empty():
		push_error("%s: empty map" % id)
		return []

	var width: int = 0
	for line: String in rows:
		width = maxi(width, line.length())
	var uneven: bool = false
	for line: String in rows:
		if line.length() != width:
			uneven = true
	if uneven:
		print("  NOTE: rows are not all the same length; padding with floor and sealing the border")

	var grid: Array = []
	for line: String in rows:
		var cells: Array = []
		for i: int in width:
			var ch: String = line[i] if i < line.length() else "."
			cells.append(ch)
		grid.append(cells)

	for y: int in grid.size():
		for x: int in width:
			if x == 0 or y == 0 or x == width - 1 or y == grid.size() - 1:
				grid[y][x] = "#"
	return grid


## Greedy rectangle merge: turns the wall cells into as few axis-aligned boxes as
## possible, so a room's four walls do not become four hundred nodes.
func _merge_walls(grid: Array, width: int, height: int) -> Array:
	var visited: Array = []
	for y: int in height:
		var row: Array = []
		for x: int in width:
			row.append(false)
		visited.append(row)

	var rects: Array = []
	for y: int in height:
		for x: int in width:
			if grid[y][x] != "#" or visited[y][x]:
				continue
			var x2: int = x
			while x2 + 1 < width and grid[y][x2 + 1] == "#" and not visited[y][x2 + 1]:
				x2 += 1
			var y2: int = y
			while y2 + 1 < height:
				var ok: bool = true
				for xi: int in range(x, x2 + 1):
					if grid[y2 + 1][xi] != "#" or visited[y2 + 1][xi]:
						ok = false
						break
				if not ok:
					break
				y2 += 1
			for yi: int in range(y, y2 + 1):
				for xi: int in range(x, x2 + 1):
					visited[yi][xi] = true
			rects.append(Rect2i(x, y, x2 - x + 1, y2 - y + 1))
	return rects


func _collect_entities(grid: Array, width: int, height: int) -> Dictionary:
	var out: Dictionary = {
		"spawn": null, "enemies": [], "lamps": [], "pickups": [], "exits": [],
		"routes": {},
	}
	for y: int in height:
		for x: int in width:
			var ch: String = grid[y][x]
			if ch == "#" or ch == "." or ch == " ":
				continue
			match ch:
				"P":
					out["spawn"] = Vector2i(x, y)
				"G", "S", "H", "g", "s", "h":
					out["enemies"].append({"cell": Vector2i(x, y), "char": ch})
				"L":
					out["lamps"].append(Vector2i(x, y))
				"-", "=", "+", "A", "U", "%":
					out["pickups"].append({"cell": Vector2i(x, y), "char": ch})
				"X", "Z":
					# `Z` is still accepted so older maps parse; the campaign decides what an exit leads
					# to now, so nothing about the character matters.
					out["exits"].append({"cell": Vector2i(x, y)})
				"1", "2", "3":
					if not out["routes"].has(ch):
						out["routes"][ch] = []
					out["routes"][ch].append(Vector2i(x, y))
				_:
					pass
	return out

#endregion


#region linting

func _lint(grid: Array, width: int, height: int, entities: Dictionary, walls: Array,
		entry: Dictionary) -> void:
	var problems: int = 0
	problems += _lint_cell("player spawn", entities["spawn"], grid, width, height, true)

	for enemy: Dictionary in entities["enemies"]:
		problems += _lint_cell("enemy '%s'" % enemy["char"], enemy["cell"], grid, width, height, true)
	for cell: Vector2i in entities["lamps"]:
		problems += _lint_cell("lamp", cell, grid, width, height, false)
	for pickup: Dictionary in entities["pickups"]:
		problems += _lint_cell("pickup '%s'" % pickup["char"], pickup["cell"], grid, width, height, true)
	for exit: Dictionary in entities["exits"]:
		problems += _lint_cell("exit", exit["cell"], grid, width, height, true)
	for key: String in entities["routes"]:
		for cell: Vector2i in entities["routes"][key]:
			problems += _lint_cell("route %s" % key, cell, grid, width, height, false)

	# Reachability from the spawn: anything the player can never walk to is a bug.
	var spawn: Variant = entities["spawn"]
	if spawn != null:
		var reachable: Array = _flood_fill(grid, width, height, spawn as Vector2i)
		var targets: Array = []
		for enemy: Dictionary in entities["enemies"]:
			targets.append({"label": "enemy '%s'" % enemy["char"], "cell": enemy["cell"]})
		for pickup: Dictionary in entities["pickups"]:
			targets.append({"label": "pickup '%s'" % pickup["char"], "cell": pickup["cell"]})
		for exit: Dictionary in entities["exits"]:
			targets.append({"label": "exit", "cell": exit["cell"]})
		for target: Dictionary in targets:
			var cell: Vector2i = target["cell"]
			if not reachable[cell.y][cell.x]:
				print("  LINT: %s at (%d, %d) cannot be reached from the spawn" % [
					target["label"], cell.x, cell.y,
				])
				problems += 1

	if entities["exits"].is_empty():
		print("  LINT: no exit defined")
		problems += 1
	if entities["spawn"] == null:
		print("  LINT: no player spawn defined")
		problems += 1

	if problems == 0:
		print("  lint: clean")
	else:
		print("  lint: %d problem(s)" % problems)


func _lint_cell(label: String, cell: Variant, grid: Array, width: int, height: int,
		must_be_floor: bool) -> int:
	if cell == null:
		return 0
	var c: Vector2i = cell
	if c.x < 0 or c.y < 0 or c.x >= width or c.y >= height:
		print("  LINT: %s is outside the map" % label)
		return 1
	if must_be_floor and grid[c.y][c.x] == "#":
		print("  LINT: %s at (%d, %d) is inside a wall" % [label, c.x, c.y])
		return 1
	return 0


func _flood_fill(grid: Array, width: int, height: int, start: Vector2i) -> Array:
	var seen: Array = []
	for y: int in height:
		var row: Array = []
		for x: int in width:
			row.append(false)
		seen.append(row)

	var queue: Array[Vector2i] = [start]
	seen[start.y][start.x] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			if seen[next.y][next.x] or grid[next.y][next.x] == "#":
				continue
			seen[next.y][next.x] = true
			queue.append(next)
	return seen

#endregion


#region scene writing

func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)


func _write_scene(entry: Dictionary, width: int, height: int, walls: Array,
		entities: Dictionary) -> String:
	var lines: Array[String] = []
	var resources: Array[String] = []
	resources.append('[ext_resource type="Script" path="res://src/levels/level.gd" id="1_level"]')
	resources.append('[ext_resource type="PackedScene" path="res://src/levels/wall.tscn" id="2_wall"]')
	resources.append('[ext_resource type="PackedScene" path="res://src/levels/lamp.tscn" id="3_lamp"]')
	resources.append('[ext_resource type="PackedScene" path="res://src/enemies/enemy.tscn" id="4_enemy"]')
	resources.append('[ext_resource type="PackedScene" path="res://src/items/pickup.tscn" id="5_pickup"]')
	resources.append('[ext_resource type="PackedScene" path="res://src/levels/exit_zone.tscn" id="6_exit"]')
	var routes: Dictionary = entities["routes"]
	if not routes.is_empty():
		resources.append('[ext_resource type="Script" path="res://src/levels/patrol_route.gd" id="8_route"]')

	lines.append("[gd_scene load_steps=%d format=3]" % (resources.size() + 1))
	lines.append("")
	lines.append_array(resources)
	lines.append("")

	# --- root
	lines.append('[node name="%s" type="Node2D"]' % entry["node"])
	lines.append('script = ExtResource("1_level")')
	lines.append('level_title = "%s"' % entry["title"])
	lines.append('objective = "%s"' % entry["objective"])
	var weapons: Array = entry["weapons"]
	var quoted: Array[String] = []
	for w: Variant in weapons:
		quoted.append('"%s"' % w)
	lines.append("start_weapons = Array[String]([%s])" % ", ".join(quoted))
	lines.append("")

	# --- floor (deliberately NO fog node here: a CanvasModulate in the scene turns
	# Godot's own 2D editor viewport black, which makes levels unauthorable. The fog
	# is created at runtime by level.gd, so it cannot be forgotten either way.)
	lines.append('[node name="Floor" type="Polygon2D" parent="."]')
	lines.append("z_index = -20")
	lines.append("color = %s" % FLOOR_COLOR)
	var margin: float = 260.0
	lines.append("polygon = PackedVector2Array(%s)" % _polygon_string(Rect2(
		-margin, -margin, width * TILE + margin * 2.0, height * TILE + margin * 2.0)))
	lines.append("")

	# --- walls
	lines.append('[node name="Walls" type="Node2D" parent="."]')
	lines.append("")
	var i: int = 0
	for rect: Rect2i in walls:
		lines.append('[node name="W%d" parent="Walls" instance=ExtResource("2_wall")]' % i)
		lines.append("position = Vector2(%s, %s)" % [
			_num(rect.position.x * TILE + rect.size.x * TILE * 0.5),
			_num(rect.position.y * TILE + rect.size.y * TILE * 0.5),
		])
		lines.append("size = Vector2(%s, %s)" % [
			_num(rect.size.x * TILE), _num(rect.size.y * TILE),
		])
		lines.append("color = %s" % WALL_TINT)
		lines.append("")
		i += 1

	# --- patrol routes
	if not routes.is_empty():
		lines.append('[node name="Routes" type="Node2D" parent="."]')
		lines.append("")
		for key: String in routes:
			lines.append('[node name="Route%s" type="Node2D" parent="Routes"]' % key)
			lines.append('script = ExtResource("8_route")')
			lines.append("")
			var points: Array = routes[key]
			for p: int in points.size():
				var cell: Vector2i = points[p]
				lines.append('[node name="P%d" type="Marker2D" parent="Routes/Route%s"]' % [p, key])
				lines.append("position = Vector2(%s, %s)" % [_num(_cell_center(cell).x), _num(_cell_center(cell).y)])
				lines.append("")

	# --- spawn
	var spawn: Variant = entities["spawn"]
	if spawn != null:
		var sc: Vector2i = spawn as Vector2i
		lines.append('[node name="PlayerSpawn" type="Marker2D" parent="."]')
		lines.append("position = Vector2(%s, %s)" % [_num(_cell_center(sc).x), _num(_cell_center(sc).y)])
		lines.append("")

	# --- lamps
	var lamps: Array = entities["lamps"]
	if not lamps.is_empty():
		lines.append('[node name="Lamps" type="Node2D" parent="."]')
		lines.append("")
		for n: int in lamps.size():
			var cell: Vector2i = lamps[n]
			lines.append('[node name="Lamp%d" parent="Lamps" instance=ExtResource("3_lamp")]' % n)
			lines.append("position = Vector2(%s, %s)" % [_num(_cell_center(cell).x), _num(_cell_center(cell).y)])
			lines.append("")

	# --- enemies
	var enemies: Array = entities["enemies"]
	if not enemies.is_empty():
		lines.append('[node name="Enemies" type="Node2D" parent="."]')
		lines.append("")
		for n: int in enemies.size():
			var info: Dictionary = enemies[n]
			var cell: Vector2i = info["cell"]
			var ch: String = info["char"]
			var route: String = "1" if ch == ch.to_upper() else ""
			lines.append('[node name="Enemy%d" parent="Enemies" instance=ExtResource("4_enemy")]' % n)
			lines.append("position = Vector2(%s, %s)" % [_num(_cell_center(cell).x), _num(_cell_center(cell).y)])
			lines.append('archetype_id = "%s"' % _archetype_for(ch))
			if not route.is_empty() and routes.has(route):
				# Enemies live under "Enemies/", so the route is two levels up.
				lines.append('patrol_route = NodePath("../../Routes/Route%s")' % route)
			else:
				lines.append("wander_radius = %s" % _num(140.0 if ch == ch.to_lower() else 0.0))
			lines.append("rotation = %s" % _num(_initial_facing(ch, cell, routes, Vector2(width, height) * 0.5)))
			lines.append("")

	# --- pickups
	var pickups: Array = entities["pickups"]
	if not pickups.is_empty():
		lines.append('[node name="Pickups" type="Node2D" parent="."]')
		lines.append("")
		for n: int in pickups.size():
			var info: Dictionary = pickups[n]
			var cell: Vector2i = info["cell"]
			var ch: String = info["char"]
			lines.append('[node name="Pickup%d" parent="Pickups" instance=ExtResource("5_pickup")]' % n)
			lines.append("position = Vector2(%s, %s)" % [_num(_cell_center(cell).x), _num(_cell_center(cell).y)])
			lines.append('kind = "%s"' % _pickup_kind(ch))
			if _pickup_kind(ch) == "weapon":
				lines.append('weapon_id = "%s"' % _pickup_weapon(ch))
			else:
				lines.append("amount = %d" % _pickup_amount(ch))
			lines.append("")

	# --- exits
	var exits: Array = entities["exits"]
	for n: int in exits.size():
		var cell: Vector2i = (exits[n] as Dictionary)["cell"]
		lines.append('[node name="Exit%d" parent="." instance=ExtResource("6_exit")]' % n)
		lines.append("position = Vector2(%s, %s)" % [_num(_cell_center(cell).x), _num(_cell_center(cell).y)])
		lines.append("")

	return "\n".join(lines)


func _polygon_string(rect: Rect2) -> String:
	return "%s, %s, %s, %s, %s, %s, %s, %s" % [
		_num(rect.position.x), _num(rect.position.y),
		_num(rect.end.x), _num(rect.position.y),
		_num(rect.end.x), _num(rect.end.y),
		_num(rect.position.x), _num(rect.end.y),
	]


func _num(value: float) -> String:
	var rounded: float = roundf(value)
	if is_equal_approx(rounded, value):
		return str(int(rounded))
	return "%.3f" % value


func _archetype_for(ch: String) -> String:
	match ch.to_lower():
		"s":
			return "scout"
		"h":
			return "heavy"
		_:
			return "guard"


func _pickup_kind(ch: String) -> String:
	match ch:
		"A":
			return "ammo"
		"U":
			return "upgrade"
		"%":
			return "health"
		_:
			return "weapon"


func _pickup_amount(ch: String) -> int:
	match ch:
		"A":
			return 40
		"%":
			return 35
		_:
			return 0


func _pickup_weapon(ch: String) -> String:
	match ch:
		"=":
			return "smg"
		"+":
			return "shotgun"
		_:
			return "pistol"


## Enemies face their first patrol point, or the middle of the map, so a freshly
## generated level does not have everybody staring the same way.
func _initial_facing(ch: String, cell: Vector2i, routes: Dictionary, center_cells: Vector2) -> float:
	var route: String = "1" if ch == ch.to_upper() else ""
	if not route.is_empty() and routes.has(route):
		var points: Array = routes[route]
		if points.size() > 0:
			return (Vector2(points[0]) - Vector2(cell)).angle()
	return (center_cells - Vector2(cell)).angle()

#endregion
