extends Node

var click_player: AudioStreamPlayer
var breakthrough_player: AudioStreamPlayer
var legendary_player: AudioStreamPlayer
var death_player: AudioStreamPlayer
var poke_player: AudioStreamPlayer

var sound_enabled := true

func _ready():
	click_player = _make_player("res://audio/glass_001.wav")
	breakthrough_player = _make_player("res://audio/confirmation_001.wav")
	legendary_player = _make_player("res://audio/legendary.wav")
	death_player = _make_player("res://audio/death.wav")
	poke_player = _make_player("res://audio/click_001.wav")

func _make_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var stream = load(path)
	if stream == null:
		print("Missing sfx: ", path)
	p.stream = stream
	p.bus = "Master"
	add_child(p)
	return p

func set_sound_enabled(enabled: bool) -> void:
	sound_enabled = enabled

func play_click():
	if not sound_enabled:
		return
	click_player.volume_db = -10.0
	click_player.play()

func play_breakthrough():
	if not sound_enabled:
		return
	breakthrough_player.play()

func play_legendary():
	if not sound_enabled:
		return
	legendary_player.play()

func play_death(volume_db: float = 0.0):
	if not sound_enabled:
		return
	death_player.volume_db = volume_db
	death_player.play()

func play_poke(volume_db: float = 0.0, pitch_variation: float = 0.0):
	if not sound_enabled:
		return
	poke_player.volume_db = volume_db
	if pitch_variation > 0.0:
		poke_player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	poke_player.play()
