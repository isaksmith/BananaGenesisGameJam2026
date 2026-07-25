extends Area2D

## SuperTuxKart-style slip hazard.

@export var slip_duration: float = 0.75
@export var slip_boost: float = 420.0
@export var one_shot: bool = true

signal slipped(body: Node2D)

var _used: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	add_to_group("peel_hazard")


func _on_body_entered(body: Node2D) -> void:
	if _used:
		return
	if body.has_method("apply_peel_slip"):
		body.apply_peel_slip(slip_duration, slip_boost)
	elif body is RigidBody2D:
		var rb := body as RigidBody2D
		var side := 1.0 if randf() > 0.5 else -1.0
		rb.apply_central_impulse(Vector2(side * slip_boost * 0.35, -slip_boost * 0.25))
		rb.apply_torque_impulse(side * 4000.0)
	elif body is CharacterBody2D:
		_slip_character(body as CharacterBody2D)
	else:
		return
	slipped.emit(body)
	GameProgress.juice_shake.emit(0.2)
	if one_shot:
		_used = true
		queue_free()


func _slip_character(body: CharacterBody2D) -> void:
	var dir := Vector2(signf(body.velocity.x), 0.0)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT if randf() > 0.5 else Vector2.LEFT
	body.velocity = dir * slip_boost + Vector2(0, -80)
