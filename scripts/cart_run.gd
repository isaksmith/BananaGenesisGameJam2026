extends Node2D

## Jungle banana logistics: load at the depot, follow the dirt road, stock both village huts.

@export var cart_speed: float = 240.0
@export var bananas_needed_a: int = 3
@export var bananas_needed_b: int = 3
@export var time_limit: float = 110.0

const TEX_SKY := "res://assets/sprites/jungle_parallax/jungle_4_sky.png"
const TEX_FAR := "res://assets/sprites/jungle_parallax/jungle_3_far.png"
const TEX_MID := "res://assets/sprites/jungle_parallax/jungle_2_mid.png"
const TEX_NEAR := "res://assets/sprites/jungle_parallax/jungle_1_near.png"
const TEX_TRACK := "res://assets/sprites/track_dirt.png"
const TEX_ROCKS := [
	"res://assets/sprites/rock_wide.png",
	"res://assets/sprites/rock_tall.png",
	"res://assets/sprites/rock_medium.png",
	"res://assets/sprites/ledge_rock.png",
	"res://assets/sprites/obstacle_rock.png",
]
const TEX_TREE := [
	"res://assets/sprites/forest_tree_0.png",
	"res://assets/sprites/forest_tree_1.png",
	"res://assets/sprites/forest_tree_2.png",
	"res://assets/sprites/forest_tree.png",
]

var _delivered_a: int = 0
var _delivered_b: int = 0
var _time_left: float = 110.0
var _done: bool = false
var _cargo: Array[Node2D] = []
var _world: Node2D

@onready var cart: CharacterBody2D = %Cart
@onready var cargo_area: Area2D = %CargoArea
@onready var dropoff_a: Area2D = %DropoffZone
@onready var dropoff_b: Area2D = %DropoffZoneB
@onready var hint: Label = %HintLabel
@onready var status: Label = %StatusLabel
@onready var pile: Node2D = %BananaPile
@onready var hazards: Node2D = %Hazards


func _ready() -> void:
	_time_left = time_limit
	hint.text = "Load bananas at the depot · follow the dirt road · stock BOTH huts\nPeels on the road make you skid · Esc/Q exits"
	dropoff_a.body_entered.connect(_on_dropoff_a)
	dropoff_b.body_entered.connect(_on_dropoff_b)
	_build_world()
	_spawn_pile()
	_spawn_route_hazards()
	_update_status()


func _physics_process(delta: float) -> void:
	if _done:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_fail_and_retry()
		return

	if cart.has_method("tick_status"):
		cart.tick_status(delta)

	var speed := cart_speed
	if cart.get("boost_mult") != null:
		speed *= float(cart.boost_mult)

	if cart.has_method("is_slipping") and cart.is_slipping():
		# Weak steering while skidding — funny, not a freeze.
		var steer := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		cart.velocity = cart.velocity.lerp(steer * speed * 0.35, 0.05)
		if cart.velocity.length() > 1.0 and cart.velocity.length() < 100.0:
			cart.velocity = cart.velocity.normalized() * 100.0
		cart.move_and_slide()
	else:
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		cart.velocity = direction * speed
		var prev_speed := cart.velocity.length()
		cart.move_and_slide()
		# Only spill on solid bumps when moving fast — not every wall tap.
		if cart.get_slide_collision_count() > 0 and _cargo.size() > 0 and prev_speed > 160.0:
			var col := cart.get_slide_collision(0)
			if col and col.get_normal().length() > 0.0:
				_spill_one()
	_update_status()


func tribe_steal_cargo() -> bool:
	if _cargo.is_empty():
		return false
	var banana: Node2D = _cargo.pop_back()
	var drop_at := cart.global_position + Vector2(randf_range(-24, 24), randf_range(-16, 16))
	if is_instance_valid(banana):
		# Drop back near the cart as a recoverable banana + leave a peel.
		var world_parent := pile
		cargo_area.remove_child(banana)
		world_parent.add_child(banana)
		banana.global_position = drop_at
	_spawn_peel_at(drop_at + Vector2(18, 8))
	GameProgress.juice_shake.emit(0.18)
	hint.text = "Tribe dropped your banana — and left a peel. Rude."
	_update_status()
	return true


