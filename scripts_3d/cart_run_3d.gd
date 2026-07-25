extends Node3D

@export var cart_speed: float = 7.0
@export var bananas_needed_a: int = 3
@export var bananas_needed_b: int = 3
@export var time_limit: float = 100.0

var _delivered_a: int = 0
var _delivered_b: int = 0
var _time_left: float = 100.0
var _done: bool = false
var _cargo: Array[Node3D] = []
var _cart: CharacterBody3D
var _pile: Node3D
var _hint: Label
var _status: Label


func _ready() -> void:
	_time_left = time_limit
	MeshKit3D.sun_and_env(self)
	_build_world()
	_build_ui()
	_spawn_cart()
	_spawn_huts()
	_spawn_pile()
	_spawn_chaos()
	_update_status()


func _build_world() -> void:
	MeshKit3D.ground_plane(self, Vector2(50, 40), Color(0.3, 0.5, 0.28))
	MeshKit3D.static_box(self, Vector3(36, 0.08, 28), Color(0.4, 0.55, 0.3), Vector3(0, 0.04, 0), 0)
	MeshKit3D.static_box(self, Vector3(2.2, 1.2, 2.2), Color(0.45, 0.4, 0.35), Vector3(-2, 0.6, -2))
	MeshKit3D.static_box(self, Vector3(1.4, 2.0, 1.4), Color(0.2, 0.45, 0.25), Vector3(4, 1.0, 3))
	AssetKit3D.add(self, AssetKit3D.ROCK_A, Vector3(-2, 0, -2), 1.2)
	AssetKit3D.add(self, AssetKit3D.FOREST_ROCKS, Vector3(4, 0, 3), 1.1)
	AssetKit3D.scatter_palms(self, [
		Vector3(-14, 0, -10), Vector3(14, 0, -10), Vector3(-14, 0, 10), Vector3(14, 0, 10),
	])
	AssetKit3D.add(self, AssetKit3D.APPLE, Vector3(-5, 0.2, 5), 2.0)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 22, 18)
	cam.look_at(Vector3(0, 0, 0))
	add_child(cam)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_top = 20
	_hint.offset_left = -420
	_hint.offset_right = 420
	_hint.offset_bottom = 90
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.text = "Deliver bananas to BOTH huts. Peels / boosts / tribe chaos.\nEsc/Q exits to camp."
	layer.add_child(_hint)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.offset_top = 92
	_status.offset_left = -280
	_status.offset_right = 280
	_status.offset_bottom = 126
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 4)
	layer.add_child(_status)


func _spawn_cart() -> void:
	_cart = CharacterBody3D.new()
	_cart.set_script(load("res://scripts_3d/vehicle_status_3d.gd"))
	_cart.name = "Cart"
	_cart.position = Vector3(-12, 1.0, 6)
	_cart.collision_layer = 1
	_cart.collision_mask = 4
	_cart.add_to_group("cart")
	_cart.add_to_group("player")
	_cart.add_child(AssetKit3D.make(AssetKit3D.CRATE, 1.6))
	_cart.add_child(AssetKit3D.make(AssetKit3D.BARREL, 0.9, 0))
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 0.9, 1.2)
	col.shape = shape
	_cart.add_child(col)
	add_child(_cart)


func _spawn_huts() -> void:
	_make_hut(Vector3(12, 0, -6), "Hut A", true)
	_make_hut(Vector3(12, 0, 6), "Hut B", false)


func _make_hut(pos: Vector3, title: String, is_a: bool) -> void:
	var hut := Area3D.new()
	hut.position = pos
	hut.collision_layer = 0
	hut.collision_mask = 1
	hut.monitoring = true
	hut.body_entered.connect(func(body: Node3D) -> void: _on_dropoff(body, is_a))
	if is_a:
		hut.add_child(AssetKit3D.make(AssetKit3D.HUT_TENT, 1.4))
	else:
		var building := AssetKit3D.make(AssetKit3D.BUILDING, 1.2)
		hut.add_child(building)
		var roof := AssetKit3D.make(AssetKit3D.BUILDING_ROOF, 1.2)
		roof.position = Vector3(0, 1.2, 0)
		hut.add_child(roof)
	hut.add_child(AssetKit3D.make(AssetKit3D.BANANA, 2.0, 90))
	var label := Label3D.new()
	label.text = title
	label.position = Vector3(0, 2.4, 0)
	label.font_size = 40
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hut.add_child(label)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.5, 3, 3.5)
	col.shape = shape
	col.position = Vector3(0, 1, 0)
	hut.add_child(col)
	add_child(hut)


func _spawn_pile() -> void:
	_pile = Node3D.new()
	_pile.position = Vector3(-12, 0.2, -4)
	add_child(_pile)
	_pile.add_child(AssetKit3D.make(AssetKit3D.BANANA, 3.5, 90))
	_pile.add_child(AssetKit3D.make(AssetKit3D.CRATE, 1.0))
	var banana_script: Script = load("res://scripts_3d/banana_3d.gd")
	var total := bananas_needed_a + bananas_needed_b + 4
	for i in total:
		var b := Area3D.new()
		b.set_script(banana_script)
		b.set("pickup_mode", "cargo")
		b.position = Vector3(randf_range(-0.8, 0.8), 0.3, randf_range(-0.8, 0.8))
		b.monitoring = false
		_pile.add_child(b)
	var load_area := Area3D.new()
	load_area.collision_layer = 0
	load_area.collision_mask = 1
	load_area.monitoring = true
	load_area.body_entered.connect(_on_load)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 2.5
	col.shape = shape
	load_area.add_child(col)
	_pile.add_child(load_area)


