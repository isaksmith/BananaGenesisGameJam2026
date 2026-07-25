extends Node2D

## Themed Mario-style course. Drawn wheel size/roundness changes what you can clear.

const WheelObstaclesScript := preload("res://scripts/wheel_obstacles.gd")

@export var move_speed: float = 340.0
@export var move_accel: float = 1600.0
@export var scroll_speed: float = 95.0
@export var gravity: float = 1600.0
@export var jump_impulse: float = 720.0
@export var course_length: float = 9000.0

var _level: Dictionary = {}
var _ground_color: Color = Color(0.4, 0.55, 0.3)
var _done: bool = false
var _dead: bool = false
var _time: float = 0.0
var _bananas: int = 0
var _roll_dist: float = 0.0
var _scroll_x: float = 640.0
var _spawn: Vector2 = Vector2(220, 420)
var _effective_jump: float = 720.0
var _effective_accel: float = 1600.0
var _bumpy: float = 0.0
var _icy: float = 0.0
var _axle_y: float = 22.0

var _wheel: CharacterBody2D
var _visual: Node2D
var _wheel_l: Node2D
var _wheel_r: Node2D
var _camera: Camera2D
var _snow: CPUParticles2D
var _obs
var _hint: Label
var _status: Label
var _finish_x: float = 8800.0
var _floor_y: float = 520.0

const ROCK_VARIANTS := [
	"res://assets/sprites/rock_small.png",
	"res://assets/sprites/rock_medium.png",
	"res://assets/sprites/rock_bump.png",
	"res://assets/sprites/rock_wide.png",
	"res://assets/sprites/obstacle_rock.png",
	"res://assets/sprites/rock_tall.png",
]


func _ready() -> void:
	_level = WheelLevels.get_level(GameProgress.selected_wheel_level)
	_apply_level_tuning()
	_obs = WheelObstaclesScript.new()
	_obs.setup(self, _on_hazard, _on_jump_pad)
	_build_world()
	_spawn_wheel()
	_spawn_pickups_and_hazards()
	_spawn_gd_patterns()
	_spawn_finish()
	_build_camera()
	_build_ui()
	var title := str(_level.get("title", "Trail"))
	_hint.text = "%s · pads launch · spikes/saws kill\n%s\nArrows · Space · Esc/Q · R" % [
		title,
		GameProgress.wheel_fit_note(),
	]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _apply_level_tuning() -> void:
	course_length = float(_level.get("course_length", course_length))
	scroll_speed = float(_level.get("scroll_speed", scroll_speed))
	_ground_color = _level.get("ground", _ground_color) as Color
	_bumpy = float(_level.get("bumpy", 0.0))
	_icy = float(_level.get("icy", 0.0))
	var size := GameProgress.wheel_size_norm
	var roundness := GameProgress.wheel_roundness
	var boost := float(_level.get("jump_size_boost", 0.4))
	var penalty := float(_level.get("small_size_jump_penalty", 0.2))
	_effective_jump = jump_impulse * lerpf(1.0 - penalty, 1.0 + boost, size)
	# Round wheels jump a bit cleaner on wobble ridge
	_effective_jump *= lerpf(0.9, 1.08, roundness) if _bumpy > 0.5 else 1.0
	var accel_f := float(_level.get("accel_size_factor", 0.3))
	# Smaller wheels → snappier accel (helps sprint delta)
	_effective_accel = move_accel * lerpf(1.0 + accel_f, 1.0 - accel_f * 0.35, size)
	# Ice: jagged wheels lose grip; round wheels keep more control
	if _icy > 0.0:
		var grip := lerpf(0.32, 0.88, roundness)
		_effective_accel *= lerpf(1.0, grip, _icy)


