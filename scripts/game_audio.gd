extends RefCounted
class_name GameAudio

## Load music/SFX even when Godot hasn't generated .import files yet.


static func load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var loaded := load(path) as AudioStream
		if loaded != null:
			return loaded
	var abs_path := ProjectSettings.globalize_path(path)
	if path.ends_with(".ogg"):
		if not FileAccess.file_exists(abs_path) and not FileAccess.file_exists(path):
			return null
		var ogg_path := abs_path if FileAccess.file_exists(abs_path) else path
		return AudioStreamOggVorbis.load_from_file(ogg_path)
	if path.ends_with(".mp3"):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			file = FileAccess.open(abs_path, FileAccess.READ)
		if file == null:
			return null
		var mp3 := AudioStreamMP3.new()
		mp3.data = file.get_buffer(file.get_length())
		return mp3
	return null


static func play(host: Node, path: String, loop: bool = false, volume_db: float = 0.0) -> AudioStreamPlayer:
	var stream := load_stream(path)
	if stream == null or host == null:
		return null
	if loop:
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	host.add_child(player)
	if not loop:
		player.finished.connect(player.queue_free)
	player.play()
	return player
