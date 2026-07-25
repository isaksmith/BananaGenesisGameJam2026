extends Node3D

## Summit → valley square-wheel run. Lean with A/D, survive the bumps, eat the banana.

@export var lean_torque: float = 28.0
@export var boost_torque: float = 12.0
@export var max_angular: float = 14.0
@export var reset_y: float = -8.0

var _done: bool = false
var _started: bool = false
var _time: float = 0.0
var _best_hint: String = ""

var _wheel: RigidBody3D
var _camera: Camera3D
var _hint: Label
var _status: Label
var _spawn: Vector3 = Vector3(0, 28, -36)


func _ready() -> void:
	MeshKit3D.sun_and_env(self, 1.15, Color(0.45, 0.55, 0.5))
	_build_slope()
	_build_decor()
	_spawn_wheel()
	_spawn_goal()
	_spawn_hazards()
	_build_camera()
	_build_ui()
	await get_tree().create_timer(0.35).timeout
	_started = true
	_hint.text = "A/D lean · W tumble · get the banana\nEsc/Q exit to camp · R reset"


func _build_slope() -> void:
	# Soft jungle ground under the course.
	MeshKit3D.ground_plane(self, Vector2(80, 120), Color(0.25, 0.42, 0.24), -2.0)

	# Segmented downhill ramp (high -Z → low +Z).
	var segments := [
		{"pos": Vector3(0, 24, -34), "size": Vector3(14, 1.2, 12), "rot": Vector3(-18, 0, 0)},
		{"pos": Vector3(0, 19.5, -24), "size": Vector3(12, 1.2, 12), "rot": Vector3(-22, 0, 0)},
		{"pos": Vector3(0, 14.5, -13), "size": Vector3(12, 1.2, 12), "rot": Vector3(-20, 0, 0)},
		{"pos": Vector3(0, 10, -2), "size": Vector3(11, 1.2, 12), "rot": Vector3(-16, 0, 0)},
		{"pos": Vector3(0, 6.5, 9), "size": Vector3(12, 1.2, 12), "rot": Vector3(-14, 0, 0)},
		{"pos": Vector3(0, 3.8, 20), "size": Vector3(14, 1.2, 12), "rot": Vector3(-10, 0, 0)},
		{"pos": Vector3(0, 1.6, 32), "size": Vector3(18, 1.0, 14), "rot": Vector3(-4, 0, 0)},
	]
	for seg in segments:
		_add_ramp(seg["pos"], seg["size"], seg["rot"], Color(0.42, 0.58, 0.32))

	# Summit platform
	MeshKit3D.static_box(self, Vector3(10, 1.0, 8), Color(0.4, 0.55, 0.3), Vector3(0, 26.2, -40))
	# Valley floor around banana
	MeshKit3D.static_box(self, Vector3(22, 1.0, 16), Color(0.38, 0.55, 0.3), Vector3(0, 0.5, 42))

	# Side rails so you don't tumble into the void immediately.
	for side in [-1.0, 1.0]:
		MeshKit3D.static_box(self, Vector3(1.2, 3.0, 70), Color(0.35, 0.28, 0.18), Vector3(side * 7.5, 12, 0))
		MeshKit3D.static_box(self, Vector3(1.2, 2.0, 20), Color(0.35, 0.28, 0.18), Vector3(side * 9.5, 2, 38))


func _add_ramp(pos: Vector3, size: Vector3, rot_deg: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = pos
	body.rotation_degrees = rot_deg
	var mi := MeshKit3D.box(size, color)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	# Decorative grass blocks along the ramp face.
	var decor := AssetKit3D.make(AssetKit3D.BLOCK_LONG, 1.0)
	decor.position = Vector3(0, size.y * 0.55, 0)
	body.add_child(decor)


func _build_decor() -> void:
	AssetKit3D.scatter_palms(self, [
		Vector3(-12, 22, -38), Vector3(12, 22, -38),
		Vector3(-14, 10, -10), Vector3(14, 10, -8),
		Vector3(-16, 2, 30), Vector3(16, 2, 34),
		Vector3(-10, 0.5, 48), Vector3(10, 0.5, 48),
	])
	AssetKit3D.add(self, AssetKit3D.ROCK_A, Vector3(-5, 8, -8), 1.2, 30)
	AssetKit3D.add(self, AssetKit3D.ROCK_B, Vector3(5, 5, 8), 1.1, -20)
	AssetKit3D.add(self, AssetKit3D.FOREST_ROCKS, Vector3(-6, 1, 28), 1.2, 50)
	AssetKit3D.add(self, AssetKit3D.FLOWER, Vector3(3, 1.2, 40), 1.5)
	AssetKit3D.add(self, AssetKit3D.FLOWER, Vector3(-4, 1.2, 44), 1.3, 70)


func _spawn_wheel() -> void:
	_wheel = RigidBody3D.new()
	_wheel.name = "SquareWheel"
	_wheel.position = _spawn
	_wheel.collision_layer = 1
	_wheel.collision_mask = 4
	_wheel.mass = 4.0
	_wheel.gravity_scale = 1.35
	_wheel.physics_material_override = _make_phys_mat()
	_wheel.continuous_cd = true
	_wheel.angular_damp = 0.35
	_wheel.linear_damp = 0.05
	_wheel.add_to_group("player")

	var crate := AssetKit3D.make(AssetKit3D.CRATE, 1.7)
	crate.name = "Crate"
	_wheel.add_child(crate)

	var monkey := AssetKit3D.make(AssetKit3D.MONKEY, 0.95, 180.0)
	monkey.name = "Monkey"
	monkey.position = Vector3(0, 1.05, 0)
	_wheel.add_child(monkey)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.35, 1.35, 1.35)
	col.shape = shape
	_wheel.add_child(col)
	add_child(_wheel)