func _build_world() -> void:
	var sky: Color = _level.get("sky", Color(0.32, 0.58, 0.8)) as Color
	var bg := Polygon2D.new()
	bg.z_index = -20
	bg.color = sky
	bg.polygon = PackedVector2Array([
		Vector2(-400, -400), Vector2(course_length + 800, -400),
		Vector2(course_length + 800, 1000), Vector2(-400, 1000)
	])
	add_child(bg)

	var winter := _icy > 0.4
	if winter:
		_build_winter_backdrop()
		_spawn_snowfall()
	else:
		_build_forest_platform_backdrop()

	var rng := RandomNumberGenerator.new()
	rng.seed = int(_level.get("seed", 26))
	var gap_min := float(_level.get("gap_min", 90.0))
	var gap_max := float(_level.get("gap_max", 170.0))
	var stretch_min := float(_level.get("stretch_min", 420.0))
	var stretch_max := float(_level.get("stretch_max", 720.0))

	var x := 0.0
	while x < course_length:
		var stretch := rng.randf_range(stretch_min, stretch_max)
		if x + stretch > course_length:
			stretch = course_length - x
		_add_ground(x, 560.0, stretch, 80.0)
		x += stretch
		if x < course_length - 200.0:
			x += rng.randf_range(gap_min, gap_max)

	var platform_count := int(_level.get("platform_count", 28))
	for i in platform_count:
		var px := 500.0 + i * 440.0 + rng.randf_range(-40, 80)
		if px > course_length - 200.0:
			break
		# Keep platform tops within jump reach of the floor (~150px max rise)
		var py := rng.randf_range(400.0, 470.0)
		_add_ground(px, py, rng.randf_range(140.0, 240.0), 28.0)

	# Ceiling / overhang rocks are SOLID only — bonking your head must not explode the cart.
	var ceiling_count := int(_level.get("ceiling_count", 10))
	var cy0 := float(_level.get("ceiling_y_min", 120.0))
	var cy1 := float(_level.get("ceiling_y_max", 210.0))
	for i in ceiling_count:
		var px := 700.0 + i * (course_length / float(maxi(ceiling_count, 1)))
		if px > course_length - 300.0:
			break
		if winter:
			_add_snow_prop(Vector2(px, rng.randf_range(cy0, cy1)), "res://assets/sprites/toffee/ice_rock.png", 0.55)
		else:
			_add_rock(Vector2(px, rng.randf_range(cy0, cy1)), false, 5)

	if winter:
		_spawn_winter_trees()
	else:
		_spawn_toffee_track_decor(rng)


func _build_forest_platform_backdrop() -> void:
	# Parallax forest pillars from ForestPlatform pack.
	var far := load("res://assets/sprites/forest_platform/bg_layer_0.png") as Texture2D
	var mid := load("res://assets/sprites/forest_platform/bg_layer_1.png") as Texture2D
	var near := load("res://assets/sprites/forest_platform/bg_wide.png") as Texture2D
	for i in 10:
		var layer_far := Sprite2D.new()
		layer_far.z_index = -16
		layer_far.texture = far
		layer_far.position = Vector2(i * 1800.0, 360)
		layer_far.modulate = Color(1, 1, 1, 0.55)
		layer_far.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(layer_far)
		var layer_mid := Sprite2D.new()
		layer_mid.z_index = -15
		layer_mid.texture = mid if mid != null else near
		layer_mid.position = Vector2(i * 1800.0 + 200.0, 360)
		layer_mid.modulate = Color(1, 1, 1, 0.75)
		layer_mid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(layer_mid)
		var layer_near := Sprite2D.new()
		layer_near.z_index = -14
		layer_near.texture = near
		layer_near.position = Vector2(i * 1800.0, 360)
		layer_near.modulate = Color(1, 1, 1, 0.9)
		layer_near.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(layer_near)


func _tile_forest_platform(body: Node2D, width: float, height: float) -> void:
	var hy := height * 0.5
	var tex_path := "res://assets/sprites/forest_platform/platform_0.png"
	if height < 40.0:
		# Floating pads — use island pieces when short.
		tex_path = "res://assets/sprites/forest_platform/island_0.png" if width < 170.0 \
			else "res://assets/sprites/forest_platform/platform_1.png"
	var tex := load(tex_path) as Texture2D
	if tex == null:
		return
	var tile_w := float(tex.get_width())
	var count := maxi(1, int(ceil(width / tile_w)))
	var start_x := -width * 0.5 + tile_w * 0.5
	var y_off := -hy - float(tex.get_height()) * 0.15
	if height < 40.0:
		y_off = -hy + 2.0
	for i in count:
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.position = Vector2(start_x + i * tile_w, y_off)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		body.add_child(spr)
	# Soft dirt fill under the grass cap so tall ground segments still read.
	if height >= 40.0:
		var fill := Polygon2D.new()
		var hx := width * 0.5
		fill.color = Color(_ground_color.r * 0.85, _ground_color.g * 0.75, _ground_color.b * 0.55, 1)
		fill.polygon = PackedVector2Array([
			Vector2(-hx + 4, -hy + 8), Vector2(hx - 4, -hy + 8),
			Vector2(hx - 4, hy), Vector2(-hx + 4, hy)
		])
		fill.z_index = -1
		body.add_child(fill)


