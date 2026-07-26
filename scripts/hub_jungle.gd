extends Node2D

const HUB_VIDEO := "res://assets/video/pixel_jungle_hub.ogv"

@onready var campfire: Node2D = %Campfire
@onready var wheel_prop: Node2D = %WheelProp
@onready var cart_prop: Node2D = %CartProp
@onready var bg_video_sprite: Sprite2D = %BgVideoSprite

var _bg_video: VideoStreamPlayer


func _ready() -> void:
	GameProgress.progress_changed.connect(_refresh_props)
	_refresh_props()
	_start_bg_video()
	# Persistent autoload music — keeps playing into the wheel-draw studio.
	AudioSettings.play_hub_music()


func _process(_delta: float) -> void:
	# Mirror decoded frames onto a world Sprite2D so Node2D shrines layer correctly.
	if _bg_video == null or bg_video_sprite == null:
		return
	if not _bg_video.is_playing():
		_bg_video.play()
	var tex := _bg_video.get_video_texture()
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


func _is_web() -> bool:
	return OS.has_feature("web") or OS.get_name() == "Web"


func _start_bg_video() -> void:
	var bg_art := get_node_or_null("BgArt") as Sprite2D
	# Keep the video-matching still visible on web (and as desktop fallback).
	if bg_art:
		bg_art.visible = true
	if bg_video_sprite:
		bg_video_sprite.visible = false

	# Theora VideoStreamPlayer commonly freezes/crashes itch.io web builds.
	if _is_web():
		set_process(false)
		return

	var host := CanvasLayer.new()
	host.name = "BgVideoHost"
	host.layer = -100
	add_child(host)
	_bg_video = VideoStreamPlayer.new()
	_bg_video.name = "BgVideo"
	_bg_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_video.expand = true
	_bg_video.loop = true
	_bg_video.volume_db = -80.0
	_bg_video.stream = load(HUB_VIDEO) as VideoStream
	host.add_child(_bg_video)
	if _bg_video.stream == null:
		push_error("Failed to load hub video: %s" % HUB_VIDEO)
		set_process(false)
		return
	_bg_video.play()


func _refresh_props() -> void:
	if campfire:
		campfire.visible = GameProgress.has_fire
	# Never show the old center-hub wheel/cart props — progress lives on shrines now.
	if wheel_prop:
		wheel_prop.visible = false
	if cart_prop:
		cart_prop.visible = false
