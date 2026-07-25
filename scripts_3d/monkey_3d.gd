extends CharacterBody3D

@export var speed: float = 7.0
@export var jump_velocity: float = 6.5
@export var mouse_sensitivity: float = 0.003
@export var camera_distance: float = 6.5

var _start_position: Vector3
var _nearby_interactable: Node = null
var _yaw: float = 0.0
var _pitch: float = -0.35

@onready var pivot: Node3D = %CameraPivot
@onready var spring: SpringArm3D = %SpringArm
@onready var camera: Camera3D = %Camera3D
@onready var interact_area: Area3D = %InteractArea
@onready var mesh_root: Node3D = $Mesh


func _ready() -> void:
	add_to_group("player")
	_start_position = global_position
	spring.spring_length = camera_distance
	spring.collision_mask = 4
	_build_mesh()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameState.round_started.connect(_on_chase_round_started)
	interact_area.area_entered.connect(_on_area_entered)
	interact_area.area_exited.connect(_on_area_exited)
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)


func _build_mesh() -> void:
	for child in mesh_root.get_children():
		child.queue_free()
	# Kenney Cube Pets monkey — facing +Z after small yaw tweak.
	var monkey := AssetKit3D.make(AssetKit3D.MONKEY, 1.15, 180.0)
	monkey.position = Vector3(0, 0, 0)
	mesh_root.add_child(monkey)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.2, 0.2)
		pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("exit_minigame"):
		# Let main handle exiting minigames; in hub just free the mouse.
		if GameProgress.current_mode == GameProgress.MODE_HUB:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if GameProgress.current_mode == GameProgress.MODE_WIN:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if GameProgress.current_mode == GameProgress.MODE_CHASE and not GameState.is_playing:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= 18.0 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var basis_yaw := Basis(Vector3.UP, _yaw)
	var direction := (basis_yaw * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		mesh_root.rotation.y = lerp_angle(mesh_root.rotation.y, atan2(direction.x, direction.z), 0.2)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
	move_and_slide()


func _try_interact() -> void:
	if _nearby_interactable and _nearby_interactable.has_method("interact"):
		_nearby_interactable.interact(self)


func _on_chase_round_started() -> void:
	if GameProgress.current_mode == GameProgress.MODE_CHASE:
		global_position = _start_position
		velocity = Vector3.ZERO


func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("interactable"):
		_nearby_interactable = area
	elif area.get_parent() and area.get_parent().is_in_group("interactable"):
		_nearby_interactable = area.get_parent()


func _on_area_exited(area: Area3D) -> void:
	var candidate: Node = area
	if area.get_parent() and area.get_parent().is_in_group("interactable"):
		candidate = area.get_parent()
	if _nearby_interactable == candidate or _nearby_interactable == area:
		_nearby_interactable = null


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("interactable"):
		_nearby_interactable = body


func _on_body_exited(body: Node3D) -> void:
	if _nearby_interactable == body:
		_nearby_interactable = null
