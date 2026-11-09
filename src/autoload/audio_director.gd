extends Node
## Sound effects, played through a small pool of players (1D for UI/player sounds, 2D for world
## sounds) by name: `play(&"door_open")`.
##
## Every sound has a synthesised version, generated once at startup from noise bursts and sine blips,
## so the game is never silent. A recorded file in `SFX_DIRECTORY` named after a sound replaces it:
## `door_open.wav` (or `.ogg`, `.mp3`) is played instead of the synthesised door. Sounds can be
## replaced one at a time, in any order.
##
## Numbered files are variants of one sound -- `footstep_1.wav`, `footstep_2.wav`, ... all play as
## `footstep` -- and one is picked at random each time, never the same one twice in a row.

## Recorded sound effects, named after the sound they replace (see the class description).
const SFX_DIRECTORY: String = "res://assets/sfx/"
const SFX_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]

const SAMPLE_RATE: int = 22050
const POOL_1D: int = 14
const POOL_2D: int = 28

## The synthesised sounds, by name.
var _bank: Dictionary = {}
## Recorded sounds from `SFX_DIRECTORY`, by name: an array of one or more variants. Checked before
## `_bank`.
var _files: Dictionary = {}
## The variant each recorded sound played last, so variety does not repeat itself.
var _last_variant: Dictionary = {}
var _pool_1d: Array[AudioStreamPlayer] = []
var _pool_2d: Array[AudioStreamPlayer2D] = []
var _steal_1d: int = 0
var _steal_2d: int = 0
var _rng := RandomNumberGenerator.new()
var _sfx_bus: StringName = &"Master"

func reinitialize():
	JavaScriptBridge.eval("""
		if (typeof window.audioContextStarted === 'undefined') {
			window.audioContextStarted = true;
			window.AudioContext = window.AudioContext || window.webkitAudioContext;
			const audioContext = new AudioContext();
			audioContext.resume();
			console.log('Audio context initialized');
		}
	""")
	_ensure_bus()
	_build_bank()
	_load_files()
	_build_pools()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_bus()
	_build_bank()
	_load_files()
	_build_pools()


## Stops playback and drops the sound bank on shutdown. Without this, whatever is
## playing when the tree is torn down is reported as leaked ObjectDB instances,
## which is noise that hides real leaks.
func _exit_tree() -> void:
	var playing: int = 0
	for p: AudioStreamPlayer in _pool_1d:
		if p.playing:
			playing += 1
		p.stop()
		p.stream = null
	for p: AudioStreamPlayer2D in _pool_2d:
		p.stop()
		p.stream = null
	_bank.clear()
	_files.clear()


## Give SFX their own bus so the volume slider (and future ducking) has a home. The
## volume itself is owned by Settings, which is why nothing is set here: it would otherwise
## fight the menu for control of the slider.
func _ensure_bus() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		_sfx_bus = &"SFX"
		AudioServer.set_bus_name(AudioServer.bus_count - 1, _sfx_bus)
		AudioServer.set_bus_send(AudioServer.get_bus_index(_sfx_bus), &"Master")


func _build_pools() -> void:
	for i: int in POOL_1D:
		var p := AudioStreamPlayer.new()
		p.bus = _sfx_bus
		add_child(p)
		_pool_1d.append(p)
	for i: int in POOL_2D:
		var p := AudioStreamPlayer2D.new()
		p.bus = _sfx_bus
		p.max_distance = 1500.0
		p.attenuation = 1.1
		add_child(p)
		_pool_2d.append(p)


#region bank

