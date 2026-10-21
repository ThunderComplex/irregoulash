@tool
class_name Lamp
extends Node2D
## Static level light. Place a few in a level and rooms get readable "lit
## pockets": you can see enemies standing in lamp light even when they are
## outside your vision cone, and lamp light is blocked by walls like everything
## else.
##
## The fixture itself is drawn unshaded by default, so distant lamps read as
## faint beacons in the dark and help you navigate without revealing the layout.

@export var color: Color = Color(1.0, 0.85, 0.58):
	set(value):
		color = value
		_rebuild()
@export var radius: float = 190.0:
	set(value):
		radius = maxf(16.0, value)
		_rebuild()
@export var energy: float = 0.9:
	set(value):
		energy = value
		_rebuild()
## Shadows make the light respect walls (recommended).
@export var shadows: bool = true:
	set(value):
		shadows = value
		_rebuild()
## Keep the fixture itself faintly visible even when unlit.
@export var beacon: bool = true:
	set(value):
		beacon = value
		_rebuild()
@export var flicker: bool = true
@export var flicker_amount: float = 0.07

@export_group("Editor")
## Ignored while playing: draws the light radius in the editor for authoring.
@export var show_radius_in_editor: bool = true

var _light: PointLight2D = null
var _fixture: Polygon2D = null
var _phase: float = 0.0


func _ready() -> void:
	flicker = flicker and not Engine.is_editor_hint()
	_phase = randf() * TAU
	_ensure_children()
	_rebuild()


func _process(delta: float) -> void:
	if not flicker or _light == null:
		return
	_phase += delta * 5.0
	var n: float = sin(_phase) * 0.5 + sin(_phase * 2.31 + 1.7) * 0.5
	_light.energy = maxf(0.0, energy * (1.0 + n * flicker_amount))


func _rebuild() -> void:
	_light = get_node_or_null("Light") as PointLight2D
	_fixture = get_node_or_null("Fixture") as Polygon2D

	if _light != null:
		# The light texture is generated at runtime. It is deliberately NOT set in
		# the editor: a generated ImageTexture would be serialised into the scene
		# file on save. The editor shows the radius with _draw() instead.
		if not Engine.is_editor_hint():
			_light.texture = VisionTextures.radial()
			_light.energy = energy
		_light.texture_scale = radius * 2.0 / float(VisionTextures.SIZE)
		_light.color = color
		_light.shadow_enabled = shadows
		_light.blend_mode = Light2D.BLEND_MODE_ADD
		_light.z_index = Layers.Z_ACTOR

	if _fixture != null:
		_fixture.polygon = Shapes.circle(7.0, 12)
		_fixture.color = color.lightened(0.35)
		_fixture.z_index = Layers.Z_ACTOR
		if beacon:
			var m: CanvasItemMaterial = _fixture.material as CanvasItemMaterial
			if m == null:
				m = CanvasItemMaterial.new()
				_fixture.material = m
			m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			_fixture.modulate = Color(0.55, 0.5, 0.4)
		else:
			_fixture.material = null
			_fixture.modulate = Color.WHITE

	queue_redraw()


func _ensure_children() -> void:
	if Engine.is_editor_hint():
		for entry: Array in [["Light", "PointLight2D"], ["Fixture", "Polygon2D"]]:
			if get_node_or_null(NodePath(entry[0])) == null:
				push_warning("Lamp '%s' is missing its '%s' child." % [name, entry[0]])
		return
	for entry: Array in [["Light", "PointLight2D"], ["Fixture", "Polygon2D"]]:
		var child_name: String = entry[0]
		if get_node_or_null(NodePath(child_name)) != null:
			continue
		var created: Object = ClassDB.instantiate(entry[1])
		if created is Node:
			var node: Node = created
			node.name = child_name
			add_child(node, false, Node.INTERNAL_MODE_DISABLED)


## Editor-only radius preview.
func _draw() -> void:
	if not Engine.is_editor_hint() or not show_radius_in_editor:
		return
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.30), 1.0)
	draw_circle(Vector2.ZERO, 3.0, Color(color.r, color.g, color.b, 0.85))
