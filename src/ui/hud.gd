class_name HUD
extends CanvasLayer
## Everything on screen: health, ammo, weapon slots, the level's threat level,
## the objective, the message feed, the death/victory/pause overlays and the
## debug readout.
##
## The layout is built in code rather than as a hand-authored scene. That is a
## deliberate trade for a WIP: it keeps every dimension in one readable file, and
## it means the HUD can never be half-broken by a scene that was edited in a
## hurry. Swap it for a .tscn whenever the layout stops changing.

const FEED_LIFE: float = 4.0
const FEED_MAX: int = 4

## Edge-only damage vignette. Writing it here (rather than as a .gdshader file)
## keeps the HUD self-contained; move it out if it grows.
const VIGNETTE_SHADER: String = """shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.62, 0.04, 0.07, 1.0);

void fragment() {
	vec2 d = abs(UV - vec2(0.5)) * 2.0;
	float edge = smoothstep(0.42, 1.0, max(d.x, d.y));
	float corner = smoothstep(0.38, 1.15, length(d));
	COLOR = vec4(tint.rgb, tint.a * max(edge, corner) * strength);
}
"""

var _root: Control
var _health_fill: ColorRect
var _health_text: Label
var _keys_text: Label
var _weapon_name: Label
var _ammo_text: Label
var _slots_text: Label
var _reload_bar: ColorRect
var _reload_bg: ColorRect
var _ability_labels: Array[Label] = []
var _alert_fill: ColorRect
var _alert_text: Label
var _objective: Label
var _feed: Label
var _banner: Label
var _vignette: ColorRect
var _overlay: Control
var _overlay_title: Label
var _overlay_body: Label
var _debug: Label

## Layout scale. Every dimension in `_build()` is written for a 720-tall screen and
## multiplied by this, so the interface keeps the same size relative to the window at any
## resolution instead of shrinking into a corner on a large display.
var _scale: float = 1.0
## Set when the window changes size; the layout is rebuilt on the next frame rather than
## inside the signal, so nothing is freed mid-notification.
var _resize_pending: bool = false

var _player: Player = null
var _settings_menu: SettingsMenu = null
var _pause_menu: MenuList = null
var _feed_lines: Array[String] = []
var _feed_age: Array[float] = []
var _vignette_alpha: float = 0.0
var _vignette_material: ShaderMaterial = null
var _banner_timer: float = 0.0
var _poll_cd: float = 0.0
var _alert: float = 0.0
var _alert_state: String = "CALM"
## "none" | "paused" | "dead" | "won"
var _overlay_kind: String = "none"


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scale = _compute_scale()
	_build()
	GameDirector.announce.connect(_on_announce)
	GameDirector.game_over.connect(_on_game_over)
	GameDirector.game_won.connect(_on_game_won)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _process(delta: float) -> void:
	if _resize_pending:
		_resize_pending = false
		_rebuild()

	_tick_feed(delta)

	if not is_instance_valid(_player):
		_player = GameDirector.valid_player()
		if _player != null:
			_player.health.damaged.connect(_on_player_damaged)

	_vignette_alpha = maxf(0.0, _vignette_alpha - delta * 1.6)
	if _vignette_material != null:
		_vignette_material.set_shader_parameter("strength", _vignette_alpha)

	if _banner_timer > 0.0:
		_banner_timer -= delta
		_banner.modulate.a = clampf(_banner_timer, 0.0, 1.0)

	_poll_cd -= delta
	if _poll_cd <= 0.0:
		_poll_cd = 0.12
		_poll_world()

	_update_health()
	_update_keys()
	_update_weapons()
	_update_abilities()
	_update_debug()
	_update_overlay()


#region live readouts

func _update_health() -> void:
	var fraction: float = 0.0
	var hp: float = 0.0
	if _player != null and is_instance_valid(_player):
		fraction = _player.health_fraction()
		hp = _player.health.current
	_health_fill.size.x = 240.0 * fraction * _scale
	_health_fill.color = Color(0.85, 0.25, 0.25).lerp(Color(0.35, 0.85, 0.45), fraction)
	_health_text.text = "HP %d" % int(round(hp))


