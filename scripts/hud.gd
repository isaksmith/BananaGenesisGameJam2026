extends Control

@onready var score_label: Label = %ScoreLabel
@onready var time_label: Label = %TimeLabel


func _ready() -> void:
	visible = false
	GameState.score_changed.connect(_on_score_changed)
	GameState.time_changed.connect(_on_time_changed)
	GameProgress.mode_changed.connect(_on_mode_changed)
	_on_mode_changed(GameProgress.current_mode)


func _on_mode_changed(mode: StringName) -> void:
	visible = mode == GameProgress.MODE_CHASE


func _on_score_changed(score: int) -> void:
	score_label.text = "Stash: %d" % score


func _on_time_changed(time_left: float) -> void:
	time_label.text = "Time: %d" % ceili(time_left)
	if time_left <= 10.0:
		time_label.modulate = Color(1.0, 0.35, 0.3)
	else:
		time_label.modulate = Color.WHITE