func _build_world() -> void:
	if _world and is_instance_valid(_world):
		_world.queue_free()
	_world = Node2D.new()
	_world.name = "WorldArt"
	add_child(_world)
	move_child(_world, 0)

	_add_parallax_layer(TEX_SKY, -20, Color(1, 1, 1, 1), 1.05)
	_add_parallax_layer(TEX_FAR, -19, Color(0.92, 0.95, 1.0, 0.95), 1.08)
	_add_parallax_layer(TEX_MID, -18, Color(1, 1, 1, 0.9), 1.12)
	_add_parallax_layer(TEX_NEAR, -17, Color(1, 1, 1, 0.55), 1.2)

	# Soft ground wash so the arena reads as a clearing.
	var ground := Polygon2D.new()
	ground.z_index = -16
	ground.color = Color(0.28, 0.42, 0.22, 0.72)
	ground.polygon = PackedVector2Array([
		Vector2(0, 120), Vector2(1280, 120), Vector2(1280, 720), Vector2(0, 720)
	])
	_world.add_child(ground)

	# Dirt road: depot → fork → Hut A (north) / Hut B (south).
	_paint_road_segment(Vector2(80, 360), Vector2(720, 360), 78.0)   # main
	_paint_road_segment(Vector2(720, 360), Vector2(1080, 190), 70.0)  # to A
	_paint_road_segment(Vector2(720, 360), Vector2(1080, 540), 70.0)  # to B
	_paint_road_segment(Vector2(140, 360), Vector2(140, 500), 64.0)   # depot spur
	_paint_road_pad(Vector2(160, 360), 90.0, Color(0.55, 0.4, 0.22, 0.9)) # depot
	_paint_road_pad(Vector2(1100, 190), 86.0, Color(0.5, 0.38, 0.2, 0.85))
	_paint_road_pad(Vector2(1100, 540), 86.0, Color(0.5, 0.38, 0.2, 0.85))

	# Roadside rocks — force the cart to stay near the road instead of cutting corners.
	var rock_spots := [
		{"pos": Vector2(420, 250), "tex": 0, "s": 1.35},
		{"pos": Vector2(420, 470), "tex": 1, "s": 1.15},
		{"pos": Vector2(620, 230), "tex": 3, "s": 1.2},
		{"pos": Vector2(620, 500), "tex": 2, "s": 1.25},
		{"pos": Vector2(860, 300), "tex": 4, "s": 1.3},
		{"pos": Vector2(860, 430), "tex": 0, "s": 1.2},
		{"pos": Vector2(980, 360), "tex": 1, "s": 1.1}, # fork island
		{"pos": Vector2(300, 200), "tex": 3, "s": 1.0},
		{"pos": Vector2(300, 540), "tex": 2, "s": 1.05},
	]
	for spot in rock_spots:
		_add_rock_obstacle(spot["pos"], int(spot["tex"]), float(spot["s"]))

	# Decorative trees framing the clearing (no collision).
	for t in [
		Vector2(60, 140), Vector2(220, 90), Vector2(500, 70), Vector2(780, 80),
		Vector2(1000, 70), Vector2(1220, 130), Vector2(60, 620), Vector2(250, 660),
		Vector2(900, 660), Vector2(1200, 620),
	]:
		_add_tree_decor(t)

	# Depot / hut labels already in scene — reposition key nodes.
	pile.position = Vector2(160, 340)
	dropoff_a.position = Vector2(1100, 190)
	dropoff_b.position = Vector2(1100, 540)
	cart.global_position = Vector2(200, 480)


func _add_parallax_layer(path: String, z: int, modulate: Color, cover: float) -> void:
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.z_index = z
	spr.texture = tex
	spr.centered = true
	spr.position = Vector2(640, 360)
	spr.modulate = modulate
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sx := (1280.0 * cover) / maxf(float(tex.get_width()), 1.0)
	var sy := (720.0 * cover) / maxf(float(tex.get_height()), 1.0)
	var s := maxf(sx, sy)
	spr.scale = Vector2(s, s)
	_world.add_child(spr)


