extends Node2D

@onready var campfire: Node2D = %Campfire
@onready var wheel_prop: Node2D = %WheelProp
@onready var cart_prop: Node2D = %CartProp
@onready var bg_video: VideoStreamPlayer = %BgVideo
@onready var bg_video_sprite: Sprite2D = %BgVideoSprite


func _ready() -> void:
	GameProgress.progress_changed.connect(_refresh_props)
	_refresh_props()
	_start_bg_video()
	# Persistent autoload music — keeps playing into the wheel-draw studio.
	AudioSettings.play_hub_music()


func _process(_delta: float) -> void:
	# Mirror decoded frames onto a world Sprite2D so Node2D shrines layer correctly.
	if bg_video == null or bg_video_sprite == null:
		return
	if not bg_video.is_playing():
		bg_video.play()
	var tex := bg_video.get_video_texture()
	if tex == null:
		return
	bg_video_sprite.texture = tex
	bg_video_sprite.visible = true
	var bg_art := get_node_or_null("BgArt") as Sprite2D
	if bg_art:
		bg_art.visible = false
	var size := tex.get_size()
	if size.x > 0.0 and size.y > 0.0:
		bg_video_sprite.scale = Vector2(1280.0 / size.x, 720.0 / size.y)


func _start_bg_video() -> void:
	if bg_video == null:
		push_warning("Hub bg video player missing")
		return
	var bg_art := get_node_or_null("BgArt") as Sprite2D
	if bg_video.stream == null:
		bg_video.stream = load("res://assets/video/pixel_jungle_hub.ogv") as VideoStream
	if bg_video.stream == null:
		push_error("Failed to load hub video: res://assets/video/pixel_jungle_hub.ogv")
		# Fall back to static jungle art so the hub isn't blank.
		if bg_art:
			bg_art.visible = true
		return
	bg_video.volume_db = -80.0
	bg_video.loop = true
	bg_video.speed_scale = 1.0
	bg_video.play()
	# Show static art until the first decoded frame arrives.
	if bg_art:
		bg_art.visible = true
	if bg_video_sprite:
		bg_video_sprite.visible = false


func _refresh_props() -> void:
	if campfire:
		campfire.visible = GameProgress.has_fire
	# Never show the old center-hub wheel prop — trails use shrines, not a camp wheel.
	if wheel_prop:
		wheel_prop.visible = false
	if cart_prop:
		cart_prop.visible = GameProgress.has_cart
