extends CharacterBody2D

## Desert hazard: rolls left on platforms, then falls with gravity off ledges / into gaps.

const TEX := "res://assets/sprites/hazards/tumbleweed.png"
const GRAVITY := 1600.0
const MAX_FALL := 900.0

@export var roll_speed: float = 70.0

var _on_hit: Callable
var _spr: Sprite2D
var _active: bool = true
var _radius: float = 7.0
var _visual_r: float = 8.0
var _hit_area: Area2D


func setup(on_hit: Callable, speed: float = 70.0, scale_mul: float = 1.0) -> void:
	_on_hit = on_hit
	roll_speed = speed
	collision_layer = 0
	collision_mask = 4 # platforms only
	floor_stop_on_slope = false
	floor_max_angle = deg_to_rad(70.0)
	add_to_group("tumbleweed")
	_build_visual(scale_mul)
	_build_hitbox()
	velocity = Vector2(-roll_speed, 0.0)
	z_index = 5


func set_active(active: bool) -> void:
	_active = active
	visible = active
	set_physics_process(active)
	if _hit_area:
		_hit_area.monitoring = active


func _build_visual(scale_mul: float) -> void:
	_spr = Sprite2D.new()
	var img := Image.load_from_file(ProjectSettings.globalize_path(TEX))
	if img != null:
		_spr.texture = ImageTexture.create_from_image(img)
	else:
		_spr.texture = load(TEX) as Texture2D
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var s := 1.15 * scale_mul
	_spr.scale = Vector2(s, s)
	_spr.modulate = Color(1.1, 0.95, 0.75, 1.0)
	# Lift the art above the collider so weeds sit on top of the sand, not in it.
	_spr.position = Vector2(0, -7)
	add_child(_spr)
	_visual_r = 8.0 * scale_mul
	_radius = 7.0 * scale_mul

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = _radius
	col.shape = shape
	col.position = Vector2(0, 0)
	add_child(col)


func _build_hitbox() -> void:
	_hit_area = Area2D.new()
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = 1
	_hit_area.monitoring = true
	_hit_area.monitorable = false
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = _radius * 1.05
	col.shape = shape
	_hit_area.add_child(col)
	_hit_area.body_entered.connect(_on_body_entered)
	add_child(_hit_area)


func _physics_process(delta: float) -> void:
	if not _active:
		return

	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	else:
		# Keep a steady leftward roll while grounded.
		velocity.x = -roll_speed
		if velocity.y > 0.0:
			velocity.y = 0.0

	# Preserve sideways speed in air (no air control, just carry momentum).
	if not is_on_floor() and absf(velocity.x) < roll_speed * 0.35:
		velocity.x = -roll_speed * 0.55

	move_and_slide()

	if _spr and _visual_r > 0.1:
		var spin_v := absf(velocity.x) if is_on_floor() else absf(velocity.x) * 0.65
		_spr.rotation += (spin_v / _visual_r) * delta

	# Off the bottom of the course (fell into a gap) or far behind camera lead.
	if global_position.y > 820.0 or global_position.x < -400.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if not _active:
		return
	if _on_hit.is_valid():
		_on_hit.call(body)
