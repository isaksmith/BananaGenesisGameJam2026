extends Area3D

@export var slip_duration: float = 0.85
@export var slip_boost: float = 8.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	var peel := AssetKit3D.make(AssetKit3D.COCONUT, 1.8, 15.0)
	peel.position = Vector3(0, 0.05, 0)
	add_child(peel)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	col.shape = shape
	add_child(col)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("apply_peel_slip"):
		body.apply_peel_slip(slip_duration, slip_boost)
	elif body is RigidBody3D:
		var rb := body as RigidBody3D
		var side := 1.0 if randf() > 0.5 else -1.0
		rb.apply_central_impulse(Vector3(side * slip_boost * 0.45, slip_boost * 0.35, slip_boost * 0.25))
		rb.apply_torque_impulse(Vector3(randf_range(-6, 6), 0, side * 8.0))
	elif body is CharacterBody3D:
		var cb := body as CharacterBody3D
		var dir := Vector3(signf(cb.velocity.x), 0.0, signf(cb.velocity.z))
		if dir == Vector3.ZERO:
			dir = Vector3.RIGHT if randf() > 0.5 else Vector3.LEFT
		cb.velocity = dir * slip_boost + Vector3(0, 3, 0)
	GameProgress.juice_shake.emit(0.12)