func _build_winter_backdrop() -> void:
	# IcePlatform pack fjord sky / mountains.
	var far := load("res://assets/sprites/ice_platform/bg_layer_0.png") as Texture2D
	var mid := load("res://assets/sprites/ice_platform/bg_layer_1.png") as Texture2D
	var near := load("res://assets/sprites/ice_platform/bg_wide.png") as Texture2D
	for i in 10:
		var layer_far := Sprite2D.new()
		layer_far.z_index = -16
		layer_far.texture = far if far != null else near
		layer_far.position = Vector2(i * 1800.0, 360)
		layer_far.modulate = Color(1, 1, 1, 0.65)
		layer_far.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(layer_far)
		var layer_mid := Sprite2D.new()
		layer_mid.z_index = -15
		layer_mid.texture = mid if mid != null else near
		layer_mid.position = Vector2(i * 1800.0 + 160.0, 360)
		layer_mid.modulate = Color(1, 1, 1, 0.8)
		layer_mid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(layer_mid)
		var layer_near := Sprite2D.new()
		layer_near.z_index = -14
		layer_near.texture = near
		layer_near.position = Vector2(i * 1800.0, 360)
		layer_near.modulate = Color(1, 1, 1, 0.95)
		layer_near.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(layer_near)

	# Distant ice pillars for depth.
	var pillar := load("res://assets/sprites/ice_platform/pillar_0.png") as Texture2D
	if pillar != null:
		for i in int(course_length / 220.0):
			var p := Sprite2D.new()
			p.z_index = -13
			p.texture = pillar
			p.position = Vector2(120 + i * 220.0, 400 + (i % 3) * 10.0)
			p.scale = Vector2(1.6, 1.8)
			p.modulate = Color(0.85, 0.92, 1.0, 0.5)
			p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if i % 2 == 0:
				p.flip_h = true
			add_child(p)


func _spawn_winter_trees() -> void:
	var pines := [
		"res://assets/sprites/ice_platform/tree_0.png",
		"res://assets/sprites/ice_platform/pillar_1.png",
		"res://assets/sprites/ice_platform/cube_0.png",
		"res://assets/sprites/toffee/ice_rock.png",
		"res://assets/sprites/ice_platform/tree_1.png",
	]
	for i in 48:
		var tree := Sprite2D.new()
		tree.z_index = -5
		tree.texture = load(pines[i % pines.size()]) as Texture2D
		tree.position = Vector2(160 + i * 180.0, 470)
		var path_str := str(pines[i % pines.size()])
		var s := 1.45 if "pillar" in path_str else 1.25
		if "cube" in path_str:
			s = 1.6
			tree.position.y = 520
		tree.scale = Vector2(s, s)
		tree.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if i % 2 == 0:
			tree.flip_h = true
		add_child(tree)


func _spawn_toffee_track_decor(rng: RandomNumberGenerator) -> void:
	var pattern := StringName(_level.get("pattern", &"gorge"))
	var trees: Array = [
		"res://assets/sprites/toffee/tree_pine_warm.png",
		"res://assets/sprites/toffee/tree_birch.png",
		"res://assets/sprites/toffee/fern.png",
	]
	match pattern:
		&"tunnel":
			trees = [
				"res://assets/sprites/toffee/tree_thin.png",
				"res://assets/sprites/toffee/tree_bare.png",
				"res://assets/sprites/toffee/cactus.png",
			]
		&"chaos":
			trees = [
				"res://assets/sprites/toffee/bush_coral_purple.png",
				"res://assets/sprites/toffee/bush_coral_red.png",
				"res://assets/sprites/toffee/bush_coral_orange.png",
			]
		&"sprint":
			trees = [
				"res://assets/sprites/toffee/tree_pine.png",
				"res://assets/sprites/toffee/tree_pine_warm.png",
				"res://assets/sprites/forest_platform/trunk_0.png",
			]
		&"gorge":
			trees = [
				"res://assets/sprites/toffee/rock_grey.png",
				"res://assets/sprites/toffee/rock_brown.png",
				"res://assets/sprites/forest_platform/trunk_1.png",
				"res://assets/sprites/toffee/cactus.png",
			]
	for i in 40:
		var prop := Sprite2D.new()
		prop.z_index = -5
		prop.texture = load(trees[i % trees.size()]) as Texture2D
		prop.position = Vector2(200 + i * 220.0, 480)
		var path_str := str(trees[i % trees.size()])
		var s := 1.05
		if "trunk" in path_str:
			s = 1.4
			prop.position.y = 430
		elif pattern == &"chaos":
			s = 1.35
		prop.scale = Vector2(s, s)
		prop.modulate = Color(1, 1, 1, 0.92)
		prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if i % 2 == 0:
			prop.flip_h = true
		add_child(prop)
		if pattern == &"gorge" or pattern == &"sprint":
			if i % 3 == 0:
				var rock := Sprite2D.new()
				rock.z_index = -4
				var rock_path := "res://assets/sprites/toffee/rock_grey.png" if i % 6 == 0 else "res://assets/sprites/toffee/rock_grey_b.png"
				rock.texture = load(rock_path) as Texture2D
				rock.position = Vector2(260 + i * 220.0, 520 + rng.randf_range(-10, 20))
				rock.scale = Vector2(0.75, 0.75)
				rock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				add_child(rock)


