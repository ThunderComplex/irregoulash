class_name GameSettings
extends Node
## Player-facing settings: window mode, resolution, vsync, the frame rate cap, the three volume buses and
## the aim line and gamepad aim assist.
##
## Persisted to `user://settings.cfg` and applied the moment they change, so there is no
## Apply button to forget. Autoloads run before the first scene, so the saved window
## settings are in place before anything is drawn.
##
## Resolution independence is what makes the resolution list safe to expose: the camera
## zooms and the HUD scales themselves, so every size offered here works, including the
## unusual aspect ratios. Nothing in the game assumes 1280x720 any more.
##
## Load order matters only in that AudioDirector and MusicDirector must have created the SFX and Music
## buses before the saved volumes are applied; this autoload is listed after them in project.godot.

signal changed()

const PATH: String = "user://settings.cfg"
const DEFAULT_MUSIC_DB: float = -24.0
## Aim assist strength, 0..1. The default is the tuning in `Tuning`; see `AimAssist`.
const DEFAULT_AIM_ASSIST_STRENGTH: float = 0.5
const AIM_ASSIST_STRENGTH_MIN: float = 0.1
## Range of the frame rate cap. 0 means no cap.
const FPS_CAP_MIN: int = 30
const FPS_CAP_MAX: int = 500
const FPS_UNLIMITED: int = 0
const DEFAULT_FPS_CAP: int = 60

enum WindowMode {
	## A normal resizable window at `resolution`.
	WINDOWED,
	## Borderless fullscreen on the current monitor. The resolution setting does not apply.
	BORDERLESS,
	## Exclusive fullscreen. The resolution setting does not apply.
	EXCLUSIVE,
}

## Sizes offered besides the desktop's own. A spread of aspects on purpose: 5:4, 16:10 and
## two ultrawides, to make the point that all of them are supported.
const COMMON_SIZES: Array[Vector2i] = [
	Vector2i(1024, 768),
	Vector2i(1280, 720),
	Vector2i(1280, 800),
	Vector2i(1366, 768),
	Vector2i(1440, 900),
	Vector2i(1600, 900),
	Vector2i(1680, 1050),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2560, 1080),
	Vector2i(2560, 1440),
	Vector2i(2560, 1600),
	Vector2i(3440, 1440),
	Vector2i(3840, 2160),
]

var window_mode: WindowMode = WindowMode.WINDOWED
var resolution: Vector2i = Vector2i(1280, 720)
var vsync_enabled: bool = true
## Frames per second the game is held to while vsync is off; `FPS_UNLIMITED` for no cap. With vsync on
## the display already paces the game, so the cap is not applied (see `_apply_frame_cap`).
var fps_cap: int = DEFAULT_FPS_CAP
var master_volume_db: float = 0.0
## The line along the next shot's path, with a crosshair where it would hit (see `AimLine`).
var aim_line_enabled: bool = true
var aim_assist_enabled: bool = true
var aim_assist_strength: float = DEFAULT_AIM_ASSIST_STRENGTH
var sfx_volume_db: float = -6.0
## Lower than the effects by default, so music sits behind the gameplay sounds.
var music_volume_db: float = DEFAULT_MUSIC_DB

## True once there is a saved file, i.e. once the player has expressed a preference. Until
## then the window is left exactly as the project (or the command line) set it up, rather
## than being resized to our default on first launch.
var _has_saved: bool = false


func _ready() -> void:
	load_settings()
	if not _has_saved:
		# Adopt whatever window we were started with, so the menu reports the truth and
		# the player's first visit starts from the size they already have.
		var current: Vector2i = DisplayServer.window_get_size()
		if current.x > 0 and current.y > 0:
			resolution = current
	apply()


#region applying

func apply() -> void:
	_apply_window()
	_apply_frame_cap()
	_apply_audio()
	changed.emit()