## Hidden at zero: a permanent "KEYS 0" is noise, and the count only matters once it is not zero.
func _update_keys() -> void:
	if _keys_text == null:
		return
	var count: int = 0
	if _player != null and is_instance_valid(_player):
		count = _player.keys
	_keys_text.visible = count > 0
	_keys_text.text = "KEYS  %d" % count


## One line per ability slot: name, and either "ready" or the seconds left. Deliberately
## no bar: the cooldown is the only state an ability has besides its name.
func _update_abilities() -> void:
	if _ability_labels.is_empty():
		return
	var holder: AbilityHolder = null
	if _player != null and is_instance_valid(_player):
		holder = _player.abilities as AbilityHolder
	for i: int in _ability_labels.size():
		var label: Label = _ability_labels[i]
		# The prompt follows the device: "Q" on a keyboard, "LB" on a pad. It follows a rebind too.
		var key_label: String = GameInput.describe_for_device("ability_%d" % (i + 1))
		var slot: AbilitySlot = holder.slot_at(i) if holder != null else null
		if slot == null or slot.data == null:
			label.text = "%s  -" % key_label
			label.modulate = Color(0.5, 0.55, 0.62)
			continue
		var title: String = slot.data.display_name.to_upper()
		# Upgrades read the same way weapons do, so a crate's effect is visible without a menu.
		if slot.level > 0:
			title += "  " + "+".repeat(slot.level)
		if slot.is_ready():
			label.text = "%s  %s" % [key_label, title]
			label.modulate = Color(0.85, 0.92, 1.0)
		else:
			label.text = "%s  %s  %0.1fs" % [key_label, title, slot.cooldown_left]
			label.modulate = Color(0.5, 0.55, 0.62)


func _update_weapons() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var holder := _player.weapons as WeaponHolder
	if holder == null:
		return
	var slot: WeaponSlot = holder.slot()
	if slot == null:
		_weapon_name.text = "UNARMED"
		_ammo_text.text = "--"
		_slots_text.text = ""
		_reload_bar.visible = false
		_reload_bg.visible = false
		return

	_weapon_name.text = slot.data.display_name
	if slot.level > 0:
		_weapon_name.text += "  " + "+".repeat(slot.level)
	_ammo_text.text = "%d / %d" % [slot.mag, slot.reserve]
	_ammo_text.modulate = Color(1.0, 0.45, 0.4) if slot.mag == 0 else Color.WHITE

	var parts: Array[String] = []
	var on_pad: bool = GameInput.using_gamepad()
	for i: int in holder.slots.size():
		var s: WeaponSlot = holder.slots[i]
		if on_pad:
			# There is no number key on a pad; the slot's own name is the marker.
			parts.append(("[%s]" % s.data.display_name) if i == holder.current else s.data.display_name)
			continue
		var bind: String = GameInput.describe_for_device("switch_%d" % (i + 1))
		var marker: String = ("[%s]" % bind) if i == holder.current else (" %s " % bind)
		parts.append("%s %s" % [marker, s.data.display_name])
	_slots_text.text = "  ".join(parts)

	var reloading: bool = holder.is_reloading()
	_reload_bar.visible = reloading
	_reload_bg.visible = reloading
	if reloading:
		_reload_bar.size.x = 150.0 * holder.reload_progress() * _scale


func _poll_world() -> void:
	var level: Node = GameDirector.current_level
	if level == null or not is_instance_valid(level):
		return
	var highest: float = 0.0
	var alert_state: String = "CALM"
	if level.has_method("alert_level"):
		highest = level.alert_level()
	_alert = highest
	if highest >= Tuning.awareness_alert:
		alert_state = "HUNTED"
	elif highest >= Tuning.awareness_suspicious:
		alert_state = "SUSPICIOUS"
	elif highest > 0.02:
		alert_state = "UNEASY"
	_alert_state = alert_state

	_alert_fill.size.x = 280.0 * clampf(highest, 0.0, 1.0) * _scale
	_alert_fill.color = Color(0.95, 0.75, 0.3).lerp(Color(0.95, 0.25, 0.2), clampf(highest, 0.0, 1.0))
	_alert_text.text = "THREAT: %s" % alert_state
	_alert_text.modulate = Color(1.0, 0.9, 0.6) if highest >= Tuning.awareness_suspicious else Color(0.75, 0.8, 0.85)


