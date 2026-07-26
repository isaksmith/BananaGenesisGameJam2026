extends Node2D

## Protect the banana stash — keep at least one banana for 30 seconds.

const ROUND_TIME := 30.0
const START_BANANAS := 8
## Keep ~5–6 thieves on the field for the whole 30s. Spawns never stop while
## time remains — kills free a slot and get refilled through the last 10s.
const SPAWN_INTERVAL := 0.85
const TARGET_LIVE_GORILLAS := 5
const GORILLA_SCRIPT := "res://scripts/thief_gorilla.gd"
const MUSIC := "res://assets/audio/trails/banana-defense-sound.mp3"
const BG_VIDEO := "res://assets/video/banana-defense-background.ogv"

@export var gorilla_speed: float = 95.0
@export var max_live_gorillas: int = 6
@export var spawn_min_separation: float = 120.0

var _bananas_left: int = START_BANANAS
var _time_left: float = ROUND_TIME
var _playing: bool = false
var _done: bool = false
var _spawn_t: float = 0.0
var _gorillas: Array[Node] = []
var _next_spawn_side: int = 0

var _stash: Node2D
var _pile_spr: Sprite2D
var _hint: Label
var _player: CharacterBody2D


func _ready() -> void:
	AudioSettings.play_music(MUSIC)
	_player = get_node_or_null("Monkey") as CharacterBody2D
	_disable_web_bg_video()
	_build_stash()
	_build_hint()
	# Hide / disable the old banana spawner if present.
	var spawner := get_node_or_null("BananaSpawner")
	if spawner:
		spawner.set_process(false)
		spawner.set_physics_process(false)
		spawner.visible = false
	GameProgress.mode_changed.connect(_on_mode_changed)
	_start_round()


func _disable_web_bg_video() -> void:
	# Desktop: Theora overlay. Web: high-res still (Theora freezes/crashes itch.io).
	var arena := get_node_or_null("Arena01")
	if arena == null:
		return
	var bg_art := arena.get_node_or_null("BgArt") as CanvasItem
	if bg_art:
		bg_art.visible = true
	if OS.has_feature("web") or OS.get_name() == "Web":
		return
	var host := CanvasLayer.new()
	host.name = "BgVideoHost"
	host.layer = -100
	arena.add_child(host)
	arena.move_child(host, 0)
	var video := VideoStreamPlayer.new()
	video.name = "BgVideo"
	video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.expand = true
	video.loop = true
	video.volume_db = -80.0
	video.stream = load(BG_VIDEO) as VideoStream
	host.add_child(video)
	if video.stream:
		video.play()
		if bg_art:
			bg_art.visible = false


func _on_mode_changed(mode: StringName) -> void:
	if mode != GameProgress.MODE_CHASE:
		_playing = false


func _build_stash() -> void:
	_stash = Node2D.new()
	_stash.name = "BananaStash"
	_stash.position = Vector2(640, 360)
	_stash.z_index = 2
	add_child(_stash)

	# Soft glow under the pile.
	var glow := Polygon2D.new()
	glow.z_index = -2
	glow.color = Color(1.0, 0.85, 0.25, 0.28)
	var gpts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		gpts.append(Vector2(cos(a) * 72.0, sin(a) * 48.0 + 12.0))
	glow.polygon = gpts
	_stash.add_child(glow)

	_pile_spr = Sprite2D.new()
	_pile_spr.texture = load("res://assets/sprites/bananas_pile.png") as Texture2D
	_pile_spr.position = Vector2(0, 8)
	_pile_spr.scale = Vector2(2.4, 2.4)
	_pile_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stash.add_child(_pile_spr)

	var label := Label.new()
	label.name = "StashLabel"
	label.text = "STASH"
	label.position = Vector2(-40, -70)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	_stash.add_child(label)


func _build_hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	_hint = Label.new()
	_hint.name = "HintLabel"
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_left = -420
	_hint.offset_right = 420
	_hint.offset_top = 86
	_hint.offset_bottom = 140
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.text = "Club gorillas 3× to banana-blast them · keep ≥1 banana for 30s"
	layer.add_child(_hint)


func _start_round() -> void:
	_clear_gorillas()
	_bananas_left = START_BANANAS
	_time_left = ROUND_TIME
	_spawn_t = 0.15
	_next_spawn_side = randi() % 4
	_done = false
	_playing = true
	_refresh_pile_visual()
	if _player:
		_player.global_position = Vector2(640, 480)
		_player.velocity = Vector2.ZERO
	# Drive the shared chase HUD.
	GameState.set_active(true)
	GameState.score = _bananas_left
	GameState.time_left = _time_left
	GameState.is_playing = true
	GameState.score_changed.emit(_bananas_left)
	GameState.time_changed.emit(_time_left)
	_hint.text = "Club gorillas 3× to banana-blast them · keep ≥1 banana for 30s"
	# Seed the field so the round isn't empty for the first few seconds.
	_spawn_gorilla()
	_spawn_gorilla()
	_spawn_gorilla()