func _paint_road_segment(a: Vector2, b: Vector2, width: float) -> void:
	var dir := (b - a)
	var len := dir.length()
	if len < 1.0:
		return
	var n := dir.normalized()
	var perp := Vector2(-n.y, n.x) * (width * 0.5)
	var poly := Polygon2D.new()
	poly.z_index = -14
	poly.color = Color(0.45, 0.32, 0.18, 0.95)
	poly.polygon = PackedVector2Array([a - perp, a + perp, b + perp, b - perp])
	_world.add_child(poly)

	# Dirt track tiles along the segment.
	var tex := load(TEX_TRACK) as Texture2D
	if tex == null:
		return
	var step := 90.0
	var count := maxi(1, int(ceil(len / step)))
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var p := a.lerp(b, t)
		var spr := Sprite2D.new()
		spr.z_index = -13
		spr.texture = tex
		spr.centered = true
		spr.position = p
		spr.rotation = n.angle()
		spr.modulate = Color(0.95, 0.85, 0.7, 0.85)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var sc := width / maxf(float(tex.get_height()), 1.0)
		spr.scale = Vector2(sc * 0.55, sc)
		_world.add_child(spr)


func _paint_road_pad(center: Vector2, radius: float, color: Color) -> void:
	var poly := Polygon2D.new()
	poly.z_index = -14
	poly.color = color
	var pts := PackedVector2Array()
	for i in 16:
		var ang := TAU * float(i) / 16.0
		pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
	poly.polygon = pts
	_world.add_child(poly)


func _add_rock_obstacle(pos: Vector2, tex_i: int, scale: float) -> void:
	var path := str(TEX_ROCKS[clampi(tex_i, 0, TEX_ROCKS.size() - 1)])
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 4
	body.collision_mask = 0
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.scale = Vector2(scale, scale)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(spr)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(float(tex.get_width()) * scale * 0.7, float(tex.get_height()) * scale * 0.55)
	col.shape = shape
	col.position = Vector2(0, float(tex.get_height()) * scale * 0.08)
	body.add_child(col)
	_world.add_child(body)


func _add_tree_decor(pos: Vector2) -> void:
	var path := str(TEX_TREE[randi() % TEX_TREE.size()])
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.z_index = -10
	spr.texture = tex
	spr.position = pos
	spr.scale = Vector2(randf_range(0.9, 1.35), randf_range(0.9, 1.35))
	spr.flip_h = randf() < 0.5
	spr.modulate = Color(0.85, 0.95, 0.8, 0.9)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_world.add_child(spr)


func _spawn_route_hazards() -> void:
	for child in hazards.get_children():
		child.queue_free()

	# Peels sit ON the road — avoid if you can, skid if you don't.
	var peel_spots := [
		Vector2(360, 360), Vector2(520, 348), Vector2(680, 370),
		Vector2(820, 280), Vector2(920, 220), # road to Hut A
		Vector2(820, 440), Vector2(940, 500), # road to Hut B
	]
	for pos in peel_spots:
		_spawn_peel_at(pos)

	# Boost bananas off the main lane — risk/reward side nibble.
	var item_scene: PackedScene = load("res://scenes/enemies/item_banana.tscn")
	for pos in [Vector2(480, 300), Vector2(760, 400)]:
		var item := item_scene.instantiate() as Node2D
		item.position = pos
		hazards.add_child(item)

	# One sticky-fingered helper near the fork; one bumper on the south road.
	var tribe_scene: PackedScene = load("res://scenes/enemies/tribe_helper.tscn")
	var thief := tribe_scene.instantiate()
	thief.position = Vector2(700, 320)
	thief.label_text = "I carry!"
	thief.set("mood", 2)
	thief.set("speed", 95.0)
	hazards.add_child(thief)
	var bumper := tribe_scene.instantiate()
	bumper.position = Vector2(880, 520)
	bumper.label_text = "Shortcut!"
	bumper.set("mood", 1)
	bumper.set("speed", 100.0)
	hazards.add_child(bumper)


func _spawn_peel_at(pos: Vector2) -> void:
	var peel_scene: PackedScene = load("res://scenes/enemies/banana_peel_hazard.tscn")
	var peel := peel_scene.instantiate() as Node2D
	peel.position = pos
	hazards.add_child(peel)


