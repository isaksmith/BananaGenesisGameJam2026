extends Node

signal inventory_changed

const MAX_STACK := 99

var _counts: Dictionary = {
	&"banana": 0,
	&"stick": 0,
	&"rock": 0,
	&"banana_peel": 0,
	&"sharp_rock": 0,
	&"spear": 0,
	&"banana_on_a_stick": 0,
	&"fire_kit": 0,
	&"square_wheel": 0,
	&"banana_cart_frame": 0,
}


func get_count(item_id: StringName) -> int:
	return int(_counts.get(item_id, 0))


func add_item(item_id: StringName, amount: int = 1) -> void:
	if amount <= 0:
		return
	var next: int = mini(get_count(item_id) + amount, MAX_STACK)
	_counts[item_id] = next
	inventory_changed.emit()


func remove_item(item_id: StringName, amount: int = 1) -> bool:
	if get_count(item_id) < amount:
		return false
	_counts[item_id] = get_count(item_id) - amount
	inventory_changed.emit()
	return true


func has_items(requirements: Dictionary) -> bool:
	for item_id in requirements:
		if get_count(item_id) < int(requirements[item_id]):
			return false
	return true


func consume(requirements: Dictionary) -> bool:
	if not has_items(requirements):
		return false
	for item_id in requirements:
		remove_item(item_id, int(requirements[item_id]))
	return true


func clear() -> void:
	for item_id in _counts.keys():
		_counts[item_id] = 0
	inventory_changed.emit()


func as_display_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for item_id in _counts:
		var count: int = get_count(item_id)
		if count > 0:
			lines.append("%s: %d" % [str(item_id).replace("_", " "), count])
	if lines.is_empty():
		lines.append("(empty pockets)")
	return lines
