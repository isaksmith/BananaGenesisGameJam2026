extends Node2D

## Banana Maze — navigate the hedge maze and grab every banana as fast as possible.
## A spotted leopard prowls the corridors (Pac-Man style). Three lives per run.

@export var move_speed: float = 250.0
@export var cols: int = 21   # must be odd
@export var rows: int = 13   # must be odd
@export var cell: float = 52.0
@export var banana_count: int = 16
@export var max_lives: int = 3
@export var leopard_speed: float = 175.0
@export var leopard_grace: float = 2.2

const TEX_MONKEY := "res://assets/sprites/monkey_idle.png"
const TEX_BANANA := "res://assets/sprites/banana.png"
const BG_VIDEO := "res://assets/video/maze-background.ogv"
const BG_STILL := "res://assets/sprites/maze_background_still.png"
const MUSIC := "res://assets/audio/trails/banana-maze-sound.mp3"
const SFX_HURT := "res://assets/audio/sfx/sfx_hurt.ogg"
const LEOPARD_SCRIPT := preload("res://scripts/maze_leopard.gd")
const MONKEY_VISUAL_SCALE := 0.9

# Floors stay readable but translucent so the looping BG video shows through.
const COLOR_FLOOR := Color(0.28, 0.40, 0.22, 0.55)
const COLOR_FLOOR_ALT := Color(0.24, 0.36, 0.20, 0.52)
const COLOR_HEDGE := Color(0.12, 0.26, 0.12, 1.0)
const COLOR_HEDGE_TOP := Color(0.18, 0.36, 0.18, 1.0)

var _grid: Array = []          # _grid[y][x] == true means wall
var _origin: Vector2 = Vector2.ZERO
var _player: CharacterBody2D
var _leopard: CharacterBody2D
var _trail: CPUParticles2D
var _bananas: Array[Area2D] = []
var _total: int = 0
var _collected: int = 0
var _lives: int = 3
var _time: float = 0.0
var _done: bool = false
var _catching: bool = false
var _invuln_t: float = 0.0
var _grace_t: float = 0.0
var _rng := RandomNumberGenerator.new()

@onready var _status: Label = %StatusLabel
@onready var _hint: Label = %HintLabel


func _ready() -> void:
	AudioSettings.play_music(MUSIC)
	if cols % 2 == 0:
		cols += 1
	if rows % 2 == 0:
		rows += 1
	_rng.randomize()
	_origin = Vector2((1280.0 - cols * cell) * 0.5, (720.0 - rows * cell) * 0.5 + 8.0)
	_lives = max_lives
	_build_background()
	_generate_maze()
	_render_maze()
	_spawn_player()
	_spawn_bananas()
	_spawn_leopard()
	_hint.text = "Grab every banana — dodge the leopard!  ·  3 lives  ·  Arrows/WASD  ·  Esc/Q exits"
	_update_status()


func _is_web() -> bool:
	return OS.has_feature("web") or OS.get_name() == "Web"


func _build_background() -> void:
	# Fallback fill under the video (also covers letterboxing).
	var fill := Polygon2D.new()
	fill.z_index = -20
	fill.color = Color(0.08, 0.14, 0.09, 1)
	fill.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(0, 720)
	])
	add_child(fill)

	# Web: high-res still (Theora freezes/crashes itch.io). Desktop: real video.
	if _is_web():
		_build_still_background()
		return

	var host := CanvasLayer.new()
	host.name = "BgVideoHost"
	host.layer = -100
	add_child(host)
	var player := VideoStreamPlayer.new()
	player.name = "BgVideo"
	player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.expand = true
	player.loop = true
	player.volume_db = -80.0
	var stream := load(BG_VIDEO) as VideoStream
	if stream == null:
		push_error("Failed to load maze background video: %s" % BG_VIDEO)
		_build_still_background()
		return
	player.stream = stream
	host.add_child(player)
	player.play()


func _build_still_background() -> void:
	var tex := load(BG_STILL) as Texture2D
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.name = "BgStill"
	spr.z_index = -18
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var size := tex.get_size()
	if size.x > 0.0 and size.y > 0.0:
		spr.scale = Vector2(1280.0 / size.x, 720.0 / size.y)
	add_child(spr)


