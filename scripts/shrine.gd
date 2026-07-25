extends Area2D

const PEDESTAL_TEX := "res://assets/sprites/shrine_base.png"
const FOREST_PLATFORM := "res://assets/sprites/forest_platform/platform_0.png"
const ICE_PLATFORM := "res://assets/sprites/ice_platform/platform_0.png"
const GRAVEYARD_PLATFORM := "res://assets/sprites/moon_graveyard/shrine_platform_chunk.png"
const LUNAR_PLATFORM := "res://assets/sprites/moon_graveyard/platform_0.png"

const ICONS := {
	&"fire": "res://assets/sprites/chef_stations/shrine_emblem.png",
	&"wheel": "res://assets/sprites/icon_square_wheel.png",
	&"cart": "res://assets/sprites/banana_cart.png",
	&"chase": "res://assets/sprites/gorilla/shrine_emblem.png",
	&"moon_graveyard": "res://assets/sprites/moon_graveyard/Salt.png",
	&"desert_sky": "res://assets/sprites/hazards/tumbleweed.png",
	&"lunar_void": "res://assets/sprites/parallax_moon/crescent_moon.png",
	&"tiger_chase": "res://assets/sprites/tiger/shrine_emblem.png",
}

@export var minigame_id: StringName = &"fire"
@export var title: String = "Shrine"
@export var subtitle: String = ""
@export var icon_path: String = ""

var _player_near: bool = false
var _pedestal_base_modulate: Color = Color.WHITE

@onready var label: Label = %Label
@onready var glow: Polygon2D = %Glow
@onready var pedestal: Sprite2D = %Pedestal
@onready var icon: Sprite2D = %Icon


func _ready() -> void:
	add_to_group("interactable")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	GameProgress.progress_changed.connect(_refresh)
	_apply_level_defaults()
	_setup_art()
	_refresh()


func _apply_level_defaults() -> void:
	if not WheelLevels.LEVELS.has(minigame_id):
		return
	var level := WheelLevels.get_level(minigame_id)
	if title == "Shrine" or title.is_empty():
		title = str(level.get("title", title))
	if subtitle.is_empty():
		subtitle = str(level.get("theme_tip", ""))
	if icon_path.is_empty():
		icon_path = str(level.get("icon", ""))


func _load_texture(path: String) -> Texture2D:
	var tex := load(path) as Texture2D
	if tex != null:
		return tex
	# Fallback when .godot/imported cache is missing/stale (common while editor is open).
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image != null:
		return ImageTexture.create_from_image(image)
	return null


func _trail_theme() -> StringName:
	if not WheelLevels.LEVELS.has(minigame_id):
		return &""
	var level := WheelLevels.get_level(minigame_id)
	return StringName(level.get("theme", &"forest"))


func _apply_theme_pedestal() -> void:
	## Match hub shrine platforms to each trail's in-level platform art.
	var theme := _trail_theme()
	pedestal.visible = true
	pedestal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pedestal_base_modulate = Color.WHITE

	match theme:
		&"winter":
			pedestal.texture = _load_texture(ICE_PLATFORM)
			pedestal.position = Vector2(0, 20)
			pedestal.scale = Vector2(1.15, 1.15)
		&"graveyard":
			# Mid-stone chunk cropped from the trail platform strip (not the full ledge).
			pedestal.texture = _load_texture(GRAVEYARD_PLATFORM)
			pedestal.position = Vector2(0, 22)
			pedestal.scale = Vector2(1.25, 1.2)
		&"lunar":
			pedestal.texture = _load_texture(LUNAR_PLATFORM)
			pedestal.position = Vector2(0, 16)
			pedestal.scale = Vector2(1.05, 1.05)
			_pedestal_base_modulate = Color(0.85, 0.9, 1.08, 1)
		&"desert":
			pedestal.texture = _load_texture(FOREST_PLATFORM)
			pedestal.position = Vector2(0, 20)
			pedestal.scale = Vector2(1.15, 1.15)
			# Same sandy tint used on Desert Sky trail platforms.
			_pedestal_base_modulate = Color(1.15, 0.95, 0.7, 1)
		&"forest":
			pedestal.texture = _load_texture(FOREST_PLATFORM)
			pedestal.position = Vector2(0, 20)
			pedestal.scale = Vector2(1.15, 1.15)
		_:
			# Non-trail shrines (Chef / Defense / Maze) keep the shared wood base.
			pedestal.texture = _load_texture(PEDESTAL_TEX)
			pedestal.position = Vector2(0, 18)
			pedestal.scale = Vector2(0.72, 0.72)

	if pedestal.texture == null:
		pedestal.texture = _load_texture(PEDESTAL_TEX)
		pedestal.position = Vector2(0, 18)
		pedestal.scale = Vector2(0.72, 0.72)
		_pedestal_base_modulate = Color.WHITE

	# Soften the sharp rectangular cuts on trail platform tiles.
	pedestal.texture = _round_texture_corners(pedestal.texture)
	pedestal.modulate = _pedestal_base_modulate


