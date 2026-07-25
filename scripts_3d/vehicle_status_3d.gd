extends CharacterBody3D

var slip_timer: float = 0.0
var boost_timer: float = 0.0
var boost_mult: float = 1.0


func apply_peel_slip(duration: float, boost: float) -> void:
	slip_timer = duration
	var dir := velocity
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = Vector3.RIGHT if randf() > 0.5 else Vector3.LEFT
	else:
		dir = dir.normalized()
	velocity = dir * boost + Vector3(0, 2.5, 0)


func apply_banana_boost(speed: float, duration: float) -> void:
	boost_timer = duration
	boost_mult = 1.6
	var dir := velocity
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()
	velocity = dir * speed


func tick_status(delta: float) -> void:
	slip_timer = maxf(slip_timer - delta, 0.0)
	boost_timer = maxf(boost_timer - delta, 0.0)
	if boost_timer <= 0.0:
		boost_mult = 1.0


func is_slipping() -> bool:
	return slip_timer > 0.0
