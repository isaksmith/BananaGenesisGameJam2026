extends Node

signal item_crafted(item_id: StringName)
signal craft_failed(reason: String)

## ingredient dict -> result item
const RECIPES: Array[Dictionary] = [
	{
		"id": &"fire_kit",
		"name": "Fire Kit",
		"result": &"fire_kit",
		"amount": 1,
		"ingredients": {&"stick": 2},
		"blurb": "Two sticks. Infinite smugness.",
	},
	{
		"id": &"sharp_rock",
		"name": "Sharp Rock",
		"result": &"sharp_rock",
		"amount": 1,
		"ingredients": {&"rock": 2},
		"blurb": "Bang rocks. Science.",
	},
	{
		"id": &"spear",
		"name": "Spear",
		"result": &"spear",
		"amount": 1,
		"ingredients": {&"sharp_rock": 1, &"stick": 1},
		"blurb": "Pointy stick supremacy.",
	},
	{
		"id": &"banana_on_a_stick",
		"name": "Banana on a Stick",
		"result": &"banana_on_a_stick",
		"amount": 1,
		"ingredients": {&"banana": 1, &"stick": 1},
		"blurb": "The ultimate early-game tool.",
	},
	{
		"id": &"square_wheel",
		"name": "Square Wheel",
		"result": &"square_wheel",
		"amount": 1,
		"ingredients": {&"rock": 1, &"banana_peel": 1},
		"blurb": "Reinvented. Incorrectly. Perfectly.",
	},
	{
		"id": &"banana_cart_frame",
		"name": "Banana Cart Frame",
		"result": &"banana_cart_frame",
		"amount": 1,
		"ingredients": {&"square_wheel": 1, &"stick": 1},
		"blurb": "Transportation, monkey-style.",
	},
]


func get_recipes() -> Array[Dictionary]:
	return RECIPES


func get_recipe(recipe_id: StringName) -> Dictionary:
	return _find_recipe(recipe_id)


func can_craft(recipe_id: StringName) -> bool:
	var recipe := get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	return Inventory.has_items(recipe["ingredients"])


func craft(recipe_id: StringName) -> bool:
	var recipe := get_recipe(recipe_id)
	if recipe.is_empty():
		craft_failed.emit("Unknown recipe")
		return false
	if not Inventory.consume(recipe["ingredients"]):
		craft_failed.emit("Missing ingredients")
		return false
	var result: StringName = recipe["result"]
	Inventory.add_item(result, int(recipe.get("amount", 1)))
	# Crafting square wheel from peel grants a peel-less joke peel if needed later.
	if result == &"banana_on_a_stick":
		Inventory.add_item(&"banana_peel", 1)
	item_crafted.emit(result)
	GameProgress.juice_shake.emit(0.2)
	return true


func _find_recipe(recipe_id: StringName) -> Dictionary:
	for recipe in RECIPES:
		if recipe["id"] == recipe_id:
			return recipe
	return {}
