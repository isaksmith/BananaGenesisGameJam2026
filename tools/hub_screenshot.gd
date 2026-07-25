extends SceneTree


func _initialize() -> void:
	call_deferred("_shot")


func _shot() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var packed := load("res://scenes/levels/hub_jungle.tscn") as PackedScene
	var hub := packed.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://hub_view.png")
	img.save_png("/tmp/hub_view.png")
	print("HUB_SHOT_OK")
	quit()
