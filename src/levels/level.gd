class_name Level
extends Node2D
## Base behaviour for every level.
##
## A level scene should contain *only* content: walls, lamps, enemies, pickups,
## exits, marker points. Everything the game needs to function is either supplied
## by this script or by an autoload, so it is impossible to create a level that
## is broken because a required node was forgotten (see AGENTS.md):
##
##   * the black fog (CanvasModulate)      -> created if missing
##   * the explored-geometry memory        -> created if missing
##   * the effect layer                    -> created if missing
##   * the HUD                             -> created if missing
##   * the player                           -> always spawned here, from PlayerSpawn
##   * camera limits                        -> derived from the walls themselves
##
## If a spawn marker is missing the player simply starts at the origin, and if
## there is no exit the level warns instead of breaking.

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")
const HUD_SCENE: PackedScene = preload("res://src/ui/hud.tscn")

@export var level_title: String = "LEVEL"
@export var objective: String = "Find the way out."
## Set on every exit that is not the last one; empty means "this is the end".
@export var next_level: PackedScene
@export var start_weapons: Array[String] = ["pistol"]
@export var starting_ammo_bonus: int = 0

@export_group("Camera bounds")
## Derive the camera limit rectangle from the walls. Recommended.
@export var auto_bounds: bool = true
## Used when `auto_bounds` is off.
@export var bounds_rect: Rect2 = Rect2(-900.0, -600.0, 1800.0, 1200.0)
@export var bounds_margin: float = 90.0
@export var min_bound_size: Vector2 = Vector2(1700.0, 1000.0)

@export_group("Fog")
@export var fog_color: Color = Color(0.0, 0.0, 0.0, 1.0)
## Ambient used by the F4 debug reveal.
@export var reveal_color: Color = Color(0.34, 0.34, 0.36, 1.0)

var player: Player = null
var walls: Array[Wall] = []
var enemies: Array[Enemy] = []
var exits: Array[ExitZone] = []

var spawn_point: Vector2 = Vector2.ZERO
var _fog: CanvasModulate = null
var _fx_layer: Node2D = null
var _memory: VisionMemory = null
var _hud: HUD = null


func _ready() -> void:
	GameDirector.on_level_ready(self)
	_collect_groups()
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
	walls.clear()
	for node: Node in get_tree().get_nodes_in_group("wall"):
		var wall := node as Wall
		if wall != null:
			walls.append(wall)
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


func _ensure_fog() -> void:
	_fog = get_node_or_null("Fog") as CanvasModulate
	if _fog == null:
		_fog = CanvasModulate.new()
		_fog.name = "Fog"
		add_child(_fog)
		move_child(_fog, 0)
	_fog.color = fog_color


func _ensure_memory() -> void:
	_memory = get_node_or_null("Memory") as VisionMemory
	if _memory == null:
		_memory = VisionMemory.new()
		_memory.name = "Memory"
		add_child(_memory)
	_memory.sample_interval = Tuning.memory_sample_interval


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
