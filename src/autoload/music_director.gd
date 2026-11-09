extends Node
## Background music: plays every song in `MUSIC_DIRECTORY` in random order, for as long as the game runs.
##
## To add a song, drop a wav, ogg or mp3 into that folder; nothing has to be registered. Songs are shuffled
## like a deck of cards, so all of them play once before any plays again, and a new shuffle never starts
## on the song that just ended.
##
## An autoload, so a song carries on across level changes, deaths and the title screen, and keeps playing
## while the game is paused. It plays on its own "Music" bus. The volume itself is owned by `Settings`,
## which applies it after this autoload has created the bus.
##
## Only the current song is kept in memory.

const MUSIC_DIRECTORY: String = "res://assets/music/"
const MUSIC_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]
const BUS: StringName = &"Music"
## Silence between two songs.
const GAP_SECONDS: float = 2.0

var _songs: Array[String] = []
## What is left of the current shuffle; songs are drawn from the back.
var _deck: Array[String] = []
var _current: String = ""
var _player: AudioStreamPlayer = null
var _gap: Timer = null


func _ready() -> void:
	# Keeps playing, and moving to the next song, while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	_find_songs()
	_player = AudioStreamPlayer.new()
	_player.name = "Player"
	_player.bus = BUS
	_player.finished.connect(_on_song_finished)
	add_child(_player)
	_gap = Timer.new()
	_gap.name = "Gap"
	_gap.one_shot = true
	_gap.wait_time = GAP_SECONDS
	_gap.timeout.connect(play_next)
	add_child(_gap)
	_gap.start()


## Starts the next song in the shuffle, cutting off whatever is playing. Does nothing with no songs.
func play_next() -> void:
	while not _songs.is_empty():
		var path: String = _next_song()
		var stream := load(path) as AudioStream
		if stream == null:
			push_warning("MusicDirector: %s is not a song." % path)
			_songs.erase(path)
			_deck.erase(path)
			continue
		_disable_loop(stream)
		_current = path
		_player.stream = stream
		_player.play()
		return


## The file playing now, or "" when there is none.
func current_song() -> String:
	return _current


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	# `set_bus_count`, not `add_bus`: on the web export `add_bus` files the new bus in front of Master in
	# the browser's mixer, so the buses end up feeding each other and nothing reaches the speakers.
	AudioServer.set_bus_count(AudioServer.bus_count + 1)
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS)
	AudioServer.set_bus_send(index, &"Master")


func _find_songs() -> void:
	_songs.clear()
	# Through the resource loader rather than the file system: an exported game has no folders to list.
	for file: String in ResourceLoader.list_directory(MUSIC_DIRECTORY):
		if not file.ends_with("/") and MUSIC_EXTENSIONS.has(file.get_extension().to_lower()):
			_songs.append(MUSIC_DIRECTORY.path_join(file))


func _next_song() -> String:
	if _deck.is_empty():
		_deck = _songs.duplicate()
		_deck.shuffle()
		# The new shuffle must not open on the song that just played.
		if _deck.size() > 1 and _deck.back() == _current:
			var other: int = randi_range(0, _deck.size() - 2)
			_deck[-1] = _deck[other]
			_deck[other] = _current
	return _deck.pop_back()


## A song imported with looping on would never finish, and the playlist would stick on it.
func _disable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif "loop" in stream:
		stream.set("loop", false)


func _on_song_finished() -> void:
	_gap.start()
