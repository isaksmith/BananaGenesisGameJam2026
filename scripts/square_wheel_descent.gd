extends Node2D

## 2D summit → valley square-wheel run.
## Uses CharacterBody2D + corner-hop tumble so the square visibly rolls.

@export var move_accel: float = 1400.0
@export var max_speed: float = 520.0
@export var gravity: float = 1400.0
@export var hop_impulse: float = 220.0
@export var tumble_degrees_per_px: float = 2.2

var _done: bool = false
var _time: float = 0.0
var _spawn: Vector2 = Vector2(160, 80)
var _roll_dist: float = 0.0
var _hop_cd: float = 0.0
var _facing: float = 1.0

var _wheel: CharacterBody2D
var _visual: Node2D
var _camera: Camera2D
var _hint: Label
var _status: Label


func _ready() -> void:
	_build_world()
	_spawn_wheel()
	_spawn_goal()
	_spawn_hazards()
	_build_camera()
	_build_ui()
	_hint.text = "A/D roll · hold W for more tumble · get the banana\nEsc/Q exit · R reset"


func _build_world() -> void:
	var bg := Polygon2D.new()
	bg.z_index = -10
	bg.color = Color(0.35, 0.62, 0.85)
	bg.polygon = PackedVector2Array([
		Vector2(-200, -200), Vector2(1600, -200), Vector2(1600, 900), Vector2(-200, 900)
	])
	add_child(bg)

	var jungle := Sprite2D.new()
	jungle.z_index = -9
	jungle.texture = load("res://assets/sprites/forest_bg.png") as Texture2D
	jungle.position = Vector2(640, 360)
	jungle.modulate = Color(1, 1, 1, 1)
	jungle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(jungle)

	# Continuous slope as one collision polygon (top surface path).
	# Points go left→right along the driving surface, then reverse along the underside.
	var surface := PackedVector2Array([
		Vector2(40, 130),
		Vector2(220, 130),
		Vector2(380, 190),
		Vector2(540, 270),
		Vector2(720, 360),
		Vector2(900, 440),
		Vector2(1080, 510),
		Vector2(1240, 560),
		Vector2(1400, 580),
	])
	_add_terrain(surface, 36.0, Color(0.42, 0.58, 0.32))

	# Valley pad under the banana
	_add_box(Vector2(1240, 640), Vector2(280, 40), Color(0.38, 0.55, 0.3))

	# Walls
	_add_box(Vector2(20, 360), Vector2(36, 720), Color(0.25, 0.4, 0.2))
	_add_box(Vector2(1420, 400), Vector2(36, 700), Color(0.25, 0.4, 0.2))

	for pos in [Vector2(180, 70), Vector2(620, 200), Vector2(960, 360), Vector2(1320, 480)]:
		var palm := Sprite2D.new()
		palm.texture = load("res://assets/sprites/forest_tree.png") as Texture2D
		palm.position = pos
		palm.scale = Vector2(1.1, 1.1)
		palm.z_index = -2
		palm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(palm)


func _add_terrain(surface: PackedVector2Array, thickness: float, color: Color) -> void:
	var poly := PackedVector2Array()
	for p in surface:
		poly.append(p)
	# Underside reverse
	for i in range(surface.size() - 1, -1, -1):
		poly.append(surface[i] + Vector2(0, thickness))

	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var visual := Polygon2D.new()
	visual.color = color
	visual.polygon = poly
	body.add_child(visual)
	var col := CollisionPolygon2D.new()
	col.polygon = poly
	body.add_child(col)
	add_child(body)

	# Grass ticks along surface
	for i in range(surface.size() - 1):
		var a: Vector2 = surface[i]
		var b: Vector2 = surface[i + 1]
		var mid := (a + b) * 0.5
		var grass := Sprite2D.new()
		grass.texture = load("res://assets/sprites/tile_platform.png") as Texture2D
		grass.position = mid + Vector2(0, -8)
		grass.rotation = (b - a).angle()
		grass.scale = Vector2((b - a).length() / 192.0, 0.5)
		grass.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(grass)


func _add_box(pos: Vector2, size: Vector2, color: Color) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 4
	body.collision_mask = 0
	var visual := Polygon2D.new()
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	visual.color = color
	visual.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)
	])
	body.add_child(visual)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _spawn_wheel() -> void:
	_wheel = CharacterBody2D.new()
	_wheel.name = "SquareWheel"
	_wheel.position = _spawn
	_wheel.collision_layer = 1
	_wheel.collision_mask = 4
	_wheel.floor_stop_on_slope = false
	_wheel.floor_max_angle = deg_to_rad(80.0)
	_wheel.safe_margin = 0.2
	_wheel.add_to_group("player")

	_visual = Node2D.new()
	_visual.name = "Visual"
	_wheel.add_child(_visual)

	var crate := Sprite2D.new()
	crate.texture = load("res://assets/sprites/icon_square_wheel.png") as Texture2D
	crate.scale = Vector2(1.6, 1.6)
	crate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_visual.add_child(crate)

	var monkey := Sprite2D.new()
	monkey.texture = load("res://assets/sprites/monkey_idle.png") as Texture2D
	monkey.position = Vector2(0, -20)
	monkey.scale = Vector2(0.55, 0.55)
	monkey.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_visual.add_child(monkey)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(44, 44)
	col.shape = shape
	_wheel.add_child(col)
	add_child(_wheel)


