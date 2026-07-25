extends CharacterBody2D

## Pac-Man-style maze chaser — BFS through open cells toward the monkey.

## Walk sheet (not run): FreePixel's run sheet has many empty direction rows,
## which made the leopard vanish whenever it faced those ways.
const WALK_TEX := "res://assets/sprites/leopard/walk.png"
const HFRAMES := 6
const VFRAMES := 8
## FreePixel rows with art on walk: 0=S, 2=W, 3=NW, 4=N, 5=NE, 7=SE
## (rows 1=SW and 6=E are empty — we use W + flip_h for east/west)

@export var move_speed: float = 175.0
@export var anim_fps: float = 12.0
@export var repath_interval: float = 0.22

var _maze: Node
var _target: Node2D
var _on_caught: Callable
var _spr: Sprite2D
var _hit: Area2D
var _frame_t: float = 0.0
var _active: bool = false
var _path: Array[Vector2i] = []
var _repath_t: float = 0.0
var _catch_armed: bool = true


func setup(maze: Node, target: Node2D, on_caught: Callable, speed: float = 175.0) -> void:
	_maze = maze
	_target = target
	_on_caught = on_caught
	move_speed = speed
	collision_layer = 0
	collision_mask = 4
	motion_mode = MOTION_MODE_FLOATING
	add_to_group("maze_leopard")
	_build_visual()
	z_index = 6


func set_active(active: bool) -> void:
	_active = active
	visible = true
	if _hit:
		_hit.monitoring = active and _catch_armed


func arm_catch(armed: bool) -> void:
	_catch_armed = armed
	if _hit:
		_hit.monitoring = _active and _catch_armed


func place_at_cell(cell: Vector2i) -> void:
	if _maze and _maze.has_method("cell_center"):
		global_position = _maze.cell_center(cell.x, cell.y)
	_path.clear()
	_repath_t = 0.0


func _build_visual() -> void:
	_spr = Sprite2D.new()
	var tex: Texture2D = null
	# Prefer imported texture; fall back to raw image if import hasn't caught up.
	if ResourceLoader.exists(WALK_TEX):
		tex = load(WALK_TEX) as Texture2D
	if tex == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path(WALK_TEX))
		if img != null:
			tex = ImageTexture.create_from_image(img)
	_spr.texture = tex
	_spr.hframes = HFRAMES
	_spr.vframes = VFRAMES
	_spr.frame_coords = Vector2i(0, 0)
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Visual only — collision + catch radii below stay unchanged.
	_spr.scale = Vector2(0.58, 0.58)
	_spr.offset = Vector2(0, -8)
	add_child(_spr)

	var shadow := Polygon2D.new()
	shadow.z_index = -1
	shadow.color = Color(0, 0, 0, 0.3)
	shadow.polygon = PackedVector2Array([
		Vector2(-16, 10), Vector2(16, 10), Vector2(11, 18), Vector2(-11, 18)
	])
	add_child(shadow)

	var body_col := CollisionShape2D.new()
	var body_shape := CircleShape2D.new()
	body_shape.radius = 14.0
	body_col.shape = body_shape
	add_child(body_col)

	_hit = Area2D.new()
	_hit.collision_layer = 0
	_hit.collision_mask = 1
	_hit.monitoring = false
	_hit.monitorable = false
	_hit.body_entered.connect(_on_body_entered)
	var hit_col := CollisionShape2D.new()
	var hit_shape := CircleShape2D.new()
	hit_shape.radius = 18.0
	hit_col.shape = hit_shape
	_hit.add_child(hit_col)
	add_child(_hit)


func _physics_process(delta: float) -> void:
	if not _active or _maze == null or _target == null or not is_instance_valid(_target):
		velocity = Vector2.ZERO
		return

	_repath_t -= delta
	if _repath_t <= 0.0 or _path.is_empty():
		_repath_t = repath_interval
		_rebuild_path()

	var goal := global_position
	if not _path.is_empty():
		var next: Vector2i = _path[0]
		goal = _maze.cell_center(next.x, next.y)
		if global_position.distance_to(goal) < 10.0:
			_path.pop_front()
			if not _path.is_empty():
				next = _path[0]
				goal = _maze.cell_center(next.x, next.y)

	var to := goal - global_position
	if to.length() > 1.0:
		velocity = to.normalized() * move_speed
	else:
		var direct := _target.global_position - global_position
		velocity = direct.normalized() * move_speed if direct.length() > 4.0 else Vector2.ZERO

	move_and_slide()
	_animate(delta, velocity)


func _rebuild_path() -> void:
	_path.clear()
	if not _maze.has_method("world_to_cell") or not _maze.has_method("is_open_cell"):
		return
	var start: Vector2i = _maze.world_to_cell(global_position)
	var goal: Vector2i = _maze.world_to_cell(_target.global_position)
	if start == goal:
		return
	_path = _bfs(start, goal)


func _bfs(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var q: Array[Vector2i] = [start]
	var came: Dictionary = {}
	came[start] = start
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	var found := false
	var guard := 0
	while not q.is_empty() and guard < 2500:
		guard += 1
		var cur: Vector2i = q.pop_front()
		if cur == goal:
			found = true
			break
		for d in dirs:
			var n := cur + d
			if came.has(n):
				continue
			if not bool(_maze.is_open_cell(n.x, n.y)):
				continue
			came[n] = cur
			q.append(n)
	if not found:
		return []
	var out: Array[Vector2i] = []
	var step := goal
	while step != start:
		out.push_front(step)
		step = came[step] as Vector2i
	return out


func _animate(delta: float, dir: Vector2) -> void:
	if _spr == null or _spr.texture == null:
		return
	if dir.length_squared() > 4.0:
		_frame_t += delta * anim_fps
		_spr.frame_coords = Vector2i(int(_frame_t) % HFRAMES, _dir_row(dir))
	else:
		_spr.frame_coords = Vector2i(0, _spr.frame_coords.y)


func _dir_row(dir: Vector2) -> int:
	# Stick to filled walk-sheet rows so the sprite never blanks out.
	if absf(dir.x) >= absf(dir.y):
		# Row 2 is west-facing; flip for east.
		_spr.flip_h = dir.x > 0.0
		return 2
	_spr.flip_h = false
	return 4 if dir.y < 0.0 else 0


func _on_body_entered(body: Node2D) -> void:
	if not _active or not _catch_armed:
		return
	if _on_caught.is_valid():
		_on_caught.call(body)