func _spawn_snowfall() -> void:
	_snow = CPUParticles2D.new()
	_snow.name = "Snowfall"
	_snow.z_index = 30
	_snow.position = Vector2(640, -40)
	_snow.emitting = true
	_snow.amount = 70
	_snow.lifetime = 3.2
	_snow.preprocess = 2.0
	_snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_snow.emission_rect_extents = Vector2(720, 8)
	_snow.direction = Vector2(0.15, 1)
	_snow.spread = 12.0
	_snow.initial_velocity_min = 40.0
	_snow.initial_velocity_max = 90.0
	_snow.gravity = Vector2(0, 28)
	_snow.scale_amount_min = 2.0
	_snow.scale_amount_max = 4.5
	_snow.color = Color(1, 1, 1, 0.85)
	add_child(_snow)


func _add_ground(x: float, y: float, width: float, height: float) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(x + width * 0.5, y)
	body.collision_layer = 4
	body.collision_mask = 0
	var visual := Polygon2D.new()
	var hx := width * 0.5
	var hy := height * 0.5
	visual.color = _ground_color
	visual.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)
	])
	body.add_child(visual)

	if _icy > 0.4:
		_tile_snow_caps(body, width, height)
	else:
		_tile_forest_platform(body, width, height)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, height)
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _tile_snow_caps(body: Node2D, width: float, height: float) -> void:
	var hy := height * 0.5
	var tile_path := "res://assets/sprites/ice_platform/platform_0.png"
	if height < 40.0:
		tile_path = "res://assets/sprites/ice_platform/platform_1.png" if width >= 170.0 \
			else "res://assets/sprites/ice_platform/cube_0.png"
	var tex := load(tile_path) as Texture2D
	if tex == null:
		return
	var tile_w := float(tex.get_width())
	var count := maxi(1, int(ceil(width / tile_w)))
	var start_x := -width * 0.5 + tile_w * 0.5
	var y_off := -hy - float(tex.get_height()) * 0.2
	if height < 40.0:
		y_off = -hy + 2.0
	for i in count:
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.position = Vector2(start_x + i * tile_w, y_off)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		body.add_child(spr)
	if height >= 40.0:
		var fill := Polygon2D.new()
		var hx := width * 0.5
		fill.color = Color(0.55, 0.72, 0.88, 1)
		fill.polygon = PackedVector2Array([
			Vector2(-hx + 4, -hy + 8), Vector2(hx - 4, -hy + 8),
			Vector2(hx - 4, hy), Vector2(-hx + 4, hy)
		])
		fill.z_index = -1
		body.add_child(fill)


