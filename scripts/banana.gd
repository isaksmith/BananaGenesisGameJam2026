extends Area2D

@export var lifetime: float = 7.0
@export var bob_amount: float = 6.0
@export var bob_speed: float = 4.0
## chase = score pickup with lifetime; hub = inventory pickup; cargo = cart cargo (no auto collect)
@export_enum("chase", "hub", "cargo") var pickup_mode: String = "chase"

var _base_y: float = 0.0
var _age: float = 0.0
var _collected: bool = false


func _ready() -> void:
	_base_y = position.y
	body_entered.connect(_on_body_entered)
	if pickup_mode == "chase":
		get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_ended)
	elif pickup_mode == "hub":
		add_to_group("interactable")
		# Keep hub bananas smaller than shrine icons/pedestals.
		var spr := get_node_or_null("Sprite") as Sprite2D
		if spr:
			spr.scale = Vector2(0.38, 0.38)
		bob_amount = 3.0
		var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
		if col and col.shape is CircleShape2D:
			(col.shape as CircleShape2D).radius = 12.0


func _process(delta: float) -> void:
	if pickup_mode == "cargo":
		return
	_age += delta
	position.y = _base_y + sin(_age * bob_speed) * bob_amount
	if pickup_mode == "chase" and lifetime - _age < 1.5:
		modulate.a = 0.4 + 0.6 * absf(sin(_age * 12.0))


func interact(_by: Node) -> void:
	if pickup_mode == "hub":
		_collect_hub()


func _on_body_entered(body: Node2D) -> void:
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
