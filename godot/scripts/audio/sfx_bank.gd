class_name SfxBank
extends Node
## Plays the baked sound effects. Browsers keep audio locked until the first
## click/tap/key; `unlock()` is called on that gesture and everything before it
## is intentionally silent.

const UNLOCK: AudioStream = preload("res://audio/sfx_unlock.wav")
const PAUSE: AudioStream = preload("res://audio/sfx_pause.wav")
const RESUME: AudioStream = preload("res://audio/sfx_resume.wav")
const RESTART: AudioStream = preload("res://audio/sfx_restart.wav")

var unlocked: bool = false
## Count of sounds actually started; lets headless checks observe playback.
var played: Array[String] = []

var _players: Dictionary = {}


func _ready() -> void:
	_players["unlock"] = _make_player(UNLOCK)
	_players["pause"] = _make_player(PAUSE)
	_players["resume"] = _make_player(RESUME)
	_players["restart"] = _make_player(RESTART)


func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	play("unlock")


func play(sound: String) -> void:
	if not unlocked:
		return
	var player: AudioStreamPlayer = _players.get(sound)
	if player == null:
		return
	played.append(sound)
	player.play()


func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	return player
