@tool
class_name Level
extends Node2D
## Base behaviour for every level.
##
## A level scene should contain *only* content: walls, lamps, enemies, pickups,
## exits, marker points. Everything the game needs to function is either supplied
## by this script or by an autoload, so it is impossible to create a level that
## is broken because a required node was forgotten (see AGENTS.md):
##
##   * the black fog (CanvasModulate)      -> created at runtime if missing
##   * the explored-geometry memory        -> created at runtime if missing
##   * the effect layer                    -> created at runtime if missing
##   * the HUD                             -> created at runtime if missing
##   * the player                           -> always spawned here, from PlayerSpawn
##   * camera limits                        -> derived from the walls themselves
##
## Note that the fog is deliberately *not* part of a level scene: a
## `CanvasModulate` in an authored scene makes Godot's own 2D editor render that
## scene black, which makes levels unauthorable. Use `editor_lighting_preview`
## below if you want to see how the lighting reads while editing.
##
## Only content nodes exist in the editor, so this script draws the level's
## camera bounds and the player's spawn point and vision reach as gizmos.

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")
const HUD_SCENE: PackedScene = preload("res://src/ui/hud.tscn")
## Read only for its exported defaults: autoloads are not available to editor code.
const TUNING_SCRIPT: GDScript = preload("res://src/autoload/tuning.gd")
const EDITOR_PREVIEW_NODE: StringName = &"EditorLightingPreview"

@export var level_title: String = "LEVEL"
@export var objective: String = "Find the way out."
## Where this level's non-final exits lead. An exit with no `next_level` of its own
## falls back to this, so a level with several exits only needs it set once here.
@export var next_level: PackedScene
@export var start_weapons: Array[String] = ["pistol"]
@export var starting_ammo_bonus: int = 0

@export_group("Camera bounds")
## Derive the camera limit rectangle from the walls. Recommended.
@export var auto_bounds: bool = true:
	set(value):
		auto_bounds = value
		if Engine.is_editor_hint():
			queue_redraw()
## Used when `auto_bounds` is off.
@export var bounds_rect: Rect2 = Rect2(-900.0, -600.0, 1800.0, 1200.0):
	set(value):
		bounds_rect = value
		if Engine.is_editor_hint():
			queue_redraw()
@export var bounds_margin: float = 90.0:
	set(value):
		bounds_margin = value
		if Engine.is_editor_hint():
			queue_redraw()
@export var min_bound_size: Vector2 = Vector2(1700.0, 1000.0)

@export_group("Surfaces")
## Look of every wall in this level. Styles are defined in `SurfaceLibrary`; "plain" is the flat colour
## walls had before textures existed, so nothing changes until you pick a style.
##
## One per level rather than per wall: it keeps authoring to one dropdown, and it means a level reads as
## one place instead of a patchwork.
@export_enum("plain", "wood") var wall_surface_id: String = "plain":
	set(value):
		wall_surface_id = value
		_refresh_surfaces()
## Look of the floor. "plain" draws no floor at all, which is how levels looked before surfaces: the
## ground is simply black outside the light.
@export_enum("plain", "stone_tile_floor") var floor_surface_id: String = "plain":
	set(value):
		floor_surface_id = value
		_refresh_surfaces()

@export_group("Fog")
@export var fog_color: Color = Color(0.0, 0.0, 0.0, 1.0)
## Ambient used by the F4 debug reveal.
@export var reveal_color: Color = Color(0.34, 0.34, 0.36, 1.0)

@export_group("Editor")
## Dim the editing viewport so lamp pools and wall shadows are visible while
## authoring. Off by default, because a dark editing viewport is unusable -- which
## is exactly why levels no longer contain a fog node.
@export var editor_lighting_preview: bool = false:
	set(value):
		editor_lighting_preview = value
		if Engine.is_editor_hint():
			_apply_editor_preview()
## How dark the preview is. The real fog is black; this only needs to be dark
## enough for a lamp pool to read.
@export_range(0.0, 1.0, 0.01) var editor_preview_ambient: float = 0.34:
	set(value):
		editor_preview_ambient = value
		if Engine.is_editor_hint():
			_apply_editor_preview()

var player: Player = null
var walls: Array[Wall] = []
var enemies: Array[Enemy] = []
var exits: Array[ExitZone] = []

