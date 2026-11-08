extends Node
## Registers every input action at runtime, and lets the player rebind them.
##
## Why runtime instead of Project Settings? Because the action list lives in version control as readable
## GDScript, it can never be silently corrupted by a bad project.godot entry, and adding a keybind is a
## one-line change. Autoloads run before the main scene, so every action exists before any game code asks
## for it.
##
## Bindings are *data*: `DEFAULT_SPECS` below is the shipped default, and an entry for an action in
## `user://bindings.cfg` replaces it. That split is what makes rebinding possible without mutating code,
## and it means an action added in a later version still gets its default for a player whose file predates
## it. Keys are stored as `physical_keycode`, so a binding means the same physical key on any layout.
##
## The titles/labels the settings menu and the title screen show are generated from the live map, so a
## rebind cannot leave text behind that lies about it.

## Emitted whenever a binding changes or is reset, so any open menu can re-read the map.
signal bindings_changed()
## Emitted when the player switches between keyboard/mouse and a gamepad, so prompts can follow.
signal device_changed(gamepad: bool)

const BINDINGS_PATH: String = "user://bindings.cfg"
const BINDINGS_FILE: String = "bindings.cfg"

## How every action is presented, in display order. `group` is the section heading in the rebinding UI.
## Debug actions (the cheats) share the same machinery but are their own group: never listed for
## rebinding, and with no events at all outside a debug build -- see `cheats_enabled`.
const META: Dictionary = {
	"move_up": {"label": "Move up", "group": "Movement"},
	"move_down": {"label": "Move down", "group": "Movement"},
	"move_left": {"label": "Move left", "group": "Movement"},
	"move_right": {"label": "Move right", "group": "Movement"},
	"dash": {"label": "Dash", "group": "Movement"},
	"fire": {"label": "Fire", "group": "Combat"},
	"reload": {"label": "Reload", "group": "Combat"},
	"ability_1": {"label": "Ability 1", "group": "Combat"},
	"ability_2": {"label": "Ability 2", "group": "Combat"},
	"aim_left": {"label": "Aim left", "group": "Aiming"},
	"aim_right": {"label": "Aim right", "group": "Aiming"},
	"aim_up": {"label": "Aim up", "group": "Aiming"},
	"aim_down": {"label": "Aim down", "group": "Aiming"},
	"switch_1": {"label": "Weapon 1", "group": "Weapons"},
	"switch_2": {"label": "Weapon 2", "group": "Weapons"},
	"switch_3": {"label": "Weapon 3", "group": "Weapons"},
	"switch_next": {"label": "Next weapon", "group": "Weapons"},
	"switch_prev": {"label": "Previous weapon", "group": "Weapons"},
	"interact": {"label": "Interact / doors", "group": "Interaction"},
	"pause": {"label": "Pause", "group": "System"},
	"debug_god": {"label": "God mode", "group": "Debug"},
	"debug_noclip": {"label": "Noclip", "group": "Debug"},
	"debug_info": {"label": "Debug readout", "group": "Debug"},
	"debug_reveal": {"label": "Lift the fog", "group": "Debug"},
	"debug_spawn": {"label": "Spawn enemy", "group": "Debug"},
	"debug_alert_all": {"label": "Alert everything", "group": "Debug"},
	"debug_give": {"label": "Give all weapons", "group": "Debug"},
	"debug_slowmo": {"label": "Slow motion", "group": "Debug"},
}

