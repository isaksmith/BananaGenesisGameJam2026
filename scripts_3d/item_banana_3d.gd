extends Area3D

@export var boost_speed: float = 12.0
@export var boost_duration: float = 1.2


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	var banana := AssetKit3D.make(AssetKit3D.BANANA, 3.2, 90.0)
	banana.position = Vector3(0, 0.35, 0)
	add_child(banana)
	# Glow ring under the banana.
	add_child(MeshKit3D.sphere(0.55, Color(1.0, 0.95, 0.3), Vector3(0, 0.1, 0), 1.8))
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	col.shape = shape
	add_child(col)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("apply_banana_boost"):
		body.apply_banana_boost(boost_speed, boost_duration)
	elif body is CharacterBody3D:
		var cb := body as CharacterBody3D
		var dir := cb.velocity
		dir.y = 0.0
		if dir.length() < 0.1:
			dir = Vector3.FORWARD
		cb.velocity = dir.normalized() * boost_speed
	var peel := Area3D.new()
	peel.set_script(load("res://scripts_3d/peel_hazard_3d.gd"))
	peel.global_position = global_position
	get_parent().add_child(peel)
	GameProgress.juice_shake.emit(0.1)
	queue_free()
