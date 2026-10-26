extends Control
## Title screen. Also the project's main scene, so the game always starts here.
##
## Doubles as the "how do I play this" screen: the control list is generated from
## GameInput.CONTROLS_TEXT so it cannot drift out of date.

var _pulse: float = 0.0
var _prompt: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT, false)
	_build()


func _process(delta: float) -> void:
	_pulse += delta
	if _prompt != null:
		_prompt.modulate.a = 0.55 + 0.45 * sin(_pulse * 2.4)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept"):
		# Handled before starting the run, which replaces this scene.
		get_viewport().set_input_as_handled()
		AudioDirector.play(&"ui_click", -4.0)
		GameDirector.start_run()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.04, 0.055, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT, false)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# A dim cone of light, echoing the thing the game is actually about.
	var beam := Polygon2D.new()
	beam.polygon = PackedVector2Array([
		Vector2(40.0, 700.0), Vector2(1420.0, 60.0), Vector2(1420.0, 700.0),
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

	_prompt = _label(Vector2(500.0, 650.0), Vector2(900.0, 50.0),
		"[ SPACE ] to start", 26, Color(1.0, 0.9, 0.6))


func _label(position_: Vector2, size: Vector2, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
