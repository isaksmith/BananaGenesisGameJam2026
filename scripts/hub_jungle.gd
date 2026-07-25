extends Node2D

@onready var campfire: Node2D = %Campfire
@onready var wheel_prop: Node2D = %WheelProp
@onready var cart_prop: Node2D = %CartProp


func _ready() -> void:
	GameProgress.progress_changed.connect(_refresh_props)
	_refresh_props()


func _refresh_props() -> void:
	if campfire:
		campfire.visible = GameProgress.has_fire
	if wheel_prop:
		wheel_prop.visible = GameProgress.has_wheel or not GameProgress.cleared_wheel_levels.is_empty()
	if cart_prop:
		cart_prop.visible = GameProgress.has_cart