func _add_rock(pos: Vector2, deadly: bool = false, variant: int = -1) -> void:
	if _icy > 0.4:
		var snow_paths := [
			"res://assets/sprites/ice_platform/cube_1.png",
			"res://assets/sprites/ice_platform/cube_2.png",
			"res://assets/sprites/ice_platform/pillar_2.png",
			"res://assets/sprites/toffee/ice_rock.png",
		]
		var idx := variant if variant >= 0 else int(absf(pos.x))
		_add_snow_prop(pos, snow_paths[idx % snow_paths.size()], 1.35)
		return

	var body: CollisionObject2D
	if deadly:
		body = Area2D.new()
		(body as Area2D).collision_layer = 0
		(body as Area2D).collision_mask = 1
		(body as Area2D).monitoring = true
		(body as Area2D).body_entered.connect(_on_hazard)
	else:
		body = StaticBody2D.new()
		body.collision_layer = 4
	body.position = pos

	var path: String
	if variant >= 0:
		path = ROCK_VARIANTS[variant % ROCK_VARIANTS.size()]
	else:
		path = ROCK_VARIANTS[int(absf(pos.x)) % ROCK_VARIANTS.size()]
	var tex := load(path) as Texture2D
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.offset = Vector2(0, -tex.get_height() * 0.5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(sprite)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	shape.size = Vector2(tw * 0.72, th * 0.55)
	col.shape = shape
	col.position = Vector2(0, -th * 0.28)
	body.add_child(col)
	add_child(body)


func _add_snow_prop(pos: Vector2, tex_path: String, scale: float = 1.4) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 4
	var tex := load(tex_path) as Texture2D
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.offset = Vector2(0, -tex.get_height() * 0.35)
	sprite.scale = Vector2(scale, scale)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(sprite)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	var tw := float(tex.get_width()) * scale
	var th := float(tex.get_height()) * scale
	shape.size = Vector2(tw * 0.65, th * 0.5)
	col.shape = shape
	col.position = Vector2(0, -th * 0.2)
	body.add_child(col)
	add_child(body)


func _spawn_wheel() -> void:
	var radius := GameProgress.wheel_radius
	_axle_y = radius * 0.85
	var wheel_spread := clampf(radius * 0.95, 20.0, 34.0)

	_wheel = CharacterBody2D.new()
	_wheel.name = "BananaCart"
	_wheel.position = _spawn
	_wheel.collision_layer = 1
	_wheel.collision_mask = 4
	_wheel.floor_stop_on_slope = false
	_wheel.floor_max_angle = deg_to_rad(70.0)
	_wheel.add_to_group("player")
	_wheel.add_to_group("cart")

	_visual = Node2D.new()
	_visual.name = "Visual"
	_wheel.add_child(_visual)

	var poly := GameProgress.get_drawn_wheel()
	_wheel_l = _make_drawn_wheel_visual(poly, Vector2(-wheel_spread, _axle_y))
	_wheel_r = _make_drawn_wheel_visual(poly, Vector2(wheel_spread, _axle_y))
	_visual.add_child(_wheel_l)
	_visual.add_child(_wheel_r)

	var cart := Sprite2D.new()
	cart.texture = load("res://assets/sprites/banana_cart.png") as Texture2D
	cart.position = Vector2(0, _axle_y - radius * 0.12 - 8.0)
	var cart_scale_y := clampf(0.18 + radius / 240.0, 0.2, 0.3)
	var cart_scale_x := cart_scale_y * 0.62
	cart.scale = Vector2(cart_scale_x, cart_scale_y)
	cart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cart.z_index = 1
	_visual.add_child(cart)

	var monkey := Sprite2D.new()
	monkey.texture = load("res://assets/sprites/monkey_idle.png") as Texture2D
	monkey.position = Vector2(1, cart.position.y - 16.0)
	monkey.scale = Vector2(0.42, 0.42)
	monkey.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	monkey.z_index = 2
	_visual.add_child(monkey)

	# Hitbox grows with wheel size — big wheels scrape Needle Pass ceilings
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	var body_h := radius * 1.85 + 14.0
	var body_w := wheel_spread * 2.0 + radius * 0.45 + 6.0
	shape.size = Vector2(body_w, body_h)
	col.shape = shape
	col.position = Vector2(0, _axle_y - radius * 0.2)
	_wheel.add_child(col)
	add_child(_wheel)


func _make_drawn_wheel_visual(poly: PackedVector2Array, offset: Vector2) -> Node2D:
	var hub := Node2D.new()
	hub.position = offset
	var fill := Polygon2D.new()
	fill.color = Color(0.85, 0.62, 0.22)
	fill.polygon = poly
	hub.add_child(fill)
	var outline := Line2D.new()
	outline.width = 3.0
	outline.default_color = Color(0.25, 0.15, 0.08)
	outline.closed = true
	for p in poly:
		outline.add_point(p)
	hub.add_child(outline)
	return hub


func _spawn_pickups_and_hazards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_level.get("seed", 42)) + 7
	var banana_scene: PackedScene = load("res://scenes/enemies/banana.tscn")
	var banana_count := int(_level.get("banana_count", 40))

	for i in banana_count:
		var bx := 400.0 + i * 160.0 + rng.randf_range(-30, 30)
		if bx > course_length - 300.0:
			break
		var by := rng.randf_range(200.0, 420.0)
		var b := banana_scene.instantiate() as Area2D
		b.position = Vector2(bx, by)
		b.pickup_mode = "chase"
		b.lifetime = 9999.0
		b.body_entered.connect(_on_banana_body.bind(b))
		add_child(b)


func _spawn_gd_patterns() -> void:
	## Geometry Dash–style sections (inspired by classic GD rhythms / OpenGD goals).
	var pattern: StringName = _level.get("pattern", &"gorge")
	match pattern:
		&"gorge":
			_pattern_gorge()
		&"tunnel":
			_pattern_tunnel()
		&"chaos":
			_pattern_chaos()
		&"sprint":
			_pattern_sprint()
		&"frost":
			_pattern_frost()
		_:
			_pattern_gorge()


func _pattern_gorge() -> void:
	# Even spike cadence with pads between
	_obs.use_metal_spikes = false
	var x := 480.0
	var i := 0
	while x < course_length - 420.0:
		match i % 3:
			0:
				_obs.add_spike(Vector2(x, _floor_y), false, 1.05, Color(1.25, 0.3, 0.35))
			1:
				_obs.add_jump_pad(Vector2(x + 20.0, _floor_y - 2.0), 820.0)
				_obs.add_trap(Vector2(x + 160.0, _floor_y), &"bear", 1.4)
			2:
				_obs.add_spike_row(Vector2(x, _floor_y), 2, 34.0, false, 1.0, Color(1.25, 0.3, 0.35))
		x += 480.0
		i += 1


