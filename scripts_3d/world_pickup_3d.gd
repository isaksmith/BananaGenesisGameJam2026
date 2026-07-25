extends Area3D

@export var item_id: StringName = &"stick"

var _collected: bool = false


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 2
	collision_mask = 1
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	_build()


func _build() -> void:
	match item_id:
		&"rock":
			AssetKit3D.add(self, AssetKit3D.ROCK_SMALL, Vector3.ZERO, 1.1)
		_:
			AssetKit3D.add(self, AssetKit3D.STICK, Vector3(0, 0.15, 0), 2.2, 40.0)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	col.shape = shape
	add_child(col)
	var label := Label3D.new()
	label.text = String(item_id).capitalize()
	label.position = Vector3(0, 1.0, 0)
	label.font_size = 28
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func interact(_by: Node) -> void:
	_collect()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_collect()


func _collect() -> void:
	if _collected:
		return
	_collected = true
	Inventory.add_item(item_id, 1)
	GameProgress.juice_shake.emit(0.08)
	queue_free()
