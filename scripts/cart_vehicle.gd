extends CharacterBody2D

var slip_timer: float = 0.0
var boost_timer: float = 0.0
var boost_mult: float = 1.0


func _ready() -> void:
	add_to_group("cart")


func apply_peel_slip(duration: float, boost: float) -> void:
	slip_timer = duration
	var dir := velocity.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT if randf() > 0.5 else Vector2.LEFT
	velocity = dir.rotated(randf_range(-0.6, 0.6)) * boost


func apply_banana_boost(speed: float, duration: float) -> void:
	boost_timer = duration
	boost_mult = 1.6
	var dir := velocity.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	velocity = dir * speed


func tick_status(delta: float) -> void:
	slip_timer = maxf(slip_timer - delta, 0.0)
	boost_timer = maxf(boost_timer - delta, 0.0)
	if boost_timer <= 0.0:
		boost_mult = 1.0


func is_slipping() -> bool:
	return slip_timer > 0.0