func _pattern_tunnel() -> void:
	# Even floor+ceiling spike pairs down the ship lane
	_obs.use_metal_spikes = true
	var x := 520.0
	var ceil_y := 310.0
	var i := 0
	while x < course_length - 380.0:
		_obs.add_spike_row(Vector2(x, _floor_y), 2, 32.0, false, 0.85, Color(0.85, 0.35, 0.55))
		_obs.add_spike_row(Vector2(x + 16.0, ceil_y), 2, 32.0, true, 0.85, Color(0.85, 0.35, 0.55))
		if i % 2 == 0:
			_obs.add_block(Vector2(x + 150.0, 360.0), 90.0, 40.0, Color(0.25, 0.28, 0.32))
		else:
			_obs.add_trap(Vector2(x + 170.0, _floor_y), &"fire", 1.4)
		x += 480.0
		i += 1


func _pattern_chaos() -> void:
	# Movers + regularly spaced spike groups
	_obs.use_metal_spikes = false
	var x := 500.0
	var i := 0
	while x < course_length - 420.0:
		if i % 2 == 0:
			_obs.add_moving_platform(
				Vector2(x + 80.0, 420.0),
				Vector2(x + 200.0, 300.0),
				130.0,
				2.0 + float(i % 3) * 0.35,
				Color(0.55, 0.4, 0.22)
			)
		_obs.add_spike_row(Vector2(x, _floor_y), 2, 34.0, false, 0.95, Color(0.9, 0.35, 0.2))
		if i % 3 == 1:
			_obs.add_trap(Vector2(x + 180.0, _floor_y), &"spike", 1.5)
		if i % 3 == 2:
			_obs.add_jump_pad(Vector2(x + 200.0, _floor_y - 2.0), 700.0, Color(1.0, 0.7, 0.2))
		x += 500.0
		i += 1


func _pattern_sprint() -> void:
	# Tight even beat: spike / pad / alternating spike packs
	_obs.use_metal_spikes = false
	var x := 420.0
	var beat := 0
	while x < course_length - 360.0:
		match beat % 4:
			0:
				_obs.add_spike(Vector2(x, _floor_y), false, 1.0, Color(1.2, 0.25, 0.35))
			1:
				_obs.add_jump_pad(Vector2(x + 10.0, _floor_y - 2.0), 760.0, Color(1.2, 0.95, 0.3))
			2:
				_obs.add_spike_row(Vector2(x, _floor_y), 2, 32.0, false, 0.95, Color(1.2, 0.25, 0.35))
			3:
				_obs.add_trap(Vector2(x + 30.0, _floor_y), &"fire", 1.4)
		x += 340.0
		beat += 1


func _pattern_frost() -> void:
	# Even ice spikes with pads / movers on a steady interval
	_obs.use_metal_spikes = true
	var x := 500.0
	var i := 0
	while x < course_length - 420.0:
		_obs.add_spike(Vector2(x, _floor_y), false, 1.05, Color(1.15, 0.35, 0.55))
		match i % 3:
			0:
				_obs.add_jump_pad(Vector2(x + 140.0, _floor_y - 2.0), 740.0, Color(1.2, 0.95, 0.35))
			1:
				_obs.add_trap(Vector2(x + 160.0, _floor_y), &"spike", 1.4, Color(0.8, 0.92, 1.1))
			2:
				_obs.add_moving_platform(
					Vector2(x + 150.0, 450.0),
					Vector2(x + 150.0, 320.0),
					120.0,
					2.6,
					Color(0.75, 0.88, 0.98)
				)
		x += 480.0
		i += 1


func _spawn_finish() -> void:
	_finish_x = course_length - 200.0
	var finish := Area2D.new()
	finish.position = Vector2(_finish_x, 420)
	finish.collision_layer = 0
	finish.collision_mask = 1
	finish.monitoring = true
	finish.body_entered.connect(_on_finish)
	var banner := Polygon2D.new()
	banner.color = Color(1, 0.85, 0.2, 0.55)
	banner.polygon = PackedVector2Array([
		Vector2(-20, -200), Vector2(20, -200), Vector2(20, 200), Vector2(-20, 200)
	])
	finish.add_child(banner)
	var pile := Sprite2D.new()
	pile.texture = load("res://assets/sprites/bananas_pile.png") as Texture2D
	pile.scale = Vector2(2.2, 2.2)
	pile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	finish.add_child(pile)
	var label := Label.new()
	label.text = "FINISH"
	label.position = Vector2(-40, -230)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	finish.add_child(label)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(80, 400)
	col.shape = shape
	finish.add_child(col)
	add_child(finish)


