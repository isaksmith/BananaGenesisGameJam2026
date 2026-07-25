extends Area2D

## Slow side-view chase predator for the jungle trail.

const RUN_TEX := "res://assets/sprites/tiger/run.png"
const RUN_FRAMES := 7
const FRAME_SIZE := 32

@export var chase_speed: float = 160.0
@export var vertical_speed: float = 110.0
@export var anim_fps: float = 10.0

var _target: Node2D
var _on_caught: Callable
var _spr: Sprite2D
var _frame_t: float = 0.0
var _active: bool = true


func setup(target: Node2D, on_caught: Callable, speed: float = 160.0) -> void:
	_target = target
	_on_caught = on_caught
	chase_speed = speed
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	_build_visual()
	z_index = 4


func set_active(active: bool) -> void:
	_active = active
	monitoring = active
	visible = active


func _build_visual() -> void:
	_spr = Sprite2D.new()
	_spr.texture = load(RUN_TEX) as Texture2D
	_spr.hframes = RUN_FRAMES
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_spr.scale = Vector2(2.2, 2.2)
	_spr.offset = Vector2(0, -8)
	add_child(_spr)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(36, 28)
	col.shape = shape
	col.position = Vector2(0, -6)
	add_child(col)


func _physics_process(delta: float) -> void:
	if not _active or _target == null or not is_instance_valid(_target):
		return
	var goal := _target.global_position
	var to := goal - global_position
	if absf(to.x) > 2.0:
		global_position.x += signf(to.x) * chase_speed * delta
		if _spr:
			_spr.flip_h = to.x < 0.0
	global_position.y = move_toward(global_position.y, goal.y + 10.0, vertical_speed * delta)
	_frame_t += delta * anim_fps
	if _spr:
		_spr.frame = int(_frame_t) % RUN_FRAMES


func _on_body_entered(body: Node2D) -> void:
	if not _active:
		return
	if _on_caught.is_valid():
		_on_caught.call(body)
