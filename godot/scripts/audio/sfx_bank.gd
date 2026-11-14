class_name SfxBank
extends Node
## Plays the baked sound effects. Browsers keep audio locked until the first
## click/tap/key; `unlock()` is called on that gesture and everything before it
## is intentionally silent. Like the prototype, the same sound is not restarted
## within `MIN_GAP_MS` of itself so a crowd of hits cannot machine-gun.

const MIN_GAP_MS: int = 40
const SOUNDS: Dictionary = {
	"unlock": preload("res://audio/sfx_unlock.wav"),
	"pause": preload("res://audio/sfx_pause.wav"),
	"resume": preload("res://audio/sfx_resume.wav"),
	"restart": preload("res://audio/sfx_restart.wav"),
	"hit": preload("res://audio/sfx_hit.wav"),
	"strike": preload("res://audio/sfx_strike.wav"),
	"kill": preload("res://audio/sfx_kill.wav"),
	"hurt": preload("res://audio/sfx_hurt.wav"),
	"dash": preload("res://audio/sfx_dash.wav"),
	"wave": preload("res://audio/sfx_wave.wav"),
	"shot": preload("res://audio/sfx_shot.wav"),
	"parry": preload("res://audio/sfx_parry.wav"),
}

var unlocked: bool = false
## Sounds actually started; lets headless checks observe playback.
var played: Array[String] = []

var _players: Dictionary = {}
var _last_ms: Dictionary = {}


func _ready() -> void:
	for sound: String in SOUNDS:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.stream = SOUNDS[sound]
		add_child(player)
		_players[sound] = player


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
	var now: int = Time.get_ticks_msec()
	if now - int(_last_ms.get(sound, -1000)) <= MIN_GAP_MS:
		return
	_last_ms[sound] = now
	played.append(sound)
	if played.size() > 512:
		played = played.slice(256)
	player.play()


## Maps simulation cues to sounds.
func play_cue(cue: SimCue) -> void:
	match cue.kind:
		SimCue.Kind.ENEMY_HIT, SimCue.Kind.WALL_SLAM:
			play("hit")
		SimCue.Kind.SWORD_STRIKE:
			play("strike")
		SimCue.Kind.ENEMY_KILLED:
			play("kill")
		SimCue.Kind.PLAYER_HURT:
			play("hurt")
		SimCue.Kind.DASH, SimCue.Kind.ULTIMATE_STARTED:
			play("dash")
		SimCue.Kind.WAVE_STARTED:
			play("wave")
		SimCue.Kind.PROJECTILE_FIRED:
			play("shot")
		SimCue.Kind.PROJECTILE_PARRIED:
			play("parry")
		SimCue.Kind.ENEMY_FROZEN:
			play("parry")
		_:
			pass