var spawn_point: Vector2 = Vector2.ZERO
var _fog: CanvasModulate = null
var _fx_layer: Node2D = null
var _memory: VisionMemory = null
var _hud: HUD = null
var _wall_decor: WallDecor = null
var _reveal: RevealMask = null

#region editor-only state
var _gizmo_hash: int = 0
var _editor_cone_reach: float = 560.0
var _editor_cone_half: float = deg_to_rad(39.0)
var _editor_near_radius: float = 115.0
#endregion


func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_ready()
		return
	set_process(false)
	GameDirector.on_level_ready(self)
	_collect_groups()
	_ensure_floor()
	_setup_wall_decor()
	_ensure_fog()
	_ensure_memory()
	_ensure_fx_layer()
	_ensure_hud()
	_find_spawn_point()
	_spawn_player()
	_apply_camera_limits()
	GameDirector.reveal_changed.connect(_on_reveal_changed)
	_warn_about_missing_content()
	if _hud != null:
		_hud.show_banner(level_title)
		_hud.set_objective(objective)


#region setup

func _collect_groups() -> void:
	_collect_walls()
	enemies.clear()
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy != null:
			enemies.append(enemy)
			enemy.died.connect(_on_enemy_died)
	exits.clear()
	for node: Node in get_tree().get_nodes_in_group("exit"):
		var exit := node as ExitZone
		if exit != null:
			exits.append(exit)


func _collect_walls() -> void:
	walls.clear()
	for node: Node in get_tree().get_nodes_in_group("wall"):
		var wall := node as Wall
		if wall != null:
			walls.append(wall)


#region surfaces

## What every wall in this level looks like. `Wall` asks for this while it builds itself, so one
## dropdown styles the whole level and no wall has to be selected.
func wall_surface() -> SurfaceStyle:
	return SurfaceLibrary.by_id(wall_surface_id)


func floor_surface() -> SurfaceStyle:
	return SurfaceLibrary.by_id(floor_surface_id)


## Re-applies the look to walls and floor. Used by the inspector setters, so picking a style updates the
## level in place instead of needing a reload.
func _refresh_surfaces() -> void:
	# Export setters run while the scene is still being instantiated, before this node has a tree. The
	# walls each resolve their own style in `_ready`, so there is nothing to do yet.
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group("wall"):
		var wall := node as Wall
		if wall != null and is_ancestor_of(wall):
			wall._rebuild()
	_rebuild_floor()
	_setup_wall_decor()


## The rim and occlusion along the outline of the whole wall mass. A rectangle cannot know whether its
## edge is a real edge, so this is drawn from the merged silhouette instead -- which is what makes joins,
## corners and overlaps read as one solid shape.
func _ensure_wall_decor() -> void:
	if _wall_decor == null or not is_instance_valid(_wall_decor):
		_wall_decor = WallDecor.new()
		_wall_decor.name = "WallDecor"
		add_child(_wall_decor, false, Node.INTERNAL_MODE_DISABLED)


func _setup_wall_decor() -> void:
	var style: SurfaceStyle = wall_surface()
	if style == null or not style.is_textured():
		if _wall_decor != null and is_instance_valid(_wall_decor):
			_wall_decor.setup([], style)
		return
	_ensure_wall_decor()
	_wall_decor.setup(walls, style)
	var reveal := _ensure_reveal_mask()
	if reveal != null:
		_wall_decor.use_reveal(reveal)


## The lighting mask walls are multiplied by. Created lazily and told the level's bounds, so it always
## covers the whole level however the walls were authored.
func _ensure_reveal_mask() -> RevealMask:
	if _reveal == null or not is_instance_valid(_reveal):
		_reveal = RevealMask.new()
		_reveal.name = "Reveal"
		add_child(_reveal, false, Node.INTERNAL_MODE_DISABLED)
	var rect: Rect2 = level_bounds().grow(64.0)
	_reveal.setup(rect, get_world_2d())
	# Wall materials cannot point at a mask that has not been rendered yet, so re-apply everything once
	# the first frame is read back.
	if not _reveal.first_sample.is_connected(_on_reveal_first_sample):
		_reveal.first_sample.connect(_on_reveal_first_sample)
	if not _reveal.sampled.is_connected(_on_reveal_sampled):
		_reveal.sampled.connect(_on_reveal_sampled)
	return _reveal


