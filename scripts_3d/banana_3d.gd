extends Area3D

@export var lifetime: float = 7.0
@export_enum("chase", "hub", "cargo") var pickup_mode: String = "chase"

var _base_y: float = 0.0
var _age: float = 0.0
var _collected: bool = false
var _visual: Node3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_base_y = position.y
	body_entered.connect(_on_body_entered)
	_visual = AssetKit3D.make(AssetKit3D.BANANA, 2.4, 90.0)
	add_child(_visual)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.55
	col.shape = shape
	add_child(col)
	if pickup_mode == "chase":
		get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_ended)
	elif pickup_mode == "hub":
		add_to_group("interactable")


func _process(delta: float) -> void:
	if pickup_mode == "cargo":
		return
	_age += delta
	position.y = _base_y + sin(_age * 4.0) * 0.12
	if _visual:
		_visual.rotation_degrees.y += 40.0 * delta


func interact(_by: Node) -> void:
	if pickup_mode == "hub":
		_collect_hub()


func _on_body_entered(body: Node3D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	match pickup_mode:
		"chase":
			if GameState.is_playing:
				GameState.add_score(1)
				_collected = true
				queue_free()
		"hub":
			_collect_hub()


func _collect_hub() -> void:
	if _collected:
		return
	_collected = true
	Inventory.add_item(&"banana", 1)
	Inventory.add_item(&"banana_peel", 1)
	GameProgress.juice_shake.emit(0.08)
	queue_free()


func _on_lifetime_ended() -> void:
	if not _collected:
		queue_free()
