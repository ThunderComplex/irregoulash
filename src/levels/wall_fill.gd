class_name WallFill
extends MeshInstance2D
## The textured surface of every wall, as one mesh whose vertices carry how lit they are.
##
## The lighting value cannot be sampled per pixel: the mask is a photograph of the level's lighting and a
## wall is an occluder, so the mask on top of a wall is the wall's own shadow. Per-pixel attempts worked
## around that by probing a ring of samples, which popped as the ring crossed a light boundary and read
## the far side's shadow as well as the near side's -- the "double shadow" you see when looking down a wall.
##
## So it is baked instead: each vertex of the fill asks `WallDecor` how lit the wall is there, and stores
## that as a vertex colour. The GPU interpolates between vertices, which is smooth by construction and
## cannot read a shadow that is not there.
##
## The value is the lighting of the space on the *player's* side of the wall, so a wall is lit as a whole
## rather than lighting one edge and going black across the rest of its thickness.

const FILL_SHADER: Shader = preload("res://src/levels/wall_fill.gdshader")
## Size of the cells the fill is divided into, in world pixels. Smaller means a smoother lighting
## gradient across a wall and more vertices.
const CELL: float = 32.0

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
	var half: Vector2 = wall.size * 0.5
	var columns: int = maxi(1, int(ceil(wall.size.x / CELL)))
	var rows: int = maxi(1, int(ceil(wall.size.y / CELL)))
	# Sample each corner of the grid once. Every interior corner is shared by four cells, and sampling is
	# by far the expensive part of this rebuild, so asking four times would quadruple it for nothing.
	var points: Array[Vector2] = []
	var lighting: PackedFloat32Array = PackedFloat32Array()
	points.resize((columns + 1) * (rows + 1))
	lighting.resize((columns + 1) * (rows + 1))
	for column: int in columns + 1:
		for row: int in rows + 1:
			var point: Vector2 = wall.to_global(Vector2(
				-half.x + wall.size.x * float(column) / float(columns),
				-half.y + wall.size.y * float(row) / float(rows)))
			var index: int = column * (rows + 1) + row
			points[index] = point
			lighting[index] = _lit(point)
	for column: int in columns:
		for row: int in rows:
			var i00: int = column * (rows + 1) + row
			var i10: int = (column + 1) * (rows + 1) + row
			_triangle(surface, points[i00], lighting[i00], points[i10], lighting[i10],
				points[i10 + 1], lighting[i10 + 1])
			_triangle(surface, points[i00], lighting[i00], points[i10 + 1], lighting[i10 + 1],
				points[i00 + 1], lighting[i00 + 1])


func _lit(world_point: Vector2) -> float:
	# `WallDecor` owns the one definition of "how lit is the wall here", so the rim and this fill cannot
	# disagree about it.
	return _decor.sample_lighting_near(world_point)


func _triangle(surface: SurfaceTool, a: Vector2, la: float, b: Vector2, lb: float, c: Vector2,
		lc: float) -> void:
	surface.set_color(Color(la, la, la, 1.0))
	surface.add_vertex(Vector3(a.x, a.y, 0.0))
	surface.set_color(Color(lb, lb, lb, 1.0))
	surface.add_vertex(Vector3(b.x, b.y, 0.0))
	surface.set_color(Color(lc, lc, lc, 1.0))
	surface.add_vertex(Vector3(c.x, c.y, 0.0))