func _on_reveal_first_sample() -> void:
	_refresh_surfaces()


## The mask moves ten times a second; the decoration is drawn on the CPU from it, so it follows here.
func _on_reveal_sampled() -> void:
	if _wall_decor != null and is_instance_valid(_wall_decor):
		_wall_decor.sync_reveal()


func reveal_mask() -> RevealMask:
	return _reveal


## Called by a wall when it becomes (or stops being) explored.
func refresh_wall_decor() -> void:
	if _wall_decor != null and is_instance_valid(_wall_decor):
		_wall_decor.refresh()


## The ground.
##
## An *unowned* child, like the editor preview fog: Godot only serialises nodes owned by the scene, so
## this exists in the editor and at runtime and is never written into a level file. It is plain
## `Polygon2D` geometry, so it takes light from lamps and the player's cone exactly like a wall top does
## -- which is the whole point: before this, the ground was simply black, and light pools had nothing to
## fall on.
func _ensure_floor() -> void:
	_rebuild_floor()


func _rebuild_floor() -> void:
	var style: SurfaceStyle = floor_surface()
	var floor_node: Polygon2D = null
	for child: Node in get_children():
		if child.name == "Floor" and child is Polygon2D:
			floor_node = child as Polygon2D
			break
	if style == null or not style.is_textured():
		if floor_node != null:
			floor_node.visible = false
		return

	if floor_node == null:
		floor_node = Polygon2D.new()
		floor_node.name = "Floor"
		add_child(floor_node, false, Node.INTERNAL_MODE_DISABLED)
	floor_node.visible = true
	floor_node.z_index = Layers.Z_FLOOR
	# Grown past the camera limits, so the floor's own edge is never on screen.
	var rect: Rect2 = level_bounds().grow(level_bounds().size.length())
	floor_node.position = rect.get_center()
	var half: Vector2 = rect.size * 0.5
	floor_node.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	var shader_material := ShaderMaterial.new()
	shader_material.shader = Wall.SURFACE_SHADER
	shader_material.set_shader_parameter("albedo", style.albedo)
	shader_material.set_shader_parameter("tile_world", style.tile_world)
	shader_material.set_shader_parameter("tint", style.tint)
	shader_material.set_shader_parameter("size_world", rect.size)
	shader_material.set_shader_parameter("rim_ao_width", style.rim_ao_width)
	shader_material.set_shader_parameter("rim_ao_strength", style.rim_ao_strength)
	shader_material.set_shader_parameter("base_band", style.base_band)
	shader_material.set_shader_parameter("base_strength", style.base_strength)
	shader_material.set_shader_parameter("breakup_amount", style.breakup_amount)
	shader_material.set_shader_parameter("breakup_scale", style.breakup_scale)
	floor_node.material = shader_material
	floor_node.color = style.tint

#endregion


func _ensure_fog() -> void:
	_fog = get_node_or_null("Fog") as CanvasModulate
	if _fog == null:
		_fog = CanvasModulate.new()
		_fog.name = "Fog"
		add_child(_fog)
		move_child(_fog, 0)
	_fog.color = fog_color


## Wall memory is retired: a textured wall is drawn from the lighting mask instead, which is both what
## the design wants and cheaper than sampling the screen for ghost polygons. The flat fallback still uses
## `Wall.mark_explored` for its silhouette, and needs no memory node for that.
func _ensure_memory() -> void:
	_memory = null


func _ensure_fx_layer() -> void:
	_fx_layer = get_node_or_null("Fx") as Node2D
	if _fx_layer == null:
		_fx_layer = Node2D.new()
		_fx_layer.name = "Fx"
		add_child(_fx_layer)
	_fx_layer.z_index = Layers.Z_FX
	FxDirector.set_world(_fx_layer)


func _ensure_hud() -> void:
	_hud = get_node_or_null("HUD") as HUD
	if _hud == null:
		_hud = HUD_SCENE.instantiate() as HUD
		add_child(_hud)