func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = false
	_camera.limit_top = -80
	_camera.limit_bottom = 780
	add_child(_camera)
	_camera.make_current()
	_scroll_x = 640.0
	_camera.global_position = Vector2(_scroll_x, 360)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_top = 14
	_hint.offset_left = -480
	_hint.offset_right = 480
	_hint.offset_bottom = 78
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 5)
	layer.add_child(_hint)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.offset_top = 78
	_status.offset_left = -360
	_status.offset_right = 360
	_status.offset_bottom = 110
	_status.add_theme_font_size_override("font_size", 17)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 4)
	layer.add_child(_status)


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("restart"):
		_respawn("Retry! Or Esc back to camp and redraw for this trail.")
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _done or _wheel == null or _dead:
		return

	_time += delta
	var progress := clampf(_wheel.global_position.x / _finish_x, 0.0, 1.0)
	_status.text = "%s  ·  Bananas %d  ·  %.0f%%  ·  %.1fs" % [
		str(_level.get("title", "Trail")),
		_bananas,
		progress * 100.0,
		_time,
	]

	var axis := Input.get_axis("move_left", "move_right")
	var target_x := axis * move_speed
	var accel := _effective_accel
	# On ice with no input, coast — jagged wheels slide farther out of control
	if _icy > 0.0 and absf(axis) < 0.15 and _wheel.is_on_floor():
		var coast_brake := lerpf(40.0, 160.0, GameProgress.wheel_roundness)
		_wheel.velocity.x = move_toward(_wheel.velocity.x, 0.0, coast_brake * _icy * delta)
	else:
		_wheel.velocity.x = move_toward(_wheel.velocity.x, target_x, accel * delta)

	if not _wheel.is_on_floor():
		_wheel.velocity.y += gravity * delta
	elif Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("move_up"):
		_wheel.velocity.y = -_effective_jump
		GameProgress.juice_shake.emit(0.05)

	# Jagged wheels bounce / skid on bumpy trails
	if _wheel.is_on_floor() and _bumpy > 0.0:
		var jag := 1.0 - GameProgress.wheel_roundness
		_wheel.velocity.x *= lerpf(1.0, 0.965, _bumpy * jag)
		if jag > 0.25 and randf() < _bumpy * jag * delta * 10.0:
			_wheel.velocity.y = -90.0 * jag
			_wheel.velocity.x += randf_range(-40.0, 40.0) * jag

	# Extra ice skate when wheels are square
	if _wheel.is_on_floor() and _icy > 0.0:
		var jag := 1.0 - GameProgress.wheel_roundness
		if jag > 0.3 and absf(_wheel.velocity.x) > 40.0:
			_wheel.velocity.x += signf(_wheel.velocity.x) * 30.0 * jag * _icy * delta

	var before := _wheel.global_position
	_wheel.move_and_slide()
	var moved := _wheel.global_position.x - before.x
	_roll_dist += moved
	var spin := _roll_dist * (0.04 + 0.8 / maxf(GameProgress.wheel_radius, 12.0))
	if _wheel_l:
		_wheel_l.rotation = spin
	if _wheel_r:
		_wheel_r.rotation = spin

	var scroll_cap := _finish_x - 200.0
	if _scroll_x < scroll_cap:
		_scroll_x += scroll_speed * delta
	var cam_y := lerpf(_camera.global_position.y, clampf(_wheel.global_position.y, 280.0, 480.0), 0.08)
	_camera.global_position = Vector2(_scroll_x, cam_y)
	if _snow:
		_snow.global_position = Vector2(_scroll_x, cam_y - 380.0)

	var right_limit := _scroll_x + 560.0
	if _wheel.global_position.x > right_limit:
		_wheel.global_position.x = right_limit
		_wheel.velocity.x = minf(_wheel.velocity.x, 0.0)

	var left_kill := _scroll_x - 660.0
	if _wheel.global_position.x < left_kill:
		_respawn("The jungle scrolled on without you.")
		return

	if _wheel.global_position.y > 780.0:
		var tip := "Fell in a gap."
		if GameProgress.wheel_size_norm < float(_level.get("want_size_min", 0.0)):
			tip = "Fell short — bigger wheels jump farther here."
		_respawn(tip)


func _on_banana_body(body: Node2D, banana: Area2D) -> void:
	if body != _wheel and not body.is_in_group("player"):
		return
	if not is_instance_valid(banana):
		return
	_bananas += 1
	GameProgress.juice_shake.emit(0.06)
	banana.queue_free()


