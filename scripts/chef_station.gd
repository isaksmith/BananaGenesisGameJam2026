extends Area2D

## Interactive prep station used by Banana Chef.

const STATION_ART := {
	&"bananas": {
		"main": "res://assets/sprites/chef_stations/crate.png",
		"overlay": "res://assets/sprites/chef_stations/bananas_pile.png",
		"main_scale": 1.75,
		"overlay_scale": 0.95,
		"overlay_offset": Vector2(0, -52),
	},
	&"grill": {
		"main": "res://assets/sprites/chef_stations/frying_pan.png",
		"overlay": "res://assets/sprites/chef_stations/flame.png",
		"main_scale": 1.9,
		"overlay_scale": 0.65,
		"overlay_offset": Vector2(0, -72),
	},
	&"chop": {
		"main": "res://assets/sprites/chef_stations/cutting_board.png",
		"overlay": "res://assets/sprites/chef_stations/knife.png",
		"main_scale": 1.75,
		"overlay_scale": 1.3,
		"overlay_offset": Vector2(24, -62),
	},
	&"salad": {
		"main": "res://assets/sprites/chef_stations/salad_bowl.png",
		"overlay": "",
		"main_scale": 1.85,
		"overlay_scale": 1.0,
		"overlay_offset": Vector2.ZERO,
	},
	&"blender": {
		"main": "res://assets/sprites/chef_stations/blender.png",
		"overlay": "",
		# Tall appliance art, so it is anchored by its base instead of centred.
		"main_scale": 1.15,
		"main_offset": Vector2(0, -78),
		"overlay_scale": 0.95,
		"overlay_offset": Vector2.ZERO,
	},
	&"serve": {
		"main": "res://assets/sprites/chef_stations/serve_plate.png",
		"overlay": "",
		"main_scale": 1.9,
		"overlay_scale": 1.0,
		"overlay_offset": Vector2.ZERO,
	},
	&"trash": {
		"main": "res://assets/sprites/chef_stations/compost_bag.png",
		"overlay": "",
		"main_scale": 1.75,
		"overlay_scale": 1.0,
		"overlay_offset": Vector2.ZERO,
	},
}

var station_id: StringName = &""
var station_title: String = ""
var station_hint: String = ""
var accent: Color = Color.WHITE
var _prompt: Label


func setup(id: StringName, title: String, hint: String, color: Color) -> void:
	station_id = id
	station_title = title
	station_hint = hint
	accent = color
	name = "%sStation" % title.replace(" ", "")
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group("interactable")
	add_to_group("chef_station")
	_build_visual()


func interact(_player: Node = null) -> void:
	var kitchen := get_parent()
	if kitchen and kitchen.has_method("use_chef_station"):
		kitchen.use_chef_station(station_id)


func set_prompt_visible(show_prompt: bool) -> void:
	if _prompt:
		_prompt.visible = show_prompt


func _build_visual() -> void:
	# Tall counter body so stations read as standing prep tables.
	var counter := Polygon2D.new()
	counter.z_index = -1
	counter.color = Color(0.28, 0.16, 0.09, 1)
	counter.polygon = PackedVector2Array([
		Vector2(-66, -52), Vector2(66, -52), Vector2(62, 38), Vector2(-62, 38),
	])
	add_child(counter)

	var face := Polygon2D.new()
	face.z_index = -1
	face.color = Color(0.2, 0.11, 0.06, 1)
	face.polygon = PackedVector2Array([
		Vector2(-62, 8), Vector2(62, 8), Vector2(62, 38), Vector2(-62, 38),
	])
	add_child(face)

	var rim := Polygon2D.new()
	rim.z_index = -1
	rim.color = Color(accent.r, accent.g, accent.b, 0.55)
	rim.polygon = PackedVector2Array([
		Vector2(-72, -58), Vector2(72, -58), Vector2(66, -44), Vector2(-66, -44),
	])
	add_child(rim)

	var art: Dictionary = STATION_ART.get(station_id, {})
	var main_path := str(art.get("main", ""))
	if not main_path.is_empty():
		var main := _make_sprite(main_path, float(art.get("main_scale", 1.5)))
		main.position = art.get("main_offset", Vector2(0, -48)) as Vector2
		add_child(main)
	var overlay_path := str(art.get("overlay", ""))
	if not overlay_path.is_empty():
		var overlay := _make_sprite(overlay_path, float(art.get("overlay_scale", 1.0)))
		overlay.position = art.get("overlay_offset", Vector2.ZERO) as Vector2
		add_child(overlay)

	var title := Label.new()
	title.position = Vector2(-90, 40)
	title.size = Vector2(180, 24)
	title.text = station_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 4)
	add_child(title)

	_prompt = Label.new()
	_prompt.position = Vector2(-40, -118)
	_prompt.size = Vector2(80, 22)
	_prompt.text = "[E]"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 16)
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.35))
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.visible = false
	add_child(_prompt)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 88.0
	col.shape = shape
	col.position = Vector2(0, -20)
	add_child(col)


func _make_sprite(path: String, scale_mul: float) -> Sprite2D:
	var spr := Sprite2D.new()
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		spr.texture = ImageTexture.create_from_image(img)
	else:
		spr.texture = load(path) as Texture2D
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(scale_mul, scale_mul)
	return spr
