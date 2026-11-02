@tool
class_name Wall
extends StaticBody2D
## Rectangular level geometry.
##
## A wall is authored as ONE property: `size`. From it this script generates the
## collider, the light occluder and the visual, and keeps them in sync live in
## the editor. That is deliberate: per AGENTS.md a level must not be breakable by
## forgetting a node, and hand-placed occluders are exactly the kind of thing
## that gets forgotten.
##
## Every wall also carries a "memory" copy of itself. Once the player has seen a
## wall it stays faintly visible (see `mark_explored`), which is what makes
## pitch-black fog navigable. The memory copy is drawn unshaded, so the
## CanvasModulate fog does not touch it. Enemies have no memory copy, so they
## stay genuinely invisible in the dark.
##
## Note on ordering: `size` can be written by the scene loader before the child
## nodes exist, so `_rebuild()` only ever *updates* children it finds. Creating
## them is `_ready()`'s job.

const MEMORY_BRIGHTNESS_EDITOR: float = 0.13
## Lit, for floors: they are the one surface light reaches.
const SURFACE_SHADER: Shader = preload("res://src/levels/surface.gdshader")
## Unlit, for wall tops: a wall cannot be lit by the light it casts shadows for, so its surface takes
## the place of the unshaded memory silhouette it used to be drawn by.
const WALL_SURFACE_SHADER: Shader = preload("res://src/levels/surface_unshaded.gdshader")

@export var size: Vector2 = Vector2(160.0, 32.0):
	set(value):
		size = Vector2(maxf(8.0, value.x), maxf(8.0, value.y))
		_rebuild()

@export var color: Color = Color(0.40, 0.44, 0.54):
	set(value):
		color = value
		_rebuild()

## Turn off for railings or anything you want to see and shoot through.
@export var occludes_light: bool = true:
	set(value):
		occludes_light = value
		_rebuild()

var _explored: bool = false


func _ready() -> void:
	add_to_group("wall")
	_ensure_children()
	_rebuild()


#region generation

func _rebuild() -> void:
	var body: Polygon2D = get_node_or_null("Body") as Polygon2D
	var outline: Line2D = get_node_or_null("Outline") as Line2D
	var ghost: Polygon2D = get_node_or_null("Ghost") as Polygon2D
	var collision: CollisionShape2D = get_node_or_null("Collision") as CollisionShape2D
	var occluder: LightOccluder2D = get_node_or_null("Occluder") as LightOccluder2D

	var points: PackedVector2Array = Shapes.rect(size)
	var style: SurfaceStyle = surface_style()
	var textured: bool = style != null and style.is_textured()

	if body != null:
		body.polygon = points
		body.z_index = Layers.Z_WALL
		_apply_surface(body, style)
		# A textured wall is drawn by the level's `WallFill` mesh instead: its lighting is baked per vertex,
		# so it cannot be one flat quad per wall. The flat fallback still uses this body.
		body.visible = not textured


	if outline != null:
		outline.points = Shapes.closed_outline(points)
		outline.width = 2.0
		# The shader draws the rim for textured walls: a Line2D at fractional world coordinates renders as
		# a broken dashed line, and it cannot follow a surface shaded per pixel anyway.
		outline.visible = not textured
		outline.default_color = color.lightened(0.25)
		outline.z_index = Layers.Z_WALL_EDGE

	if ghost != null:
		ghost.polygon = points
		# A textured wall draws itself (see above), so the ghost is only used by the flat fallback --
		# which is where it started.
		ghost.color = color
		# The memory copy is composited ON TOP of the wall body at a low alpha:
		#   lit    -> body * light  * 0.7  +  colour * 0.3  == colour
		#   unlit  -> body * 0      * 0.7  +  colour * 0.3  == faint memory
		# Drawn above the body because an opaque unlit body would hide it
		# completely, and unshaded so that the black CanvasModulate fog cannot
		# darken the memory into nothing.
		ghost.z_index = Layers.Z_WALL_EDGE + 1
		if ghost.material == null:
			var m := CanvasItemMaterial.new()
			m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			ghost.material = m
	_update_memory_visibility()

	if collision != null:
		var rect := RectangleShape2D.new()
		rect.size = size
		collision.shape = rect

	if occluder != null:
		var poly := OccluderPolygon2D.new()
		poly.polygon = points
		poly.closed = true
		occluder.occluder = poly
		# Light mask 1 is the default mask of both the vision rig and the lamps.
		occluder.occluder_light_mask = 1 if occludes_light else 0
		occluder.visible = occludes_light


## The look of this wall, taken from the level so that one dropdown styles every wall in it.
##
## Looked up by walking up the parent chain rather than by being pushed in from the level: children are
## ready before their parent, so this works in the editor and at runtime with no ordering rules, and a
## per-wall override later is one property that short-circuits this lookup.
func surface_style() -> SurfaceStyle:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("wall_surface"):
			var style: SurfaceStyle = node.call("wall_surface")
			if style != null:
				return style
			break
		node = node.get_parent()
	return SurfaceLibrary.by_id("plain")


