class_name RevealMask
extends Node
## A low-resolution photograph of the level's lighting, used to decide which parts of a wall are visible.
##
## Walls are drawn unshaded, because a wall casts the shadows the vision system depends on and can
## therefore never be lit by the lights it occludes. That means "how lit is this wall" cannot be read
## from the lighting system directly -- so instead we photograph the lighting:
##
##   * a white plate covers the level, on a render layer nothing else uses;
##   * a `SubViewport` sharing this level's `world_2d` renders that plate with a camera culled to that
##     layer only, so what it sees is the plate being lit;
##   * the wall shader samples the result in world space and multiplies its own colour by it.
##
## Everything the design asks for then comes for free, from the lighting the game already has: the
## player's cone lights walls it actually reaches, lamps light walls by brightness and distance, their
## existing line-of-sight gating means a lamp the player cannot see contributes nothing, and wall
## occluders shadow the plate exactly as they shadow the floor.
##
## Read back at 10 Hz rather than every frame: it is cheap, and the stepping as the player turns is a
## look worth having.

## World pixels per texel of the mask. Coarser means softer, cheaper, and more visibly retro.
const WORLD_PER_TEXEL: float = 8.0
## How often the mask is refreshed, in seconds.
const UPDATE_INTERVAL: float = 0.05
## Visibility layer used only by the mask's plate. The plate has to sit on the same canvas as the lights
## -- a `CanvasLayer` would isolate it from them -- so the *main* viewport has this bit cleared instead,
## which is what keeps a full-screen white rectangle out of the game.
const CULL_BIT: int = 19

## Emitted once, when the first frame has been read back. Wall materials cannot point at the mask before
## it exists, so the level rebuilds them when this fires.
signal first_sample()
## Emitted after every read-back, so decoration drawn on the CPU can follow the lighting.
signal sampled()

var texture: Texture2D = null
## The world-space rectangle the mask covers, which is what turns a world position into a texel.
var world_rect: Rect2 = Rect2()

var _viewport: SubViewport = null
var _camera: Camera2D = null
var _plate: ColorRect = null
var _image_texture: ImageTexture = null
var _cooldown: float = 0.0


func _ready() -> void:
	set_process(true)


## Attaches the mask to a level and its world. Called by `Level` once its bounds are known.
func setup(rect: Rect2, world: World2D) -> void:
	world_rect = rect
	set_world(world)


func set_world(world: World2D) -> void:
	if _viewport == null:
		_build()
	if world == null:
		return
	_viewport.world_2d = world
	_resize()


func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "RevealPass"
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Not `INTERNAL_MODE`: the viewport still has to run, it just must not be saved.
	add_child(_viewport, false, Node.INTERNAL_MODE_DISABLED)

	# Culling is per *viewport* in 2D, not per camera: the mask viewport draws only the plate's visibility
	# layer, so nothing else in the level ends up in it.
	_viewport.canvas_cull_mask = 1 << CULL_BIT
	# ...and the main viewport must not draw that layer, or the plate would be a white rectangle over the
	# game. Nothing else in the project uses this bit.
	var main := get_viewport()
	if main != null:
		main.canvas_cull_mask &= ~(1 << CULL_BIT)

	_camera = Camera2D.new()
	_camera.name = "MaskCamera"
	_camera.enabled = true
	_viewport.add_child(_camera)

	_plate = ColorRect.new()
	_plate.name = "LightPlate"
	_plate.color = Color.WHITE
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Lit by every light that matters, but rendered only into this viewport.
	_plate.light_mask = 1
	_plate.visibility_layer = 1 << CULL_BIT
	_viewport.add_child(_plate)


func _resize() -> void:
	if _viewport == null or world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return
	var size := Vector2i(
		maxi(1, int(round(world_rect.size.x / WORLD_PER_TEXEL))),
		maxi(1, int(round(world_rect.size.y / WORLD_PER_TEXEL))))
	if _viewport.size != size:
		_viewport.size = size
		_camera.zoom = Vector2(float(size.x) / world_rect.size.x,
			float(size.y) / world_rect.size.y)
		_camera.global_position = world_rect.get_center()
		_plate.position = world_rect.position
		_plate.size = world_rect.size
		if _image_texture != null:
			texture = null
			_image_texture = null


func _process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = UPDATE_INTERVAL
	_sample()


## Grabs the rendered plate. Cheap because the viewport is tiny; the cost is the GPU readback, which is
## why it happens ten times a second instead of sixty.
func _sample() -> void:
	if _viewport == null or _viewport.size.x <= 0 or _viewport.size.y <= 0:
		return
	var rendered: Texture2D = _viewport.get_texture()
	if rendered == null:
		return
	var image: Image = rendered.get_image()
	if image == null or image.is_empty():
		return
	if _image_texture == null:
		_image_texture = ImageTexture.create_from_image(image)
		texture = _image_texture
		first_sample.emit()
	else:
		_image_texture.update(image)
	# Decoration is drawn on the CPU and reads the mask directly, so it has to be told when the mask moves.
	sampled.emit()


func is_ready() -> bool:
	return texture != null and world_rect.size.x > 0.0 and world_rect.size.y > 0.0
