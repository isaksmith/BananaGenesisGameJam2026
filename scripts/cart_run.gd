extends Node2D

## Micro-logistics: deliver bananas to TWO huts (OpenTTD-lite) while peels / item bananas / tribe interfere.

@export var cart_speed: float = 220.0
@export var bananas_needed_a: int = 3
@export var bananas_needed_b: int = 3
@export var time_limit: float = 100.0

var _delivered_a: int = 0
var _delivered_b: int = 0
var _time_left: float = 100.0
var _done: bool = false
var _cargo: Array[Node2D] = []

@onready var cart: CharacterBody2D = %Cart
@onready var cargo_area: Area2D = %CargoArea
@onready var dropoff_a: Area2D = %DropoffZone
@onready var dropoff_b: Area2D = %DropoffZoneB
@onready var hint: Label = %HintLabel
@onready var status: Label = %StatusLabel
@onready var pile: Node2D = %BananaPile
@onready var hazards: Node2D = %Hazards


func _ready() -> void:
	_time_left = time_limit
	hint.text = "Deliver to BOTH huts. Peels / boosts / tribe chaos.\nEsc/Q exits to camp."
	dropoff_a.body_entered.connect(_on_dropoff_a)
	dropoff_b.body_entered.connect(_on_dropoff_b)
	_spawn_pile()
	_spawn_chaos()
	_update_status()


func _physics_process(delta: float) -> void:
	if _done:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_fail_and_retry()
		return

	if cart.has_method("tick_status"):
		cart.tick_status(delta)

	var speed := cart_speed
	if cart.get("boost_mult") != null:
		speed *= float(cart.boost_mult)

	if cart.has_method("is_slipping") and cart.is_slipping():
		cart.velocity = cart.velocity.lerp(Vector2.ZERO, 0.02)
		cart.move_and_slide()
	else:
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		cart.velocity = direction * speed
		var prev_vel := cart.velocity
		cart.move_and_slide()
		if cart.get_slide_collision_count() > 0 and _cargo.size() > 0:
			if prev_vel.length() > 120.0:
				_spill_one()
	_update_status()


func tribe_steal_cargo() -> bool:
	if _cargo.is_empty():
		return false
	var banana: Node2D = _cargo.pop_back()
	if is_instance_valid(banana):
		banana.queue_free()
	GameProgress.juice_shake.emit(0.18)
	hint.text = "Tribe 'helped' by taking a banana. Classic."
	_update_status()
	return true


func _spawn_chaos() -> void:
	var peel_scene: PackedScene = load("res://scenes/enemies/banana_peel_hazard.tscn")
	var item_scene: PackedScene = load("res://scenes/enemies/item_banana.tscn")
	var tribe_scene: PackedScene = load("res://scenes/enemies/tribe_helper.tscn")
	for pos in [Vector2(450, 360), Vector2(700, 280), Vector2(900, 480), Vector2(600, 520)]:
		var peel := peel_scene.instantiate() as Node2D
		peel.position = pos
		hazards.add_child(peel)
	for pos in [Vector2(380, 220), Vector2(860, 340)]:
		var item := item_scene.instantiate() as Node2D
		item.position = pos
		hazards.add_child(item)
	var thief := tribe_scene.instantiate()
	thief.position = Vector2(640, 400)
	thief.label_text = "Delivery help!"
	thief.set("mood", 2) # STEAL_CARGO
	hazards.add_child(thief)
	var bumper := tribe_scene.instantiate()
	bumper.position = Vector2(500, 500)
	bumper.label_text = "I push!"
	bumper.set("mood", 1) # CHASE cart/player
	hazards.add_child(bumper)


func _spawn_pile() -> void:
	for child in pile.get_children():
		child.queue_free()
	var banana_scene: PackedScene = load("res://scenes/enemies/banana.tscn")
	var total := bananas_needed_a + bananas_needed_b + 4
	for i in total:
		var b := banana_scene.instantiate() as Area2D
		b.pickup_mode = "cargo"
		b.position = Vector2(randf_range(-30, 30), randf_range(-20, 20))
		b.monitoring = false
		b.monitorable = false
		pile.add_child(b)
	if not pile.has_node("LoadArea"):
		var load_area := Area2D.new()
		load_area.name = "LoadArea"
		load_area.collision_layer = 0
		load_area.collision_mask = 1
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 50.0
		shape.shape = circle
		load_area.add_child(shape)
		pile.add_child(load_area)
		load_area.body_entered.connect(_on_pile_body_entered)


func _on_pile_body_entered(body: Node2D) -> void:
	if body != cart:
		return
	while _cargo.size() < 3 and pile.get_child_count() > 1:
		var banana: Node = null
		for child in pile.get_children():
			if child is Area2D and child.name != "LoadArea":
				banana = child
				break
		if banana == null:
			break
		pile.remove_child(banana)
		cargo_area.add_child(banana)
		banana.position = Vector2(randf_range(-12, 12), randf_range(-8, 4))
		_cargo.append(banana)
		GameProgress.juice_shake.emit(0.05)
	_update_status()


func _spill_one() -> void:
	if _cargo.is_empty():
		return
	var banana: Node2D = _cargo.pop_back()
	if is_instance_valid(banana):
		var world_pos := banana.global_position
		cargo_area.remove_child(banana)
		pile.add_child(banana)
		banana.global_position = world_pos + Vector2(randf_range(-40, 40), randf_range(-20, 20))
	GameProgress.juice_shake.emit(0.15)
	_update_status()


func _on_dropoff_a(body: Node2D) -> void:
	_deliver_to(body, true)


func _on_dropoff_b(body: Node2D) -> void:
	_deliver_to(body, false)


func _deliver_to(body: Node2D, is_a: bool) -> void:
	if _done or body != cart:
		return
	var count := _cargo.size()
	if count <= 0:
		return
	if is_a:
		_delivered_a += count
	else:
		_delivered_b += count
	for banana in _cargo:
		if is_instance_valid(banana):
			banana.queue_free()
	_cargo.clear()
	GameProgress.juice_shake.emit(0.25)
	hint.text = "Hut %s stocked!" % ("A" if is_a else "B")
	_update_status()
	if _delivered_a >= bananas_needed_a and _delivered_b >= bananas_needed_b:
		_succeed()


func _succeed() -> void:
	_done = true
	hint.text = "Both huts fed! Banana logistics reinvented."
	await get_tree().create_timer(1.0).timeout
	GameProgress.complete_minigame(GameProgress.MODE_CART)


func _fail_and_retry() -> void:
	hint.text = "Routes collapsed. Retrying logistics..."
	await get_tree().create_timer(1.2).timeout
	_delivered_a = 0
	_delivered_b = 0
	_time_left = time_limit
	_done = false
	for banana in _cargo:
		if is_instance_valid(banana):
			banana.queue_free()
	_cargo.clear()
	for child in hazards.get_children():
		child.queue_free()
	_spawn_pile()
	_spawn_chaos()
	cart.global_position = Vector2(180, 500)
	hint.text = "Deliver to BOTH huts. Peels slip. Tribe steals. Go!"
	_update_status()


func _update_status() -> void:
	status.text = "HutA %d/%d  HutB %d/%d  |  Cargo %d  |  Time %d" % [
		_delivered_a, bananas_needed_a, _delivered_b, bananas_needed_b, _cargo.size(), ceili(_time_left)
	]