func _build_bank() -> void:
	_bank[&"shot_pistol"] = _wav(_noise(0.10, 42.0, 250.0, 0.30, 0.45))
	_bank[&"shot_smg"] = _wav(_noise(0.065, 58.0, 330.0, 0.22, 0.38))
	_bank[&"shot_shotgun"] = _wav(_noise(0.22, 20.0, 110.0, 0.42, 0.22))
	_bank[&"dry_fire"] = _wav(_blip(1100.0, 420.0, 0.05, 70.0))
	_bank[&"reload_out"] = _wav(_mix([_blip(420.0, 260.0, 0.05, 80.0), _noise(0.04, 90.0, 0.0, 0.0, 0.5)]))
	_bank[&"reload_in"] = _wav(_blip(300.0, 720.0, 0.08, 45.0))
	_bank[&"impact_wall"] = _wav(_noise(0.06, 70.0, 700.0, 0.18, 0.75))
	_bank[&"impact_flesh"] = _wav(_noise(0.10, 42.0, 150.0, 0.5, 0.22))
	_bank[&"hurt"] = _wav(_blip(230.0, 120.0, 0.24, 14.0))
	_bank[&"enemy_hurt"] = _wav(_blip(320.0, 180.0, 0.14, 26.0))
	_bank[&"enemy_die"] = _wav(_mix([_blip(180.0, 60.0, 0.55, 5.0), _noise(0.5, 6.0, 90.0, 0.35, 0.1)]))
	_bank[&"player_die"] = _wav(_mix([_blip(200.0, 50.0, 0.9, 3.0), _noise(0.8, 4.0, 70.0, 0.3, 0.08)]))
	_bank[&"pickup"] = _wav(_blip(520.0, 900.0, 0.12, 24.0))
	_bank[&"pickup_weapon"] = _wav(_blip(280.0, 760.0, 0.2, 16.0))
	_bank[&"upgrade"] = _wav(_mix([
		_blip(300.0, 300.0, 0.1, 12.0),
		_pad(0.1, _blip(450.0, 450.0, 0.1, 12.0)),
		_pad(0.2, _blip(700.0, 700.0, 0.24, 8.0)),
	]))
	_bank[&"footstep"] = _wav(_noise(0.05, 95.0, 95.0, 0.28, 0.14))
	_bank[&"dash"] = _wav(_noise(0.16, 26.0, 0.0, 0.0, 0.09))
	_bank[&"alert"] = _wav(_blip(300.0, 820.0, 0.28, 11.0))
	_bank[&"suspicious"] = _wav(_blip(380.0, 520.0, 0.18, 18.0))
	_bank[&"lose_player"] = _wav(_blip(560.0, 300.0, 0.22, 14.0))
	_bank[&"shot_enemy"] = _wav(_noise(0.09, 46.0, 210.0, 0.3, 0.4))
	_bank[&"exit"] = _wav(_mix([
		_blip(420.0, 420.0, 0.14, 9.0),
		_pad(0.12, _blip(560.0, 560.0, 0.14, 9.0)),
		_pad(0.24, _blip(840.0, 840.0, 0.5, 5.0)),
	]))
	_bank[&"win"] = _wav(_mix([
		_blip(520.0, 520.0, 0.16, 8.0),
		_pad(0.14, _blip(660.0, 660.0, 0.16, 8.0)),
		_pad(0.28, _blip(780.0, 780.0, 0.16, 8.0)),
		_pad(0.42, _blip(1040.0, 1040.0, 0.9, 3.0)),
	]))
	_bank[&"ui_click"] = _wav(_blip(820.0, 820.0, 0.03, 90.0))
	_bank[&"cast_fire"] = _wav(_mix([
		_noise(0.45, 14.0, 120.0, 0.35, 0.14), _noise(0.25, 26.0, 260.0, 0.2, 0.3)]))
	_bank[&"cast_explosion"] = _wav(_mix([
		_noise(0.5, 10.0, 70.0, 0.5, 0.09), _noise(0.2, 40.0, 180.0, 0.3, 0.25)]))
	_bank[&"cast_lightning"] = _wav(_mix([
		_noise(0.22, 34.0, 900.0, 0.25, 0.8), _blip(1400.0, 320.0, 0.2, 16.0)]))
	_bank[&"cast_refused"] = _wav(_blip(220.0, 160.0, 0.14, 30.0))
	# Doors. A creak is a slow noise sweep; a thud is a low blip with grit on it; a smash is a
	# short burst with a wooden body under it.
	_bank[&"door_open"] = _wav(_mix([
		_noise(0.34, 5.0, 320.0, 0.45, 0.06), _blip(320.0, 210.0, 0.3, 9.0)]))
	_bank[&"door_close"] = _wav(_mix([
		_noise(0.2, 16.0, 150.0, 0.4, 0.1), _blip(150.0, 90.0, 0.18, 26.0)]))
	_bank[&"door_locked"] = _wav(_mix([
		_noise(0.16, 30.0, 900.0, 0.2, 0.6), _blip(1200.0, 700.0, 0.1, 40.0)]))
	_bank[&"door_unlock"] = _wav(_mix([
		_noise(0.22, 24.0, 1100.0, 0.25, 0.7), _blip(700.0, 1100.0, 0.16, 30.0)]))
	_bank[&"door_smash"] = _wav(_mix([
		_noise(0.4, 11.0, 220.0, 0.5, 0.12), _noise(0.2, 26.0, 900.0, 0.28, 0.5),
		_blip(180.0, 70.0, 0.28, 14.0)]))
	_bank[&"pickup_ability"] = _wav(_mix([
		_blip(500.0, 600.0, 0.075, 12.0),
		_pad(0.075, _blip(550.0, 650.0, 0.075, 12.0)),
	]))
	

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		var v: float = clampf(samples[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


## Noise burst with a low-passed body and optional tonal thump.
func _noise(dur: float, decay: float, tone_hz: float, tone_mix: float, lowpass: float) -> PackedFloat32Array:
	var n: int = maxi(1, int(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var env: float = 1.0
	var env_decay: float = exp(-decay / float(SAMPLE_RATE))
	var lp_state: float = 0.0
	var a: float = clampf(lowpass, 0.001, 1.0)
	for i: int in n:
		var white: float = _rng.randf_range(-1.0, 1.0)
		lp_state += (white - lp_state) * a
		var body: float = sin(TAU * tone_hz * float(i) / float(SAMPLE_RATE)) * tone_mix
		out[i] = (lp_state * (1.0 - tone_mix) + body) * env
		env *= env_decay
	return out


## Sine sweep with exponential decay.
func _blip(f0: float, f1: float, dur: float, decay: float) -> PackedFloat32Array:
	var n: int = maxi(1, int(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var env: float = 1.0
	var env_decay: float = exp(-decay / float(SAMPLE_RATE))
	var phase: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(n)
		phase += TAU * lerpf(f0, f1, t) / float(SAMPLE_RATE)
		out[i] = sin(phase) * env
		env *= env_decay
	return out


## Pad the front of `samples` with silence (used to build little arpeggios).
func _pad(seconds: float, samples: PackedFloat32Array) -> PackedFloat32Array:
	var pad := PackedFloat32Array()
	pad.resize(int(seconds * SAMPLE_RATE))
	return _mix([pad, samples])


func _mix(parts: Array) -> PackedFloat32Array:
	var total: int = 0
	for p: PackedFloat32Array in parts:
		total += p.size()
	var out := PackedFloat32Array()
	out.resize(total)
	var cursor: int = 0
	for p: PackedFloat32Array in parts:
		for i: int in p.size():
			out[cursor + i] = p[i]
		cursor += p.size()
	return out

#endregion


#region playback

## Non-positional sound (player gun, UI, feedback).
func play(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _stream_for(sound)
	if stream == null:
		return
	var p: AudioStreamPlayer = _free_1d()
	p.stream = stream
	p.pitch_scale = pitch * _rng.randf_range(0.97, 1.03)
	p.volume_db = volume_db
	p.play()


## Positional sound in the world (enemy gunfire, footsteps, impacts).
func play_at(sound: StringName, position: Vector2, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _stream_for(sound)
	if stream == null:
		return
	var p: AudioStreamPlayer2D = _free_2d()
	p.stream = stream
	p.global_position = position
	p.pitch_scale = pitch * _rng.randf_range(0.96, 1.04)
	p.volume_db = volume_db
	p.play()


## What to play for `sound`: a recorded file when there is one (a random variant when there are
## several), else the synthesised version, else null.
func _stream_for(sound: StringName) -> AudioStream:
	var variants: Variant = _files.get(sound)
	if variants == null:
		return _bank.get(sound)
	var choices: Array = variants
	if choices.size() == 1:
		return choices[0]
	# Never the same variant twice running: a repeated footstep is exactly what variants are for avoiding.
	var last: int = int(_last_variant.get(sound, -1))
	var pick: int = _rng.randi_range(0, choices.size() - 2)
	if pick >= last and last >= 0:
		pick += 1
	_last_variant[sound] = pick
	return choices[pick]


## Loads every recorded sound in `SFX_DIRECTORY` over the synthesised bank. Listed through the
## resource loader rather than the file system, so it finds the files in an exported game too.
func _load_files() -> void:
	_files.clear()
	if not DirAccess.dir_exists_absolute(SFX_DIRECTORY):
		return
	var numbered := RegEx.create_from_string("^(.+)_(\\d+)$")
	var names: Array[String] = []
	for file: String in ResourceLoader.list_directory(SFX_DIRECTORY):
		if file.ends_with("/") or not SFX_EXTENSIONS.has(file.get_extension().to_lower()):
			continue
		names.append(file)
	# Sorted, so `footstep_2` comes before `footstep_10` and variant order does not depend on the disk.
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	for file: String in names:
		var stream := load(SFX_DIRECTORY.path_join(file)) as AudioStream
		if stream == null:
			push_warning("AudioDirector: %s is not a sound." % file)
			continue
		var sound_name: String = file.get_basename()
		# `footstep_2` is a variant of `footstep` -- unless `footstep_2` is itself the name of a sound.
		var variant: RegExMatch = numbered.search(sound_name)
		if variant != null and not _bank.has(StringName(sound_name)):
			sound_name = variant.get_string(1)
		var key := StringName(sound_name)
		if not _files.has(key):
			_files[key] = []
		(_files[key] as Array).append(stream)


func _free_1d() -> AudioStreamPlayer:
	for p: AudioStreamPlayer in _pool_1d:
		if not p.playing:
			return p
	_steal_1d = (_steal_1d + 1) % _pool_1d.size()
	return _pool_1d[_steal_1d]


func _free_2d() -> AudioStreamPlayer2D:
	for p: AudioStreamPlayer2D in _pool_2d:
		if not p.playing:
			return p
	_steal_2d = (_steal_2d + 1) % _pool_2d.size()
	return _pool_2d[_steal_2d]


## One-line summary for the dev probe / debug overlay.
func debug_summary() -> String:
	var playing: int = 0
	for p: AudioStreamPlayer in _pool_1d:
		if p.playing:
			playing += 1
	var longest: float = 0.0
	for key: Variant in _bank:
		var stream: AudioStream = _stream_for(key)
		longest = maxf(longest, stream.get_length())
	var recorded: int = 0
	for key: Variant in _files:
		recorded += (_files[key] as Array).size()
	return "bank=%d recorded=%d sounds/%d files pool=%d+%d playing=%d longest=%.2fs" % [
		_bank.size(), _files.size(), recorded, _pool_1d.size(), _pool_2d.size(), playing, longest,
	]

#endregion
