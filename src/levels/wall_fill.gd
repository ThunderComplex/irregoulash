class_name WallFill
extends MeshInstance2D
## The textured surface of every wall, as one mesh whose vertices carry how lit they are.
##
## The lighting value cannot be sampled per pixel: the mask is a photograph of the level's lighting and a
## wall is an occluder, so the mask on top of a wall is the wall's own shadow. Per-pixel attempts worked
## around that by probing a ring of samples, which popped as the ring crossed a light boundary and read
## the far side's shadow as well as the near side's -- the "double shadow" you see when looking down a wall.
##
## So it is baked instead: each vertex of the fill asks `WallDecor` where the nearest piece of the merged
## outline is, samples the mask just outside it, and stores that as a vertex colour. The GPU interpolates
## between vertices, which is smooth by construction and cannot read a shadow that is not there.

const FILL_SHADER: Shader = preload("res://src/levels/wall_fill.gdshader")
## Size of the cells the fill is divided into, in world pixels. Smaller means a smoother lighting
## gradient across a wall and more vertices.
const CELL: float = 24.0

var _walls: Array[Wall] = []
var _style: SurfaceStyle = null
var _decor: WallDecor = null
var _material: ShaderMaterial = null


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = FILL_SHADER
	material = _material
	z_index = Layers.Z_WALL


func setup(walls: Array[Wall], style: SurfaceStyle, decor: WallDecor) -> void:
	_walls = walls
	_style = style
	_decor = decor
	if _style != null and _style.is_textured() and _material != null:
		_material.set_shader_parameter("albedo", _style.albedo)
		_material.set_shader_parameter("tile_world", _style.tile_world)
		_material.set_shader_parameter("tint", _style.tint)
		_material.set_shader_parameter("breakup_amount", _style.breakup_amount)
		_material.set_shader_parameter("breakup_scale", _style.breakup_scale)
	refresh()


## Rebuilds the mesh from the cached walls and the mask's current state.
func refresh() -> void:
	if _style == null or not _style.is_textured() or _decor == null:
		mesh = null
		visible = false
		return
	visible = true
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for wall: Wall in _walls:
		if wall != null and is_instance_valid(wall):
			_emit_wall(surface, wall)
	mesh = surface.commit()


## A grid over the wall's footprint, each vertex carrying its own lighting.
func _emit_wall(surface: SurfaceTool, wall: Wall) -> void:
	print("hi")
	var half: Vector2 = wall.size * 0.5
	var columns: int = maxi(1, int(ceil(wall.size.x / CELL)))
	var rows: int = maxi(1, int(ceil(wall.size.y / CELL)))
	for column: int in columns:
		for row: int in rows:
			var x0: float = - half.x + wall.size.x * (float(column) / float(columns))
			var x1: float = - half.x + wall.size.x * (float(column + 1) / float(columns))
			var y0: float = - half.y + wall.size.y * (float(row) / float(rows))
			var y1: float = - half.y + wall.size.y * (float(row + 1) / float(rows))
			var p00: Vector2 = wall.to_global(Vector2(x0, y0))
			var p10: Vector2 = wall.to_global(Vector2(x1, y0))
			var p11: Vector2 = wall.to_global(Vector2(x1, y1))
			var p01: Vector2 = wall.to_global(Vector2(x0, y1))
			var l00: float = _lit(wall, p00)
			var l10: float = _lit(wall, p10)
			var l11: float = _lit(wall, p11)
			var l01: float = _lit(wall, p01)
			_triangle(surface, p00, l00, p10, l10, p11, l11)
			_triangle(surface, p00, l00, p11, l11, p01, l01)


func _lit(wall: Wall, world_point: Vector2) -> float:
	return _decor.sample_lighting_near(world_point, wall)


func _triangle(surface: SurfaceTool, a: Vector2, la: float, b: Vector2, lb: float, c: Vector2,
		lc: float) -> void:
	surface.set_color(Color(la, la, la, 1.0))
	surface.add_vertex(Vector3(a.x, a.y, 0.0))
	surface.set_color(Color(lb, lb, lb, 1.0))
	surface.add_vertex(Vector3(b.x, b.y, 0.0))
	surface.set_color(Color(lc, lc, lc, 1.0))
	surface.add_vertex(Vector3(c.x, c.y, 0.0))
