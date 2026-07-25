extends Area3D

@export var minigame_id: StringName = &"fire"
@export var title: String = "Shrine"
@export var accent: Color = Color(1.0, 0.85, 0.2)

var _player_near: bool = false
var _label: Label3D
var _icon_root: Node3D


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 2
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	GameProgress.progress_changed.connect(_refresh)
	_build_visuals()
	_refresh()


func _build_visuals() -> void:
	AssetKit3D.add(self, AssetKit3D.STONE_TALL, Vector3(0, 0, 0), 1.4)
	AssetKit3D.add(self, AssetKit3D.ROCK_SMALL, Vector3(-0.9, 0, 0.6), 1.0, 40.0)
	AssetKit3D.add(self, AssetKit3D.ROCK_SMALL, Vector3(0.9, 0, 0.5), 0.9, -25.0)

	_icon_root = Node3D.new()
	_icon_root.position = Vector3(0, 2.2, 0)
	add_child(_icon_root)
	var icon_path := AssetKit3D.BANANA
	var icon_scale := 2.2
	match minigame_id:
		&"fire":
			icon_path = AssetKit3D.CAMPFIRE
			icon_scale = 1.3
		&"wheel":
			icon_path = AssetKit3D.CRATE
			icon_scale = 1.4
		&"cart":
			icon_path = AssetKit3D.BARREL
			icon_scale = 1.5
		&"chase":
			icon_path = AssetKit3D.BANANA
			icon_scale = 2.8
	var icon := AssetKit3D.make(icon_path, icon_scale)
	_icon_root.add_child(icon)

	_label = Label3D.new()
	_label.position = Vector3(0, 3.4, 0)
	_label.font_size = 48
	_label.outline_size = 12
	_label.modulate = Color(1, 0.98, 0.9)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	col.shape = sphere
	col.position = Vector3(0, 1.0, 0)
	add_child(col)


func interact(_by: Node) -> void:
	# All games unlocked — replay anytime.
	GameProgress.start_minigame(minigame_id)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near = true
		_refresh()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near = false
		_refresh()


func _refresh() -> void:
	var status := GameProgress.shrine_status(minigame_id)
	if status == "done":
		_label.text = "%s\n[E] Replay" % title
		_label.modulate = Color(0.55, 0.95, 0.55)
		_icon_root.scale = Vector3.ONE * (1.1 if _player_near else 0.95)
	else:
		_label.text = "%s\n[E] Enter" % title
		_label.modulate = accent
		_icon_root.scale = Vector3.ONE * (1.15 if _player_near else 1.0)