## Gives the Body its textured material, or takes it away for a flat colour.
##
## One material per wall rather than one shared material: it carries this wall's `size_world`, which the
## edge shading needs. Walls number in the dozens, so the cost is nothing.
func _apply_surface(body: Polygon2D, style: SurfaceStyle) -> void:
	if style == null or not style.is_textured():
		body.material = null
		body.color = color
		return
	var shader_material := ShaderMaterial.new()
	shader_material.shader = WALL_SURFACE_SHADER
	shader_material.set_shader_parameter("albedo", style.albedo)
	shader_material.set_shader_parameter("tile_world", style.tile_world)
	shader_material.set_shader_parameter("tint", style.tint)
	shader_material.set_shader_parameter("size_world", size)
	# The rim, its occlusion and the south shadow are drawn by `WallDecor` from the merged outline of the
	# whole wall mass, so this per-rectangle fill contributes texture only. Anything edge-shaped here
	# would reappear as an artificial line wherever two walls meet.
	shader_material.set_shader_parameter("rim_width", 0.0)
	shader_material.set_shader_parameter("rim_boost", 0.0)
	shader_material.set_shader_parameter("rim_ao_strength", 0.0)
	shader_material.set_shader_parameter("base_strength", 0.0)
	shader_material.set_shader_parameter("breakup_amount", style.breakup_amount)
	shader_material.set_shader_parameter("breakup_scale", style.breakup_scale)
	body.material = shader_material
	# White: the tint is a shader uniform now, so the polygon must not tint on top of it. `color` remains
	# the flat fallback used when a wall has no texture.
	body.color = Color.WHITE
	# The lighting mask is owned by the level; ask it rather than caching, so a level rebuilt in the
	# editor or a run started from the title screen both work.
	var reveal := _reveal_mask()
	if reveal != null:
		shader_material.set_shader_parameter("reveal", reveal.texture)
		shader_material.set_shader_parameter("reveal_origin", reveal.world_rect.position)
		shader_material.set_shader_parameter("reveal_size", reveal.world_rect.size)


## The level's reveal mask, found by walking up: the same pattern as `surface_style()`.
func _reveal_mask() -> RevealMask:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("reveal_mask"):
			return node.call("reveal_mask") as RevealMask
		node = node.get_parent()
	return null


## Safety net: if a wall ever ends up without its generated children (hand-built
## node, stripped scene), recreate them at runtime so the level cannot break.
## In the editor we only warn, because editing an instanced scene's children is
## not allowed and would spam errors.
func _ensure_children() -> void:
	if Engine.is_editor_hint():
		for entry: Array in [["Body", "Polygon2D"], ["Outline", "Line2D"], ["Ghost", "Polygon2D"],
				["Collision", "CollisionShape2D"], ["Occluder", "LightOccluder2D"]]:
			if get_node_or_null(NodePath(entry[0])) == null:
				push_warning("Wall '%s' is missing its '%s' child." % [name, entry[0]])
		return

	for entry: Array in [["Ghost", "Polygon2D"], ["Body", "Polygon2D"], ["Outline", "Line2D"],
			["Collision", "CollisionShape2D"], ["Occluder", "LightOccluder2D"]]:
		var child_name: String = entry[0]
		if get_node_or_null(NodePath(child_name)) != null:
			continue
		var created: Object = ClassDB.instantiate(entry[1])
		if created is Node:
			var node: Node = created
			node.name = child_name
			add_child(node, false, Node.INTERNAL_MODE_DISABLED)


## Tuning is an autoload and autoloads are not guaranteed to exist in the editor,
## so fall back to a literal there.
func memory_brightness() -> float:
	if Engine.is_editor_hint():
		return MEMORY_BRIGHTNESS_EDITOR
	return Tuning.memory_brightness

#endregion


#region runtime

func mark_explored() -> void:
	if _explored:
		return
	_explored = true
	_update_memory_visibility()
	_refresh_wall_decor()


func is_explored() -> bool:
	return _explored


func reset_memory() -> void:
	_explored = false
	_update_memory_visibility()
	_refresh_wall_decor()


## Tells the level the outline's visibility changed. Cheap: the decor caches the merged geometry and only
## rebuilds its vertex data.
func _refresh_wall_decor() -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("refresh_wall_decor"):
			node.call("refresh_wall_decor")
			return
		node = node.get_parent()


## Shows what this wall has revealed of itself.
##
## A textured wall no longer tracks whether it has been looked at: its shader multiplies it by
## `RevealMask`, so it appears exactly where it is lit by the player's cone or a visible lamp, and a long
## wall shows only the lit stretch. The flat fallback has no shader to do that with, so it keeps the old
## explored-once silhouette.
func _update_memory_visibility() -> void:
	var body: Polygon2D = get_node_or_null("Body") as Polygon2D
	var ghost: Polygon2D = get_node_or_null("Ghost") as Polygon2D
	var textured: bool = body != null and body.material is ShaderMaterial
	if body != null:
		body.modulate.a = 1.0
	if ghost != null:
		ghost.modulate.a = (memory_brightness() if _explored else 0.0) if not textured else 0.0


## This wall's footprint as a world-space polygon, so rotated walls work and so the merged outline can
## be built from real geometry rather than from an axis-aligned box.
func world_polygon() -> PackedVector2Array:
	var out := PackedVector2Array()
	var half: Vector2 = size * 0.5
	for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		out.append(to_global(corner))
	return out


## World-space rectangle covered by this wall.
func world_rect() -> Rect2:
	return Rect2(global_position - size * 0.5, size)


func world_center() -> Vector2:
	return global_position

#endregion