func _update_debug() -> void:
	_debug.visible = GameDirector.debug_info
	if not GameDirector.debug_info:
		return
	var lines: Array[String] = []
	lines.append("FPS %d   enemies %d   time %s" % [
		Engine.get_frames_per_second(), _enemy_count(), GameDirector.format_time(GameDirector.run_time),
	])
	lines.append("pos %s  aim %s" % [
		Vector2i(_player.global_position) if _player != null else Vector2i.ZERO,
		_short_dir(),
	])
	lines.append("god %s   noclip %s   reveal %s" % [
		GameDirector.god_mode, GameDirector.noclip, GameDirector.reveal,
	])
	lines.append(GameInput.pad_summary())
	lines.append("hp %.0f   kills %d   shots %d   alerts %d" % [
		_player.health.current if _player != null else 0.0,
		GameDirector.kills, GameDirector.shots_fired, GameDirector.enemies_alerted,
	])
	var level: Node = GameDirector.current_level
	if level != null and is_instance_valid(level) and (level.get("enemies") != null):
		var enemies: Array = level.get("enemies")
		for enemy: Variant in enemies:
			if not is_instance_valid(enemy):
				continue
			var e := enemy as Enemy
			if e == null or e.is_dead():
				continue
			lines.append("  %s  dist %d" % [
				e.debug_state(), int(e.global_position.distance_to(_player.global_position)) if _player != null else -1,
			])
	_debug.text = "\n".join(lines)


func _enemy_count() -> int:
	var level: Node = GameDirector.current_level
	if level != null and is_instance_valid(level) and level.has_method("alive_enemies"):
		return level.alive_enemies()
	return 0


func _short_dir() -> String:
	if _player == null:
		return "-"
	return "(%.2f, %.2f)" % [_player.aim_direction.x, _player.aim_direction.y]

#endregion


#region feed / banner / overlays

func _on_announce(text: String, _color: Color) -> void:
	_feed_lines.append(text)
	_feed_age.append(FEED_LIFE)
	while _feed_lines.size() > FEED_MAX:
		_feed_lines.remove_at(0)
		_feed_age.remove_at(0)
	if _feed != null:
		_feed.text = "\n".join(_feed_lines)


func _tick_feed(delta: float) -> void:
	if _feed_lines.is_empty():
		return
	var changed: bool = false
	for i: int in range(_feed_age.size() - 1, -1, -1):
		_feed_age[i] -= delta
		if _feed_age[i] <= 0.0:
			_feed_lines.remove_at(i)
			_feed_age.remove_at(i)
			changed = true
	if changed and _feed != null:
		_feed.text = "\n".join(_feed_lines)


## Big centred title, used for the level name.
func show_banner(text: String, color: Color = Color(0.95, 0.98, 1.0)) -> void:
	if _banner == null:
		return
	_banner.text = text
	_banner.modulate = color
	_banner_timer = 2.6


## Objective line in the top right ("Find the way out." etc).
func set_objective(text: String) -> void:
	if _objective != null:
		_objective.text = text


func _on_player_damaged(_amount: float, _source: Node, _hit: Vector2, _dir: Vector2) -> void:
	_vignette_alpha = minf(0.75, _vignette_alpha + 0.5)


func _on_game_over(reason: String) -> void:
	_show_overlay("dead", "YOU DIED", "%s\n\n%s\n\n[ %s ]  restart this level\n[ %s ]    back to title" % [
		reason, GameDirector.stats_line(),
		GameInput.describe_for_device("ui_accept"), GameInput.describe_for_device("ui_cancel"),
	], Color(1.0, 0.42, 0.4))