func _generate_maze() -> void:
	_grid.clear()
	for y in rows:
		var row := []
		for x in cols:
			row.append(true)
		_grid.append(row)

	# Recursive backtracker on odd cells (perfect maze seed).
	var stack: Array[Vector2i] = []
	var start := Vector2i(1, 1)
	_grid[start.y][start.x] = false
	stack.append(start)
	var dirs: Array[Vector2i] = [
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)
	]
	while not stack.is_empty():
		var cur: Vector2i = stack[stack.size() - 1]
		var options: Array[Vector2i] = []
		for d in dirs:
			var nx: int = cur.x + d.x
			var ny: int = cur.y + d.y
			if nx > 0 and nx < cols - 1 and ny > 0 and ny < rows - 1 and bool(_grid[ny][nx]):
				options.append(Vector2i(nx, ny))
		if options.is_empty():
			stack.pop_back()
			continue
		var chosen: Vector2i = options[_rng.randi_range(0, options.size() - 1)]
		# Knock out the wall between cur and chosen.
		_grid[int((cur.y + chosen.y) / 2)][int((cur.x + chosen.x) / 2)] = false
		_grid[chosen.y][chosen.x] = false
		stack.append(chosen)

	# Pac-Man style: carve through-lines + lots of loops so corridors interconnect.
	_carve_pacman_openings()


func _carve_pacman_openings() -> void:
	# A few full-length avenues (top, middle, bottom) for clean escape routes.
	var avenue_ys: Array[int] = [1, int(rows / 2) | 1, rows - 2]
	for y in avenue_ys:
		y = clampi(y, 1, rows - 2)
		if y % 2 == 0:
			y += 1
		y = clampi(y, 1, rows - 2)
		for x in range(1, cols - 1):
			_grid[y][x] = false

	# Matching vertical avenues (left, middle, right).
	var avenue_xs: Array[int] = [1, int(cols / 2) | 1, cols - 2]
	for x in avenue_xs:
		x = clampi(x, 1, cols - 2)
		if x % 2 == 0:
			x += 1
		x = clampi(x, 1, cols - 2)
		for y in range(1, rows - 1):
			_grid[y][x] = false

	# Punch a modest number of loop-making walls — enough to avoid dead ends
	# without dissolving the maze into an open field.
	var candidates: Array[Vector2i] = []
	for y in range(1, rows - 1):
		for x in range(1, cols - 1):
			if not bool(_grid[y][x]):
				continue
			var open_n := 0
			if x > 0 and not bool(_grid[y][x - 1]):
				open_n += 1
			if x < cols - 1 and not bool(_grid[y][x + 1]):
				open_n += 1
			if y > 0 and not bool(_grid[y - 1][x]):
				open_n += 1
			if y < rows - 1 and not bool(_grid[y + 1][x]):
				open_n += 1
			# Prefer walls that already bridge two open cells (loop makers).
			if open_n >= 2:
				candidates.append(Vector2i(x, y))
	candidates.shuffle()
	var punch := maxi(int(float(candidates.size()) * 0.18), 8)
	for i in mini(punch, candidates.size()):
		var c: Vector2i = candidates[i]
		_grid[c.y][c.x] = false

	# Keep a solid outer border.
	for x in cols:
		_grid[0][x] = true
		_grid[rows - 1][x] = true
	for y in rows:
		_grid[y][0] = true
		_grid[y][cols - 1] = true


func _render_maze() -> void:
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	walls.collision_layer = 4
	walls.collision_mask = 0
	add_child(walls)

	# One draw node instead of hundreds of Polygon2Ds (web-friendly).
	var drawer := MazeDrawer.new()
	drawer.name = "MazeDraw"
	drawer.z_index = -8
	drawer.setup(self)
	add_child(drawer)

	for y in rows:
		for x in cols:
			if not bool(_grid[y][x]):
				continue
			var col := CollisionShape2D.new()
			var shape := RectangleShape2D.new()
			shape.size = Vector2(cell, cell)
			col.shape = shape
			col.position = _cell_center(x, y)
			walls.add_child(col)


class MazeDrawer extends Node2D:
	var _maze: Node2D

	func setup(maze: Node2D) -> void:
		_maze = maze
		queue_redraw()

	func _draw() -> void:
		if _maze == null:
			return
		var g: Array = _maze.get("_grid")
		var c: float = float(_maze.get("cell"))
		var origin: Vector2 = _maze.get("_origin")
		var cols_n: int = int(_maze.get("cols"))
		var rows_n: int = int(_maze.get("rows"))
		for y in rows_n:
			for x in cols_n:
				var pos := origin + Vector2((float(x) + 0.5) * c, (float(y) + 0.5) * c)
				var half := c * 0.5
				var rect := Rect2(pos.x - half, pos.y - half, c, c)
				if bool(g[y][x]):
					draw_rect(rect, Color(0.12, 0.26, 0.12, 1.0), true)
					var top := Rect2(rect.position + Vector2(c * 0.09, -c * 0.16), Vector2(c * 0.82, c * 0.82))
					draw_rect(top, Color(0.18, 0.36, 0.18, 1.0), true)
				else:
					var floor_c := (
						Color(0.28, 0.40, 0.22, 0.55)
						if (x + y) % 2 == 0
						else Color(0.24, 0.36, 0.20, 0.52)
					)
					draw_rect(rect, floor_c, true)


