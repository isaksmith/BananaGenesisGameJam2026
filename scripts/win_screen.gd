extends Control

@onready var title_label: Label = %TitleLabel
@onready var body_label: Label = %BodyLabel
@onready var hint_label: Label = %HintLabel


func _ready() -> void:
	visible = false
	GameProgress.game_won.connect(_on_game_won)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("restart"):
		GameProgress.reset_campaign()
		get_tree().reload_current_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("exit_minigame") or event.is_action_pressed("ui_cancel"):
		visible = false
		GameProgress.load_hub(true)
		get_viewport().set_input_as_handled()


func _on_game_won(final_chase_score: int) -> void:
	visible = true
	title_label.text = "The Tribe Invents Reinventing"
	body_label.text = (
		"Bananas defended: %d\n\n"
		+ "Having reinvented fire, the wheel, and logistics,\n"
		+ "the monkeys invent the *concept* of reinventing the wheel\n"
		+ "as a recreational sport.\n\n"
		+ "They call it a game jam."
	) % final_chase_score
	hint_label.text = "R = restart campaign · Esc/Q = back to camp"
