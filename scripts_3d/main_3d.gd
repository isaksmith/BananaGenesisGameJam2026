extends Node3D

@onready var stage: Node3D = %Stage
@onready var camera_rig: Node3D = %ShakeRig


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
	if camera_rig == null:
		return
	var strength := amount * 0.25
	var tween := create_tween()
	for i in 6:
		var offset := Vector3(randf_range(-strength, strength), randf_range(-strength, strength), 0.0)
		tween.tween_property(camera_rig, "position", offset, 0.03)
	tween.tween_property(camera_rig, "position", Vector3.ZERO, 0.05)
