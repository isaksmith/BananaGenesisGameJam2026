class_name WheelObstacles
extends RefCounted

## Obstacle builders — floor spikes from floor spikes pack + Kenney saws/pads.

const TEX_SPIKE_SMALL_WOOD := "res://assets/sprites/floor_spikes/small_wood_spike.png"
const TEX_SPIKE_SMALL_METAL := "res://assets/sprites/floor_spikes/small_metal_spike.png"
const TEX_SPIKE_LONG_WOOD := "res://assets/sprites/floor_spikes/long_wood_spike.png"
const TEX_SPIKE_LONG_METAL := "res://assets/sprites/floor_spikes/long_metal_spike.png"
const TEX_SPIKE_BLOCK := "res://assets/sprites/hazards/spike_block.png"
const TEX_SAW := "res://assets/sprites/hazards/saw.png"
## Animated trap sheets (CC0) — horizontal strips of 32px frames
const TRAPS := {
	&"spike": {"path": "res://assets/sprites/traps/spike_trap.png", "frames": 14, "fps": 10.0},
	&"fire": {"path": "res://assets/sprites/traps/fire_trap.png", "frames": 14, "fps": 12.0},
	&"bear": {"path": "res://assets/sprites/traps/bear_trap.png", "frames": 4, "fps": 6.0},
}
const TEX_SPRING := "res://assets/sprites/hazards/spring.png"
const TEX_MOVER := "res://assets/sprites/hazards/block_moving.png"
const TEX_MOVER_LG := "res://assets/sprites/hazards/block_moving_large.png"
const TEX_MOVER_BLUE := "res://assets/sprites/hazards/block_moving_blue.png"

var _host: Node2D
var _on_hazard: Callable
var _on_pad: Callable
## true = metal spikes (tunnel/frost), false = wood (jungle tracks)
var use_metal_spikes: bool = false


func setup(host: Node2D, on_hazard: Callable, on_pad: Callable) -> void:
	_host = host
	_on_hazard = on_hazard
	_on_pad = on_pad


func _spike_tex(long: bool = false) -> String:
	if use_metal_spikes:
		return TEX_SPIKE_LONG_METAL if long else TEX_SPIKE_SMALL_METAL
	return TEX_SPIKE_LONG_WOOD if long else TEX_SPIKE_SMALL_WOOD


func _sprite(path: String, scale: float = 1.0, flip_v: bool = false) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = load(path) as Texture2D
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(scale, scale)
	spr.flip_v = flip_v
	return spr


## Keep hazards readable on green grass — never allow green-ish tints.
func _danger_modulate(color: Color) -> Color:
	if color.g > color.r and color.g > color.b:
		return Color(1.25, 0.35, 0.45, 1.0)
	return Color(
		clampf(color.r * 1.15 + 0.1, 0.0, 1.5),
		clampf(color.g * 0.85, 0.0, 1.2),
		clampf(color.b * 0.95, 0.0, 1.3),
		1.0
	)


func add_spike(pos: Vector2, upside_down: bool = false, scale: float = 1.0, color: Color = Color(1.2, 0.35, 0.4), long: bool = false) -> void:
	var area := Area2D.new()
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.body_entered.connect(func(b: Node2D) -> void: _on_hazard.call(b))
	var path := _spike_tex(long)
	var spr := _sprite(path, 0.38 * scale, upside_down)
	spr.modulate = _danger_modulate(color)
	var tex := spr.texture
	var h := float(tex.get_height()) * spr.scale.y if tex else 40.0
	var w := float(tex.get_width()) * spr.scale.x if tex else 36.0
	# Sit on ground / hang from ceiling (sprite origin is center)
	spr.offset = Vector2(0, h * 0.42 if upside_down else -h * 0.42)
	area.add_child(spr)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w * 0.7, h * 0.72)
	col.shape = shape
	col.position = Vector2(0, h * 0.22 if upside_down else -h * 0.28)
	area.add_child(col)
	_host.add_child(area)


func add_spike_row(origin: Vector2, count: int, spacing: float, upside_down: bool = false, scale: float = 1.0, color: Color = Color(1.2, 0.35, 0.4)) -> void:
	# Place individual spikes evenly — long spikes for denser packs
	var use_long := count >= 4
	for i in count:
		add_spike(origin + Vector2(spacing * float(i), 0.0), upside_down, scale, color, use_long)


