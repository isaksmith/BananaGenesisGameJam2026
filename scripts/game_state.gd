extends Node

## Chase-only round state. Inactive during hub / other minigames.

signal score_changed(score: int)
signal time_changed(time_left: float)
signal round_ended(final_score: int)
signal round_started

const ROUND_TIME := 45.0

var score: int = 0
var time_left: float = ROUND_TIME
var is_playing: bool = false
var is_active: bool = false


func set_active(active: bool) -> void:
	is_active = active
	if not active:
		is_playing = false


func _process(delta: float) -> void:
	if not is_active or not is_playing:
		return
	time_left = maxf(time_left - delta, 0.0)
	time_changed.emit(time_left)
	if time_left <= 0.0:
		end_round()


func add_score(amount: int = 1) -> void:
	if not is_active or not is_playing:
		return
	score += amount
	score_changed.emit(score)


func start_round() -> void:
	if not is_active:
		return
	score = 0
	time_left = ROUND_TIME
	is_playing = true
	score_changed.emit(score)
	time_changed.emit(time_left)
	round_started.emit()


func end_round() -> void:
	if not is_playing:
		return
	is_playing = false
	time_left = 0.0
	time_changed.emit(time_left)
	round_ended.emit(score)
	# Finale: chase ends the campaign.
	GameProgress.report_chase_finished(score)