## True when the resolution setting has any effect: in a fullscreen mode it does not, and
## the menu greys the row out to say so.
func resolution_is_relevant() -> bool:
	return window_mode == WindowMode.WINDOWED


func _apply_window() -> void:
	if window_mode == WindowMode.WINDOWED and not _has_saved:
		# Nothing saved yet: leave the window as the project or command line set it up
		# instead of resizing an unsuspecting player's window on first launch.
		return
	match window_mode:
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.EXCLUSIVE:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
			_center_window()
	var mode: int = DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode)


## Holds the frame rate to the cap -- only while vsync is off, which is when nothing else limits it.
func _apply_frame_cap() -> void:
	Engine.max_fps = 0 if vsync_enabled else fps_cap


## Puts the window in the middle of the desktop, and shrinks it if the requested size does
## not fit on this monitor. The stored resolution is left alone: plugging a bigger display
## back in should give the requested size back.
func _center_window() -> void:
	var screen: int = DisplayServer.window_get_current_screen()
	var usable: Vector2i = DisplayServer.screen_get_usable_rect(screen).size
	var target: Vector2i = resolution
	if usable.x > 0 and usable.y > 0:
		target.x = mini(target.x, usable.x)
		target.y = mini(target.y, usable.y)
	if target != resolution:
		DisplayServer.window_set_size(target)
	var origin: Vector2i = DisplayServer.screen_get_position(screen)

	@warning_ignore("integer_division")
	DisplayServer.window_set_position(origin + (usable - target) / 2)


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, master_volume_db)
	var sfx: int = AudioServer.get_bus_index("SFX")
	if sfx >= 0:
		AudioServer.set_bus_volume_db(sfx, sfx_volume_db)
	var music: int = AudioServer.get_bus_index(MusicDirector.BUS)
	if music >= 0:
		AudioServer.set_bus_volume_db(music, music_volume_db)

#endregion


#region setters (each one applies and persists)

func set_window_mode(mode: WindowMode) -> void:
	if window_mode == mode:
		return
	window_mode = mode
	apply()
	save_settings()


func set_resolution(size: Vector2i) -> void:
	if resolution == size:
		return
	resolution = size
	apply()
	save_settings()


func set_vsync(enabled: bool) -> void:
	if vsync_enabled == enabled:
		return
	vsync_enabled = enabled
	apply()
	save_settings()


## `cap` in frames per second, clamped to `FPS_CAP_MIN`..`FPS_CAP_MAX`; `FPS_UNLIMITED` (0) for none.
func set_fps_cap(cap: int) -> void:
	var clamped: int = FPS_UNLIMITED if cap <= FPS_UNLIMITED else clampi(cap, FPS_CAP_MIN, FPS_CAP_MAX)
	if fps_cap == clamped:
		return
	fps_cap = clamped
	_apply_frame_cap()
	changed.emit()
	save_settings()


func set_aim_line(enabled: bool) -> void:
	if aim_line_enabled == enabled:
		return
	aim_line_enabled = enabled
	changed.emit()
	save_settings()


func set_aim_assist(enabled: bool) -> void:
	if aim_assist_enabled == enabled:
		return
	aim_assist_enabled = enabled
	changed.emit()
	save_settings()


func set_aim_assist_strength(strength: float) -> void:
	var clamped: float = clampf(strength, AIM_ASSIST_STRENGTH_MIN, 1.0)
	if is_equal_approx(aim_assist_strength, clamped):
		return
	aim_assist_strength = clamped
	changed.emit()
	save_settings()


func set_master_volume_db(db: float) -> void:
	if is_equal_approx(master_volume_db, db):
		return
	master_volume_db = db
	_apply_audio()
	changed.emit()
	save_settings()


func set_sfx_volume_db(db: float) -> void:
	if is_equal_approx(sfx_volume_db, db):
		return
	sfx_volume_db = db
	_apply_audio()
	changed.emit()
	save_settings()


