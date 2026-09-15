extends Node
## Lightweight UI/SFX helper. No external audio assets beyond project wavs.

var _players: Dictionary = {}
var enabled: bool = true

const PATHS = {
	"click": "res://assets/audio/ui_click.wav",
	"confirm": "res://assets/audio/ui_confirm.wav",
	"alert": "res://assets/audio/ui_alert.wav",
	"turn": "res://assets/audio/turn_resolve.wav",
	"ambient": "res://assets/audio/ambient_pad.wav",
}

func _ready() -> void:
	for key in PATHS:
		var player = AudioStreamPlayer.new()
		player.name = "Sfx_" + str(key)
		player.volume_db = -8.0 if key != "ambient" else -18.0
		if key == "ambient":
			player.volume_db = -22.0
		add_child(player)
		_players[key] = player
		if ResourceLoader.exists(PATHS[key]):
			player.stream = load(PATHS[key])
	play("ambient", true)

func play(key: String, loop: bool = false) -> void:
	if not enabled or not _players.has(key):
		return
	var player: AudioStreamPlayer = _players[key]
	if player.stream == null:
		return
	if player.stream is AudioStreamWAV:
		player.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	if player.playing and key == "ambient":
		return
	player.play()

func stop(key: String) -> void:
	if _players.has(key):
		_players[key].stop()

func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		stop("ambient")
	else:
		play("ambient", true)
