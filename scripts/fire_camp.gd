extends Node2D

@export var rub_rate: float = 0.35
@export var decay_rate: float = 0.12

var _progress: float = 0.0
var _done: bool = false

@onready var bar: ProgressBar = %RubBar
@onready var hint: Label = %HintLabel
@onready var flame: CanvasItem = %Flame


func _ready() -> void:
	add_to_group("fire_camp")
	flame.visible = false
	bar.value = 0.0
	hint.text = "Hold E to rub sticks. Tribe monkeys will 'help'.\nEsc/Q exits to camp."
	_spawn_helpers()


func _process(delta: float) -> void:
	if _done:
		return
	var rubbing := Input.is_action_pressed("interact")
	if rubbing:
		_progress = minf(_progress + rub_rate * delta, 1.0)
	else:
		_progress = maxf(_progress - decay_rate * delta, 0.0)
	bar.value = _progress * 100.0
	if _progress >= 1.0:
		_succeed()


func tribe_interfere(amount: float) -> void:
	if _done:
		return
	_progress = maxf(_progress - amount, 0.0)
	bar.value = _progress * 100.0
	hint.text = "Stop helping!! Hold E anyway."


func _spawn_helpers() -> void:
	var tribe_scene: PackedScene = load("res://scenes/enemies/tribe_helper.tscn")
	var a := tribe_scene.instantiate()
	a.position = Vector2(480, 500)
	a.label_text = "I help!"
	a.set("mood", 3) # HELP_FIRE
	add_child(a)
	var b := tribe_scene.instantiate()
	b.position = Vector2(800, 520)
	b.label_text = "Fire friend"
	b.set("mood", 3)
	add_child(b)


func _succeed() -> void:
	_done = true
	flame.visible = true
	hint.text = "Fire! Despite the help."
	_spawn_sparks()
	GameProgress.juice_shake.emit(0.5)
	await get_tree().create_timer(1.0).timeout
	GameProgress.complete_minigame(GameProgress.MODE_FIRE)


func _spawn_sparks() -> void:
	var sparks := CPUParticles2D.new()
	sparks.position = flame.position
	sparks.one_shot = true
	sparks.explosiveness = 0.85
	sparks.amount = 24
	sparks.lifetime = 0.6
	sparks.direction = Vector2(0, -1)
	sparks.spread = 180.0
	sparks.initial_velocity_min = 60.0
	sparks.initial_velocity_max = 160.0
	sparks.gravity = Vector2(0, 180)
	sparks.color = Color(1.0, 0.6, 0.15, 1)
	add_child(sparks)
	sparks.emitting = true