## Default bindings, in the same plain-data shape `bindings.cfg` stores: a list of
## `{type = "key", code = physical_keycode}` or `{type = "mouse", button = MouseButton}`.
##
## Data rather than ready-made `InputEvent`s so a default can be saved, compared and described by the
## same code that handles a rebind, and so nothing can share and mutate one event object.
const DEFAULT_SPECS: Dictionary = {
	"move_up": [
		{"type": "key", "code": KEY_W},
		{"type": "joy_axis", "axis": JOY_AXIS_LEFT_Y, "value": -1.0},
	],
	"move_down": [
		{"type": "key", "code": KEY_S},
		{"type": "joy_axis", "axis": JOY_AXIS_LEFT_Y, "value": 1.0},
	],
	"move_left": [
		{"type": "key", "code": KEY_A},
		{"type": "joy_axis", "axis": JOY_AXIS_LEFT_X, "value": -1.0},
	],
	"move_right": [
		{"type": "key", "code": KEY_D},
		{"type": "joy_axis", "axis": JOY_AXIS_LEFT_X, "value": 1.0},
	],
	"dash": [
		{"type": "key", "code": KEY_SHIFT},
		{"type": "joy_button", "button": JOY_BUTTON_B},
	],
	"fire": [
		{"type": "mouse", "button": MOUSE_BUTTON_LEFT},
		# The trigger is an axis, not a button, on every pad Godot supports.
		{"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "value": 1.0},
	],
	"reload": [
		{"type": "key", "code": KEY_R},
		{"type": "joy_button", "button": JOY_BUTTON_X},
	],
	"aim_left": [{"type": "joy_axis", "axis": JOY_AXIS_RIGHT_X, "value": -1.0}],
	"aim_right": [{"type": "joy_axis", "axis": JOY_AXIS_RIGHT_X, "value": 1.0}],
	"aim_up": [{"type": "joy_axis", "axis": JOY_AXIS_RIGHT_Y, "value": -1.0}],
	"aim_down": [{"type": "joy_axis", "axis": JOY_AXIS_RIGHT_Y, "value": 1.0}],
	"ability_1": [
		{"type": "key", "code": KEY_Q},
		{"type": "joy_button", "button": JOY_BUTTON_LEFT_SHOULDER},
	],
	"ability_2": [
		{"type": "key", "code": KEY_E},
		{"type": "joy_button", "button": JOY_BUTTON_RIGHT_SHOULDER},
	],
	"switch_1": [{"type": "key", "code": KEY_1}],
	"switch_2": [{"type": "key", "code": KEY_2}],
	"switch_3": [{"type": "key", "code": KEY_3}],
	"switch_next": [
		{"type": "mouse", "button": MOUSE_BUTTON_WHEEL_DOWN},
		{"type": "joy_button", "button": JOY_BUTTON_DPAD_RIGHT},
	],
	"switch_prev": [
		{"type": "mouse", "button": MOUSE_BUTTON_WHEEL_UP},
		{"type": "joy_button", "button": JOY_BUTTON_DPAD_LEFT},
	],
	"interact": [
		{"type": "key", "code": KEY_F},
		{"type": "joy_button", "button": JOY_BUTTON_Y},
	],
	"pause": [
		{"type": "key", "code": KEY_ESCAPE},
		{"type": "joy_button", "button": JOY_BUTTON_START},
	],
	"debug_god": [{"type": "key", "code": KEY_F1}],
	"debug_noclip": [{"type": "key", "code": KEY_F2}],
	"debug_info": [{"type": "key", "code": KEY_F3}],
	"debug_reveal": [{"type": "key", "code": KEY_F4}],
	"debug_spawn": [{"type": "key", "code": KEY_F5}],
	"debug_alert_all": [{"type": "key", "code": KEY_F6}],
	"debug_give": [{"type": "key", "code": KEY_F7}],
	"debug_slowmo": [{"type": "key", "code": KEY_F9}],
}

const DEBUG_GROUP: String = "Debug"
## Groups the player cannot rebind or see in the Controls list: the cheats, and aiming, which is the mouse
## or the right stick and nothing else.
const FIXED_GROUPS: Array[String] = [DEBUG_GROUP, "Aiming"]
## Function keys belong to the debug keys. No other action may be bound to one, in any build, so a
## cheat can never share a key with a game action and the defaults never have to move.
const RESERVED_KEY_FIRST: Key = KEY_F1
const RESERVED_KEY_LAST: Key = KEY_F12

## Actions the title screen lists. A subset: the HUD already shows the weapon slots, and the debug keys
## only appear in a debug build. Aim is not an action (yet) -- it follows the mouse.
const TITLE_ACTIONS: Array[String] = [
	"move_up", "move_down", "move_left", "move_right",
	"fire", "reload", "ability_1", "ability_2", "interact", "dash", "pause",
]

## Menus are built on Godot's `ui_*` actions, and on this build their defaults are keyboard-only, so a
## controller cannot confirm or back out of anything. These fill in the pad side only: the engine's own
## events (Enter, Space, the arrows) are left alone, because menus still have to work with a keyboard.
const UI_PAD_SPECS: Dictionary = {
	"ui_accept": [{"type": "joy_button", "button": JOY_BUTTON_A}],
	"ui_cancel": [{"type": "joy_button", "button": JOY_BUTTON_B}],
	"ui_up": [{"type": "joy_button", "button": JOY_BUTTON_DPAD_UP}],
	"ui_down": [{"type": "joy_button", "button": JOY_BUTTON_DPAD_DOWN}],
	"ui_left": [{"type": "joy_button", "button": JOY_BUTTON_DPAD_LEFT}],
	"ui_right": [{"type": "joy_button", "button": JOY_BUTTON_DPAD_RIGHT}],
}

## Only the actions the player has rebound. Absence means "use the default", which is how a new action in
## a later version still works for an existing `bindings.cfg`.
var _overrides: Dictionary = {}

## True when the last input came from a gamepad. Everything that shows a prompt reads this, so the HUD
## says "LB" on a pad and "Q" on a keyboard without either side needing to know the other exists.
var _gamepad_in_use: bool = false
## The last pad press or stick push, for the debug readout: the fastest way to answer "can Godot see
## this controller at all, and what does it call its buttons".
var _last_pad_input: String = ""


func _ready() -> void:
	# Device detection has to keep working in menus, which run while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A pad that is already connected is the likely input on a handheld, so start on pad prompts rather
	# than waiting for the first stick movement. Any real input corrects it immediately.
	_gamepad_in_use = not Input.get_connected_joypads().is_empty()
	load_bindings()
	register_all()


## The right stick, deadzoned. Zero when there is no pad or the stick is at rest.
##
## Four actions rather than a raw axis read, so the stick goes through the same input map and deadzone
## handling as everything else. They are fixed to the right stick: see `FIXED_GROUPS`.
func aim_vector() -> Vector2:
	return Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down",
		Tuning.gamepad_aim_deadzone)


