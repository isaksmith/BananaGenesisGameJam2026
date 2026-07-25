extends Node

## Persistent sound toggle (Master bus mute) + cross-scene music player.

signal sound_changed(enabled: bool)

const CONFIG_PATH := "user://audio_settings.cfg"
const SECTION := "audio"
const KEY_SOUND := "sound_enabled"
const HUB_MUSIC := "res://assets/audio/Palm_Tree_Ascent.mp3"

var sound_enabled: bool = true
var _music: AudioStreamPlayer
var _music_path: String = ""


func _ready() -> void:
	_load()
	_apply()
	_music = AudioStreamPlayer.new()
	_music.name = "MusicPlayer"
	add_child(_music)


func set_sound_enabled(enabled: bool) -> void:
	if sound_enabled == enabled:
		return
	sound_enabled = enabled
	_apply()
	_save()
	sound_changed.emit(sound_enabled)


func toggle_sound() -> void:
	set_sound_enabled(not sound_enabled)


## Keep hub music playing across hub → wheel-draw (and resume after trails).
func play_hub_music() -> void:
	play_music(HUB_MUSIC)


## Switch BGM. Same path already playing is left alone (no restart).
func play_music(path: String, volume_db: float = 0.0) -> void:
	if path.is_empty() or _music == null:
		return
	if _music_path == path and _music.playing:
		_music.volume_db = volume_db
		return
	var stream := GameAudio.load_stream(path)
	if stream == null:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_music.stop()
	_music.stream = stream
	_music.volume_db = volume_db
	_music_path = path
	_music.play()


func stop_music() -> void:
	if _music == null:
		return
	_music.stop()
	_music.stream = null
	_music_path = ""


func _apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, not sound_enabled)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	sound_enabled = bool(cfg.get_value(SECTION, KEY_SOUND, true))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(SECTION, KEY_SOUND, sound_enabled)
	cfg.save(CONFIG_PATH)