func _physics_process(delta: float) -> void:
	if not _playing or _done:
		return

	_time_left = maxf(_time_left - delta, 0.0)
	GameState.time_left = _time_left
	GameState.time_changed.emit(_time_left)

	# Keep trying to spawn for the entire timer. No fixed budget that can run out
	# after early kills — empty slots get refilled through the last 10 seconds.
	if _time_left > 0.0:
		_spawn_t -= delta
		if _spawn_t <= 0.0:
			var live := _active_gorilla_count()
			if live < max_live_gorillas:
				_spawn_gorilla()
				live = _active_gorilla_count()
				# Push hard toward the target count; ease off only near the cap.
				if live < TARGET_LIVE_GORILLAS:
					_spawn_t = SPAWN_INTERVAL * 0.35
				elif live < max_live_gorillas:
					_spawn_t = SPAWN_INTERVAL * 0.65
				else:
					_spawn_t = SPAWN_INTERVAL
			else:
				# Cap reached — poll soon so a kill/flee immediately frees a slot.
				_spawn_t = 0.15

	_try_bump_gorillas()

	if _bananas_left <= 0:
		_fail_round()
		return
	if _time_left <= 0.0:
		_win_round()


func _try_bump_gorillas() -> void:
	if _player == null:
		return
	for g in _gorillas:
		if not is_instance_valid(g):
			continue
		# Don't interrupt thieves already escaping with loot.
		if g.has_method("is_fleeing") and g.is_fleeing():
			continue
		if g.has_method("is_dead") and g.is_dead():
			continue
		if _player.global_position.distance_to(g.global_position) < 52.0:
			if not g.has_method("register_hit"):
				continue
			var result: int = int(g.register_hit(_player.global_position, 320.0))
			if result == 0:
				continue
			if _player.has_method("pulse_club_swing"):
				_player.pulse_club_swing()
			if result == 2:
				_kill_gorilla(g)
			else:
				GameProgress.juice_shake.emit(0.08)
				if g.has_method("hits_left"):
					_hint.text = "Whack! %d more hit(s) to blast this gorilla" % g.hits_left()


func _kill_gorilla(g: Node) -> void:
	var boom_at: Vector2 = Vector2(640, 360)
	if g is Node2D:
		boom_at = (g as Node2D).global_position
	_spawn_banana_explosion(boom_at)
	GameProgress.juice_shake.emit(0.5)
	_hint.text = "Banana blast! Gorilla down."
	_gorillas.erase(g)
	if is_instance_valid(g):
		g.queue_free()
	# Cleared the field — no need to wait out the timer.
	if not _done and _bananas_left > 0 and _active_gorilla_count() == 0:
		_hint.text = "All gorillas defeated! Stash secure."
		_win_round()


