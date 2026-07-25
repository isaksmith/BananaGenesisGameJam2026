extends Area2D

const PEDESTAL_TEX := "res://assets/sprites/shrine_base.png"
const GRAVEYARD_PEDESTAL := "res://assets/sprites/moon_graveyard/shrine_pedestal.png"

const ICONS := {
	&"fire": "res://assets/sprites/flame.png",
	&"wheel": "res://assets/sprites/icon_square_wheel.png",
	&"cart": "res://assets/sprites/banana_cart.png",
	&"chase": "res://assets/sprites/bananas_pile.png",
	&"moon_graveyard": "res://assets/sprites/moon_graveyard/Salt.png",
	&"desert_sky": "res://assets/sprites/parallax_desert/shrine_emblem.png",
	&"lunar_void": "res://assets/sprites/parallax_moon/shrine_emblem.png",
	&"tiger_chase": "res://assets/sprites/tiger/shrine_emblem.png",
}

@export var minigame_id: StringName = &"fire"
@export var title: String = "Shrine"
@export var subtitle: String = ""
@export var icon_path: String = ""

var _player_near: bool = false

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


func _setup_art() -> void:
	var path := icon_path
	if path.is_empty():
		path = ICONS.get(minigame_id, ICONS[&"chase"])
	if minigame_id == &"tiger_chase":
		# Source images may change while Godot is running; bypass its stale import cache.
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		icon.texture = ImageTexture.create_from_image(image) if image != null else load(path) as Texture2D
	else:
		icon.texture = load(path) as Texture2D
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pedestal.visible = true
	pedestal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	match minigame_id:
		&"moon_graveyard":
			# Stone slab under the hooded statue; keep statue compact.
			var ped := load(GRAVEYARD_PEDESTAL) as Texture2D
			pedestal.texture = ped if ped != null else load(PEDESTAL_TEX) as Texture2D
			pedestal.position = Vector2(0, 28)
			pedestal.scale = Vector2(0.7, 0.9) if ped != null else Vector2(0.72, 0.72)
			icon.position = Vector2(0, -6)
			icon.scale = Vector2(0.32, 0.32)
			glow.position = Vector2(0, 18)
		&"desert_sky":
			pedestal.texture = load(PEDESTAL_TEX) as Texture2D
			pedestal.position = Vector2(0, 18)
			pedestal.scale = Vector2(0.72, 0.72)
			icon.position = Vector2(0, -14)
			icon.scale = Vector2(0.85, 0.85)
			glow.position = Vector2(0, 8)
		&"lunar_void":
			# Center globe above the shared pedestal.
			pedestal.texture = load(PEDESTAL_TEX) as Texture2D
			pedestal.position = Vector2(0, 18)
			pedestal.scale = Vector2(0.72, 0.72)
			icon.position = Vector2(0, -16)
			icon.scale = Vector2(0.9, 0.9)
			glow.position = Vector2(0, 8)
		&"tiger_chase":
			pedestal.texture = load(PEDESTAL_TEX) as Texture2D
			pedestal.position = Vector2(0, 18)
			pedestal.scale = Vector2(0.72, 0.72)
			icon.position = Vector2(0, -12)
			icon.scale = Vector2(1.15, 1.15)
			glow.position = Vector2(0, 8)
		_:
			pedestal.texture = load(PEDESTAL_TEX) as Texture2D
			pedestal.position = Vector2(0, 18)
			pedestal.scale = Vector2(0.72, 0.72)
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
				icon.scale = Vector2(0.45, 0.45)
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
		pedestal.modulate = Color(0.9, 1.0, 0.9, 1)
	else:
		glow.color = Color(1.0, 0.88, 0.25, 0.45 if _player_near else 0.32)
		icon.modulate = Color(1.15, 1.1, 0.9, 1)
		pedestal.modulate = Color(1, 1, 1, 1)