func _on_game_won() -> void:
	_show_overlay("won", "YOU ESCAPED",
		"%s\n\n[ %s ]  play again\n[ %s ]    back to title" % [
			GameDirector.stats_line(),
			GameInput.describe_for_device("ui_accept"), GameInput.describe_for_device("ui_cancel"),
		],
		Color(0.6, 1.0, 0.7))


func _show_overlay(kind: String, title: String, body: String, color: Color) -> void:
	_overlay_kind = kind
	_overlay.visible = true
	_overlay_title.text = title
	_overlay_title.modulate = color
	_overlay_body.text = body
	# The pause state is a real menu; death and victory are still text with a key hint, and the
	# menu must not sit underneath either of them.
	_pause_menu.visible = kind == "paused"
	if kind == "paused":
		# Opens on Continue, so Enter resumes: the muscle memory every player already has.
		_pause_menu.focus_item(&"continue")


func _hide_overlay() -> void:
	_overlay_kind = "none"
	_overlay.visible = false
	if _pause_menu != null:
		_pause_menu.visible = false


## Whatever the pause menu asks for. "Quit to Menu" deliberately leaves the checkpoint alone:
## pausing already refreshed it, so the title screen can offer to resume this level.
func _on_pause_menu(id: StringName) -> void:
	match id:
		&"settings":
			open_settings_menu()
		&"continue":
			GameDirector.set_paused(false)
		&"quit_to_menu":
			GameDirector.go_to_title()


## Settings, opened from the pause menu. They apply live, so closing them returns here with the
## game still paused, exactly where the player left it.
func open_settings_menu() -> void:
	if _settings_menu != null and is_instance_valid(_settings_menu):
		return
	_settings_menu = SettingsMenu.new()
	add_child(_settings_menu)


func _update_overlay() -> void:
	var paused: bool = GameDirector.is_paused()

	match _overlay_kind:
		"dead", "won":
			if Input.is_action_just_pressed(&"ui_accept") and not paused:
				AudioDirector.play(&"ui_click", -6.0)
				if _overlay_kind == "dead":
					GameDirector.retry_level()
				else:
					GameDirector.start_run()
				_hide_overlay()
			elif Input.is_action_just_pressed(&"ui_cancel") and not paused:
				# The hint under this text has always promised this, and nothing implemented
				# it: the pause action is ignored here because the run is already over.
				GameDirector.go_to_title()
			return
		"paused":
			if not paused:
				_hide_overlay()
			return

	if paused:
		_show_overlay("paused", "PAUSED", GameDirector.stats_line(), Color(0.92, 0.96, 1.0))


#endregion


#region layout

## Current HUD scale: 1.0 on a 720-tall screen, larger on a taller one. Public so the
## probe can report it alongside the camera zoom.
func ui_scale() -> float:
	return _scale


func _compute_scale() -> float:
	var height: float = get_viewport().get_visible_rect().size.y
	if height <= 0.0:
		return 1.0
	return clampf(height / maxf(1.0, Tuning.ui_reference_height), 0.5, 4.0)


func _on_viewport_resized() -> void:
	# Any size change, not only one that changes the scale. The scale is derived from height alone, so a
	# width-only change used to skip the rebuild and leave the pause menu (placed from the viewport) at
	# its old x while the anchored title and stats moved. Deferred, so a resize during a signal is safe.
	_resize_pending = true


