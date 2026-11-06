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

const BINDINGS_PATH: String = "user://bindings.cfg"
const BINDINGS_FILE: String = "bindings.cfg"

## How every action is presented, in display order. `group` is the section heading in the rebinding UI.
## Debug actions share the same machinery: they are simply their own group, hidden outside debug builds.
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
	"move_up": [ {"type": "key", "code": KEY_W}],
	"move_down": [ {"type": "key", "code": KEY_S}],
	"move_left": [ {"type": "key", "code": KEY_A}],
	"move_right": [ {"type": "key", "code": KEY_D}],
	"dash": [ {"type": "key", "code": KEY_SHIFT}],
	"fire": [ {"type": "mouse", "button": MOUSE_BUTTON_LEFT}],
	"reload": [ {"type": "key", "code": KEY_R}],
	"ability_1": [ {"type": "key", "code": KEY_Q}],
	"ability_2": [ {"type": "key", "code": KEY_E}],
	"switch_1": [ {"type": "key", "code": KEY_1}],
	"switch_2": [ {"type": "key", "code": KEY_2}],
	"switch_3": [ {"type": "key", "code": KEY_3}],
	"switch_next": [ {"type": "mouse", "button": MOUSE_BUTTON_WHEEL_DOWN}],
	"switch_prev": [ {"type": "mouse", "button": MOUSE_BUTTON_WHEEL_UP}],
	"interact": [ {"type": "key", "code": KEY_F}],
	"pause": [ {"type": "key", "code": KEY_ESCAPE}],
	"debug_god": [ {"type": "key", "code": KEY_F1}],
	"debug_noclip": [ {"type": "key", "code": KEY_F2}],
	"debug_info": [ {"type": "key", "code": KEY_F3}],
	"debug_reveal": [ {"type": "key", "code": KEY_F4}],
	"debug_spawn": [ {"type": "key", "code": KEY_F5}],
	"debug_alert_all": [ {"type": "key", "code": KEY_F6}],
	"debug_give": [ {"type": "key", "code": KEY_F7}],
	"debug_slowmo": [ {"type": "key", "code": KEY_F9}],
}

## Actions the title screen lists. A subset: the HUD already shows the weapon slots, and the debug keys
## only appear in a debug build. Aim is not an action (yet) -- it follows the mouse.
const TITLE_ACTIONS: Array[String] = [
	"move_up", "move_down", "move_left", "move_right",
	"fire", "reload", "ability_1", "ability_2", "interact", "dash", "pause",
]

## Only the actions the player has rebound. Absence means "use the default", which is how a new action in
## a later version still works for an existing `bindings.cfg`.
var _overrides: Dictionary = {}


func _ready() -> void:
	load_bindings()
	register_all()


#region registering

## Builds the InputMap from defaults, then applies whatever the player changed. Idempotent, so
## `reset_all` is the same path as startup.
func register_all() -> void:
	for action: String in META:
		_apply(action, specs_for(action))


## The bindings an action should have right now: the player's, or the default.
func specs_for(action: String) -> Array:
	if _overrides.has(action):
		return (_overrides[action] as Array).duplicate(true)
	return (DEFAULT_SPECS.get(action, []) as Array).duplicate(true)


## Replaces one action's bindings in the InputMap. An action with no events would be silently unusable,
## so an empty list is refused rather than applied.
func set_action_events(action: String, events: Array[InputEvent]) -> void:
	if not META.has(action):
		return
	var specs: Array = []
	for event: InputEvent in events:
		var spec: Dictionary = spec_from_event(event)
		if not spec.is_empty():
			specs.append(spec)
	if specs.is_empty():
		return
	_overrides[action] = specs
	_apply(action, specs)
	save_bindings()
	bindings_changed.emit()


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


## Whether two events would mean the same press. Compared field by field rather than with `is_match`,
## which also weighs modifiers we deliberately do not bind: pressing Ctrl+Z stores the bare Z.
static func events_match(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka: InputEventKey = a
		var kb: InputEventKey = b
		return ka.physical_keycode != KEY_NONE and ka.physical_keycode == kb.physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false

#endregion


#region presentation

## A binding as the player should read it: "W", "Shift", "LMB", "Wheel down".
static func describe(event: InputEvent) -> String:
	if event is InputEventKey:
		var key: InputEventKey = event
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		var text: String = OS.get_keycode_string(code)
		return text if not text.is_empty() else "?"
	if event is InputEventMouseButton:
		return mouse_name((event as InputEventMouseButton).button_index)
	return "?"


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


func action_label(action: String) -> String:
	var meta: Dictionary = META.get(action, {})
	return String(meta.get("label", action))


## Group headings in display order. Debug is hidden in a release build: those keys exist, but a player
## has no reason to rebind them and every reason not to be shown them.
func groups() -> Array[String]:
	var out: Array[String] = []
	for action: String in META:
		var group: String = String((META[action] as Dictionary).get("group", ""))
		if group == "Debug" and not OS.is_debug_build():
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
## so a rebind cannot leave this screen lying about the keys.
func title_rows() -> Array:
	var rows: Array = [["Mouse", "Aim"]]
	for action: String in TITLE_ACTIONS:
		rows.append([describe_action(action), action_label(action)])
	return rows


## The debug keys on one line, so the title screen can mention them without a nine-row table.
func debug_short_text() -> String:
	var parts: Array[String] = []
	for action: String in actions_in("Debug"):
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
		if not config.has_section_key("bindings", action):
			continue
		var stored: Variant = config.get_value("bindings", action, [])
		if not (stored is Array):
			continue
		var specs: Array = []
		for entry: Variant in stored:
			if entry is Dictionary and event_from_spec(entry) != null:
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
	return {}

#endregion


## Movement vector from WASD, normalised. Screen-relative by design: W is always
## "up on the monitor", never "forward toward the mouse".
func move_vector() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
