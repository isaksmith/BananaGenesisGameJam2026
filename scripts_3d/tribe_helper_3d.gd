extends CharacterBody3D

enum Mood { WANDER, CHASE_PLAYER, STEAL_CARGO, HELP_FIRE }

@export var label_text: String = "Helper"
@export var mood: int = Mood.WANDER
@export var speed: float = 3.5
@export var steal_radius: float = 2.2

var _cooldown: float = 0.0
var _wander_dir: Vector3 = Vector3.FORWARD
var _wander_timer: float = 0.0
var _label: Label3D
var _mesh: Node3D


func _ready() -> void:
	add_to_group("tribe_helper")
	collision_layer = 1
	collision_mask = 4
	_build()


func _build() -> void:
	_mesh = AssetKit3D.make(AssetKit3D.MONKEY, 1.05, 180.0)
	add_child(_mesh)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.3
	col.shape = shape
	col.position = Vector3(0, 0.75, 0)
	add_child(col)
	_label = Label3D.new()
	_label.text = label_text
	_label.position = Vector3(0, 2.0, 0)
	_label.font_size = 28
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = 0.0

	match mood:
		Mood.WANDER:
			_do_wander(delta)
		Mood.CHASE_PLAYER:
			_chase_target(delta)
		Mood.STEAL_CARGO:
			_steal_loop(delta)
		Mood.HELP_FIRE:
			_help_fire(delta)
	move_and_slide()


func _do_wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		_wander_timer = randf_range(1.0, 2.5)
	velocity.x = _wander_dir.x * speed * 0.7
	velocity.z = _wander_dir.z * speed * 0.7
	if _mesh and _wander_dir.length() > 0.1:
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, atan2(_wander_dir.x, _wander_dir.z), 0.15)
	_bump_player()


func _chase_target(delta: float) -> void:
	var target := get_tree().get_first_node_in_group("cart") as Node3D
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	if target == null:
		_do_wander(delta)
		return
	var dir := target.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.1:
		dir = dir.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		if _mesh:
			_mesh.rotation.y = lerp_angle(_mesh.rotation.y, atan2(dir.x, dir.z), 0.2)
	_bump_player()


func _steal_loop(delta: float) -> void:
	var cart := get_tree().get_first_node_in_group("cart") as Node3D
	if cart == null:
		_do_wander(delta)
		return
	var dir := cart.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.1:
		dir = dir.normalized()
		velocity.x = dir.x * speed * 1.1
		velocity.z = dir.z * speed * 1.1
	if _label and _label.text != label_text and _cooldown < 1.4:
		_label.text = label_text
	if _cooldown <= 0.0 and global_position.distance_to(cart.global_position) < steal_radius:
		var run := cart.get_parent()
		if run and run.has_method("tribe_steal_cargo") and run.tribe_steal_cargo():
			_label.text = "Helping!"
			_cooldown = 2.5


func _help_fire(delta: float) -> void:
	_do_wander(delta)
	if _cooldown > 0.0:
		return
	var camp := get_tree().get_first_node_in_group("fire_camp")
	if camp and camp.has_method("tribe_interfere"):
		camp.tribe_interfere(0.08)
		_cooldown = 1.4
		_label.text = "Spark!"


func _bump_player() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider is CharacterBody3D and collider.is_in_group("player"):
			var cb := collider as CharacterBody3D
			var push := -col.get_normal() * 4.0
			cb.velocity += Vector3(push.x, 0.5, push.z)