## Rebuilds the layout at the current scale. Cheap, and it cannot leave a half-rescaled
## layout behind, which is exactly the kind of bug a window resize would otherwise cause.
func _rebuild() -> void:
	_scale = _compute_scale()
	_root.free()
	_ability_labels.clear()
	_build()
	# A window resize while paused rebuilds the overlay the pause menu lives in, so put it back
	# the way the player left it instead of leaving them staring at a bare PAUSED title.
	if _overlay_kind == "paused":
		_show_overlay("paused", "PAUSED", GameDirector.stats_line(), Color(0.92, 0.96, 1.0))


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	# `set_anchors_and_offsets_preset`, not `set_anchors_preset`: the latter leaves the
	# offsets alone, which makes a FULL_RECT control zero-sized when its parent is another
	# Control rather than a CanvasLayer. The overlay below is affected the same way.
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# The HUD root is the *first* child, always. The settings menu is a sibling added later, so a
	# rebuild (a window resize, or a resolution change from inside that menu) used to append the new
	# root after it and draw the pause overlay straight over the settings panel. Sibling order is draw
	# order in a canvas layer, so this is the whole fix.
	move_child(_root, 0)

	# --- damage vignette, first so every readout stays legible on top of it.
	# A plain full-screen tint would wash the whole scene out, so this is an
	# edge-only vignette driven by a tiny shader.
	var vignette_shader := Shader.new()
	vignette_shader.code = VIGNETTE_SHADER
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = vignette_shader
	_vignette = _rect(_root, Control.PRESET_FULL_RECT, 0.0, 0.0, 0.0, 0.0, Color.WHITE)
	_vignette.material = _vignette_material

	# --- keys, above the health readout and only while carrying any
	_keys_text = _label(_root, Control.PRESET_BOTTOM_LEFT, 28.0, -142.0, 268.0, -118.0, 15,
		HORIZONTAL_ALIGNMENT_LEFT, Color(1.0, 0.85, 0.4))
	_keys_text.visible = false

	# --- health, bottom left
	_health_text = _label(_root, Control.PRESET_BOTTOM_LEFT, 28.0, -114.0, 268.0, -90.0, 16,
		HORIZONTAL_ALIGNMENT_LEFT, Color(0.85, 0.9, 0.95))
	var health_bg := _rect(_root, Control.PRESET_BOTTOM_LEFT, 28.0, -86.0, 268.0, -66.0,
		Color(0.08, 0.09, 0.11, 0.85))
	_health_fill = _rect(_root, Control.PRESET_BOTTOM_LEFT, 30.0, -84.0, 266.0, -68.0,
		Color(0.35, 0.85, 0.45))
	_health_fill.size.x = 240.0 * _scale
	health_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# --- weapon, bottom right
	_weapon_name = _label(_root, Control.PRESET_BOTTOM_RIGHT, -320.0, -104.0, -28.0, -80.0, 20,
		HORIZONTAL_ALIGNMENT_RIGHT, Color(0.92, 0.96, 1.0))
	_ammo_text = _label(_root, Control.PRESET_BOTTOM_RIGHT, -320.0, -80.0, -28.0, -52.0, 26,
		HORIZONTAL_ALIGNMENT_RIGHT, Color.WHITE)
	_slots_text = _label(_root, Control.PRESET_BOTTOM_RIGHT, -420.0, -50.0, -28.0, -30.0, 15,
		HORIZONTAL_ALIGNMENT_RIGHT, Color(0.7, 0.76, 0.84))
	_reload_bg = _rect(_root, Control.PRESET_BOTTOM_RIGHT, -180.0, -26.0, -30.0, -20.0,
		Color(0.1, 0.11, 0.13, 0.9))
	_reload_bar = _rect(_root, Control.PRESET_BOTTOM_RIGHT, -180.0, -26.0, -180.0, -20.0,
		Color(0.95, 0.85, 0.45))

	# --- abilities, one line each, above the weapon readout. The key labels mirror
	# GameInput's ability_1 / ability_2 bindings.
	for i: int in AbilityHolder.MAX_SLOTS:
		var key_label: String = GameInput.describe_for_device("ability_%d" % (i + 1))
		var label := _label(_root, Control.PRESET_BOTTOM_RIGHT,
			-420.0, -178.0 + float(i) * 24.0, -28.0, -154.0 + float(i) * 24.0, 15,
			HORIZONTAL_ALIGNMENT_RIGHT, Color(0.72, 0.78, 0.9))
		label.text = "%s  -" % key_label
		_ability_labels.append(label)

	# --- threat meter, top centre
	var alert_bg := _rect(_root, Control.PRESET_CENTER_TOP, -140.0, 20.0, 140.0, 32.0,
		Color(0.08, 0.09, 0.11, 0.85))
	alert_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_fill = _rect(_root, Control.PRESET_CENTER_TOP, -139.0, 21.0, -139.0, 31.0,
		Color(0.95, 0.75, 0.3))
	_alert_text = _label(_root, Control.PRESET_CENTER_TOP, -200.0, 36.0, 200.0, 58.0, 15,
		HORIZONTAL_ALIGNMENT_CENTER, Color(0.8, 0.85, 0.9))

	# --- objective, top right
	_objective = _label(_root, Control.PRESET_TOP_RIGHT, -460.0, 20.0, -28.0, 60.0, 16,
		HORIZONTAL_ALIGNMENT_RIGHT, Color(0.72, 0.82, 0.92))

	# --- message feed, above the health bar
	_feed = _label(_root, Control.PRESET_CENTER_BOTTOM, -360.0, -170.0, 360.0, -110.0, 16,
		HORIZONTAL_ALIGNMENT_CENTER, Color.WHITE)
	_feed.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

	# --- level banner
	_banner = _label(_root, Control.PRESET_CENTER, -400.0, -110.0, 400.0, -40.0, 42,
		HORIZONTAL_ALIGNMENT_CENTER, Color.WHITE)
	_banner.modulate.a = 0.0

	# --- debug readout
	_debug = _label(_root, Control.PRESET_TOP_LEFT, 28.0, 90.0, 620.0, 420.0, 14,
		HORIZONTAL_ALIGNMENT_LEFT, Color(0.75, 1.0, 0.8))
	_debug.visible = false

	_build_overlay()


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_root.add_child(_overlay)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.04, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(shade)

	_overlay_title = _label(_overlay, Control.PRESET_CENTER, -400.0, -170.0, 400.0, -90.0, 54,
		HORIZONTAL_ALIGNMENT_CENTER, Color.WHITE)
	_overlay_body = _label(_overlay, Control.PRESET_CENTER, -400.0, -80.0, 400.0, 40.0, 20,
		HORIZONTAL_ALIGNMENT_CENTER, Color(0.85, 0.9, 0.95))

	# Paused menu, centred under the stats line. Horizontally it has to be worked out from the viewport:
	# the title and the stats are anchored to the centre (so they follow a resize), but a `MenuList` is
	# placed in pixels, so fixed reference coordinates left the buttons off-centre the moment the window
	# was not 1280 wide.
	var reference_width: float = get_viewport().get_visible_rect().size.x / maxf(0.001, _scale)
	_pause_menu = MenuList.new()
	_pause_menu.configure(Rect2(reference_width * 0.5 - 160.0, 330.0, 320.0,
		3.0 * MenuList.ROW_HEIGHT), _scale)
	_pause_menu.add_item(&"settings", "SETTINGS")
	_pause_menu.add_item(&"continue", "CONTINUE")
	_pause_menu.add_item(&"quit_to_menu", "QUIT TO MENU")
	_pause_menu.activated.connect(_on_pause_menu)
	_pause_menu.visible = false
	_overlay.add_child(_pause_menu)


func _label(parent: Control, preset: int, l: float, t: float, r: float, b: float, font_size: int,
		halign: int, color: Color) -> Label:
	var label := Label.new()
	label.set_anchors_preset(preset, false)
	# `l..b` and `font_size` are written in reference (720-tall) units and scaled here, so
	# every call site above reads at a fixed size no matter the window.
	label.offset_left = l * _scale
	label.offset_top = t * _scale
	label.offset_right = r * _scale
	label.offset_bottom = b * _scale
	label.horizontal_alignment = halign as HorizontalAlignment
	label.add_theme_font_size_override("font_size", int(round(float(font_size) * _scale)))
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _rect(parent: Control, preset: int, l: float, t: float, r: float, b: float, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(preset, false)
	rect.offset_left = l * _scale
	rect.offset_top = t * _scale
	rect.offset_right = r * _scale
	rect.offset_bottom = b * _scale
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

#endregion