func _spawn_goal() -> void:
	var goal := Area2D.new()
	goal.name = "BananaGoal"
	goal.position = Vector2(1240, 560)
	goal.collision_layer = 0
	goal.collision_mask = 1
	goal.monitoring = true
	goal.body_entered.connect(_on_goal)

	var banana := Sprite2D.new()
	banana.texture = load("res://assets/sprites/bananas_pile.png") as Texture2D
	banana.scale = Vector2(1.8, 1.8)
	banana.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	goal.add_child(banana)

	var glow := Polygon2D.new()
	glow.z_index = -1
	glow.color = Color(1, 0.9, 0.2, 0.35)
	glow.polygon = PackedVector2Array([
		Vector2(-44, -44), Vector2(44, -44), Vector2(44, 44), Vector2(-44, 44)
	])
	goal.add_child(glow)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 52.0
	col.shape = shape
	goal.add_child(col)
	add_child(goal)

	var tween := create_tween().set_loops()
	tween.tween_property(banana, "position:y", -12.0, 0.55).set_trans(Tween.TRANS_SINE)
	tween.tween_property(banana, "position:y", 4.0, 0.55).set_trans(Tween.TRANS_SINE)


func _spawn_hazards() -> void:
	var peel_scene: PackedScene = load("res://scenes/enemies/banana_peel_hazard.tscn")
	for pos in [Vector2(420, 200), Vector2(640, 310), Vector2(880, 420), Vector2(1080, 500)]:
		var peel := peel_scene.instantiate() as Node2D
		peel.position = pos
		peel.set("slip_boost", 320.0)
		peel.set("one_shot", false)
		add_child(peel)

	for pos in [Vector2(520, 250), Vector2(780, 380), Vector2(1000, 470)]:
		var rock := StaticBody2D.new()
		rock.position = pos
		rock.collision_layer = 4
		var sprite := Sprite2D.new()
		sprite.texture = load("res://assets/sprites/rock_medium.png") as Texture2D
		sprite.scale = Vector2(1.3, 1.3)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rock.add_child(sprite)
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 16.0
		col.shape = shape
		rock.add_child(col)
		add_child(rock)


func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	_camera.limit_left = 0
	_camera.limit_top = -40
	_camera.limit_right = 1440
	_camera.limit_bottom = 780
	add_child(_camera)
	_camera.make_current()
	_camera.global_position = _spawn


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_top = 24
	_hint.offset_left = -420
	_hint.offset_right = 420
	_hint.offset_bottom = 100
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.text = "Square Wheel Descent"
	layer.add_child(_hint)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.offset_top = 100
	_status.offset_left = -280
	_status.offset_right = 280
	_status.offset_bottom = 132
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 4)
	layer.add_child(_status)


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("restart"):
		_time = 0.0
		_reset_wheel("Manual reset. Pride is optional.")
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _done or _wheel == null:
		return

	_time += delta
	_hop_cd = maxf(_hop_cd - delta, 0.0)
	_status.text = "Time %.1fs  ·  Speed %d  ·  R reset" % [_time, int(_wheel.velocity.length())]

	var axis := Input.get_axis("move_left", "move_right")
	var drive := Input.get_axis("move_down", "move_up") # W = +drive
	var input_x := axis
	if absf(drive) > 0.1:
		# W biases downhill (right); S brakes / goes left a bit.
		input_x = clampf(input_x + drive * 0.85, -1.0, 1.0)

	if absf(input_x) > 0.05:
		_facing = signf(input_x)
		_wheel.velocity.x = move_toward(_wheel.velocity.x, input_x * max_speed, move_accel * delta)
	else:
		_wheel.velocity.x = move_toward(_wheel.velocity.x, 0.0, move_accel * 0.35 * delta)

	# Gravity always.
	if not _wheel.is_on_floor():
		_wheel.velocity.y += gravity * delta
	else:
		# Gentle downhill pull so you start rolling without fighting left input.
		if input_x >= -0.1:
			_wheel.velocity.x = move_toward(_wheel.velocity.x, maxf(_wheel.velocity.x, max_speed * 0.4), 320.0 * delta)
		# Corner hop = square-wheel comedy
		var speed_x := absf(_wheel.velocity.x)
		if speed_x > 50.0 and _hop_cd <= 0.0:
			_wheel.velocity.y = -hop_impulse * clampf(speed_x / max_speed, 0.35, 1.0)
			_hop_cd = 0.4
			GameProgress.juice_shake.emit(0.04)

	var before := _wheel.global_position
	_wheel.move_and_slide()
	var traveled := _wheel.global_position.distance_to(before)
	_roll_dist += traveled
	# Spin the square with travel distance.
	_visual.rotation_degrees = _roll_dist * tumble_degrees_per_px * _facing

	_camera.global_position = _camera.global_position.lerp(_wheel.global_position, 0.15)

	if _wheel.global_position.y > 820.0 or _wheel.global_position.x < -20.0 or _wheel.global_position.x > 1480.0:
		_reset_wheel("Fell off the square path. Again from the top!")


func _reset_wheel(msg: String) -> void:
	_wheel.velocity = Vector2.ZERO
	_wheel.global_position = _spawn
	_roll_dist = 0.0
	_visual.rotation = 0.0
	_hint.text = msg
	GameProgress.juice_shake.emit(0.25)


func _on_goal(body: Node2D) -> void:
	if _done:
		return
	if body == _wheel or body.is_in_group("player"):
		_done = true
		_wheel.velocity *= 0.2
		_hint.text = "BANANA! Square wheel: scientifically delicious."
		_status.text = "Cleared in %.1fs" % _time
		GameProgress.juice_shake.emit(0.55)
		await get_tree().create_timer(1.3).timeout
		GameProgress.complete_minigame(GameProgress.MODE_WHEEL)