func _round_texture_corners(tex: Texture2D, radius_frac: float = 0.24) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w < 4 or h < 4:
		return tex
	var r := clampf(float(mini(w, h)) * radius_frac, 3.0, float(mini(w, h)) * 0.4)
	var r2 := r * r
	for y in h:
		for x in w:
			var px := img.get_pixel(x, y)
			if px.a < 0.01:
				continue
			var ax := float(x) + 0.5
			var ay := float(y) + 0.5
			var cx := ax
			var cy := ay
			var in_corner := false
			if ax < r and ay < r:
				cx = r
				cy = r
				in_corner = true
			elif ax > float(w) - r and ay < r:
				cx = float(w) - r
				cy = r
				in_corner = true
			elif ax < r and ay > float(h) - r:
				cx = r
				cy = float(h) - r
				in_corner = true
			elif ax > float(w) - r and ay > float(h) - r:
				cx = float(w) - r
				cy = float(h) - r
				in_corner = true
			if not in_corner:
				continue
			var dx := ax - cx
			var dy := ay - cy
			var d2 := dx * dx + dy * dy
			if d2 > r2:
				px.a = 0.0
				img.set_pixel(x, y, px)
			elif d2 > (r - 1.25) * (r - 1.25):
				# One-pixel soft rim so the curve doesn't look jagged at nearest filter.
				px.a *= 0.55
				img.set_pixel(x, y, px)
	return ImageTexture.create_from_image(img)


func _setup_art() -> void:
	var path := icon_path
	if path.is_empty():
		path = ICONS.get(minigame_id, ICONS[&"chase"])
	icon.texture = _load_texture(path)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_theme_pedestal()

	match minigame_id:
		&"moon_graveyard":
			icon.position = Vector2(0, -8)
			icon.scale = Vector2(0.32, 0.32)
			glow.position = Vector2(0, 14)
		&"desert_sky":
			icon.position = Vector2(0, -16)
			icon.scale = Vector2(2.4, 2.4)
			glow.position = Vector2(0, 8)
		&"lunar_void":
			icon.position = Vector2(0, -10)
			icon.scale = Vector2(0.7, 0.7)
			glow.position = Vector2(0, 6)
		&"tiger_chase":
			icon.position = Vector2(0, -12)
			icon.scale = Vector2(1.15, 1.15)
			glow.position = Vector2(0, 8)
		&"frost_fjord":
			icon.position = Vector2(0, -12)
			icon.scale = Vector2(1.05, 1.05)
			glow.position = Vector2(0, 8)
		&"fire":
			# Banana Chef — frying pan from the kitchen stations.
			icon.position = Vector2(0, -14)
			icon.scale = Vector2(1.55, 1.55)
			glow.position = Vector2(0, 8)
		_:
			icon.position = Vector2(0, -10)
			glow.position = Vector2.ZERO
			if WheelLevels.LEVELS.has(minigame_id):
				# Keep trail icons compact — never stretch wide track art as a shrine emblem.
				var tex := icon.texture
				if tex != null and tex.get_width() > tex.get_height() * 2:
					var target_w := 48.0
					var s := target_w / float(tex.get_width())
					icon.scale = Vector2(s, s)
				else:
					icon.scale = Vector2(1.05, 1.05)
			elif minigame_id == &"cart":
				icon.scale = Vector2(1.3, 1.3)
			else:
				icon.scale = Vector2(1.35, 1.35)


func _unhandled_input(event: InputEvent) -> void:
	if _player_near and event.is_action_pressed("interact"):
		interact(null)
		get_viewport().set_input_as_handled()


func interact(_by: Node) -> void:
	if WheelLevels.LEVELS.has(minigame_id):
		GameProgress.start_wheel_level(minigame_id)
	else:
		GameProgress.start_minigame(minigame_id)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near = true
		_refresh()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near = false
		_refresh()


func _refresh() -> void:
	var status := GameProgress.shrine_status(minigame_id)
	var action := "[E] Enter"
	if status == "done":
		action = "[E] Replay"
	if _player_near and not subtitle.is_empty():
		label.text = "%s\n%s\n%s" % [title, subtitle, action]
	else:
		label.text = "%s\n%s" % [title, action]
	if status == "done":
		glow.color = Color(0.45, 0.9, 0.45, 0.35 if _player_near else 0.28)
		icon.modulate = Color(0.85, 1.05, 0.85, 1)
		pedestal.modulate = _pedestal_base_modulate * Color(0.9, 1.0, 0.9, 1)
	else:
		glow.color = Color(1.0, 0.88, 0.25, 0.45 if _player_near else 0.32)
		icon.modulate = Color(1.15, 1.1, 0.9, 1)
		pedestal.modulate = _pedestal_base_modulate