func set_music_volume_db(db: float) -> void:
	if is_equal_approx(music_volume_db, db):
		return
	music_volume_db = db
	_apply_audio()
	changed.emit()
	save_settings()


func reset_defaults() -> void:
	window_mode = WindowMode.WINDOWED
	resolution = Vector2i(1280, 720)
	vsync_enabled = true
	fps_cap = DEFAULT_FPS_CAP
	aim_line_enabled = true
	aim_assist_enabled = true
	aim_assist_strength = DEFAULT_AIM_ASSIST_STRENGTH
	master_volume_db = 0.0
	sfx_volume_db = -6.0
	music_volume_db = DEFAULT_MUSIC_DB
	apply()
	save_settings()


## The menu works in 0..100; the mixer works in decibels, and 0 has to mean silence
## rather than -infinity.
static func slider_to_db(value: float) -> float:
	if value <= 0.0:
		return -80.0
	return linear_to_db(value / 100.0)


static func db_to_slider(db: float) -> float:
	return clampf(db_to_linear(maxf(db, -80.0)) * 100.0, 0.0, 100.0)

#endregion


#region persistence

func save_settings() -> void:
	# From here on we own the window: there is a stored preference to honour.
	_has_saved = true
	var config := ConfigFile.new()
	config.set_value("display", "window_mode", int(window_mode))
	config.set_value("display", "resolution", resolution)
	config.set_value("display", "vsync", vsync_enabled)
	config.set_value("display", "fps_cap", fps_cap)
	config.set_value("audio", "master_db", master_volume_db)
	config.set_value("gameplay", "aim_line", aim_line_enabled)
	config.set_value("gameplay", "aim_assist", aim_assist_enabled)
	config.set_value("gameplay", "aim_assist_strength", aim_assist_strength)
	config.set_value("audio", "sfx_db", sfx_volume_db)
	config.set_value("audio", "music_db", music_volume_db)
	var error: Error = config.save(PATH)
	if error != OK:
		# Not fatal: the game runs fine with unpersisted settings.
		push_warning("Could not save settings to %s (error %d)." % [PATH, error])


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	_has_saved = true
	window_mode = clampi(int(config.get_value("display", "window_mode", int(window_mode))),
		WindowMode.WINDOWED, WindowMode.EXCLUSIVE) as WindowMode
	resolution = config.get_value("display", "resolution", resolution)
	vsync_enabled = bool(config.get_value("display", "vsync", vsync_enabled))
	var cap: int = int(config.get_value("display", "fps_cap", fps_cap))
	fps_cap = FPS_UNLIMITED if cap <= FPS_UNLIMITED else clampi(cap, FPS_CAP_MIN, FPS_CAP_MAX)
	master_volume_db = float(config.get_value("audio", "master_db", master_volume_db))
	aim_line_enabled = bool(config.get_value("gameplay", "aim_line", aim_line_enabled))
	aim_assist_enabled = bool(config.get_value("gameplay", "aim_assist", aim_assist_enabled))
	aim_assist_strength = clampf(float(config.get_value("gameplay", "aim_assist_strength",
		aim_assist_strength)), AIM_ASSIST_STRENGTH_MIN, 1.0)
	sfx_volume_db = float(config.get_value("audio", "sfx_db", sfx_volume_db))
	music_volume_db = float(config.get_value("audio", "music_db", music_volume_db))


## Every resolution the menu offers: the desktop's own first, then the common list, all
## de-duplicated and sorted smallest to largest.
func resolution_options() -> Array[Vector2i]:
	var options: Array[Vector2i] = [DisplayServer.screen_get_size()]
	options.append_array(COMMON_SIZES)
	var unique: Array[Vector2i] = []
	for option: Vector2i in options:
		if option.x <= 0 or option.y <= 0 or unique.has(option):
			continue
		unique.append(option)
	unique.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x * a.y < b.x * b.y)
	return unique

#endregion
