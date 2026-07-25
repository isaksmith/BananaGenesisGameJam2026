extends Area2D

@export var item_id: StringName = &"stick"
@export var amount: int = 1
@export var pickup_on_touch: bool = true

const TEXTURES := {
	&"stick": "res://assets/sprites/stick.png",
	&"rock": "res://assets/sprites/rock.png",
	&"banana": "res://assets/sprites/banana.png",
	&"banana_peel": "res://assets/sprites/banana_peel.png",
}


func _ready() -> void:
	add_to_group("interactable")
	body_entered.connect(_on_body_entered)
	_apply_texture()


func _apply_texture() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var path: String = TEXTURES.get(item_id, TEXTURES[&"stick"])
	sprite.texture = load(path)
	# Hub collectibles stay smaller than shrine pedestals/icons.
	if item_id == &"rock":
		sprite.scale = Vector2(0.32, 0.32)
	elif item_id == &"stick":
		sprite.scale = Vector2(0.34, 0.34)
	else:
		sprite.scale = Vector2(0.36, 0.36)


func interact(_by: Node) -> void:
	_collect()


func _on_body_entered(body: Node2D) -> void:
	if pickup_on_touch and body.is_in_group("player"):
		_collect()


func _collect() -> void:
	Inventory.add_item(item_id, amount)
	if item_id == &"banana":
		Inventory.add_item(&"banana_peel", 1)
	GameProgress.juice_shake.emit(0.08)
	queue_free()