func add_trap(pos: Vector2, kind: StringName = &"spike", scale: float = 1.4, color: Color = Color(1, 1, 1)) -> void:
	var info: Dictionary = TRAPS.get(kind, TRAPS[&"spike"])
	var area := Area2D.new()
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.body_entered.connect(func(b: Node2D) -> void: _on_hazard.call(b))
	var spr := _sprite(String(info["path"]), scale)
	var frames := int(info["frames"])
	spr.hframes = frames
	spr.modulate = color
	var frame_h := float(spr.texture.get_height()) * scale if spr.texture else 32.0 * scale
	var frame_w := 32.0 * scale
	spr.offset = Vector2(0, -spr.texture.get_height() * 0.5 if spr.texture else -16.0)
	area.add_child(spr)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(frame_w * 0.7, frame_h * 0.6)
	col.shape = shape
	col.position = Vector2(0, -frame_h * 0.35)
	area.add_child(col)
	_host.add_child(area)
	var fps := float(info["fps"])
	var tw := _host.create_tween().set_loops()
	tw.tween_method(
		func(f: float) -> void: spr.frame = int(f) % frames,
		0.0, float(frames), float(frames) / fps
	)


func add_saw(pos: Vector2, radius: float = 28.0, spin: float = 3.5, color: Color = Color(1.3, 0.55, 0.25)) -> void:
	var area := Area2D.new()
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.body_entered.connect(func(b: Node2D) -> void: _on_hazard.call(b))
	var s := (radius / 28.0) * 1.35
	var spr := _sprite(TEX_SAW, s)
	spr.modulate = _danger_modulate(color)
	area.add_child(spr)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius * 0.9
	col.shape = shape
	area.add_child(col)
	_host.add_child(area)
	var tw := _host.create_tween().set_loops()
	tw.tween_property(spr, "rotation", TAU, 1.0 / maxf(absf(spin), 0.1)).set_trans(Tween.TRANS_LINEAR)


func add_jump_pad(pos: Vector2, boost: float = 780.0, color: Color = Color(1, 1, 1)) -> void:
	var area := Area2D.new()
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.body_entered.connect(func(b: Node2D) -> void: _on_pad.call(b, boost))
	var spr := _sprite(TEX_SPRING, 1.15)
	spr.modulate = color
	spr.offset = Vector2(0, -10)
	area.add_child(spr)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(48, 28)
	col.shape = shape
	col.position = Vector2(0, -6)
	area.add_child(col)
	_host.add_child(area)
	var tw := _host.create_tween().set_loops()
	tw.tween_property(spr, "scale", Vector2(1.2, 1.05), 0.28).set_trans(Tween.TRANS_SINE)
	tw.tween_property(spr, "scale", Vector2(1.15, 1.15), 0.28).set_trans(Tween.TRANS_SINE)


func add_moving_platform(a: Vector2, b: Vector2, width: float = 140.0, period: float = 2.4, color: Color = Color(1, 1, 1)) -> void:
	var body := AnimatableBody2D.new()
	body.global_position = a
	body.collision_layer = 4
	body.collision_mask = 0
	var tex_path := TEX_MOVER_LG if width >= 130.0 else TEX_MOVER
	if color.b > color.r and color.b > 0.7:
		tex_path = TEX_MOVER_BLUE
	var tile_w := 56.0
	var count := maxi(1, int(round(width / tile_w)))
	var start := -((count - 1) * tile_w) * 0.5
	for i in count:
		var spr := _sprite(tex_path, 1.05)
		spr.modulate = color
		spr.position = Vector2(start + float(i) * tile_w, 0)
		body.add_child(spr)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(float(count) * tile_w * 0.9, 28)
	col.shape = shape
	body.add_child(col)
	_host.add_child(body)
	var tw := _host.create_tween().set_loops()
	tw.tween_property(body, "global_position", b, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(body, "global_position", a, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func add_block(pos: Vector2, w: float, h: float, color: Color = Color(1, 1, 1)) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 4
	var spr := _sprite(TEX_SPIKE_BLOCK if h >= 50.0 else TEX_MOVER, maxf(w, h) / 56.0)
	spr.modulate = color
	body.add_child(spr)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, h)
	col.shape = shape
	body.add_child(col)
	_host.add_child(body)