func _spawn_banana_explosion(origin: Vector2) -> void:
	var banana_tex := load("res://assets/sprites/banana.png") as Texture2D
	var peel_tex := load("res://assets/sprites/banana_peel.png") as Texture2D

	var flash := Polygon2D.new()
	flash.z_index = 40
	flash.color = Color(1.0, 0.92, 0.35, 0.85)
	var ring := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		ring.append(Vector2(cos(a), sin(a)) * 18.0)
	flash.polygon = ring
	flash.global_position = origin
	add_child(flash)
	var flash_tween := create_tween()
	flash_tween.tween_property(flash, "scale", Vector2(6.5, 6.5), 0.28)
	flash_tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.28)
	flash_tween.tween_callback(flash.queue_free)

	var bits := CPUParticles2D.new()
	bits.z_index = 39
	bits.global_position = origin
	bits.emitting = true
	bits.one_shot = true
	bits.explosiveness = 1.0
	bits.amount = 36
	bits.lifetime = 0.55
	bits.direction = Vector2(0, -1)
	bits.spread = 180.0
	bits.initial_velocity_min = 180.0
	bits.initial_velocity_max = 420.0
	bits.gravity = Vector2(0, 900)
	bits.scale_amount_min = 3.0
	bits.scale_amount_max = 7.0
	bits.color = Color(1.0, 0.85, 0.25, 1)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.4, 1),
		Color(1.0, 0.55, 0.1, 0.85),
		Color(0.4, 0.2, 0.05, 0),
	])
	bits.color_ramp = grad
	add_child(bits)
	bits.finished.connect(bits.queue_free)

	for i in 14:
		var spr := Sprite2D.new()
		spr.z_index = 41
		spr.texture = peel_tex if i % 3 == 0 else banana_tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(0.55, 0.55) if i % 3 == 0 else Vector2(0.7, 0.7)
		spr.global_position = origin + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		spr.rotation = randf_range(0, TAU)
		add_child(spr)
		var dir := Vector2(randf_range(-1, 1), randf_range(-1.2, -0.2)).normalized()
		var dist := randf_range(90.0, 220.0)
		var end := origin + dir * dist + Vector2(0, randf_range(40, 120))
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(spr, "global_position", end, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(spr, "rotation", spr.rotation + randf_range(-8, 8), 0.7)
		tw.tween_property(spr, "modulate:a", 0.0, 0.7).set_delay(0.25)
		tw.chain().tween_callback(spr.queue_free)


func _spawn_gorilla() -> bool:
	if _done or not _playing or _time_left <= 0.0:
		return false
	_gorillas = _gorillas.filter(func(n: Node) -> bool: return is_instance_valid(n))
	if _active_gorilla_count() >= max_live_gorillas:
		return false

	var pos := _edge_spawn()
	var script: Script = load(GORILLA_SCRIPT) as Script
	var g := CharacterBody2D.new()
	g.set_script(script)
	g.global_position = pos
	add_child(g)
	var speed := gorilla_speed + randf_range(-8.0, 12.0) + (ROUND_TIME - _time_left) * 0.45
	g.call("setup", _stash, _on_gorilla_steal, speed)
	_gorillas.append(g)
	return true


func _active_gorilla_count() -> int:
	var n := 0
	for g in _gorillas:
		if not is_instance_valid(g):
			continue
		if g.has_method("is_fleeing") and g.is_fleeing():
			continue
		if g.has_method("is_dead") and g.is_dead():
			continue
		n += 1
	return n


func _edge_spawn() -> Vector2:
	# Rotate sides; always return a spawn so the round never goes dry.
	var fallback := Vector2(-40, 360)
	for attempt in 12:
		var side := (_next_spawn_side + attempt) % 4
		var pos: Vector2
		match side:
			0:
				pos = Vector2(randf_range(80, 1200), -40)
			1:
				pos = Vector2(randf_range(80, 1200), 760)
			2:
				pos = Vector2(-40, randf_range(80, 640))
			_:
				pos = Vector2(1320, randf_range(80, 640))
		if attempt == 0:
			fallback = pos
		if _spawn_is_clear(pos):
			_next_spawn_side = (side + 1) % 4
			return pos
	_next_spawn_side = (_next_spawn_side + 1) % 4
	return fallback


func _spawn_is_clear(pos: Vector2) -> bool:
	for g in _gorillas:
		if not is_instance_valid(g):
			continue
		if g.has_method("is_fleeing") and g.is_fleeing():
			continue
		if g.has_method("is_dead") and g.is_dead():
			continue
		if pos.distance_to(g.global_position) < spawn_min_separation:
			return false
	return true


func _on_gorilla_steal(_gorilla: Node) -> bool:
	if _done or not _playing or _bananas_left <= 0:
		return false
	_bananas_left -= 1
	GameState.score = _bananas_left
	GameState.score_changed.emit(_bananas_left)
	_refresh_pile_visual()
	GameProgress.juice_shake.emit(0.22)
	_hint.text = "A gorilla stole a banana! %d left" % _bananas_left
	return true


func _refresh_pile_visual() -> void:
	if _pile_spr == null:
		return
	var t := float(_bananas_left) / float(START_BANANAS)
	_pile_spr.scale = Vector2(0.7 + t * 1.1, 0.7 + t * 1.1)
	_pile_spr.modulate = Color(1, 1, 1, 1) if _bananas_left > 0 else Color(1, 1, 1, 0.15)
	var label := _stash.get_node_or_null("StashLabel") as Label
	if label:
		label.text = "STASH x%d" % _bananas_left


func _win_round() -> void:
	if _done:
		return
	_done = true
	_playing = false
	GameState.is_playing = false
	_clear_gorillas()
	_hint.text = "Protected! %d banana(s) safe." % _bananas_left
	GameProgress.juice_shake.emit(0.5)
	await get_tree().create_timer(0.85).timeout
	GameProgress.report_chase_finished(_bananas_left)


func _fail_round() -> void:
	if _done:
		return
	_done = true
	_playing = false
	GameState.is_playing = false
	_clear_gorillas()
	_hint.text = "The stash is empty… Retrying defense!"
	GameProgress.juice_shake.emit(0.35)
	await get_tree().create_timer(1.4).timeout
	if GameProgress.current_mode == GameProgress.MODE_CHASE:
		_start_round()


func _clear_gorillas() -> void:
	for g in _gorillas:
		if is_instance_valid(g):
			g.queue_free()
	_gorillas.clear()
