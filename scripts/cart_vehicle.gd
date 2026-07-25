extends CharacterBody2D

## Banana delivery cart — flips to face travel, spins wheels, slides on peels.

var slip_timer: float = 0.0
var boost_timer: float = 0.0
var boost_mult: float = 1.0
var _roll: float = 0.0
var _facing: float = 1.0

@onready var _wheel_l: Sprite2D = get_node_or_null("WheelL") as Sprite2D
@onready var _wheel_r: Sprite2D = get_node_or_null("WheelR") as Sprite2D
@onready var _body: Sprite2D = get_node_or_null("Body") as Sprite2D


func _ready() -> void:
	add_to_group("cart")


func apply_peel_slip(duration: float, boost: float) -> void:
	slip_timer = duration
	var dir := velocity.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT.rotated(randf_range(-0.4, 0.4))
	# Funny sideways skid, still moving — not a hard freeze.
	velocity = dir.rotated(randf_range(-0.85, 0.85)) * boost


func apply_banana_boost(speed: float, duration: float) -> void:
	boost_timer = duration
	boost_mult = 1.55
	var dir := velocity.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	velocity = dir * speed


func tick_status(delta: float) -> void:
	slip_timer = maxf(slip_timer - delta, 0.0)
	boost_timer = maxf(boost_timer - delta, 0.0)
	if boost_timer <= 0.0:
		boost_mult = 1.0
	_update_visuals(delta)


func is_slipping() -> bool:
	return slip_timer > 0.0


func _update_visuals(delta: float) -> void:
	var speed := velocity.length()
	if absf(velocity.x) > 20.0:
		_facing = signf(velocity.x)
	if _body:
		_body.scale = Vector2(0.72 * _facing, 0.72)
		# Tiny bounce while rolling.
		_body.position.y = -16.0 + sin(Time.get_ticks_msec() * 0.02) * (1.5 if speed > 40.0 else 0.0)
	if speed > 8.0:
		_roll += speed * delta * 0.09
		if _wheel_l:
			_wheel_l.rotation = _roll
		if _wheel_r:
			_wheel_r.rotation = _roll
