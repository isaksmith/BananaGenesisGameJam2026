extends Node2D

@export var banana_scene: PackedScene
@export var spawn_interval: float = 1.1
@export var max_bananas: int = 8
@export var spawn_margin: float = 48.0

var _timer: float = 0.0
var _arena_size: Vector2 = Vector2(1280, 720)


func _ready() -> void:
	GameState.round_started.connect(_on_round_started)
	if GameState.is_playing:
		_on_round_started()


func _process(delta: float) -> void:
	if not GameState.is_playing:
		return
	_timer += delta
	if _timer >= spawn_interval and get_child_count() < max_bananas:
		_timer = 0.0
		_spawn_banana()


func _on_round_started() -> void:
	for child in get_children():
		child.queue_free()
	_timer = 0.0
	# Seed a few bananas immediately
	for i in 3:
		_spawn_banana()


func _spawn_banana() -> void:
	if banana_scene == null:
		push_warning("BananaSpawner: banana_scene is not set")
		return
	var banana := banana_scene.instantiate() as Node2D
	banana.position = Vector2(
		randf_range(spawn_margin, _arena_size.x - spawn_margin),
		randf_range(spawn_margin, _arena_size.y - spawn_margin)
	)
	add_child(banana)