func using_gamepad() -> bool:
	return _gamepad_in_use


## Last device wins. Keys and clicks switch to the mouse; anything from a pad switches to the pad. Mouse
## *motion* switches too, with a small threshold, because a player who reaches for the mouse to aim has
## not pressed anything yet.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			_last_pad_input = describe(event)
		_set_device(true)
	elif event is InputEventJoypadMotion:
		# Only a deliberate push: a resting stick emits motion constantly and would fill the readout
		# with noise.
		var motion: InputEventJoypadMotion = event
		if absf(motion.axis_value) > 0.5:
			_last_pad_input = describe(motion)
		_set_device(true)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		_set_device(false)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_set_device(false)
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 1.0:
		_set_device(false)


## What the engine currently sees of gamepads, for the debug readout. With no pad it says so; with one
## it names each device and the last button or stick pushed, which is what makes a mapping problem
## visible instead of guesswork.
func pad_summary() -> String:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		return "gamepad: none connected"
	var names: Array[String] = []
	for id: int in pads:
		names.append("%s #%d" % [Input.get_joy_name(id), id])
	var last: String = _last_pad_input if not _last_pad_input.is_empty() else "-"
	return "gamepad: %s   last: %s" % [", ".join(names), last]


func _set_device(gamepad: bool) -> void:
	if _gamepad_in_use == gamepad:
		return
	_gamepad_in_use = gamepad
	device_changed.emit(gamepad)


#region registering

## Builds the InputMap from defaults, then applies whatever the player changed. Idempotent, so
## `reset_all` is the same path as startup.
func register_all() -> void:
	for action: String in META:
		_apply(action, specs_for(action))
	_fill_ui_pad_bindings()


## Adds only the missing pad events to the built-in menu actions, leaving the engine's keyboard events
## untouched. Menus must work with both devices, and rebinding must not be able to break `ui_cancel`.
func _fill_ui_pad_bindings() -> void:
	for action: String in UI_PAD_SPECS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for spec: Variant in UI_PAD_SPECS[action]:
			if not (spec is Dictionary):
				continue
			var event: InputEvent = event_from_spec(spec)
			if event == null:
				continue
			var present: bool = false
			for existing: InputEvent in InputMap.action_get_events(action):
				if events_match(existing, event):
					present = true
					break
			if not present:
				InputMap.action_add_event(action, event)


