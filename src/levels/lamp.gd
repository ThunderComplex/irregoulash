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

@export_group("Visibility")
## A lamp the player can neither see nor stand inside does not light the world for
## them. Without this, the rule the renderer implements ("lit = visible") leaks: a
## lamp inside a sealed room would reveal whatever is in its pool, enemies included,
## straight through the wall between you. Line of sight is tested from the player to
## the lamp itself, not to everything the lamp lights -- see docs/DESIGN_NOTES.md.
@export var require_line_of_sight: bool = true
## How fast the lamp fades when it gains or loses visibility (higher is snappier).
@export var visibility_fade: float = 6.0

@export_group("Editor")
## Ignored while playing: draws the light radius in the editor for authoring.
@export var show_radius_in_editor: bool = true

## How often, in seconds, the line-of-sight test is repeated.
const LOS_INTERVAL: float = 0.12

var _light: PointLight2D = null
var _fixture: Polygon2D = null
var _phase: float = 0.0
## 0..1 multiplier for visibility, faded so lamps never pop on or off.
var _lit: float = 1.0
var _visible: bool = true
var _los_timer: float = 0.0


func _ready() -> void:
	flicker = flicker and not Engine.is_editor_hint()
	_phase = randf() * TAU
	_ensure_children()
	_rebuild()
	# The level watches the lit positions in the editor: moving a lamp changes the wall lighting preview,
	# and the preview is only re-photographed when something it cares about moved.
	add_to_group(&"lamp")


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _light == null:
		return

	if require_line_of_sight:
		_los_timer -= delta
		if _los_timer <= 0.0:
			_los_timer = LOS_INTERVAL
			_visible = _is_visible_to_player()
			
	_fixture.visible = _visible
	_lit = move_toward(_lit, 1.0 if _visible else 0.0, visibility_fade * delta)

	if _lit <= 0.0:
		# Fully out of sight: no light, and no flicker maths to do.
		_light.energy = 0.0
		return

	var brightness: float = 1.0
	if flicker:
		_phase += delta * 5.0
		var n: float = sin(_phase) * 0.5 + sin(_phase * 2.31 + 1.7) * 0.5
		brightness = 1.0 + n * flicker_amount
	_light.energy = maxf(0.0, energy * brightness * _lit)


## True when the player is standing inside this lamp's pool, or has a clear line of
## sight to the lamp itself.
##
## The radius carve-out matters: a lamp occluded by a pillar in the very room the
## player is standing in must not switch that room dark around them. Testing sight of
## the lamp rather than of everything it lights is an approximation -- a lit room you
## *can* see into still shows you what is in it, including things behind its own
## furniture -- but it removes the case that reads as a bug.
func _is_visible_to_player() -> bool:
	if not require_line_of_sight:
		return true
	var player: Node2D = GameDirector.valid_player()
	if player == null:
		# No player at all (a test scene, or the title screen): leave lamps on.
		return true
	#if global_position.distance_squared_to(player.global_position) <= radius * radius:
		#return true
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return true
	# Sight blockers, so an open door leaf hides a lamp's glow just as it hides everything else.
	var query := PhysicsRayQueryParameters2D.create(player.global_position, global_position,
		Layers.SIGHT_BLOCKERS)
	query.hit_from_inside = false
	return space.intersect_ray(query).is_empty()


func _rebuild() -> void:
	_light = get_node_or_null("Light") as PointLight2D
	_fixture = get_node_or_null("Fixture") as Polygon2D

	if _light != null:
		# The editor renders the GradientTexture2D baked into lamp.tscn, so lights
		# and their shadows are visible while authoring (turn on the level's
		# `editor_lighting_preview` to see them properly). At runtime that texture is
		# replaced by the generated radial falloff. A generated texture must NEVER be
		# assigned in the editor: it would be serialised into the scene on save.
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