func _make_phys_mat() -> PhysicsMaterial:
	var mat := PhysicsMaterial.new()
	mat.friction = 0.95
	mat.bounce = 0.18
	return mat


func _spawn_goal() -> void:
	var goal := Area3D.new()
	goal.name = "BananaGoal"
	goal.position = Vector3(0, 2.0, 44)
	goal.collision_layer = 0
	goal.collision_mask = 1
	goal.monitoring = true
	goal.body_entered.connect(_on_goal)
	var banana := AssetKit3D.make(AssetKit3D.BANANA, 4.5, 90.0)
	banana.position = Vector3(0, 0.6, 0)
	goal.add_child(banana)
	var glow := MeshKit3D.sphere(1.1, Color(1.0, 0.9, 0.25), Vector3(0, 0.4, 0), 1.6)
	goal.add_child(glow)
	var star := AssetKit3D.make(AssetKit3D.STAR, 1.8)
	star.position = Vector3(0, 2.2, 0)
	goal.add_child(star)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 2.2
	col.shape = shape
	goal.add_child(col)
	add_child(goal)

	# Bob the banana.
	var tween := create_tween().set_loops()
	tween.tween_property(banana, "position:y", 1.1, 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(banana, "position:y", 0.5, 0.7).set_trans(Tween.TRANS_SINE)


func _spawn_hazards() -> void:
	var peel_script: Script = load("res://scripts_3d/peel_hazard_3d.gd")
	for pos in [Vector3(-2, 16, -20), Vector3(2, 11, -6), Vector3(-1.5, 6, 10), Vector3(2.5, 3, 22)]:
		var peel := Area3D.new()
		peel.set_script(peel_script)
		peel.position = pos
		peel.set("slip_boost", 5.0)
		add_child(peel)
	# Bump rocks on the path (visual + collision)
	_add_bump(Vector3(2.5, 13, -15), 0.9)
	_add_bump(Vector3(-2.8, 8, 2), 1.0)
	_add_bump(Vector3(2.0, 4.5, 16), 0.85)


func _add_bump(pos: Vector3, scale: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.position = pos
	body.add_child(AssetKit3D.make(AssetKit3D.ROCK_SMALL, scale))
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.7 * scale
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 68.0
	_camera.current = true
	add_child(_camera)


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
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.text = "Square Wheel Descent"
	layer.add_child(_hint)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.offset_top = 100
	_status.offset_left = -240
	_status.offset_right = 240
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
	if not _started:
		return

	_time += delta
	_status.text = "Time %.1fs  ·  Speed %d  ·  R reset" % [_time, int(_wheel.linear_velocity.length())]

	var lean := Input.get_axis("move_left", "move_right")
	var drive := Input.get_axis("move_down", "move_up") # W = more tumble downhill
	if absf(lean) > 0.05:
		_wheel.apply_torque(Vector3(0, 0, -lean * lean_torque))
	if drive > 0.05:
		# Pitch forward down the slope (+X torque rolls toward +Z when oriented).
		_wheel.apply_torque(Vector3(drive * boost_torque, 0, 0))
	elif drive < -0.05:
		_wheel.apply_torque(Vector3(drive * boost_torque * 0.6, 0, 0))

	# Clamp wild spins a bit so peels stay funny, not nauseating.
	if _wheel.angular_velocity.length() > max_angular:
		_wheel.angular_velocity = _wheel.angular_velocity.limit_length(max_angular)

	_update_camera(delta)

	if _wheel.global_position.y < reset_y or absf(_wheel.global_position.x) > 22.0:
		_reset_wheel("Fell off the square path. Again from the top!")


func _update_camera(_delta: float) -> void:
	var target := _wheel.global_position
	var desired := target + Vector3(0, 7.5, -11)
	_camera.global_position = _camera.global_position.lerp(desired, 0.08)
	_camera.look_at(target + Vector3(0, 0.5, 2), Vector3.UP)


func _reset_wheel(msg: String) -> void:
	_wheel.linear_velocity = Vector3.ZERO
	_wheel.angular_velocity = Vector3.ZERO
	_wheel.global_transform = Transform3D(Basis.IDENTITY, _spawn)
	_hint.text = msg
	GameProgress.juice_shake.emit(0.25)


func _on_goal(body: Node3D) -> void:
	if _done:
		return
	if body == _wheel or body.is_in_group("player"):
		_done = true
		_wheel.linear_velocity *= 0.2
		_wheel.angular_velocity *= 0.2
		_hint.text = "BANANA! Square wheel: scientifically delicious."
		_status.text = "Cleared in %.1fs" % _time
		GameProgress.juice_shake.emit(0.55)
		await get_tree().create_timer(1.4).timeout
		GameProgress.complete_minigame(GameProgress.MODE_WHEEL)