func _find_spawn_point() -> void:
	var marker := find_child("PlayerSpawn", true, false) as Marker2D
	if marker != null:
		spawn_point = marker.global_position
	else:
		spawn_point = global_position
		push_warning("Level '%s' has no PlayerSpawn marker; spawning at the origin." % name)


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.global_position = spawn_point
	# Keys are inventory like the loadout: they survive the level change, so a key found in a level
	# cannot be lost by walking through an exit.
	player.keys = GameDirector.carried_keys
	var holder := player.weapons as WeaponHolder
	if holder != null:
		if GameDirector.carried_loadout.is_empty():
			holder.set_loadout(start_weapons)
		else:
			holder.deserialize(GameDirector.carried_loadout)
		if starting_ammo_bonus > 0:
			holder.add_ammo(starting_ammo_bonus)
	GameDirector.set_player(player)


func _apply_camera_limits() -> void:
	if player == null:
		return
	var camera := player.get_node_or_null("Camera") as Camera2D
	if camera == null:
		return
	var rect: Rect2 = level_bounds()
	camera.limit_left = int(rect.position.x)
	camera.limit_top = int(rect.position.y)
	camera.limit_right = int(rect.end.x)
	camera.limit_bottom = int(rect.end.y)


func _warn_about_missing_content() -> void:
	if exits.is_empty():
		push_warning("Level '%s' has no ExitZone; the player cannot finish it." % name)


## The rectangle the camera is allowed to show. Derived from the walls so it
## tracks the geometry automatically as the level is edited.
func level_bounds() -> Rect2:
	var rect: Rect2 = bounds_rect
	if auto_bounds:
		var first: bool = true
		for wall: Wall in walls:
			if not is_instance_valid(wall):
				continue
			if first:
				rect = wall.world_rect()
				first = false
			else:
				rect = rect.merge(wall.world_rect())
		if first:
			rect = bounds_rect
	rect = rect.grow(bounds_margin)
	var min_size: Vector2 = min_bound_size
	var size: Vector2 = rect.size
	if size.x < min_size.x:
		rect.position.x -= (min_size.x - size.x) * 0.5
		rect.size.x = min_size.x
	if size.y < min_size.y:
		rect.position.y -= (min_size.y - size.y) * 0.5
		rect.size.y = min_size.y
	return rect

#endregion


#region editor gizmo

## Editor-only setup. Never touches autoloads (they are not available to editor
## code) and never generates nodes that could be written into the level file.
func _editor_ready() -> void:
	_collect_editor_objects()
	# So the floor and the wall outline are visible while authoring, not only when the level runs.
	_ensure_floor()
	_setup_wall_decor()
	_find_spawn_point()
	_read_tuning_defaults()
	_apply_editor_preview()
	_warn_about_missing_content()
	set_process(true)
	queue_redraw()


## Editor-only gathering: the same groups the runtime uses, but without connecting
## signals (this runs every editor frame to notice newly added or moved nodes).
func _collect_editor_objects() -> void:
	_collect_walls()
	enemies.clear()
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy != null:
			enemies.append(enemy)
	exits.clear()
	for node: Node in get_tree().get_nodes_in_group("exit"):
		var exit := node as ExitZone
		if exit != null:
			exits.append(exit)


## The vision numbers live in an autoload, so read the exported defaults off a
## throwaway instance of that script instead.
func _read_tuning_defaults() -> void:
	var tuning: Node = TUNING_SCRIPT.new()
	_editor_near_radius = tuning.sight_near_radius
	_editor_cone_reach = tuning.sight_far_range
	_editor_cone_half = deg_to_rad(tuning.sight_far_degrees * 0.5)
	tuning.free()


## An *unowned* CanvasModulate: Godot only serialises nodes owned by the scene
## root, so this can never end up saved into a level file.
func _apply_editor_preview() -> void:
	var existing: CanvasModulate = get_node_or_null(NodePath(EDITOR_PREVIEW_NODE)) as CanvasModulate
	if not editor_lighting_preview:
		if existing != null:
			existing.free()
		return
	var ambient: float = editor_preview_ambient
	var fog: CanvasModulate = existing
	if fog == null:
		fog = CanvasModulate.new()
		fog.name = String(EDITOR_PREVIEW_NODE)
		add_child(fog, false, Node.INTERNAL_MODE_DISABLED)
	fog.color = Color(ambient, ambient, minf(1.0, ambient * 1.08), 1.0)


