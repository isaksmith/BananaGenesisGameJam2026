extends Control

var _open: bool = false

@onready var panel: PanelContainer = %Panel
@onready var recipe_list: VBoxContainer = %RecipeList
@onready var inventory_list: VBoxContainer = %InventoryList
@onready var toggle_hint: Label = %ToggleHint
@onready var toggle_hint_panel: PanelContainer = $ToggleHintPanel
@onready var dim: ColorRect = %Dim


func _ready() -> void:
	visible = true
	panel.visible = false
	dim.visible = false
	toggle_hint.text = "[C] Recipe Book"
	Inventory.inventory_changed.connect(_refresh)
	Crafting.item_crafted.connect(_on_crafted)
	GameProgress.mode_changed.connect(_on_mode_changed)
	_build_recipes()
	_refresh()
	_on_mode_changed(GameProgress.current_mode)


func _unhandled_input(event: InputEvent) -> void:
	if GameProgress.current_mode == GameProgress.MODE_WIN:
		return
	if event.is_action_pressed("craft_menu"):
		_open = not _open
		panel.visible = _open
		dim.visible = _open
		if _open:
			_refresh()
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		_open = false
		panel.visible = false
		dim.visible = false
		get_viewport().set_input_as_handled()


func _on_mode_changed(mode: StringName) -> void:
	var in_hub_flow := mode == GameProgress.MODE_HUB or mode == GameProgress.MODE_FIRE \
		or mode == GameProgress.MODE_WHEEL or mode == GameProgress.MODE_CART
	toggle_hint_panel.visible = in_hub_flow
	if mode == GameProgress.MODE_WIN or mode == GameProgress.MODE_CHASE:
		_open = false
		panel.visible = false
		dim.visible = false


func _build_recipes() -> void:
	for child in recipe_list.get_children():
		child.queue_free()
	for recipe in Crafting.get_recipes():
		var row := PanelContainer.new()
		row.set_meta("recipe_id", recipe["id"])
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		row.add_child(margin)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		margin.add_child(h)

		h.add_child(UiIcons.make_icon(recipe["result"], Vector2(40, 40)))

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.name = "InfoBox"
		h.add_child(info)

		var title := Label.new()
		title.name = "Title"
		title.text = recipe["name"]
		title.add_theme_font_size_override("font_size", 16)
		title.add_theme_color_override("font_outline_color", Color.BLACK)
		title.add_theme_constant_override("outline_size", 3)
		info.add_child(title)

		var ingredients := HBoxContainer.new()
		ingredients.name = "Ingredients"
		ingredients.add_theme_constant_override("separation", 6)
		info.add_child(ingredients)
		_fill_ingredients(ingredients, recipe["ingredients"])

		var blurb := Label.new()
		blurb.name = "Blurb"
		blurb.text = recipe["blurb"]
		blurb.add_theme_font_size_override("font_size", 12)
		blurb.modulate = Color(0.9, 0.9, 0.8)
		info.add_child(blurb)

		var btn := Button.new()
		btn.name = "CraftBtn"
		btn.text = "Craft"
		btn.custom_minimum_size = Vector2(72, 36)
		btn.pressed.connect(_craft.bind(recipe["id"]))
		h.add_child(btn)

		recipe_list.add_child(row)


func _fill_ingredients(container: HBoxContainer, ingredients: Dictionary) -> void:
	for child in container.get_children():
		child.queue_free()
	var first := true
	for item_id in ingredients:
		if not first:
			var plus := Label.new()
			plus.text = "+"
			plus.add_theme_font_size_override("font_size", 14)
			container.add_child(plus)
		first = false
		container.add_child(UiIcons.make_icon(item_id, Vector2(24, 24)))
		var count := Label.new()
		count.text = "x%d" % int(ingredients[item_id])
		count.add_theme_font_size_override("font_size", 13)
		container.add_child(count)


func _refresh() -> void:
	_refresh_inventory_panel()
	for row in recipe_list.get_children():
		var recipe_id: StringName = row.get_meta("recipe_id")
		var btn: Button = row.find_child("CraftBtn", true, false)
		if btn:
			btn.disabled = not Crafting.can_craft(recipe_id)
			btn.text = "Craft" if not btn.disabled else "Need more"


func _refresh_inventory_panel() -> void:
	for child in inventory_list.get_children():
		child.queue_free()
	var lines := Inventory.as_display_lines()
	if lines.size() == 1 and lines[0].begins_with("(empty"):
		var empty := Label.new()
		empty.text = "Empty pockets"
		inventory_list.add_child(empty)
		return
	for item_id in UiIcons.PATHS.keys():
		var count := Inventory.get_count(item_id)
		if count <= 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UiIcons.make_icon(item_id, Vector2(28, 28)))
		var label := Label.new()
		label.text = "%s  x%d" % [str(item_id).replace("_", " "), count]
		label.add_theme_font_size_override("font_size", 14)
		row.add_child(label)
		inventory_list.add_child(row)


func _craft(recipe_id: StringName) -> void:
	Crafting.craft(recipe_id)
	_refresh()


func _on_crafted(_item_id: StringName) -> void:
	_refresh()