func _spawn_player() -> void:
	_player = CharacterBody2D.new()
	_player.name = "Monkey"
	_player.collision_layer = 1
	_player.collision_mask = 4
	_player.position = _cell_center(1, 1)
	_player.add_to_group("player")

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = cell * 0.3
	col.shape = shape
	_player.add_child(col)

	var shadow := Polygon2D.new()
	shadow.color = Color(0, 0, 0, 0.32)
	shadow.z_index = 4
	var r := cell * 0.28
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		pts.append(Vector2(cos(a) * r, sin(a) * r * 0.5 + cell * 0.24))
	shadow.polygon = pts
	_player.add_child(shadow)

	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = load(TEX_MONKEY) as Texture2D
	spr.scale = Vector2(MONKEY_VISUAL_SCALE, MONKEY_VISUAL_SCALE)
	spr.offset = Vector2(0, -14)
	spr.z_index = 5
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player.add_child(spr)

	# Particles/afterimages are desktop-only — cheaper path for itch.io web.
	if not _is_web():
		_trail = CPUParticles2D.new()
		_trail.name = "MoveTrail"
		_trail.z_index = -4
		_trail.emitting = false
		_trail.amount = 28
		_trail.lifetime = 0.45
		_trail.preprocess = 0.0
		_trail.explosiveness = 0.0
		_trail.randomness = 0.4
		_trail.local_coords = false
		_trail.direction = Vector2(0, -1)
		_trail.spread = 50.0
		_trail.gravity = Vector2(0, -20)
		_trail.initial_velocity_min = 18.0
		_trail.initial_velocity_max = 55.0
		_trail.scale_amount_min = 2.5
		_trail.scale_amount_max = 5.5
		_trail.color = Color(1.0, 0.88, 0.35, 0.75)
		var grad := Gradient.new()
		grad.colors = PackedColorArray([
			Color(1.0, 0.95, 0.45, 0.8),
			Color(1.0, 0.55, 0.15, 0.35),
			Color(0.6, 0.25, 0.05, 0.0),
		])
		_trail.color_ramp = grad
		_player.add_child(_trail)
		_player.move_child(_trail, 0)

	add_child(_player)


func _spawn_bananas() -> void:
	var floor_cells: Array[Vector2i] = []
	for y in rows:
		for x in cols:
			if not bool(_grid[y][x]) and not (x == 1 and y == 1):
				floor_cells.append(Vector2i(x, y))
	floor_cells.shuffle()
	_total = mini(banana_count, floor_cells.size())
	var tex := load(TEX_BANANA) as Texture2D
	for i in _total:
		var c := floor_cells[i]
		var area := Area2D.new()
		area.collision_layer = 0
		area.collision_mask = 1
		area.position = _cell_center(c.x, c.y)
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = cell * 0.34
		shape.shape = circle
		area.add_child(shape)
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.scale = Vector2(0.55, 0.55)
		spr.z_index = 3
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		area.add_child(spr)
		# Gentle bob so pickups pop (skip endless tweens on web).
		if not _is_web():
			var tw := create_tween().set_loops()
			tw.tween_property(spr, "position:y", -4.0, 0.5).set_trans(Tween.TRANS_SINE)
			tw.tween_property(spr, "position:y", 2.0, 0.5).set_trans(Tween.TRANS_SINE)
		area.body_entered.connect(_on_banana_collected.bind(area))
		add_child(area)
		_bananas.append(area)


func _spawn_leopard() -> void:
	_leopard = CharacterBody2D.new()
	_leopard.set_script(LEOPARD_SCRIPT)
	add_child(_leopard)
	_leopard.call("setup", self, _player, _on_leopard_caught, leopard_speed)
	_leopard.call("place_at_cell", _far_open_cell())
	_grace_t = leopard_grace
	_leopard.call("set_active", false)


func _physics_process(delta: float) -> void:
	if _done or _player == null:
		return
	_time += delta
	_invuln_t = maxf(_invuln_t - delta, 0.0)
	if _grace_t > 0.0:
		_grace_t = maxf(_grace_t - delta, 0.0)
		if _grace_t <= 0.0 and _leopard and is_instance_valid(_leopard):
			_leopard.call("set_active", true)
			_leopard.call("arm_catch", _invuln_t <= 0.0)
			_hint.text = "The leopard is hunting — keep moving!"

	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_player.velocity = dir * move_speed
	_player.move_and_slide()
	var moving := dir.length() > 0.15
	var spr := _player.get_node_or_null("Sprite") as Sprite2D
	if spr:
		if absf(_player.velocity.x) > 12.0:
			spr.scale.x = MONKEY_VISUAL_SCALE * signf(_player.velocity.x)
			spr.scale.y = MONKEY_VISUAL_SCALE
		# Blink while invulnerable after a catch.
		if _invuln_t > 0.0:
			spr.modulate.a = 0.35 if int(_invuln_t * 10.0) % 2 == 0 else 1.0
		else:
			spr.modulate.a = 1.0
	if _trail and is_instance_valid(_trail):
		_trail.emitting = moving
		if moving:
			_trail.direction = -_player.velocity.normalized() if _player.velocity.length() > 1.0 else Vector2(0, -1)
			if not _is_web() and randf() < delta * 18.0:
				_spawn_afterimage(spr)
	if _leopard and is_instance_valid(_leopard) and _leopard.has_method("arm_catch"):
		_leopard.call("arm_catch", _invuln_t <= 0.0 and _grace_t <= 0.0 and not _catching)
	_update_status()


