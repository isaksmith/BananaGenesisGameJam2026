extends Node3D

@export var drive_speed: float = 6.5
@export var hop_impulse: float = 5.5

var _finished: bool = false
var _hop_cooldown: float = 0.0
var _vehicle: CharacterBody3D
var _hint: Label
var _finish: Area3D


func _ready() -> void:
	MeshKit3D.sun_and_env(self, 1.0, Color(0.4, 0.5, 0.55))
	_build_world()
	_build_ui()
	_spawn_vehicle()
	_spawn_hazards()
	_spawn_finish()
	_spawn_tribe()


func _build_world() -> void:
	MeshKit3D.ground_plane(self, Vector2(80, 30), Color(0.3, 0.45, 0.35))
	# Grass block track from Platformer Kit
	for x in range(-22, 23, 2):
		AssetKit3D.add(self, AssetKit3D.BLOCK_LONG, Vector3(float(x), 0, 0), 1.0)
	MeshKit3D.static_box(self, Vector3(50, 0.5, 4), Color(0.45, 0.32, 0.18), Vector3(0, 0.25, 0))
	AssetKit3D.scatter_palms(self, [
		Vector3(-18, 0, -6), Vector3(-6, 0, -7), Vector3(8, 0, -6), Vector3(16, 0, -7),
	])
	AssetKit3D.add(self, AssetKit3D.ROCK_A, Vector3(-10, 0, 5), 1.1)
	AssetKit3D.add(self, AssetKit3D.BARREL, Vector3(4, 0, 4), 1.3)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 10, 16)
	cam.look_at(Vector3(0, 1, 0))
	add_child(cam)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_top = 28
	_hint.offset_left = -380
	_hint.offset_right = 380
	_hint.offset_bottom = 100
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.text = "A/D drive the square wheel (crate). Avoid peels. Grab bananas.\nReach the star finish!"
	layer.add_child(_hint)


func _spawn_vehicle() -> void:
	_vehicle = CharacterBody3D.new()
	_vehicle.set_script(load("res://scripts_3d/vehicle_status_3d.gd"))
	_vehicle.position = Vector3(-20, 1.2, 0)
	_vehicle.collision_layer = 1
	_vehicle.collision_mask = 4
	_vehicle.add_to_group("player")
	var crate := AssetKit3D.make(AssetKit3D.CRATE, 1.5)
	crate.name = "Visual"
	_vehicle.add_child(crate)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 1.2, 1.2)
	col.shape = shape
	_vehicle.add_child(col)
	add_child(_vehicle)


func _spawn_finish() -> void:
	_finish = Area3D.new()
	_finish.position = Vector3(20, 1.2, 0)
	_finish.collision_layer = 0
	_finish.collision_mask = 1
	_finish.monitoring = true
	_finish.body_entered.connect(_on_finish)
	_finish.add_child(AssetKit3D.make(AssetKit3D.STAR, 2.0))
	_finish.add_child(AssetKit3D.make(AssetKit3D.BANANA, 2.5, 90))
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 3, 4)
	col.shape = shape
	_finish.add_child(col)
	add_child(_finish)


func _spawn_hazards() -> void:
	var peel_script: Script = load("res://scripts_3d/peel_hazard_3d.gd")
	var item_script: Script = load("res://scripts_3d/item_banana_3d.gd")
	for x in [-10.0, -2.0, 6.0, 12.0]:
		var peel := Area3D.new()
		peel.set_script(peel_script)
		peel.position = Vector3(x, 0.7, 0)
		add_child(peel)
	for x in [-6.0, 8.0]:
		var item := Area3D.new()
		item.set_script(item_script)
		item.position = Vector3(x, 0.9, 0)
		add_child(item)


func _spawn_tribe() -> void:
	var helper := CharacterBody3D.new()
	helper.set_script(load("res://scripts_3d/tribe_helper_3d.gd"))
	helper.position = Vector3(0, 1, 2)
	helper.set("label_text", "I race too!")
	helper.set("mood", 1)
	add_child(helper)


func _physics_process(delta: float) -> void:
	if _finished or _vehicle == null:
		return
	if _vehicle.has_method("tick_status"):
		_vehicle.tick_status(delta)
	_hop_cooldown = maxf(_hop_cooldown - delta, 0.0)

	var speed := drive_speed
	if _vehicle.get("boost_mult") != null:
		speed *= float(_vehicle.boost_mult)

	var visual := _vehicle.get_node_or_null("Visual") as Node3D
	if _vehicle.has_method("is_slipping") and _vehicle.is_slipping():
		_vehicle.velocity.y -= 18.0 * delta
		_vehicle.move_and_slide()
		if visual:
			visual.rotation_degrees.z += 400.0 * delta
	else:
		var axis := Input.get_axis("move_left", "move_right")
		_vehicle.velocity.x = axis * speed
		_vehicle.velocity.z = move_toward(_vehicle.velocity.z, 0.0, 20.0 * delta)
		if absf(axis) > 0.1 and _hop_cooldown <= 0.0 and _vehicle.is_on_floor():
			_vehicle.velocity.y = hop_impulse
			_hop_cooldown = 0.55
		elif not _vehicle.is_on_floor():
			_vehicle.velocity.y -= 18.0 * delta
		_vehicle.move_and_slide()
		if visual and absf(axis) > 0.1:
			visual.rotation_degrees.z -= axis * 220.0 * delta

	_vehicle.global_position.x = clampf(_vehicle.global_position.x, -22.0, 22.0)
	_vehicle.global_position.z = clampf(_vehicle.global_position.z, -1.5, 1.5)
	if _vehicle.global_position.y < -5.0:
		_vehicle.global_position = Vector3(-20, 1.2, 0)
		_vehicle.velocity = Vector3.ZERO


func _on_finish(body: Node3D) -> void:
	if _finished:
		return
	if body == _vehicle or body.is_in_group("player"):
		_finished = true
		_hint.text = "It rolls! Kind of. Invention accepted."
		GameProgress.juice_shake.emit(0.5)
		await get_tree().create_timer(1.0).timeout
		GameProgress.complete_minigame(GameProgress.MODE_WHEEL)