func _on_jump_pad(body: Node2D, boost: float) -> void:
	if _done or _dead or _wheel == null:
		return
	if body != _wheel and not body.is_in_group("player"):
		return
	_wheel.velocity.y = -boost
	GameProgress.juice_shake.emit(0.08)


func _on_hazard(body: Node2D) -> void:
	# Spikes / saws only — never used for platform underside bonks.
	if _done or _dead:
		return
	if body == _wheel or body.is_in_group("player"):
		_respawn("Spike / saw! Redesign the wheel if this trail hates your shape.")


func _control_hint() -> String:
	return "%s · Arrows move · Space jump · keep up!\nEsc/Q exit · R retry · redraw at camp if needed" % str(
		_level.get("title", "Trail")
	)


func _respawn(msg: String) -> void:
	_dead = true
	_hint.text = msg
	var boom_at := _wheel.global_position
	_wheel.velocity = Vector2.ZERO
	if _visual:
		_visual.visible = false
	_spawn_banana_explosion(boom_at)
	GameProgress.juice_shake.emit(0.55)
	await get_tree().create_timer(0.85).timeout
	if _done:
		return
	_wheel.global_position = _spawn
	_wheel.velocity = Vector2.ZERO
	_roll_dist = 0.0
	if _wheel_l:
		_wheel_l.rotation = 0.0
	if _wheel_r:
		_wheel_r.rotation = 0.0
	if _visual:
		_visual.visible = true
		_visual.modulate = Color(1, 1, 1, 0)
		var fade := create_tween()
		fade.tween_property(_visual, "modulate:a", 1.0, 0.2)
	_scroll_x = 640.0
	_camera.global_position = Vector2(_scroll_x, 360)
	_dead = false
	_hint.text = _control_hint()


func _spawn_banana_explosion(origin: Vector2) -> void:
	var banana_tex := load("res://assets/sprites/banana.png") as Texture2D
	var peel_tex := load("res://assets/sprites/banana_peel.png") as Texture2D

	# Flash ring
	var flash := Polygon2D.new()
	flash.z_index = 40
	flash.color = Color(1.0, 0.92, 0.35, 0.85)
	var ring := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		ring.append(Vector2(cos(a), sin(a)) * 18.0)
	flash.polygon = ring
	flash.global_position = origin
	add_child(flash)
	var flash_tween := create_tween()
	flash_tween.tween_property(flash, "scale", Vector2(6.5, 6.5), 0.28)
	flash_tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.28)
	flash_tween.tween_callback(flash.queue_free)

	# Particle burst
	var bits := CPUParticles2D.new()
	bits.z_index = 39
	bits.global_position = origin
	bits.emitting = true
	bits.one_shot = true
	bits.explosiveness = 1.0
	bits.amount = 36
	bits.lifetime = 0.55
	bits.direction = Vector2(0, -1)
	bits.spread = 180.0
	bits.initial_velocity_min = 180.0
	bits.initial_velocity_max = 420.0
	bits.gravity = Vector2(0, 900)
	bits.scale_amount_min = 3.0
	bits.scale_amount_max = 7.0
	bits.color = Color(1.0, 0.85, 0.25, 1)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.4, 1),
		Color(1.0, 0.55, 0.1, 0.85),
		Color(0.4, 0.2, 0.05, 0),
	])
	bits.color_ramp = grad
	add_child(bits)
	bits.finished.connect(bits.queue_free)

	# Flying bananas + peels
	for i in 14:
		var spr := Sprite2D.new()
		spr.z_index = 41
		spr.texture = peel_tex if i % 3 == 0 else banana_tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(0.55, 0.55) if i % 3 == 0 else Vector2(0.7, 0.7)
		spr.global_position = origin + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		spr.rotation = randf_range(0, TAU)
		add_child(spr)
		var dir := Vector2(randf_range(-1, 1), randf_range(-1.2, -0.2)).normalized()
		var dist := randf_range(90.0, 220.0)
		var end := origin + dir * dist + Vector2(0, randf_range(40, 120))
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(spr, "global_position", end, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(spr, "rotation", spr.rotation + randf_range(-8, 8), 0.7)
		tw.tween_property(spr, "modulate:a", 0.0, 0.7).set_delay(0.25)
		tw.chain().tween_callback(spr.queue_free)


func _on_finish(body: Node2D) -> void:
	if _done:
		return
	if body == _wheel or body.is_in_group("player"):
		_done = true
		_wheel.velocity *= 0.2
		_hint.text = "%s clear! Your wheel fit the challenge." % str(_level.get("title", "Trail"))
		_status.text = "Done — %d bananas in %.1fs" % [_bananas, _time]
		GameProgress.juice_shake.emit(0.55)
		await get_tree().create_timer(1.4).timeout
		GameProgress.complete_minigame(GameProgress.MODE_WHEEL)
