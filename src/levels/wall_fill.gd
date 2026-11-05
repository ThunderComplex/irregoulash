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
##
## It rebuilds every time the mask updates, so the per-frame part is kept small: the grid, its triangles
## and everything about each vertex's lighting lookup that does not change while the walls stand still
## are worked out once in `setup`. A refresh only reads the lighting and swaps in new vertex colours.

const FILL_SHADER: Shader = preload("res://src/levels/wall_fill.gdshader")
## Size of the cells the fill is divided into, in world pixels. Smaller means a smoother lighting
## gradient across a wall and more vertices.
const CELL: float = 32.0

var _walls: Array[Wall] = []
var _style: SurfaceStyle = null
var _decor: WallDecor = null
var _material: ShaderMaterial = null
var _mesh: ArrayMesh = null

## The grid over every wall, built once per setup: one vertex per grid corner, shared by the cells around
## it, and the triangles between them.
var _points := PackedVector2Array()
var _indices := PackedInt32Array()
var _lighting: WallDecor.LightingCache = null
var _lit := PackedFloat32Array()
var _colors := PackedColorArray()


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
	_build_grid()
	refresh()


## Rebuilds the vertex colours from the mask's current state.
func refresh() -> void:
	if _style == null or not _style.is_textured() or _decor == null or _points.is_empty():
		mesh = null
		visible = false
		return
	visible = true
	if _decor.has_lighting():
		# Built on the first refresh that has a mask frame, not in `setup`: until then (and always in the
		# editor, where the mask is never photographed) every point is fully lit and the cache would go
		# unused, while building it costs tens of milliseconds -- every wall edit, in the editor.
		if _lighting == null:
			_lighting = _decor.lighting_cache(_points)
		_decor.sample_cached(_lighting, _lit)
	else:
		_lit.resize(_points.size())
		_lit.fill(1.0)
	_colors.resize(_lit.size())
	for index: int in _lit.size():
		var value: float = _lit[index]
		_colors[index] = Color(value, value, value, 1.0)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _points
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	if _mesh == null:
		_mesh = ArrayMesh.new()
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = _mesh


## A grid over each wall's footprint, `CELL` apart. The lighting lookups for its corners are left to the
## first refresh that needs them.
func _build_grid() -> void:
	_points.clear()
	_indices.clear()
	_lighting = null
	if _style == null or not _style.is_textured() or _decor == null:
		return
	for wall: Wall in _walls:
		if wall != null and is_instance_valid(wall):
			_add_wall(wall)


func _add_wall(wall: Wall) -> void:
	var half: Vector2 = wall.size * 0.5
	var columns: int = maxi(1, int(ceil(wall.size.x / CELL)))
	var rows: int = maxi(1, int(ceil(wall.size.y / CELL)))
	var base: int = _points.size()
	for column: int in columns + 1:
		for row: int in rows + 1:
			_points.append(wall.to_global(Vector2(
				-half.x + wall.size.x * float(column) / float(columns),
				-half.y + wall.size.y * float(row) / float(rows))))
	for column: int in columns:
		for row: int in rows:
			var i00: int = base + column * (rows + 1) + row
			var i10: int = base + (column + 1) * (rows + 1) + row
			_indices.append_array(PackedInt32Array([i00, i10, i10 + 1, i00, i10 + 1, i00 + 1]))
