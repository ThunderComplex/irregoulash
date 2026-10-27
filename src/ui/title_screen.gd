extends Control
## Title screen. Also the project's main scene, so the game always starts here.
##
## Doubles as the "how do I play this" screen: the control list is generated from
## GameInput.CONTROLS_TEXT so it cannot drift out of date.
##
## The layout below is written in the coordinates of a 1280x720 frame and scaled to fit the
## window, so the same screen works on a small window and on a 4K monitor. It is rebuilt on
## resize rather than nudged, because a rebuild is cheap and cannot half-apply.

## The frame the layout is written for.
const REFERENCE: Vector2 = Vector2(1280.0, 720.0)
## How much of that frame the two columns occupy, used to work out the margins.
const CONTENT_WIDTH: float = 1160.0

var _pulse: float = 0.0
var _prompt: Label = null
var _scale: float = 1.0
## Top-left of the reference frame in screen pixels. The frame is centred, so an unusual
## aspect ratio gets even bands around the content rather than everything hugging a corner.
var _origin: Vector2 = Vector2.ZERO
var _resize_pending: bool = false
var _menu: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_compute_layout()
	_build()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _process(delta: float) -> void:
	if _resize_pending:
		_resize_pending = false
		_rebuild()
	_pulse += delta
	if _prompt != null:
		_prompt.modulate.a = 0.55 + 0.45 * sin(_pulse * 2.4)


func _unhandled_input(event: InputEvent) -> void:
	if _menu != null and is_instance_valid(_menu):
		return
	if event.is_action_pressed(&"settings"):
		get_viewport().set_input_as_handled()
		open_settings()
	elif event.is_action_pressed(&"ui_accept"):
		# Handled before starting the run, which replaces this scene.
		get_viewport().set_input_as_handled()
		AudioDirector.play(&"ui_click", -4.0)
		GameDirector.start_run()
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		get_tree().quit()


## Opens the settings menu over the title. Public so the dev probe can open it too.
func open_settings() -> void:
	if _menu != null and is_instance_valid(_menu):
		return
	AudioDirector.play(&"ui_click", -6.0)
	_menu = SettingsMenu.new()
	add_child(_menu)


func _compute_layout() -> void:
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return
	# Fit rather than scale-by-height: a 4:3 or 5:4 window is narrower than 16:9, and a
	# height-only scale would push the second column off the right edge.
	_scale = clampf(minf(viewport.x / REFERENCE.x, viewport.y / REFERENCE.y), 0.35, 4.0)
	_origin = (viewport - REFERENCE * _scale) * 0.5


func _on_viewport_resized() -> void:
	_resize_pending = true


## Rebuilds everything except an open settings menu, which stays put.
func _rebuild() -> void:
	for child: Node in get_children():
		if child == _menu:
			continue
		child.free()
	_compute_layout()
	_build()


func _build() -> void:
	# The background and the beam are sized from the viewport explicitly: a Control inside
	# another Control is not automatically given its parent's rect, and relying on that is
	# what put the settings panel half off-screen once already.
	var viewport: Vector2 = get_viewport().get_visible_rect().size

	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.04, 0.055, 1.0)
	bg.position = Vector2.ZERO
	bg.size = viewport
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# A dim cone of light, echoing the thing the game is actually about.
	var beam := Polygon2D.new()
	beam.polygon = PackedVector2Array([
		_to_screen(Vector2(40.0, 700.0)),
		_to_screen(Vector2(1420.0, 60.0)),
		_to_screen(Vector2(1420.0, 700.0)),
	])
	beam.color = Color(0.16, 0.18, 0.24, 1.0)
	add_child(beam)

	_label(Vector2(80.0, 90.0), Vector2(1100.0, 80.0), "TOP DOWN SHOOTER", 52,
		Color(0.93, 0.96, 1.0))
	_label(Vector2(84.0, 176.0), Vector2(1100.0, 40.0),
		"work-in-progress vertical slice  --  line of sight is the whole game", 18,
		Color(0.6, 0.68, 0.8))

	_label(Vector2(84.0, 256.0), Vector2(520.0, 340.0), GameInput.CONTROLS_TEXT, 17,
		Color(0.78, 0.84, 0.92))

	_label(Vector2(640.0, 256.0), Vector2(600.0, 300.0),
		"""What to try

- Walk into a dark room and notice how
  the walls you have seen stay faintly
  lit, so you can still find your way.
- Sneak up on a guard. Awareness is a
  meter, not a switch: it fills faster the
  closer you are, and much faster when
  you shine your own light on them.
- Fire a shot and listen: noise pulls
  guards towards you.
- Get out of the light and break line of
  sight, and they will search for you.
- Clear the yard, find the exit, escape.""", 16, Color(0.62, 0.72, 0.84))

	_prompt = _label(Vector2(0.0, 650.0), Vector2(1280.0, 50.0),
		"[ SPACE ] start        [ S ] settings        [ ESC ] quit", 26, Color(1.0, 0.9, 0.6),
		HORIZONTAL_ALIGNMENT_CENTER)


## Reference frame -> screen pixels.
func _to_screen(point: Vector2) -> Vector2:
	return _origin + point * _scale


func _label(position_: Vector2, size: Vector2, text: String, font_size: int, color: Color,
		halign: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = _to_screen(position_)
	label.size = size * _scale
	label.add_theme_font_size_override("font_size", maxi(1, int(round(float(font_size) * _scale))))
	label.horizontal_alignment = halign
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