func _spawn_chaos() -> void:
	var peel_script: Script = load("res://scripts_3d/peel_hazard_3d.gd")
	var item_script: Script = load("res://scripts_3d/item_banana_3d.gd")
	var tribe_script: Script = load("res://scripts_3d/tribe_helper_3d.gd")
	for pos in [Vector3(-4, 0.5, 0), Vector3(0, 0.5, 4), Vector3(4, 0.5, -3), Vector3(2, 0.5, 6)]:
		var peel := Area3D.new()
		peel.set_script(peel_script)
		peel.position = pos
		add_child(peel)
	for pos in [Vector3(-6, 0.6, 3), Vector3(6, 0.6, -2)]:
		var item := Area3D.new()
		item.set_script(item_script)
		item.position = pos
		add_child(item)
	var thief := CharacterBody3D.new()
	thief.set_script(tribe_script)
	thief.position = Vector3(0, 1, 0)
	thief.set("label_text", "Delivery help!")
	thief.set("mood", 2)
	add_child(thief)
	var bumper := CharacterBody3D.new()
	bumper.set_script(tribe_script)
	bumper.position = Vector3(-2, 1, 5)
	bumper.set("label_text", "I push!")
	bumper.set("mood", 1)
	add_child(bumper)


func tribe_steal_cargo() -> bool:
	if _cargo.is_empty():
		return false
	var banana: Node3D = _cargo.pop_back()
	if is_instance_valid(banana):
		banana.queue_free()
	GameProgress.juice_shake.emit(0.18)
	_hint.text = "Tribe 'helped' by taking a banana."
	_update_status()
	return true


func _physics_process(delta: float) -> void:
	if _done:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_fail_and_retry()
		return
	if _cart.has_method("tick_status"):
		_cart.tick_status(delta)
	var speed := cart_speed
	if _cart.get("boost_mult") != null:
		speed *= float(_cart.boost_mult)
	if _cart.has_method("is_slipping") and _cart.is_slipping():
		_cart.velocity = _cart.velocity.lerp(Vector3.ZERO, 0.02)
		_cart.move_and_slide()
	else:
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var move := Vector3(direction.x, 0.0, direction.y) * speed
		var prev := move
		_cart.velocity.x = move.x
		_cart.velocity.z = move.z
		if not _cart.is_on_floor():
			_cart.velocity.y -= 18.0 * delta
		_cart.move_and_slide()
		if _cart.get_slide_collision_count() > 0 and _cargo.size() > 0 and prev.length() > 4.0:
			_spill_one()
	_update_cargo_follow()
	_update_status()


func _on_load(body: Node3D) -> void:
	if body != _cart:
		return
	while _cargo.size() < 3:
		var banana: Node3D = null
		for child in _pile.get_children():
			if child is Area3D and child.get("pickup_mode") == "cargo":
				banana = child
				break
		if banana == null:
			break
		_pile.remove_child(banana)
		_cart.add_child(banana)
		banana.position = Vector3(0, 1.0 + _cargo.size() * 0.35, 0)
		_cargo.append(banana)
	_update_status()


func _on_dropoff(body: Node3D, is_a: bool) -> void:
	if body != _cart or _cargo.is_empty():
		return
	var banana: Node3D = _cargo.pop_back()
	if is_instance_valid(banana):
		banana.queue_free()
	if is_a:
		_delivered_a = mini(_delivered_a + 1, bananas_needed_a)
	else:
		_delivered_b = mini(_delivered_b + 1, bananas_needed_b)
	_hint.text = "Hut %s stocked!" % ("A" if is_a else "B")
	GameProgress.juice_shake.emit(0.15)
	_update_status()
	if _delivered_a >= bananas_needed_a and _delivered_b >= bananas_needed_b:
		_succeed()


func _spill_one() -> void:
	if _cargo.is_empty():
		return
	var banana: Node3D = _cargo.pop_back()
	if is_instance_valid(banana):
		_cart.remove_child(banana)
		add_child(banana)
		banana.global_position = _cart.global_position + Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1))
		banana.queue_free()
	_hint.text = "Spilled a banana. Smooth."


func _update_cargo_follow() -> void:
	for i in _cargo.size():
		var b := _cargo[i]
		if is_instance_valid(b):
			b.position = Vector3(0, 1.0 + i * 0.35, 0)


func _update_status() -> void:
	_status.text = "HutA %d/%d  HutB %d/%d  |  Cargo %d  |  Time %d" % [
		_delivered_a, bananas_needed_a, _delivered_b, bananas_needed_b, _cargo.size(), int(_time_left)
	]


func _succeed() -> void:
	_done = true
	_hint.text = "Logistics mastered!"
	GameProgress.juice_shake.emit(0.45)
	await get_tree().create_timer(1.0).timeout
	GameProgress.complete_minigame(GameProgress.MODE_CART)


func _fail_and_retry() -> void:
	_done = true
	_hint.text = "Time's up — try again!"
	await get_tree().create_timer(1.2).timeout
	GameProgress.start_minigame(GameProgress.MODE_CART)
