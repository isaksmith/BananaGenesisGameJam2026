extends CharacterBody2D

@export var speed: float = 280.0
@export var climb_speed: float = 220.0

var _start_position: Vector2
var _nearby_interactable: Node = null
var _in_climb_zone: bool = false


func _ready() -> void:
	add_to_group("player")
	_start_position = global_position
	GameState.round_started.connect(_on_chase_round_started)
	if has_node("InteractArea"):
		$InteractArea.area_entered.connect(_on_interact_area_entered)
		$InteractArea.area_exited.connect(_on_interact_area_exited)
		$InteractArea.body_entered.connect(_on_interact_body_entered)
		$InteractArea.body_exited.connect(_on_interact_body_exited)


func _physics_process(_delta: float) -> void:
	if GameProgress.current_mode == GameProgress.MODE_WIN:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# During chase, freeze when round is over.
	if GameProgress.current_mode == GameProgress.MODE_CHASE and not GameState.is_playing:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _in_climb_zone:
		velocity = direction * climb_speed
	else:
		velocity = direction * speed
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()


func _try_interact() -> void:
	if _nearby_interactable and _nearby_interactable.has_method("interact"):
		_nearby_interactable.interact(self)


func set_climb_zone(active: bool) -> void:
	_in_climb_zone = active


func _on_chase_round_started() -> void:
	if GameProgress.current_mode == GameProgress.MODE_CHASE:
		global_position = _start_position
		velocity = Vector2.ZERO


func _on_interact_area_entered(area: Area2D) -> void:
	if area.is_in_group("interactable"):
		_nearby_interactable = area
	elif area.get_parent() and area.get_parent().is_in_group("interactable"):
		_nearby_interactable = area.get_parent()


func _on_interact_area_exited(area: Area2D) -> void:
	var candidate: Node = area
	if area.get_parent() and area.get_parent().is_in_group("interactable"):
		candidate = area.get_parent()
	if _nearby_interactable == candidate or _nearby_interactable == area:
		_nearby_interactable = null


func _on_interact_body_entered(body: Node2D) -> void:
	if body.is_in_group("interactable"):
		_nearby_interactable = body


func _on_interact_body_exited(body: Node2D) -> void:
	if _nearby_interactable == body:
		_nearby_interactable = null
