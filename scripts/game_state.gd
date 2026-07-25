extends Node

## Chase / defense round HUD state. Arena scripts drive the values.

signal score_changed(score: int)
signal time_changed(time_left: float)
signal round_ended(final_score: int)
signal round_started

const ROUND_TIME := 30.0

var score: int = 0
var time_left: float = ROUND_TIME
var is_playing: bool = false
var is_active: bool = false


func set_active(active: bool) -> void:
	is_active = active
	if not active:
		is_playing = false


func _process(_delta: float) -> void:
	# Timer is owned by chase_arena — this autoload only stores HUD state.
	pass


func add_score(amount: int = 1) -> void:
	if not is_active or not is_playing:
		return
	score += amount
	score_changed.emit(score)


func start_round() -> void:
	# Kept for compatibility; chase_arena starts itself in _ready.
	if not is_active:
		return
	is_playing = true
	round_started.emit()


func end_round() -> void:
	if not is_playing:
		return
	is_playing = false
	round_ended.emit(score)
