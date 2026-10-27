extends Node
## Registers every input action at runtime.
##
## Why runtime instead of Project Settings? Because the action list lives in
## version control as readable GDScript, it can never be silently corrupted by a
## bad project.godot entry, and adding a keybind is a one-line change. Autoloads
## run before the main scene, so every action exists before any game code asks
## for it.
##
## Edit KEY_BINDINGS / MOUSE_BINDINGS below to rebind.

const KEY_BINDINGS: Dictionary = {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"reload": [KEY_R],
	"interact": [KEY_F],
	"dash": [KEY_SHIFT, KEY_SPACE],
	"switch_1": [KEY_1],
	"switch_2": [KEY_2],
	"switch_3": [KEY_3],
	"ability_1": [KEY_Q],
	"ability_2": [KEY_E],
	"settings": [KEY_O, KEY_F8],
	"pause": [KEY_ESCAPE],
	"debug_god": [KEY_F1],
	"debug_noclip": [KEY_F2],
	"debug_info": [KEY_F3],
	"debug_reveal": [KEY_F4],
	"debug_spawn": [KEY_F5],
	"debug_alert_all": [KEY_F6],
	"debug_give": [KEY_F7],
	"debug_slowmo": [KEY_F9],
}

const MOUSE_BINDINGS: Dictionary = {
	"fire": [MOUSE_BUTTON_LEFT],
	"switch_next": [MOUSE_BUTTON_WHEEL_DOWN],
	"switch_prev": [MOUSE_BUTTON_WHEEL_UP],
}

## Shown on the title screen.
const CONTROLS_TEXT := """WASD / Arrows     Move
Mouse             Aim
Left Mouse        Fire
R                 Reload
Shift / Space     Dash
1 2 3 / Wheel     Switch weapon
Q E               Use ability
O                 Settings
Esc               Pause

Walk over weapons, ammo and medkits to pick them up.

Debug
F1  god mode        F2  noclip
F3  debug readout   F4  lift the fog
F5  spawn enemy     F6  alert everything
F7  give all weapons
F9  slow motion"""


func _ready() -> void:
	register_all()


func register_all() -> void:
	for action: String in KEY_BINDINGS:
		var events: Array[InputEvent] = []
		for code: int in KEY_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code as Key
			events.append(ev)
		_apply(action, events)

	for action: String in MOUSE_BINDINGS:
		var events: Array[InputEvent] = []
		for button: int in MOUSE_BINDINGS[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button as MouseButton
			events.append(ev)
		_apply(action, events)


func _apply(action: String, events: Array[InputEvent]) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.25)
	for ev: InputEvent in events:
		InputMap.action_add_event(action, ev)


## Movement vector from WASD, normalised. Screen-relative by design: W is always
## "up on the monitor", never "forward toward the mouse".
func move_vector() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
