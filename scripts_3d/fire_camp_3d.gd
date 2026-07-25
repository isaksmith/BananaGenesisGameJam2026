extends Node3D

@export var rub_rate: float = 0.35
@export var decay_rate: float = 0.12

var _progress: float = 0.0
var _done: bool = false
var _flame_root: Node3D
var _hint: Label
var _bar: ProgressBar


func _ready() -> void:
	add_to_group("fire_camp")
	MeshKit3D.sun_and_env(self, 0.55, Color(0.25, 0.2, 0.18))
	_build_world()
	_build_ui()
	_spawn_helpers()


func _build_world() -> void:
	MeshKit3D.ground_plane(self, Vector2(40, 40), Color(0.18, 0.16, 0.14))
	AssetKit3D.add(self, AssetKit3D.CAMPFIRE_STONES, Vector3.ZERO, 1.5)
	AssetKit3D.add(self, AssetKit3D.CAMPFIRE, Vector3.ZERO, 1.5)
	AssetKit3D.add(self, AssetKit3D.LOG_STACK, Vector3(-2.5, 0, 1.2), 1.2, 20)
	AssetKit3D.add(self, AssetKit3D.STICK, Vector3(-0.4, 0.5, 0.2), 2.5, 35)
	AssetKit3D.add(self, AssetKit3D.STICK, Vector3(0.4, 0.5, -0.1), 2.5, -40)

	_flame_root = Node3D.new()
	_flame_root.position = Vector3(0, 0.9, 0)
	_flame_root.visible = false
	add_child(_flame_root)
	_flame_root.add_child(MeshKit3D.sphere(0.45, Color(1, 0.45, 0.1), Vector3.ZERO, 3.0))
	_flame_root.add_child(MeshKit3D.sphere(0.25, Color(1, 0.85, 0.3), Vector3(0, 0.35, 0), 2.5))

	AssetKit3D.scatter_palms(self, [
		Vector3(-8, 0, -6), Vector3(8, 0, -6), Vector3(-8, 0, 6), Vector3(8, 0, 6),
	])

	var cam := Camera3D.new()
	cam.position = Vector3(0, 5, 10)
	cam.look_at(Vector3(0, 1, 0))
	add_child(cam)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_top = 36
	_hint.offset_left = -320
	_hint.offset_right = 320
	_hint.offset_bottom = 110
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.text = "Hold E to rub sticks. Tribe monkeys will 'help'.\nEsc/Q exits to camp."
	layer.add_child(_hint)
	_bar = ProgressBar.new()
	_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bar.offset_top = 120
	_bar.offset_left = -200
	_bar.offset_right = 200
	_bar.offset_bottom = 148
	_bar.max_value = 100
	_bar.show_percentage = false
	layer.add_child(_bar)


func _process(delta: float) -> void:
	if _done:
		return
	if Input.is_action_pressed("interact"):
		_progress = minf(_progress + rub_rate * delta, 1.0)
	else:
		_progress = maxf(_progress - decay_rate * delta, 0.0)
	_bar.value = _progress * 100.0
	if _progress >= 1.0:
		_succeed()


func tribe_interfere(amount: float) -> void:
	if _done:
		return
	_progress = maxf(_progress - amount, 0.0)
	_bar.value = _progress * 100.0
	_hint.text = "Stop helping!! Hold E anyway."


func _spawn_helpers() -> void:
	var script: Script = load("res://scripts_3d/tribe_helper_3d.gd")
	for pos in [Vector3(-4, 0, 3), Vector3(4, 0, 3)]:
		var helper := CharacterBody3D.new()
		helper.set_script(script)
		helper.position = pos
		helper.set("label_text", "I help!")
		helper.set("mood", 3)
		add_child(helper)


func _succeed() -> void:
	_done = true
	_flame_root.visible = true
	_hint.text = "Fire! Despite the help."
	GameProgress.juice_shake.emit(0.5)
	await get_tree().create_timer(1.0).timeout
	GameProgress.complete_minigame(GameProgress.MODE_FIRE)