func _process(_delta: float) -> void:
	# Editor only (see _ready).
	if not Engine.is_editor_hint():
		return
	_collect_editor_objects()
	var current: int = _editor_state()
	if current != _gizmo_hash:
		_gizmo_hash = current
		queue_redraw()


func _editor_state() -> int:
	var parts: Array = [level_bounds(), walls.size()]
	for wall: Wall in walls:
		if is_instance_valid(wall):
			parts.append(wall.world_rect())
	parts.append(exits.size())
	var marker := find_child("PlayerSpawn", true, false) as Marker2D
	parts.append(marker.global_position if marker != null else Vector2.ZERO)
	return hash(parts)


## Draws what the player will actually be able to see, and flags the two mistakes
## that make a level unplayable. Drawn underneath the walls (the level's own
## drawing happens before its children), so it lives in open floor space.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var font: Font = ThemeDB.fallback_font
	var info := Color(0.62, 0.80, 0.95, 0.7)
	var warning := Color(1.0, 0.55, 0.4, 0.95)

	var bounds: Rect2 = level_bounds()
	var corners: Array[Vector2] = [
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
	]
	for i: int in corners.size():
		draw_dashed_line(corners[i], corners[(i + 1) % corners.size()], Color(info, 0.55), 1.0, 12.0)
	draw_string(font, bounds.position + Vector2(8.0, 18.0),
		"camera bounds: how far the camera may follow", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(info, 0.9))

	var marker := find_child("PlayerSpawn", true, false) as Marker2D
	if marker == null:
		draw_string(font, Vector2(30.0, 44.0),
			"no PlayerSpawn marker: the player will start at the origin",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, warning)
	else:
		var origin: Vector2 = to_local(marker.global_position)
		var faint := Color(0.55, 0.85, 1.0, 0.25)
		draw_arc(origin, _editor_near_radius, 0.0, TAU, 28, faint, 1.0)
		draw_arc(origin, _editor_cone_reach, -_editor_cone_half, _editor_cone_half, 40, faint, 1.0)
		draw_line(origin, origin + Vector2.from_angle(-_editor_cone_half) * _editor_cone_reach,
			faint, 1.0)
		draw_line(origin, origin + Vector2.from_angle(_editor_cone_half) * _editor_cone_reach,
			faint, 1.0)
		draw_circle(origin, 8.0, Color(0.55, 0.85, 1.0, 0.85))
		draw_string(font, origin + Vector2(13.0, -13.0), "spawn + vision reach",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.92, 1.0, 0.9))

	if exits.is_empty():
		draw_string(font, Vector2(30.0, 66.0),
			"no ExitZone in this level: it cannot be finished",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, warning)

#endregion


#region runtime

func _on_reveal_changed(revealed: bool) -> void:
	if _fog != null:
		_fog.color = reveal_color if revealed else fog_color


func exit_for_current_level() -> ExitZone:
	for exit: ExitZone in exits:
		if not exit.is_final:
			return exit
	return null


func alive_enemies() -> int:
	var count: int = 0
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy) and not enemy.is_dead():
			count += 1
	return count


## Keeps the tracked list free of freed enemies (projectiles and the HUD walk it).
func _on_enemy_died(enemy: Enemy) -> void:
	var index: int = enemies.find(enemy)
	if index >= 0:
		enemies.remove_at(index)


## Highest awareness in the level, for the HUD threat indicator.
func alert_level() -> float:
	var highest: float = 0.0
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy) and not enemy.is_dead():
			highest = maxf(highest, enemy.awareness)
	return highest

#endregion


#region debug

func debug_spawn_enemy() -> void:
	if player == null:
		return
	var enemy := (load("res://src/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	add_child(enemy)
	enemy.global_position = player.global_position + player.aim_direction * 240.0
	enemies.append(enemy)
	GameDirector.announce_message("Spawned %s" % enemy.archetype_id, Color(1.0, 0.8, 0.3))


func debug_alert_all() -> void:
	if player == null:
		return
	for enemy: Enemy in enemies:
		if is_instance_valid(enemy) and not enemy.is_dead():
			enemy.alert_from(player.global_position)
	GameDirector.announce_message("All enemies alerted", Color(1.0, 0.5, 0.3))

#endregion
