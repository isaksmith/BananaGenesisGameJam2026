extends Control

const TRACK_ITEMS: Array[StringName] = [
	&"banana", &"stick", &"rock", &"banana_peel",
	&"fire_kit", &"square_wheel", &"banana_cart_frame",
]

@onready var objective_label: Label = %ObjectiveLabel
@onready var inventory_row: HBoxContainer = %InventoryRow
@onready var progress_row: HBoxContainer = %ProgressRow
@onready var tip_label: Label = %TipLabel


func _ready() -> void:
	Inventory.inventory_changed.connect(_refresh_inventory)
	GameProgress.progress_changed.connect(_refresh_progress)
	GameProgress.mode_changed.connect(_on_mode_changed)
	_build_progress_chips()
	_refresh_inventory()
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
		{"id": &"fire", "label": "Fire", "icon": &"fire_kit"},
		{"id": &"wheel", "label": "Trails", "icon": &"square_wheel"},
		{"id": &"cart", "label": "Cart", "icon": &"banana_cart_frame"},
		{"id": &"chase", "label": "Raid", "icon": &"banana"},
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


func _refresh_inventory() -> void:
	for child in inventory_row.get_children():
		child.queue_free()
	var any := false
	for item_id in TRACK_ITEMS:
		var count := Inventory.get_count(item_id)
		if count <= 0:
			continue
		any = true
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.add_child(UiIcons.make_icon(item_id, Vector2(28, 28)))
		var label := Label.new()
		label.text = "x%d" % count
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		cell.add_child(label)
		inventory_row.add_child(cell)
	if not any:
		var empty := Label.new()
		empty.text = "Pockets empty — grab sticks, rocks, bananas"
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_outline_color", Color.BLACK)
		empty.add_theme_constant_override("outline_size", 3)
		inventory_row.add_child(empty)


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
	var cleared := GameProgress.cleared_wheel_levels.size()
	var total := WheelLevels.ids().size()
	return "Explore the jungle · enter a shrine with E · trails %d/%d cleared" % [cleared, total]
