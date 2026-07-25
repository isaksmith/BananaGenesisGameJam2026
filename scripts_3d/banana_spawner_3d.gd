extends Node

@export var spawn_interval: float = 1.1
@export var arena_half: float = 14.0

var _timer: float = 0.0


func _process(delta: float) -> void:
	if not GameState.is_playing:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn_one()


func _spawn_one() -> void:
	var banana := Area3D.new()
	banana.set_script(load("res://scripts_3d/banana_3d.gd"))
	banana.set("pickup_mode", "chase")
	banana.position = Vector3(
		randf_range(-arena_half, arena_half),
		0.5,
		randf_range(-arena_half, arena_half)
	)
	get_parent().add_child(banana)
