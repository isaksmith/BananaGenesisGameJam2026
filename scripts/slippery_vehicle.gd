extends CharacterBody2D

## Mixin-style helpers for peel slip + banana boost (used by cart / wheel via composition).
## Attach this script OR call these methods from the controlling minigame.

var slip_timer: float = 0.0
var boost_timer: float = 0.0
var boost_mult: float = 1.0
var slip_dir: Vector2 = Vector2.ZERO


func apply_peel_slip(duration: float, boost: float) -> void:
	slip_timer = duration
	var dir := Vector2(signf(velocity.x), 0.0)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT if randf() > 0.5 else Vector2.LEFT
	slip_dir = dir
	velocity = dir * boost + Vector2(0, -100)


func apply_banana_boost(speed: float, duration: float) -> void:
	boost_timer = duration
	boost_mult = 1.65
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
