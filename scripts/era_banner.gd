extends Control

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var anim_player: AnimationPlayer = null

var _hide_tween: Tween


func _ready() -> void:
	modulate.a = 0.0
	visible = true
	GameProgress.era_banner_requested.connect(show_banner)


func show_banner(title: String, subtitle: String) -> void:
	title_label.text = title
	subtitle_label.text = subtitle
	if _hide_tween:
		_hide_tween.kill()
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_hide_tween = create_tween()
	_hide_tween.tween_interval(2.4)
	_hide_tween.tween_property(self, "modulate:a", 0.0, 0.4)