func _spawn_pile() -> void:
	for child in pile.get_children():
		if child.name == "PileMarker" or child.name == "DepotSign" or child.name == "LoadArea":
			continue
		child.queue_free()
	var banana_scene: PackedScene = load("res://scenes/enemies/banana.tscn")
	var total := bananas_needed_a + bananas_needed_b + 4
	for i in total:
		var b := banana_scene.instantiate() as Area2D
		b.pickup_mode = "cargo"
		b.position = Vector2(randf_range(-28, 28), randf_range(-18, 18))
		b.monitoring = false
		b.monitorable = false
		pile.add_child(b)
	if not pile.has_node("LoadArea"):
		var load_area := Area2D.new()
		load_area.name = "LoadArea"
		load_area.collision_layer = 0
		load_area.collision_mask = 1
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 58.0
		shape.shape = circle
		load_area.add_child(shape)
		pile.add_child(load_area)
		load_area.body_entered.connect(_on_pile_body_entered)
	if not pile.has_node("DepotSign"):
		var sign := Label.new()
		sign.name = "DepotSign"
		sign.text = "DEPOT"
		sign.position = Vector2(-36, -70)
		sign.add_theme_font_size_override("font_size", 16)
		sign.add_theme_color_override("font_outline_color", Color.BLACK)
		sign.add_theme_constant_override("outline_size", 4)
		pile.add_child(sign)


func _on_pile_body_entered(body: Node2D) -> void:
	if body != cart:
		return
	while _cargo.size() < 3:
		var banana: Node = null
		for child in pile.get_children():
			if child is Area2D and child.name != "LoadArea":
				banana = child
				break
		if banana == null:
			break
		pile.remove_child(banana)
		cargo_area.add_child(banana)
		banana.position = Vector2(randf_range(-12, 12), randf_range(-10, 2))
		_cargo.append(banana)
		GameProgress.juice_shake.emit(0.05)
	if _cargo.size() > 0:
		hint.text = "Cargo loaded — take the dirt road to Hut A or Hut B."
	_update_status()


func _spill_one() -> void:
	if _cargo.is_empty():
		return
	var banana: Node2D = _cargo.pop_back()
	if is_instance_valid(banana):
		var world_pos := banana.global_position
		cargo_area.remove_child(banana)
		pile.add_child(banana)
		banana.global_position = world_pos + Vector2(randf_range(-36, 36), randf_range(-20, 20))
		_spawn_peel_at(world_pos + Vector2(randf_range(-10, 10), 12))
	GameProgress.juice_shake.emit(0.15)
	hint.text = "Bump spilled a banana — and left a peel."
	_update_status()


func _on_dropoff_a(body: Node2D) -> void:
	_deliver_to(body, true)


func _on_dropoff_b(body: Node2D) -> void:
	_deliver_to(body, false)


func _deliver_to(body: Node2D, is_a: bool) -> void:
	if _done or body != cart:
		return
	if _cargo.is_empty():
		return
	var need_left := (bananas_needed_a - _delivered_a) if is_a else (bananas_needed_b - _delivered_b)
	if need_left <= 0:
		hint.text = "Hut %s is already full — stock the other hut." % ("A" if is_a else "B")
		return
	# Deliver one banana per visit so routes stay meaningful.
	var banana: Node2D = _cargo.pop_back()
	if is_instance_valid(banana):
		banana.queue_free()
	if is_a:
		_delivered_a += 1
	else:
		_delivered_b += 1
	GameProgress.juice_shake.emit(0.2)
	hint.text = "Delivered to Hut %s! (%d left in cargo)" % [("A" if is_a else "B"), _cargo.size()]
	_update_status()
	if _delivered_a >= bananas_needed_a and _delivered_b >= bananas_needed_b:
		_succeed()


func _succeed() -> void:
	_done = true
	hint.text = "Both huts stocked! Jungle logistics complete."
	await get_tree().create_timer(1.0).timeout
	GameProgress.complete_minigame(GameProgress.MODE_CART)


func _fail_and_retry() -> void:
	hint.text = "Time's up — the village is still hungry. Retrying..."
	await get_tree().create_timer(1.2).timeout
	_delivered_a = 0
	_delivered_b = 0
	_time_left = time_limit
	_done = false
	for banana in _cargo:
		if is_instance_valid(banana):
			banana.queue_free()
	_cargo.clear()
	_spawn_pile()
	_spawn_route_hazards()
	cart.global_position = Vector2(200, 480)
	cart.velocity = Vector2.ZERO
	cart.rotation = 0.0
	hint.text = "Load at the depot · follow the dirt road · stock BOTH huts"
	_update_status()


func _update_status() -> void:
	status.text = "Hut A %d/%d   Hut B %d/%d   |   Cargo %d   |   %ds" % [
		_delivered_a, bananas_needed_a, _delivered_b, bananas_needed_b, _cargo.size(), ceili(_time_left)
	]