## The bindings an action should have right now: the player's, or the default.
func specs_for(action: String) -> Array:
	if _overrides.has(action):
		return (_overrides[action] as Array).duplicate(true)
	return (DEFAULT_SPECS.get(action, []) as Array).duplicate(true)


## Replaces one action's bindings with `events` outright. Used by tools and tests; the menu uses
## `rebind()`, which keeps the other device's bindings.
func set_action_events(action: String, events: Array[InputEvent]) -> void:
	if not is_rebindable(action):
		return
	for event: InputEvent in events:
		if is_reserved(event):
			return
	var specs: Array = _specs_from_events(events)
	if specs.is_empty():
		return
	_overrides[action] = specs
	_apply(action, specs)
	save_bindings()
	bindings_changed.emit()


## Rebinds one action to a single event, replacing the bindings for *that device* and leaving the
## other device alone.
##
## This matters once every action has a key and a pad binding: replacing everything would take the
## mouse away from Fire when a pad player moves it to a face button, and take the pad away from a
## keyboard player who presses a key. One action, one binding per device, is the rule the menu shows.
func rebind(action: String, event: InputEvent) -> void:
	if not is_rebindable(action) or is_reserved(event):
		return
	var new_spec: Dictionary = spec_from_event(event)
	if new_spec.is_empty():
		return
	var want_pad: bool = _is_pad_event(event)
	var specs: Array = []
	for existing: InputEvent in InputMap.action_get_events(action):
		if _is_pad_event(existing) != want_pad:
			specs.append(spec_from_event(existing))
	specs.append(new_spec)
	_overrides[action] = specs
	_apply(action, specs)
	save_bindings()
	bindings_changed.emit()


static func _is_pad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func _specs_from_events(events: Array[InputEvent]) -> Array:
	var specs: Array = []
	for event: InputEvent in events:
		var spec: Dictionary = spec_from_event(event)
		if not spec.is_empty():
			specs.append(spec)
	return specs


## Puts one action back to its shipped default.
func reset_action(action: String) -> void:
	if not _overrides.has(action):
		return
	_overrides.erase(action)
	_apply(action, specs_for(action))
	save_bindings()
	bindings_changed.emit()


## Puts every action back, and removes the file so the defaults can keep evolving between versions.
func reset_all() -> void:
	_overrides.clear()
	register_all()
	save_bindings()
	bindings_changed.emit()


func is_rebound(action: String) -> bool:
	return _overrides.has(action)


func _apply(action: String, specs: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.25)
	# A release build still has the cheat actions, so code asking about them stays valid, but nothing
	# can trigger them.
	if is_debug_action(action) and not cheats_enabled():
		return
	for spec: Variant in specs:
		if not (spec is Dictionary):
			continue
		var event: InputEvent = event_from_spec(spec)
		if event != null:
			InputMap.action_add_event(action, event)

#endregion


#region conflicts and comparison

## The action that already uses one of `events`, or "" when none does.
##
## Two actions on one key is a bug the player cannot see: the later action wins silently. Refusing the
## bind is better than accepting it and letting them find out in a fight.
func conflict_for(ignore: String, events: Array[InputEvent]) -> String:
	for other: String in META:
		if other == ignore:
			continue
		for existing: InputEvent in InputMap.action_get_events(other):
			for candidate: InputEvent in events:
				if events_match(candidate, existing):
					return other
	return ""


## Cheats only exist in debug builds (the editor, and debug exports). A release export has the actions
## but no keys on them, and `GameDirector` ignores them too.
func cheats_enabled() -> bool:
	return OS.is_debug_build()


static func is_debug_action(action: String) -> bool:
	return String((META.get(action, {}) as Dictionary).get("group", "")) == DEBUG_GROUP


func is_rebindable(action: String) -> bool:
	return META.has(action) and not FIXED_GROUPS.has(String((META[action] as Dictionary).get("group", "")))


