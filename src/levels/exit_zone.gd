@tool
class_name ExitZone
extends Area2D
## The way out. Walk into it to finish the level; `is_final` marks the last one,
## which wins the run.
##
## An exit nobody can find is a broken exit, so it carries its own lights and an
## unshaded marker that is visible through the fog from across a dark room. In the
## editor it draws a ring plus its destination, so a level's exits and their
## targets can be checked without running anything.

signal entered(exit: ExitZone)

@export var is_final: bool = false:
	set(value):
		is_final = value
		if Engine.is_editor_hint():
			queue_redraw()
@export var next_level: PackedScene:
	set(value):
		next_level = value
		if Engine.is_editor_hint():
			queue_redraw()
@export var radius: float = 46.0:
	set(value):
		radius = value
		if Engine.is_editor_hint():
			queue_redraw()
## Extra light so the exit reads as a landmark in the dark.
@export var beacon_range: float = 260.0

var _t: float = 0.0
var _marker: Polygon2D = null
var _ring: Line2D = null
var _label: Label = null
var _light: PointLight2D = null
var _used: bool = false


func _ready() -> void:
	add_to_group("exit")
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	_build_collision()
	_build_art()


func accent_color() -> Color:
	return Color(1.0, 0.85, 0.35) if is_final else Color(0.45, 1.0, 0.6)


func _build_collision() -> void:
	var collision := get_node_or_null("Collision") as CollisionShape2D
	if collision == null:
		collision = CollisionShape2D.new()
		collision.name = "Collision"
		add_child(collision)
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision.shape = shape


func _build_art() -> void:
	var color: Color = accent_color()

	_light = PointLight2D.new()
	_light.texture = VisionTextures.radial()
	_light.texture_scale = beacon_range * 2.0 / float(VisionTextures.SIZE)
	_light.color = color
	_light.energy = 0.8
	_light.blend_mode = Light2D.BLEND_MODE_ADD
	_light.z_index = Layers.Z_ACTOR
	add_child(_light)

	# Unshaded: visible through the fog, on purpose.
	_ring = Line2D.new()
	_ring.points = Shapes.closed_outline(Shapes.circle(radius, 24))
	_ring.width = 3.0
	_ring.default_color = color
	_ring.material = FxDirector.unshaded_material()
	_ring.modulate.a = 0.75
	_ring.z_index = Layers.Z_PICKUP + 1
	add_child(_ring)

	_marker = Polygon2D.new()
	_marker.polygon = Shapes.triangle(radius * 0.7, radius * 0.7)
	_marker.rotation = PI  # point backwards, into the exit
	_marker.color = color
	_marker.material = FxDirector.unshaded_material()
	_marker.z_index = Layers.Z_PICKUP + 2
	add_child(_marker)

	_label = Label.new()
	_label.text = "ESCAPE" if not is_final else "WAY OUT"
	_label.add_theme_font_size_override("font_size", 16)
	_label.modulate = color
	_label.z_index = Layers.Z_PICKUP + 2
	_label.position = Vector2(-32.0, radius + 6.0)
	_label.material = FxDirector.unshaded_material()
	add_child(_label)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	var pulse: float = 0.5 + 0.5 * sin(_t * 3.0)
	if _light != null:
		_light.energy = 0.55 + pulse * 0.5
	if (_marker != null) and (_ring != null):
		var scale: float = 1.0 + pulse * 0.05
		_marker.scale = Vector2.ONE * scale
		_ring.scale = Vector2.ONE * scale
		_ring.modulate.a = 0.5 + pulse * 0.4

	if _used:
		return
	# Polling as well as the signal, so an exit still works if the player is
	# teleported, respawned or spawned inside it.
	for body: Node2D in get_overlapping_bodies():
		var player := body as Player
		if player != null and not player.is_dead():
			_enter(player)
			return


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null or player.is_dead():
		return
	_enter(player)


func _enter(_player: Player) -> void:
	if _used:
		return
	_used = true
	entered.emit(self)

	if is_final:
		GameDirector.notify_win()
		return

	GameDirector.notify_level_cleared()
	var target: PackedScene = next_level
	if target == null:
		target = level_next_level()
	if target != null:
		GameDirector.load_level(target.resource_path)
	else:
		GameDirector.announce_message("No next level set", Color(1.0, 0.5, 0.4))
		GameDirector.notify_win()


## The owning level's own `next_level`, used when this exit has none of its own, so a
## level with several exits only needs the destination set once.
func level_next_level() -> PackedScene:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("level_bounds"):
			var fallback: Variant = node.get("next_level")
			return fallback as PackedScene
		node = node.get_parent()
	return null


#region editor gizmo

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var tint: Color = accent_color()
	var font: Font = ThemeDB.fallback_font

	draw_circle(Vector2.ZERO, radius, Color(tint, 0.10))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(tint, 0.95), 2.0)
	draw_arc(Vector2.ZERO, radius * 0.25, 0.0, TAU, 16, Color(tint, 0.6), 1.0)

	var label: String = editor_label()
	var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(-width * 0.5, radius + 20.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		12, Color(tint, 0.95))


## Where this exit goes, for the editor label.
func editor_label() -> String:
	if is_final:
		return "FINAL EXIT: WINS THE RUN"
	var target: PackedScene = next_level
	if target == null:
		target = level_next_level()
	if target == null:
		return "NO NEXT LEVEL SET"
	var path: String = target.resource_path
	if path.is_empty():
		return "TO: (unsaved scene)"
	return "TO: " + path.get_file().get_basename().to_upper()

#endregion
