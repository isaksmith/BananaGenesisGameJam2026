extends Node3D


func _ready() -> void:
	MeshKit3D.sun_and_env(self)
	_build_world()
	_spawn_player()
	_spawn_spawner()


func _build_world() -> void:
	MeshKit3D.ground_plane(self, Vector2(40, 40), Color(0.28, 0.48, 0.26))
	MeshKit3D.static_box(self, Vector3(32, 0.08, 32), Color(0.4, 0.58, 0.32), Vector3(0, 0.04, 0), 0)
	MeshKit3D.static_box(self, Vector3(3, 1.2, 3), Color(0.45, 0.42, 0.38), Vector3(0, 0.6, 0))
	AssetKit3D.add(self, AssetKit3D.ROCK_C, Vector3(0, 0, 0), 1.4)
	for p in [Vector3(0, 2, -18), Vector3(0, 2, 18), Vector3(-18, 2, 0), Vector3(18, 2, 0)]:
		var size := Vector3(38, 4, 1.2) if absf(p.z) > 10 else Vector3(1.2, 4, 38)
		MeshKit3D.static_box(self, size, Color(0.18, 0.38, 0.2), p)
	AssetKit3D.scatter_palms(self, [
		Vector3(-10, 0, -10), Vector3(10, 0, 10), Vector3(-10, 0, 10), Vector3(10, 0, -10),
		Vector3(0, 0, -14), Vector3(0, 0, 14),
	])
	AssetKit3D.add(self, AssetKit3D.APPLE, Vector3(-6, 0.2, 4), 2.0)
	AssetKit3D.add(self, AssetKit3D.APPLE, Vector3(7, 0.2, -5), 2.0)
	AssetKit3D.add(self, AssetKit3D.FLOWER, Vector3(3, 0, 6), 1.4)


func _spawn_player() -> void:
	var packed: PackedScene = load("res://scenes_3d/player/monkey_3d.tscn")
	var monkey := packed.instantiate()
	monkey.position = Vector3(0, 1.2, 6)
	add_child(monkey)


func _spawn_spawner() -> void:
	var spawner := Node.new()
	spawner.set_script(load("res://scripts_3d/banana_spawner_3d.gd"))
	add_child(spawner)
