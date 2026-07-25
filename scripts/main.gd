extends Node

@onready var stage: Node2D = %Stage
@onready var shake_camera: Camera2D = %ShakeCamera


func _ready() -> void:
	GameProgress.bind_stage(stage)
	GameProgress.juice_shake.connect(_on_juice_shake)
	GameProgress.load_hub(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("exit_minigame") or event.is_action_pressed("ui_cancel"):
		if GameProgress.current_mode != GameProgress.MODE_HUB and GameProgress.current_mode != GameProgress.MODE_WIN:
			GameProgress.exit_minigame()
			get_viewport().set_input_as_handled()


func _on_juice_shake(amount: float) -> void:
	if shake_camera == null:
		return
	var strength := amount * 12.0
	var tween := create_tween()
	for i in 6:
		var offset := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(shake_camera, "offset", offset, 0.03)
	tween.tween_property(shake_camera, "offset", Vector2.ZERO, 0.05)