func _spawn_afterimage(spr: Sprite2D) -> void:
	if spr == null or spr.texture == null or _player == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = spr.texture
	ghost.global_position = spr.global_position
	ghost.scale = spr.scale * 0.95
	ghost.offset = spr.offset
	ghost.modulate = Color(1.0, 0.85, 0.35, 0.45)
	ghost.z_index = _player.z_index - 1
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(ghost)
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.28)
	tw.parallel().tween_property(ghost, "scale", ghost.scale * 1.15, 0.28)
	tw.tween_callback(ghost.queue_free)


func _on_banana_collected(body: Node2D, area: Area2D) -> void:
	if _done or body != _player or not is_instance_valid(area):
		return
	_collected += 1
	_bananas.erase(area)
	area.queue_free()
	GameProgress.juice_shake.emit(0.06)
	_update_status()
	if _collected >= _total:
		_succeed()


func _on_leopard_caught(body: Node2D) -> void:
	if _done or _catching or _invuln_t > 0.0 or _grace_t > 0.0:
		return
	if body != _player:
		return
	_catching = true
	_lives -= 1
	GameAudio.play(self, SFX_HURT, false, -2.0)
	GameProgress.juice_shake.emit(0.35)
	if _lives <= 0:
		_hint.text = "Caught! Out of lives — maze resets."
		_update_status()
		await get_tree().create_timer(0.85).timeout
		_restart_run()
		return
	_hint.text = "Caught! %d %s left — keep collecting." % [_lives, "life" if _lives == 1 else "lives"]
	_invuln_t = 1.6
	if _player:
		_player.global_position = cell_center(1, 1)
		_player.velocity = Vector2.ZERO
	if _leopard and is_instance_valid(_leopard):
		_leopard.call("place_at_cell", _far_open_cell())
		_leopard.call("arm_catch", false)
	_catching = false
	_update_status()


func _restart_run() -> void:
	# Full restart: new maze layout, bananas, lives, timer.
	get_tree().reload_current_scene()


func _succeed() -> void:
	_done = true
	if _leopard and is_instance_valid(_leopard):
		_leopard.call("set_active", false)
	_hint.text = "All bananas collected in %.1fs! Nice route." % _time
	GameProgress.juice_shake.emit(0.35)
	await get_tree().create_timer(1.3).timeout
	GameProgress.complete_minigame(GameProgress.MODE_CART)


func _update_status() -> void:
	_status.text = "Bananas %d/%d   ·   Lives %d   ·   %.1fs" % [_collected, _total, _lives, _time]


func _far_open_cell() -> Vector2i:
	# Prefer the opposite corner from the monkey spawn.
	var candidates: Array[Vector2i] = [
		Vector2i(cols - 2, rows - 2),
		Vector2i(cols - 2, 1),
		Vector2i(1, rows - 2),
	]
	for c in candidates:
		if is_open_cell(c.x, c.y):
			return c
	for y in range(rows - 2, 0, -1):
		for x in range(cols - 2, 0, -1):
			if is_open_cell(x, y) and not (x == 1 and y == 1):
				return Vector2i(x, y)
	return Vector2i(cols - 2, rows - 2)


## Public helpers used by maze_leopard.gd pathfinding.
func cell_center(x: int, y: int) -> Vector2:
	return _cell_center(x, y)


func world_to_cell(world: Vector2) -> Vector2i:
	var local := world - _origin
	var x := clampi(int(floor(local.x / cell)), 0, cols - 1)
	var y := clampi(int(floor(local.y / cell)), 0, rows - 1)
	return Vector2i(x, y)


func is_open_cell(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return false
	return not bool(_grid[y][x])


func _cell_center(x: int, y: int) -> Vector2:
	return _origin + Vector2((float(x) + 0.5) * cell, (float(y) + 0.5) * cell)


func _cell_rect(center: Vector2, size: float) -> PackedVector2Array:
	var h := size * 0.5
	return PackedVector2Array([
		center + Vector2(-h, -h), center + Vector2(h, -h),
		center + Vector2(h, h), center + Vector2(-h, h),
	])
