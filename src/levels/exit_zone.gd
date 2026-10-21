class_name ExitZone
extends Area2D
## The way out. Walk into it to finish the level; `is_final` marks the last one,
## which wins the run.
##
## An exit nobody can find is a broken exit, so it carries its own lights and an
## unshaded marker that is visible through the fog from across a dark room.

signal entered(exit: ExitZone)

@export var is_final: bool = false
@export var next_level: PackedScene
@export var radius: float = 46.0
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
	if next_level != null:
		GameDirector.load_level(next_level.resource_path)
	else:
		GameDirector.announce_message("No next level set", Color(1.0, 0.5, 0.4))
		GameDirector.notify_win()
