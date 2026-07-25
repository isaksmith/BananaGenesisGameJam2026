extends Area2D

## Kart-style item banana: pickup for a short boost, or leave as a peel trap.

@export var boost_speed: float = 380.0
@export var boost_time: float = 0.9

signal collected(by: Node2D)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	add_to_group("item_banana")


func _on_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D:
		return
	if body.has_method("apply_banana_boost"):
		body.apply_banana_boost(boost_speed, boost_time)
	elif body is CharacterBody2D:
		var cb := body as CharacterBody2D
		var dir := cb.velocity.normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		cb.velocity = dir * boost_speed
	collected.emit(body)
	GameProgress.juice_shake.emit(0.12)
	# Drop a peel behind the collector.
	_spawn_peel(global_position + Vector2(randf_range(-30, 30), randf_range(-10, 10)))
	queue_free()


func _spawn_peel(at: Vector2) -> void:
	var peel_scene: PackedScene = load("res://scenes/enemies/banana_peel_hazard.tscn")
	if peel_scene == null:
		return
	var peel := peel_scene.instantiate() as Node2D
	peel.global_position = at
	var parent := get_parent()
	if parent:
		parent.add_child(peel)
