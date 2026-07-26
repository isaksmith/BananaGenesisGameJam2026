extends CharacterBody2D

## Mushroom Grove hazard: hops toward the player along platforms / through air.

const TEX_OPTIONS := [
	"res://assets/sprites/mushroom/Mushrooms64x64.png",
	"res://assets/sprites/mushroom/Mushrooms64x65.png",
	"res://assets/sprites/mushroom/Mushrooms64x68.png",
	"res://assets/sprites/mushroom/Mushrooms64x70.png",
	"res://assets/sprites/mushroom/Mushrooms64x72.png",
	"res://assets/sprites/mushroom/hop/red.png",
	"res://assets/sprites/mushroom/hop/purple.png",
	"res://assets/sprites/mushroom/hop/pink.png",
	"res://assets/sprites/mushroom/hop/blue.png",
]

## Roughly player / wheel size on the trail.
const TARGET_HEIGHT := 46.0
const GRAVITY := 1700.0
const MAX_FALL := 980.0

@export var hop_speed: float = 95.0
@export var hop_impulse: float = 420.0

var _on_hit: Callable
var _target: Node2D
var _spr: Sprite2D
var _overlay: Sprite2D
var _aura: Polygon2D
var _active: bool = true
var _radius: float = 12.0
var _hit_area: Area2D
var _hop_cd: float = 0.0
var _armed: bool = true
var _base_scale: float = 0.7
var _hue: float = 0.0


func setup(on_hit: Callable, target: Node2D, speed: float = 95.0, scale_mul: float = 1.0) -> void:
	_on_hit = on_hit
	_target = target
	hop_speed = speed
	collision_layer = 0
	collision_mask = 4
	floor_stop_on_slope = false
	add_to_group("hop_mushroom")
	_hue = randf()
	_build_visual(scale_mul)
	_build_hitbox()
	_hop_cd = randf_range(0.05, 0.35)
	z_index = 6


func set_active(active: bool) -> void:
	_active = active
	visible = active
	set_physics_process(active)
	if _hit_area:
		_hit_area.monitoring = active and _armed


func _build_visual(scale_mul: float) -> void:
	var path: String = TEX_OPTIONS[randi() % TEX_OPTIONS.size()]
	var tex := load(path) as Texture2D
	var tex_h := 64.0
	if tex != null:
		tex_h = maxf(float(tex.get_height()), 1.0)
	_base_scale = (TARGET_HEIGHT / tex_h) * scale_mul
	var spr_pos := Vector2(0, -TARGET_HEIGHT * 0.42 * scale_mul)

	# Soft rainbow aura behind the shroom.
	_aura = Polygon2D.new()
	_aura.z_index = -1
	var pts := PackedVector2Array()
	var r := 18.0 * scale_mul
	for i in 12:
		var ang := TAU * float(i) / 12.0
		pts.append(Vector2(cos(ang), sin(ang)) * r + spr_pos * 0.35)
	_aura.polygon = pts
	_aura.color = Color(1, 0.4, 1, 0.35)
	add_child(_aura)

	_spr = Sprite2D.new()
	_spr.texture = tex
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_spr.scale = Vector2(_base_scale, _base_scale)
	_spr.position = spr_pos
	add_child(_spr)

	# Additive rainbow wash over the same sprite (same idea as the screen trip).
	_overlay = Sprite2D.new()
	_overlay.texture = tex
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay.scale = Vector2(_base_scale, _base_scale)
	_overlay.position = spr_pos
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_overlay.material = mat
	_overlay.modulate = Color(1, 1, 1, 0.55)
	add_child(_overlay)

	_radius = 11.0 * scale_mul

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = _radius
	col.shape = shape
	add_child(col)


func _build_hitbox() -> void:
	_hit_area = Area2D.new()
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = 1
	_hit_area.monitoring = true
	_hit_area.monitorable = false
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = _radius * 1.15
	col.shape = shape
	_hit_area.add_child(col)
	_hit_area.body_entered.connect(_on_body_entered)
	add_child(_hit_area)


func _update_rainbow(delta: float) -> void:
	_hue = fmod(_hue + delta * 0.9, 1.0)
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008 + _hue * TAU)
	var tint := Color.from_hsv(_hue, 0.8, 1.0)
	if _spr:
		_spr.modulate = Color(1.05, 1.05, 1.05, 1.0).lerp(tint, 0.45)
	if _overlay:
		_overlay.modulate = Color.from_hsv(_hue, 0.75, 1.25, 0.4 + 0.35 * pulse)
		_overlay.scale = _spr.scale if _spr else Vector2(_base_scale, _base_scale)
		_overlay.flip_h = _spr.flip_h if _spr else false
	if _aura:
		_aura.color = Color.from_hsv(fmod(_hue + 0.2, 1.0), 0.7, 1.0, 0.22 + 0.18 * pulse)
		_aura.scale = Vector2(0.9 + 0.15 * pulse, 0.9 + 0.15 * pulse)


func _physics_process(delta: float) -> void:
	if not _active:
		return

	var toward := -1.0
	if _target != null and is_instance_valid(_target):
		toward = signf(_target.global_position.x - global_position.x)
		if toward == 0.0:
			toward = -1.0

	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	else:
		_hop_cd -= delta
		velocity.x = toward * hop_speed
		if _hop_cd <= 0.0:
			velocity.y = -hop_impulse * randf_range(0.85, 1.15)
			_hop_cd = randf_range(0.45, 0.85)
			if _spr:
				_spr.scale = Vector2(_base_scale * 1.12, _base_scale * 0.78)

	if _spr:
		_spr.scale.x = move_toward(_spr.scale.x, _base_scale, delta * 5.0)
		_spr.scale.y = move_toward(_spr.scale.y, _base_scale, delta * 5.0)
		if absf(velocity.x) > 8.0:
			_spr.flip_h = velocity.x > 0.0

	_update_rainbow(delta)
	move_and_slide()

	if global_position.y > 860.0 or global_position.x < -480.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if not _active or not _armed:
		return
	if _on_hit.is_valid():
		_on_hit.call(body, self)
	_armed = false
	if _hit_area:
		_hit_area.monitoring = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(self, "scale", Vector2(1.6, 0.4), 0.25)
	tw.tween_callback(queue_free)
