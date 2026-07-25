extends Node2D

@export var drive_speed: float = 160.0
@export var hop_impulse: float = 220.0

var _finished: bool = false
var _hop_cooldown: float = 0.0

@onready var vehicle: CharacterBody2D = %SquareWheelVehicle
@onready var hint: Label = %HintLabel
@onready var finish: Area2D = %FinishLine
@onready var hazards: Node2D = %Hazards


func _ready() -> void:
	hint.text = "A/D drive the square wheel. Avoid peels. Grab glowing bananas for a boost.\nRival monkey 'helps'. Reach the finish!"
	finish.body_entered.connect(_on_finish_body_entered)
	_spawn_hazards()
	_spawn_tribe()


func _physics_process(delta: float) -> void:
	if _finished or vehicle == null:
		return
	if vehicle.has_method("tick_status"):
		vehicle.tick_status(delta)
	_hop_cooldown = maxf(_hop_cooldown - delta, 0.0)

	var speed := drive_speed
	if vehicle.get("boost_mult") != null:
		speed *= float(vehicle.boost_mult)

	if vehicle.has_method("is_slipping") and vehicle.is_slipping():
		# No steering while slipping — comedy.
		vehicle.velocity.y += 900.0 * delta
		vehicle.move_and_slide()
	else:
		var axis := Input.get_axis("move_left", "move_right")
		vehicle.velocity.x = axis * speed
		if absf(axis) > 0.1 and _hop_cooldown <= 0.0 and vehicle.is_on_floor():
			vehicle.velocity.y = -hop_impulse
			_hop_cooldown = 0.55
			GameProgress.juice_shake.emit(0.06)
		else:
			vehicle.velocity.y += 900.0 * delta
		vehicle.move_and_slide()

	vehicle.global_position.x = clampf(vehicle.global_position.x, 40.0, 1240.0)
	if vehicle.global_position.y > 900.0:
		vehicle.global_position = Vector2(160, 480)
		vehicle.velocity = Vector2.ZERO


func _spawn_hazards() -> void:
	var peel_scene: PackedScene = load("res://scenes/enemies/banana_peel_hazard.tscn")
	var item_scene: PackedScene = load("res://scenes/enemies/item_banana.tscn")
	for x in [320.0, 520.0, 720.0, 900.0]:
		var peel := peel_scene.instantiate() as Node2D
		peel.position = Vector2(x, 500)
		hazards.add_child(peel)
	for x in [400.0, 800.0]:
		var item := item_scene.instantiate() as Node2D
		item.position = Vector2(x, 470)
		hazards.add_child(item)


func _spawn_tribe() -> void:
	var tribe_scene: PackedScene = load("res://scenes/enemies/tribe_helper.tscn")
	var helper := tribe_scene.instantiate()
	helper.position = Vector2(600, 470)
	helper.label_text = "I race too!"
	helper.set("mood", 1) # CHASE_PLAYER
	hazards.add_child(helper)


func _on_finish_body_entered(body: Node2D) -> void:
	if _finished:
		return
	if body == vehicle or body.is_in_group("player"):
		_finished = true
		hint.text = "It rolls! Kind of. Invention accepted."
		GameProgress.juice_shake.emit(0.5)
		await get_tree().create_timer(1.0).timeout
		GameProgress.complete_minigame(GameProgress.MODE_WHEEL)
