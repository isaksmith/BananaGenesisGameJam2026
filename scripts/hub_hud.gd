extends Control

@onready var objective_label: Label = %ObjectiveLabel
@onready var progress_row: HBoxContainer = %ProgressRow


func _ready() -> void:
	GameProgress.progress_changed.connect(_refresh_progress)
	GameProgress.mode_changed.connect(_on_mode_changed)
	_build_progress_chips()
	_refresh_progress()
	_on_mode_changed(GameProgress.current_mode)


func _on_mode_changed(mode: StringName) -> void:
	visible = mode == GameProgress.MODE_HUB
	if visible:
		_refresh_progress()


func _build_progress_chips() -> void:
	for child in progress_row.get_children():
		child.queue_free()
	for era in [
		{"id": &"fire", "label": "Chef", "icon": &"fire_kit"},
		{"id": &"wheel", "label": "Trails", "icon": &"square_wheel"},
		{"id": &"cart", "label": "Maze", "icon": &"banana"},
		{"id": &"chase", "label": "Defend", "icon": &"banana"},
	]:
		var chip := PanelContainer.new()
		chip.name = str(era["id"])
		chip.set_meta("era_id", era["id"])
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_top", 4)
		margin.add_theme_constant_override("margin_bottom", 4)
		chip.add_child(margin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		margin.add_child(row)
		row.add_child(UiIcons.make_icon(era["icon"], Vector2(28, 28)))
		var label := Label.new()
		label.text = era["label"]
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 3)
		row.add_child(label)
		progress_row.add_child(chip)


func _refresh_progress() -> void:
	objective_label.text = _objective_text()
	for chip in progress_row.get_children():
		var era_id: StringName = chip.get_meta("era_id")
		var status := "open"
		if era_id == &"wheel":
			status = "done" if not GameProgress.cleared_wheel_levels.is_empty() else "open"
		else:
			status = GameProgress.shrine_status(era_id)
		match status:
			"done":
				chip.modulate = Color(0.55, 1.0, 0.55)
			"open":
				chip.modulate = Color(1.0, 0.95, 0.45)
			_:
				chip.modulate = Color(0.55, 0.55, 0.6)


func _objective_text() -> String:
	var cleared := GameProgress.cleared_trail_count()
	var total := GameProgress.trail_count()
	if GameProgress.campaign_complete or (total > 0 and cleared >= total):
		return "All %d trails cleared! · side shrines stay open · Esc/Q exits courses" % total
	return "Explore the jungle · enter a shrine with E · trails %d/%d cleared" % [cleared, total]
