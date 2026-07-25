extends Node3D


func _ready() -> void:
	MeshKit3D.sun_and_env(self)
	_build_world()
	_spawn_shrines()
	_spawn_pickups()
	_spawn_player()
	_spawn_props()


func _build_world() -> void:
	MeshKit3D.ground_plane(self, Vector2(60, 60), Color(0.28, 0.48, 0.26))
	MeshKit3D.static_box(self, Vector3(40, 0.08, 40), Color(0.38, 0.55, 0.3), Vector3(0, 0.04, 0), 0)

	for p in [Vector3(0, 2, -30), Vector3(0, 2, 30), Vector3(-30, 2, 0), Vector3(30, 2, 0)]:
		var size := Vector3(62, 4, 2) if absf(p.z) > 20 else Vector3(2, 4, 62)
		MeshKit3D.static_box(self, size, Color(0.15, 0.35, 0.18), p)

	AssetKit3D.scatter_palms(self, [
		Vector3(-18, 0, -12), Vector3(18, 0, -12), Vector3(-18, 0, 14), Vector3(18, 0, 14),
		Vector3(0, 0, -22), Vector3(-22, 0, 0), Vector3(22, 0, 2), Vector3(-8, 0, 18),
	])
	AssetKit3D.add(self, AssetKit3D.ROCK_A, Vector3(-6, 0, -4), 1.2, 20)
	AssetKit3D.add(self, AssetKit3D.ROCK_B, Vector3(7, 0, 5), 1.0, -15)
	AssetKit3D.add(self, AssetKit3D.FOREST_ROCKS, Vector3(12, 0, -6), 1.3, 50)
	AssetKit3D.add(self, AssetKit3D.FLOWER, Vector3(-3, 0, 3), 1.5)
	AssetKit3D.add(self, AssetKit3D.FLOWER, Vector3(4, 0, -2), 1.3, 80)
	AssetKit3D.add(self, AssetKit3D.LOG_STACK, Vector3(-10, 0, 2), 1.2, 35)


func _spawn_shrines() -> void:
	var configs := [
		{"id": &"fire", "title": "Fire", "pos": Vector3(-14, 0, -10), "color": Color(1, 0.55, 0.2)},
		{"id": &"wheel", "title": "Square Descent", "pos": Vector3(0, 0, -16), "color": Color(0.95, 0.8, 0.25)},
		{"id": &"cart", "title": "Cart", "pos": Vector3(14, 0, -10), "color": Color(0.45, 0.8, 0.95)},
		{"id": &"chase", "title": "Banana Defense", "pos": Vector3(0, 0, 14), "color": Color(1, 0.92, 0.3)},
	]
	var shrine_script: Script = load("res://scripts_3d/shrine_3d.gd")
	for cfg in configs:
		var shrine := Area3D.new()
		shrine.set_script(shrine_script)
		shrine.position = cfg["pos"]
		shrine.set("minigame_id", cfg["id"])
		shrine.set("title", cfg["title"])
		shrine.set("accent", cfg["color"])
		add_child(shrine)


func _spawn_pickups() -> void:
	var pickup_script: Script = load("res://scripts_3d/world_pickup_3d.gd")
	var banana_script: Script = load("res://scripts_3d/banana_3d.gd")
	for pos in [Vector3(-10, 0.2, 6), Vector3(-8, 0.2, 8), Vector3(-12, 0.2, 9)]:
		var stick := Area3D.new()
		stick.set_script(pickup_script)
		stick.position = pos
		stick.set("item_id", &"stick")
		add_child(stick)
	for pos in [Vector3(10, 0.2, 6), Vector3(8, 0.2, 9), Vector3(12, 0.2, 8)]:
		var rock := Area3D.new()
		rock.set_script(pickup_script)
		rock.position = pos
		rock.set("item_id", &"rock")
		add_child(rock)
	for pos in [Vector3(-4, 0.2, 0), Vector3(4, 0.2, 2)]:
		var banana := Area3D.new()
		banana.set_script(banana_script)
		banana.position = pos
		banana.set("pickup_mode", "hub")
		banana.set("lifetime", 9999.0)
		add_child(banana)


func _spawn_player() -> void:
	var packed: PackedScene = load("res://scenes_3d/player/monkey_3d.tscn")
	var monkey := packed.instantiate()
	monkey.position = Vector3(0, 1.2, 4)
	add_child(monkey)


func _spawn_props() -> void:
	GameProgress.progress_changed.connect(_refresh_props)
	_refresh_props()


func _refresh_props() -> void:
	_clear_group("hub_prop_3d")
	if GameProgress.has_fire:
		var fire := AssetKit3D.make(AssetKit3D.CAMPFIRE, 1.4)
		fire.position = Vector3(-3, 0, 2)
		fire.add_to_group("hub_prop_3d")
		add_child(fire)
	if GameProgress.has_wheel:
		var wheel := AssetKit3D.make(AssetKit3D.CRATE, 1.3, 25)
		wheel.position = Vector3(0, 0, 2)
		wheel.add_to_group("hub_prop_3d")
		add_child(wheel)
	if GameProgress.has_cart:
		var cart := AssetKit3D.make(AssetKit3D.BARREL, 1.5)
		cart.position = Vector3(3, 0, 2)
		cart.add_to_group("hub_prop_3d")
		add_child(cart)


func _clear_group(group_name: String) -> void:
	for n in get_tree().get_nodes_in_group(group_name):
		n.queue_free()
