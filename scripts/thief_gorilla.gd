extends CharacterBody2D

## Animated gorilla that walks toward the banana stash and steals one.

const WALK_TEX := "res://assets/sprites/gorilla/walk.png"
const BANANA_TEX := "res://assets/sprites/banana.png"
const HFRAMES := 6
const VFRAMES := 4
## Sheet rows: 0=down, 1=left, 2=up, 3=right

@export var move_speed: float = 95.0
@export var anim_fps: float = 9.0
@export var hits_to_kill: int = 3
@export var hit_cooldown: float = 0.35

var _target: Node2D
var _on_steal: Callable
var _spr: Sprite2D
var _banana_spr: Sprite2D
var _frame_t: float = 0.0
var _active: bool = true
var _fleeing: bool = false
var _flee_dir: Vector2 = Vector2.ZERO
var _knock_vel: Vector2 = Vector2.ZERO
var _steal_radius: float = 42.0
var _hits: int = 0
var _hit_cd: float = 0.0
var _dead: bool = false


func setup(target: Node2D, on_steal: Callable, speed: float = 95.0) -> void:
	_target = target
	_on_steal = on_steal
	move_speed = speed
	collision_layer = 0
	collision_mask = 0
	add_to_group("thief_gorilla")
	_build_visual()
	z_index = 6


func is_fleeing() -> bool:
	return _fleeing


func is_dead() -> bool:
	return _dead


func hits_left() -> int:
	return maxi(hits_to_kill - _hits, 0)


## 0 = ignored (cooldown/dead), 1 = landed hit, 2 = fatal hit.
func register_hit(from: Vector2, strength: float = 300.0) -> int:
	if _dead or _fleeing:
		return 0
	if _hit_cd > 0.0:
		return 0
	_hit_cd = hit_cooldown
	_hits += 1
	knock_back(from, strength)
	if _spr:
		_spr.modulate = Color(1.0, 0.55, 0.45, 1)
	if _hits >= hits_to_kill:
		_dead = true
		_active = false
		return 2
	return 1


func knock_back(from: Vector2, strength: float = 280.0) -> void:
	if _fleeing or _dead:
		return
	var dir := (global_position - from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT.rotated(randf() * TAU)
	_knock_vel = dir * strength


func _build_visual() -> void:
	_spr = Sprite2D.new()
	var img := Image.load_from_file(ProjectSettings.globalize_path(WALK_TEX))
	if img != null:
		_spr.texture = ImageTexture.create_from_image(img)
	else:
		_spr.texture = load(WALK_TEX) as Texture2D
	_spr.hframes = HFRAMES
	_spr.vframes = VFRAMES
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_spr.scale = Vector2(0.85, 0.85)
	_spr.offset = Vector2(0, -10)
	add_child(_spr)

	_banana_spr = Sprite2D.new()
	_banana_spr.name = "StolenBanana"
	_banana_spr.texture = load(BANANA_TEX) as Texture2D
	_banana_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_banana_spr.scale = Vector2(0.7, 0.7)
	_banana_spr.position = Vector2(18, -6)
	_banana_spr.z_index = 1
	_banana_spr.visible = false
	add_child(_banana_spr)

	var shadow := Polygon2D.new()
	shadow.z_index = -1
	shadow.color = Color(0, 0, 0, 0.3)
	shadow.polygon = PackedVector2Array([
		Vector2(-22, 18), Vector2(22, 18), Vector2(14, 28), Vector2(-14, 28)
	])
	add_child(shadow)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 22.0
	col.shape = shape
	col.position = Vector2(0, 4)
	add_child(col)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not _active:
		return

	_hit_cd = maxf(_hit_cd - delta, 0.0)
	if _spr and _hit_cd <= 0.0 and _spr.modulate != Color.WHITE:
		_spr.modulate = _spr.modulate.lerp(Color.WHITE, delta * 8.0)

	if _knock_vel.length() > 8.0:
		global_position += _knock_vel * delta
		_knock_vel = _knock_vel.move_toward(Vector2.ZERO, 520.0 * delta)
		_animate(delta, _knock_vel)
		_clamp_arena()
		return

	if _fleeing:
		if _flee_dir.length_squared() < 0.01:
			_flee_dir = (global_position - Vector2(640, 360)).normalized()
			if _flee_dir.length_squared() < 0.01:
				_flee_dir = Vector2.RIGHT.rotated(randf() * TAU)
		velocity = _flee_dir * move_speed * 1.35
		global_position += velocity * delta
		_animate(delta, velocity)
		_update_carried_banana()
		if global_position.x < -100 or global_position.x > 1380 \
				or global_position.y < -100 or global_position.y > 820:
			queue_free()
		return

	if _target == null or not is_instance_valid(_target):
		return

	var to := _target.global_position - global_position
	if to.length() <= _steal_radius:
		if _on_steal.is_valid() and _on_steal.call(self):
			_begin_flee(true)
		else:
			# Never park on the stash — leave room for new spawns.
			_begin_flee(false)
		return

	velocity = to.normalized() * move_speed
	global_position += velocity * delta
	_animate(delta, velocity)
	_clamp_arena()


func _begin_flee(with_banana: bool) -> void:
	_fleeing = true
	_knock_vel = Vector2.ZERO
	_flee_dir = (global_position - Vector2(640, 360)).normalized()
	if _flee_dir.length_squared() < 0.01:
		_flee_dir = Vector2.RIGHT.rotated(randf() * TAU)
	if with_banana and _banana_spr:
		_banana_spr.visible = true
		_update_carried_banana()


func _update_carried_banana() -> void:
	if _banana_spr == null or not _banana_spr.visible:
		return
	# Hold the banana on the leading side while walking away.
	var side := 1.0 if _flee_dir.x >= 0.0 else -1.0
	_banana_spr.position = Vector2(18.0 * side, -8.0)
	_banana_spr.rotation = sin(Time.get_ticks_msec() * 0.012) * 0.2


func _animate(delta: float, dir: Vector2) -> void:
	if _spr == null:
		return
	_frame_t += delta * anim_fps
	_spr.frame_coords = Vector2i(int(_frame_t) % HFRAMES, _dir_row(dir))


func _dir_row(dir: Vector2) -> int:
	if dir.length_squared() < 0.01:
		return 0
	if absf(dir.x) > absf(dir.y):
		return 1 if dir.x < 0.0 else 3
	return 2 if dir.y < 0.0 else 0


func _clamp_arena() -> void:
	global_position.x = clampf(global_position.x, 40.0, 1240.0)
	global_position.y = clampf(global_position.y, 60.0, 680.0)