## True for a key no game action may use (F1-F12, which belong to the debug keys).
func is_reserved(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key: InputEventKey = event
	var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	return code >= RESERVED_KEY_FIRST and code <= RESERVED_KEY_LAST


func _spec_reserved(spec: Dictionary) -> bool:
	var event: InputEvent = event_from_spec(spec)
	return event != null and is_reserved(event)


## Whether two events would mean the same press. Compared field by field rather than with `is_match`,
## which also weighs modifiers we deliberately do not bind: pressing Ctrl+Z stores the bare Z.
static func events_match(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka: InputEventKey = a
		var kb: InputEventKey = b
		return ka.physical_keycode != KEY_NONE and ka.physical_keycode == kb.physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ma: InputEventJoypadMotion = a
		var mb: InputEventJoypadMotion = b
		# The same axis pushed the other way is a different control.
		return ma.axis == mb.axis and signf(ma.axis_value) == signf(mb.axis_value)
	return false

#endregion


#region presentation

## A binding as the player should read it: "W", "Shift", "LMB", "Wheel down", "LB", "Right stick ->".
static func describe(event: InputEvent) -> String:
	if event is InputEventKey:
		var key: InputEventKey = event
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		var text: String = OS.get_keycode_string(code)
		return text if not text.is_empty() else "?"
	if event is InputEventMouseButton:
		return mouse_name((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		return joy_button_name((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var axis: InputEventJoypadMotion = event
		return axis_name(axis.axis, axis.axis_value)
	return "?"


## Pad buttons, named the way they are printed on the pad rather than by Godot's enum.
static func joy_button_name(button: JoyButton) -> String:
	match button:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		JOY_BUTTON_BACK:
			return "Back"
		JOY_BUTTON_START:
			return "Start"
		JOY_BUTTON_LEFT_STICK:
			return "L3"
		JOY_BUTTON_RIGHT_STICK:
			return "R3"
		JOY_BUTTON_DPAD_UP:
			return "D-pad up"
		JOY_BUTTON_DPAD_DOWN:
			return "D-pad down"
		JOY_BUTTON_DPAD_LEFT:
			return "D-pad left"
		JOY_BUTTON_DPAD_RIGHT:
			return "D-pad right"
		_:
			return "Pad %d" % int(button)


## A stick or trigger direction. Triggers have no direction, so they are named once; sticks read as an
## arrow so "Left stick left" does not need repeating in every row.
static func axis_name(axis: JoyAxis, value: float) -> String:
	match axis:
		JOY_AXIS_LEFT_X:
			return "Left stick " + ("right" if value > 0.0 else "left")
		JOY_AXIS_LEFT_Y:
			return "Left stick " + ("down" if value > 0.0 else "up")
		JOY_AXIS_RIGHT_X:
			return "Right stick " + ("right" if value > 0.0 else "left")
		JOY_AXIS_RIGHT_Y:
			return "Right stick " + ("down" if value > 0.0 else "up")
		JOY_AXIS_TRIGGER_LEFT:
			return "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "RT"
		_:
			return "Axis %d" % int(axis)


static func mouse_name(button: MouseButton) -> String:
	match button:
		MOUSE_BUTTON_LEFT:
			return "LMB"
		MOUSE_BUTTON_RIGHT:
			return "RMB"
		MOUSE_BUTTON_MIDDLE:
			return "MMB"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel down"
		MOUSE_BUTTON_XBUTTON1:
			return "Mouse 4"
		MOUSE_BUTTON_XBUTTON2:
			return "Mouse 5"
		_:
			return "Mouse %d" % int(button)


## Everything bound to one action, joined the way the menu shows it: "W / Up".
func describe_action(action: String) -> String:
	var parts: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action):
		parts.append(describe(event))
	return " / ".join(parts) if not parts.is_empty() else "unbound"


## One action for the device in hand, for a prompt: "Q" on a keyboard, "LB" on a pad. Falls back to the
## first binding of any kind when the action has nothing for that device, so an unbound-on-pad action
## still says something rather than nothing.
func describe_for_device(action: String) -> String:
	var want_pad: bool = _gamepad_in_use
	for event: InputEvent in InputMap.action_get_events(action):
		if want_pad and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
			return describe(event)
		if not want_pad and (event is InputEventKey or event is InputEventMouseButton):
			return describe(event)
	return describe_action(action)


func action_label(action: String) -> String:
	var meta: Dictionary = META.get(action, {})
	return String(meta.get("label", action))


## Group headings in display order, for the rebinding UI. Never a fixed group: those bindings are not
## the player's to move.
func groups() -> Array[String]:
	var out: Array[String] = []
	for action: String in META:
		var group: String = String((META[action] as Dictionary).get("group", ""))
		if FIXED_GROUPS.has(group):
			continue
		if not out.has(group):
			out.append(group)
	return out


func actions_in(group: String) -> Array[String]:
	var out: Array[String] = []
	for action: String in META:
		if String((META[action] as Dictionary).get("group", "")) == group:
			out.append(action)
	return out


## The title screen's control table, as [what to press, what it does] pairs. Generated from the live map
## and from the device in hand, so a rebind or a controller cannot leave this screen lying about the keys.
func title_rows() -> Array:
	var rows: Array = [["Mouse" if not _gamepad_in_use else "Right stick", "Aim"]]
	for action: String in TITLE_ACTIONS:
		rows.append([describe_for_device(action), action_label(action)])
	return rows


## The debug keys on one line, so the title screen can mention them without a nine-row table.
func debug_short_text() -> String:
	var parts: Array[String] = []
	for action: String in actions_in(DEBUG_GROUP):
		parts.append("%s %s" % [describe_action(action), action_label(action)])
	return "   ".join(parts)

#endregion


#region persistence

func save_bindings() -> void:
	# Nothing rebound: remove the file rather than leave an empty one behind, so a future change to the
	# defaults reaches this player.
	if _overrides.is_empty():
		var dir := DirAccess.open("user://")
		if dir != null and dir.file_exists(BINDINGS_FILE):
			dir.remove(BINDINGS_FILE)
		return
	var config := ConfigFile.new()
	for action: String in _overrides:
		config.set_value("bindings", action, _overrides[action])
	var error: Error = config.save(BINDINGS_PATH)
	if error != OK:
		push_warning("Could not save bindings to %s (error %d)." % [BINDINGS_PATH, error])


## Reads the file into `_overrides`, keeping only actions that still exist and entries that still make
## sense. A half-written or hand-edited file must not leave the game with an unusable action.
func load_bindings() -> void:
	_overrides.clear()
	var config := ConfigFile.new()
	if config.load(BINDINGS_PATH) != OK:
		return
	for action: String in META:
		# A fixed action rebound by an older version goes back to its default.
		if not is_rebindable(action) or not config.has_section_key("bindings", action):
			continue
		var stored: Variant = config.get_value("bindings", action, [])
		if not (stored is Array):
			continue
		var specs: Array = []
		for entry: Variant in stored:
			# A function key saved before they were reserved falls back to the default.
			if entry is Dictionary and event_from_spec(entry) != null and not _spec_reserved(entry):
				specs.append(entry)
		if not specs.is_empty():
			_overrides[action] = specs

#endregion


#region data <-> events

static func event_from_spec(spec: Dictionary) -> InputEvent:
	match String(spec.get("type", "")):
		"key":
			var code: int = int(spec.get("code", 0))
			if code == 0:
				return null
			var key := InputEventKey.new()
			key.physical_keycode = code as Key
			return key
		"mouse":
			var button: int = int(spec.get("button", -1))
			if button < 0:
				return null
			var mouse := InputEventMouseButton.new()
			mouse.button_index = button as MouseButton
			return mouse
		"joy_button":
			var pad_button: int = int(spec.get("button", -1))
			if pad_button < 0:
				return null
			var pressed := InputEventJoypadButton.new()
			pressed.button_index = pad_button as JoyButton
			pressed.pressed = true
			return pressed
		"joy_axis":
			var axis_index: int = int(spec.get("axis", -1))
			if axis_index < 0:
				return null
			var motion := InputEventJoypadMotion.new()
			motion.axis = axis_index as JoyAxis
			# The sign is what defines the direction; the magnitude is the player's to push.
			motion.axis_value = 1.0 if float(spec.get("value", 1.0)) >= 0.0 else -1.0
			return motion
	return null


static func spec_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key: InputEventKey = event
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_NONE:
			return {}
		return {"type": "key", "code": int(code)}
	if event is InputEventMouseButton:
		return {"type": "mouse", "button": int((event as InputEventMouseButton).button_index)}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "button": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var axis: InputEventJoypadMotion = event
		return {
			"type": "joy_axis",
			"axis": int(axis.axis),
			"value": 1.0 if axis.axis_value >= 0.0 else -1.0,
		}
	return {}

#endregion


## Movement vector from WASD, normalised. Screen-relative by design: W is always
## "up on the monitor", never "forward toward the mouse".
func move_vector() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
