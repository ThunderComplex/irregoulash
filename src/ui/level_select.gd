class_name LevelSelect
extends Control
## The level picker, opened from the title screen once the campaign has been finished.
##
## Choosing a level starts a *practice* run: every weapon fully upgraded and fully stocked, no
## abilities, no checkpoint recording, and the level's exit returns here instead of continuing the
## campaign. The campaign is a chain, so the only way to replay a level is to pick it deliberately --
## and the only time that makes sense is after the story is over.
##
## Built in code like the settings menu, in the same 1280x720 reference frame scaled to the window.

signal closed()

const REFERENCE: Vector2 = Vector2(1280.0, 720.0)
const PANEL_SIZE: Vector2 = Vector2(760.0, 560.0)
const PADDING: float = 44.0

var _scale: float = 1.0
var _menu: MenuList = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scale = _compute_scale()
	_build()
	_menu.focus_first()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	AudioDirector.play(&"ui_click", -6.0)
	closed.emit()
	queue_free()


## Probe hook: choose a level as if its button had been pressed.
func choose(path: String) -> bool:
	return _menu.activate(StringName(path))


func _compute_scale() -> float:
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return 1.0
	return clampf(minf(viewport.x / REFERENCE.x, viewport.y / REFERENCE.y), 0.35, 4.0)


func _build() -> void:
	var viewport: Vector2 = get_viewport().get_visible_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.9)
	dim.position = Vector2.ZERO
	dim.size = viewport
	# Swallows clicks, so nothing behind the picker reacts while it is open.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := Control.new()
	panel.position = (viewport - PANEL_SIZE * _scale) * 0.5
	panel.size = PANEL_SIZE * _scale
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_rect(panel, Vector2(-3.0, -3.0), PANEL_SIZE + Vector2(6.0, 6.0), Color(0.16, 0.19, 0.24))
	_rect(panel, Vector2.ZERO, PANEL_SIZE, Color(0.055, 0.065, 0.085, 0.98))
	_label(panel, Vector2(PADDING, 34.0), "LEVEL SELECT", 30, Color(0.92, 0.96, 1.0))
	_label(panel, Vector2(PADDING, 80.0),
		"Practice run: every weapon fully upgraded, no abilities. Nothing here is saved.",
		15, Color(0.55, 0.62, 0.72))

	var paths: Array[String] = CampaignLibrary.paths()
	# Back is the last item, so the whole picker is one focusable list from top to bottom.
	var rows: int = int(ceil(float(paths.size() + 1) / 2.0))
	_menu = MenuList.new()
	_menu.configure(Rect2(PADDING, 118.0, PANEL_SIZE.x - PADDING * 2.0,
		float(maxi(1, rows)) * MenuList.ROW_HEIGHT), _scale, 2)
	for i: int in paths.size():
		var path: String = paths[i]
		var title: String = CampaignLibrary.title_of(path)
		if title.is_empty():
			title = path.get_file().get_basename().replace("_", " ")
		_menu.add_item(StringName(path), "%d   %s" % [i + 1, title.to_upper()])
	_menu.add_item(&"back", "BACK")
	_menu.activated.connect(_on_item)
	panel.add_child(_menu)

	var footer := _label(panel, Vector2(0.0, PANEL_SIZE.y - 44.0), "", 15,
		Color(0.55, 0.62, 0.72))
	footer.size = Vector2(PANEL_SIZE.x, 24.0) * _scale
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.text = "[ %s ] back to the title" % GameInput.describe_for_device("ui_cancel")


func _on_item(id: StringName) -> void:
	AudioDirector.play(&"ui_click", -6.0)
	if id == &"back":
		close()
		return
	GameDirector.start_selected_level(String(id))


func _rect(parent: Control, position_: Vector2, rect_size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = position_ * _scale
	rect.size = rect_size * _scale
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _label(parent: Control, position_: Vector2, text: String, font_size: int,
		color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_ * _scale
	label.add_theme_font_size_override("font_size",
		maxi(1, int(round(float(font_size) * _scale))))
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
