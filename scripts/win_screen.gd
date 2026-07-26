extends Control

@onready var title_label: Label = %TitleLabel
@onready var body_label: Label = %BodyLabel
@onready var hint_label: Label = %HintLabel


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameProgress.game_won.connect(_on_game_won)
	GameProgress.mode_changed.connect(_on_mode_changed)


func _on_mode_changed(mode: StringName) -> void:
	if mode != GameProgress.MODE_WIN:
		visible = false


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


func _on_game_won(trails_cleared: int) -> void:
	visible = true
	move_to_front()
	var total := maxi(trails_cleared, GameProgress.trail_count())
	title_label.text = "All Courses Cleared!"
	body_label.text = (
		"Jungle trails conquered: %d / %d\n\n"
		+ "Having reinvented every wheel the jungle demanded,\n"
		+ "the monkeys invent the *concept* of reinventing the wheel\n"
		+ "as a recreational sport.\n\n"
		+ "They call it a game jam.\n\n"
		+ "Chef, Maze, and Defense shrines stay open for fun runs."
	) % [trails_cleared, total]
	hint_label.text = "R = restart campaign · Esc/Q = back to camp"
