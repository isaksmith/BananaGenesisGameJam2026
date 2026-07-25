class_name UiIcons
extends RefCounted

const PATHS := {
	&"banana": "res://assets/sprites/banana.png",
	&"banana_peel": "res://assets/sprites/banana_peel.png",
	&"banana_peeled": "res://assets/sprites/banana_peeled.png",
	&"stick": "res://assets/sprites/stick.png",
	&"rock": "res://assets/sprites/rock.png",
	&"fire_kit": "res://assets/sprites/icon_fire_kit.png",
	&"sharp_rock": "res://assets/sprites/icon_sharp_rock.png",
	&"spear": "res://assets/sprites/icon_spear.png",
	&"banana_on_a_stick": "res://assets/sprites/icon_banana_on_a_stick.png",
	&"square_wheel": "res://assets/sprites/icon_square_wheel.png",
	&"banana_cart_frame": "res://assets/sprites/banana_cart.png",
}


static func texture(item_id: StringName) -> Texture2D:
	var path: String = PATHS.get(item_id, PATHS[&"banana"])
	return load(path) as Texture2D


static func make_icon(item_id: StringName, size: Vector2 = Vector2(32, 32)) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture(item_id)
	icon.custom_minimum_size = size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return icon
