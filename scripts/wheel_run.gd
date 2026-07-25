extends Node2D

## Themed Mario-style course. Drawn wheel size/roundness changes what you can clear.

const WheelObstaclesScript := preload("res://scripts/wheel_obstacles.gd")

@export var move_speed: float = 340.0
@export var move_accel: float = 1600.0
@export var scroll_speed: float = 95.0
@export var gravity: float = 1600.0
@export var jump_impulse: float = 780.0
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
var _effective_jump: float = 780.0
var _effective_accel: float = 1600.0
var _bumpy: float = 0.0
var _icy: float = 0.0
var _theme: StringName = &"forest"
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
## Registered ground / floating pads — hazards snap to these surfaces.
var _platforms: Array[Dictionary] = []
var _tiger: Area2D = null

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
	if bool(_level.get("chase_tiger", false)):
		_spawn_chase_tiger()
	_build_camera()
	_build_ui()
	var title := str(_level.get("title", "Trail"))
	var tip := "pads launch · spikes kill"
	if bool(_level.get("chase_tiger", false)):
		tip = "tiger chases — don't get caught · spikes kill"
	_hint.text = "%s · %s\n%s\nArrows · Space · Esc/Q · R" % [
		title,
		tip,
		GameProgress.wheel_fit_note(),
	]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _apply_level_tuning() -> void:
	course_length = float(_level.get("course_length", course_length))
	scroll_speed = float(_level.get("scroll_speed", scroll_speed))
	_ground_color = _level.get("ground", _ground_color) as Color
	_bumpy = float(_level.get("bumpy", 0.0))
	_icy = float(_level.get("icy", 0.0))
	_theme = StringName(_level.get("theme", &"forest" if _icy < 0.4 else &"winter"))
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
	_platforms.clear()
	var sky: Color = _level.get("sky", Color(0.32, 0.58, 0.8)) as Color
	var bg := Polygon2D.new()
	bg.z_index = -20
	bg.color = sky
	bg.polygon = PackedVector2Array([
		Vector2(-400, -400), Vector2(course_length + 800, -400),
		Vector2(course_length + 800, 1000), Vector2(-400, 1000)
	])
	add_child(bg)

	var winter := _theme == &"winter" or _icy > 0.4
	match _theme:
		&"winter":
			_build_winter_backdrop()
			_spawn_snowfall()
		&"graveyard":
			_build_graveyard_backdrop()
		&"desert":
			_build_parallax_backdrop("res://assets/sprites/parallax_desert/", [
				"sky.png", "moon.png", "cloud.png", "mountain.png", "dune_mid.png", "dune_front.png"
			], [0.35, 0.45, 0.55, 0.7, 0.85, 0.95], [2200.0, 2600.0, 2000.0, 2400.0, 1800.0, 1600.0])
		&"lunar":
			_build_parallax_backdrop("res://assets/sprites/parallax_moon/", [
				"sky.png", "earth.png", "back.png", "mid.png", "front.png", "floor.png"
			], [0.4, 0.5, 0.6, 0.75, 0.88, 0.95], [2200.0, 2600.0, 2400.0, 2000.0, 1800.0, 1600.0])
		_:
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

	# Three runnable levels: low stepping pads, mid lane, high lane (floor stretches = ground).
	# Vertical gaps (~120px+) leave room for the compact cart to jump between lanes.
	var lane_ys: Array = [
		float(_level.get("lane_low_y", 455.0)),
		float(_level.get("lane_mid_y", 335.0)),
		float(_level.get("lane_high_y", 210.0)),
	]
	var spacing := float(_level.get("platform_spacing", 540.0))
	var platform_count := int(_level.get("platform_count", 36))
	for i in platform_count:
		var px := 420.0 + float(i) * spacing + rng.randf_range(-50, 70)
		if px > course_length - 200.0:
			break
		var py: float = float(lane_ys[i % 3]) + rng.randf_range(-12.0, 12.0)
		_add_ground(px, py, rng.randf_range(120.0, 200.0), 24.0)

	# Ceiling / overhang rocks are SOLID only — bonking your head must not explode the cart.
	# Keep them above the high lane so mid/low stay passable.
	var ceiling_count := int(_level.get("ceiling_count", 10))
	var cy0 := float(_level.get("ceiling_y_min", 70.0))
	var cy1 := float(_level.get("ceiling_y_max", 140.0))
	for i in ceiling_count:
		var px := 700.0 + i * (course_length / float(maxi(ceiling_count, 1)))
		if px > course_length - 300.0:
			break
		if winter or _theme == &"lunar":
			_add_snow_prop(Vector2(px, rng.randf_range(cy0, cy1)), "res://assets/sprites/toffee/ice_rock.png", 0.55)
		elif _theme == &"graveyard":
			_add_snow_prop(Vector2(px, rng.randf_range(cy0, cy1)), "res://assets/sprites/moon_graveyard/Salt.png", 0.45)
		else:
			_add_rock(Vector2(px, rng.randf_range(cy0, cy1)), false, 5)

	match _theme:
		&"winter":
			_spawn_winter_trees()
		&"graveyard":
			_spawn_graveyard_decor(rng)
		&"desert", &"lunar":
			pass
		_:
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


func _build_graveyard_backdrop() -> void:
	var far := load("res://assets/sprites/moon_graveyard/Background_0.png") as Texture2D
	var mid := load("res://assets/sprites/moon_graveyard/Background_1.png") as Texture2D
	var grass := load("res://assets/sprites/moon_graveyard/Grass_background_1.png") as Texture2D
	var grass2 := load("res://assets/sprites/moon_graveyard/Grass_background_2.png") as Texture2D
	for i in 12:
		var x := float(i) * 760.0
		for pair in [
			[far, -18, 0.55, Color(1, 1, 1, 0.9)],
			[mid, -17, 0.7, Color(1, 1, 1, 0.85)],
			[grass, -16, 0.85, Color(1, 1, 1, 0.9)],
			[grass2, -15, 0.95, Color(1, 1, 1, 0.95)],
		]:
			var tex: Texture2D = pair[0]
			if tex == null:
				continue
			var spr := Sprite2D.new()
			spr.z_index = int(pair[1])
			spr.texture = tex
			spr.position = Vector2(x + 100.0 * float(pair[2]), 360)
			spr.scale = Vector2(1.05, 1.05)
			spr.modulate = pair[3]
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(spr)


func _build_parallax_backdrop(folder: String, files: Array, alphas: Array, spacings: Array) -> void:
	for layer_i in files.size():
		var tex := load(folder + String(files[layer_i])) as Texture2D
		if tex == null:
			continue
		var spacing: float = float(spacings[layer_i]) if layer_i < spacings.size() else 2000.0
		var alpha: float = float(alphas[layer_i]) if layer_i < alphas.size() else 0.8
		var tiles := maxi(6, int(ceil((course_length + 1600.0) / spacing)) + 1)
		for i in tiles:
			var spr := Sprite2D.new()
			spr.z_index = -18 + layer_i
			spr.texture = tex
			# Fit ~720px tall view while keeping pixel look
			var s := 720.0 / maxf(float(tex.get_height()), 1.0)
			spr.scale = Vector2(s, s)
			spr.position = Vector2(float(i) * spacing, 360)
			spr.modulate = Color(1, 1, 1, alpha)
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(spr)


func _tile_graveyard_platform(body: Node2D, width: float, height: float) -> void:
	var hy := height * 0.5
	var tex_path := "res://assets/sprites/moon_graveyard/platform_1.png" if width >= 150.0 \
		else "res://assets/sprites/moon_graveyard/platform_0.png"
	var tex := load(tex_path) as Texture2D
	if tex == null:
		return
	var y_off := -hy + 2.0 if height < 40.0 else -hy - float(tex.get_height()) * 0.1
	_tile_cap_row(body, tex, width, y_off)
	if height >= 40.0:
		var fill := Polygon2D.new()
		var hx := width * 0.5
		fill.color = Color(0.22, 0.21, 0.2, 1)
		fill.polygon = PackedVector2Array([
			Vector2(-hx + 4, -hy + 8), Vector2(hx - 4, -hy + 8),
			Vector2(hx - 4, hy), Vector2(-hx + 4, hy)
		])
		fill.z_index = -1
		body.add_child(fill)


func _tile_desert_platform(body: Node2D, width: float, height: float) -> void:
	# Reuse forest platform caps, tinted sandy, over desert fill.
	_tile_forest_platform(body, width, height)
	for child in body.get_children():
		if child is Sprite2D:
			(child as Sprite2D).modulate = Color(1.15, 0.95, 0.7, 1)


func _spawn_graveyard_decor(rng: RandomNumberGenerator) -> void:
	var props := [
		"res://assets/sprites/moon_graveyard/Salt.png",
		"res://assets/sprites/moon_graveyard/brush.png",
	]
	for i in 18:
		var px := 500.0 + float(i) * 420.0 + rng.randf_range(-40, 80)
		if px > course_length - 250.0:
			break
		var path: String = props[i % props.size()]
		var s := 0.35 if path.ends_with("brush.png") else 0.5
		_add_snow_prop(Vector2(px, rng.randf_range(470.0, 520.0)), path, s)


## Tile a cap texture across a platform, cropping the final tile so the art
## never overhangs the physical collision width (falling off "invisible" edges).
func _tile_cap_row(body: Node2D, tex: Texture2D, width: float, y_off: float) -> void:
	var tile_w := float(tex.get_width())
	var tex_h := float(tex.get_height())
	var left := -width * 0.5
	var x := left
	while x < left + width - 0.5:
		var remaining := left + width - x
		var w := minf(tile_w, remaining)
		var spr := Sprite2D.new()
		spr.texture = tex
		if w < tile_w - 0.5:
			spr.region_enabled = true
			spr.region_rect = Rect2(0, 0, w, tex_h)
		spr.position = Vector2(x + w * 0.5, y_off)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		body.add_child(spr)
		x += w


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
	var y_off := -hy - float(tex.get_height()) * 0.15
	if height < 40.0:
		y_off = -hy + 2.0
	_tile_cap_row(body, tex, width, y_off)
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

	if _theme == &"winter" or _icy > 0.4:
		_tile_snow_caps(body, width, height)
	elif _theme == &"graveyard" or _theme == &"lunar":
		_tile_graveyard_platform(body, width, height)
	elif _theme == &"desert":
		_tile_desert_platform(body, width, height)
	else:
		_tile_forest_platform(body, width, height)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, height)
	col.shape = shape
	body.add_child(col)
	add_child(body)
	_platforms.append({
		"left": x,
		"right": x + width,
		"top": y - height * 0.5,
		"bottom": y + height * 0.5,
		"w": width,
		"h": height,
		"elevated": height < 40.0,
	})


func _plat_point(plat: Dictionary, t: float, hang: bool = false) -> Vector2:
	var margin := minf(28.0, float(plat["w"]) * 0.25)
	var px := lerpf(float(plat["left"]) + margin, float(plat["right"]) - margin, clampf(t, 0.05, 0.95))
	return Vector2(px, float(plat["bottom"]) if hang else float(plat["top"]))


func _plats_ground() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _platforms:
		if not bool(p["elevated"]):
			out.append(p)
	return out


func _plats_air() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _platforms:
		if bool(p["elevated"]):
			out.append(p)
	return out


func _plats_high() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _platforms:
		if bool(p["elevated"]) and float(p["top"]) < 280.0:
			out.append(p)
	return out


func _tile_snow_caps(body: Node2D, width: float, height: float) -> void:
	var hy := height * 0.5
	var tile_path := "res://assets/sprites/ice_platform/platform_0.png"
	if height < 40.0:
		tile_path = "res://assets/sprites/ice_platform/platform_1.png" if width >= 170.0 \
			else "res://assets/sprites/ice_platform/cube_0.png"
	var tex := load(tile_path) as Texture2D
	if tex == null:
		return
	var y_off := -hy - float(tex.get_height()) * 0.2
	if height < 40.0:
		y_off = -hy + 2.0
	_tile_cap_row(body, tex, width, y_off)
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
	# Compact hitbox (unchanged) — visuals can be larger without scraping lanes
	var wheel_vis := 0.58
	_axle_y = radius * 0.5 * wheel_vis + 8.0
	var wheel_spread := clampf(radius * 0.55, 10.0, 18.0)
	var body_h := radius * 0.9 * wheel_vis + 10.0
	var body_w := wheel_spread * 2.0 + radius * 0.22 + 4.0

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

	# Slightly wider axle so tires sit under the bigger cart body
	var visual_spread := clampf(radius * 0.72, 14.0, 24.0)
	var poly := GameProgress.get_drawn_wheel()
	_wheel_l = _make_drawn_wheel_visual(poly, Vector2(-visual_spread, _axle_y))
	_wheel_r = _make_drawn_wheel_visual(poly, Vector2(visual_spread, _axle_y))
	_wheel_l.scale = Vector2(wheel_vis, wheel_vis)
	_wheel_r.scale = Vector2(wheel_vis, wheel_vis)
	_visual.add_child(_wheel_l)
	_visual.add_child(_wheel_r)

	var cart := Sprite2D.new()
	cart.texture = load("res://assets/sprites/banana_cart.png") as Texture2D
	cart.position = Vector2(0, _axle_y - radius * 0.1 - 6.0)
	var cart_scale_y := clampf(0.16 + radius / 300.0, 0.18, 0.28)
	var cart_scale_x := cart_scale_y * 0.62
	cart.scale = Vector2(cart_scale_x, cart_scale_y)
	cart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cart.z_index = 1
	_visual.add_child(cart)

	var monkey := Sprite2D.new()
	monkey.texture = load("res://assets/sprites/monkey_idle.png") as Texture2D
	monkey.position = Vector2(1, cart.position.y - 14.0)
	monkey.scale = Vector2(0.36, 0.36)
	monkey.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	monkey.z_index = 2
	_visual.add_child(monkey)

	# Hitbox locked to the compact size — independent of cart/monkey visuals
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(body_w, body_h)
	col.shape = shape
	col.position = Vector2(0, _axle_y - body_h * 0.15)
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
	## Hazards always sit on a platform top or hang from a platform underside.
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
		&"grave":
			_pattern_grave()
		&"desert":
			_pattern_desert()
		&"lunar":
			_pattern_lunar()
		&"jungle":
			_pattern_jungle()
		_:
			_pattern_gorge()


func _pattern_gorge() -> void:
	_obs.use_metal_spikes = false
	var grounds := _plats_ground()
	var airs := _plats_air()
	for i in grounds.size():
		var p: Dictionary = grounds[i]
		if i % 2 == 1:
			continue
		match i % 6:
			0:
				_obs.add_spike(_plat_point(p, 0.4), false, 1.05, Color(1.25, 0.3, 0.35))
			2:
				_obs.add_jump_pad(_plat_point(p, 0.35) + Vector2(0, -2), 820.0)
				_obs.add_trap(_plat_point(p, 0.7), &"bear", 1.4)
			4:
				_obs.add_spike_row(_plat_point(p, 0.3), 2, 34.0, false, 1.0, Color(1.25, 0.3, 0.35))
	for i in airs.size():
		var p: Dictionary = airs[i]
		if i % 3 == 0:
			_obs.add_spike(_plat_point(p, 0.5, true), true, 0.95, Color(1.25, 0.3, 0.35))
		elif i % 3 == 1:
			_obs.add_spike(_plat_point(p, 0.55), false, 0.95, Color(1.25, 0.3, 0.35))


func _pattern_tunnel() -> void:
	_obs.use_metal_spikes = true
	var grounds := _plats_ground()
	var highs := _plats_high()
	var airs := _plats_air()
	for i in grounds.size():
		var p: Dictionary = grounds[i]
		if i % 2 == 1:
			continue
		_obs.add_spike_row(_plat_point(p, 0.25), 2, 32.0, false, 0.85, Color(0.85, 0.35, 0.55))
		if i % 4 == 0:
			_obs.add_trap(_plat_point(p, 0.7), &"fire", 1.4)
	for i in highs.size():
		var p: Dictionary = highs[i]
		_obs.add_spike_row(_plat_point(p, 0.3, true), 2, 32.0, true, 0.85, Color(0.85, 0.35, 0.55))
	for i in airs.size():
		var p: Dictionary = airs[i]
		if i % 4 != 0 or float(p["top"]) < 280.0:
			continue
		# Low-lane pads get a solid block hazard sitting on top
		_obs.add_block(_plat_point(p, 0.5) + Vector2(0, -18), 70.0, 28.0, Color(0.25, 0.28, 0.32))


func _pattern_chaos() -> void:
	_obs.use_metal_spikes = false
	var grounds := _plats_ground()
	var airs := _plats_air()
	for i in grounds.size():
		var p: Dictionary = grounds[i]
		if i % 2 == 1:
			continue
		_obs.add_spike_row(_plat_point(p, 0.3), 2, 34.0, false, 0.95, Color(0.9, 0.35, 0.2))
		if i % 3 == 1:
			_obs.add_trap(_plat_point(p, 0.7), &"spike", 1.5)
		if i % 3 == 2:
			_obs.add_jump_pad(_plat_point(p, 0.55) + Vector2(0, -2), 700.0, Color(1.0, 0.7, 0.2))
	for i in airs.size():
		var p: Dictionary = airs[i]
		if i % 2 == 0:
			_obs.add_spike(_plat_point(p, 0.5, true), true, 0.9, Color(0.9, 0.35, 0.2))
		else:
			_obs.add_spike(_plat_point(p, 0.5), false, 0.9, Color(0.9, 0.35, 0.2))
		# Movers between mid/high — spikes ride with them
		if i % 4 == 0 and i + 1 < airs.size():
			var a: Dictionary = airs[i]
			var b: Dictionary = airs[i + 1]
			var mover: Node2D = _obs.add_moving_platform(
				_plat_point(a, 0.5),
				_plat_point(b, 0.5),
				120.0,
				2.0 + float(i % 3) * 0.35,
				Color(0.55, 0.4, 0.22)
			)
			_obs.add_spike(Vector2(0, -14), false, 0.85, Color(0.9, 0.35, 0.2), false, mover)
			_obs.add_spike(Vector2(0, 14), true, 0.85, Color(0.9, 0.35, 0.2), false, mover)


func _pattern_sprint() -> void:
	_obs.use_metal_spikes = false
	var grounds := _plats_ground()
	var airs := _plats_air()
	for i in grounds.size():
		var p: Dictionary = grounds[i]
		match i % 4:
			0:
				_obs.add_spike(_plat_point(p, 0.45), false, 1.0, Color(1.2, 0.25, 0.35))
			1:
				_obs.add_jump_pad(_plat_point(p, 0.5) + Vector2(0, -2), 760.0, Color(1.2, 0.95, 0.3))
			2:
				_obs.add_spike_row(_plat_point(p, 0.3), 2, 32.0, false, 0.95, Color(1.2, 0.25, 0.35))
			3:
				_obs.add_trap(_plat_point(p, 0.55), &"fire", 1.4)
	for i in airs.size():
		if i % 2 != 0:
			continue
		var p: Dictionary = airs[i]
		if i % 4 == 0:
			_obs.add_spike(_plat_point(p, 0.5, true), true, 0.9, Color(1.2, 0.25, 0.35))
		else:
			_obs.add_spike(_plat_point(p, 0.5), false, 0.9, Color(1.2, 0.25, 0.35))


func _pattern_frost() -> void:
	_obs.use_metal_spikes = true
	var grounds := _plats_ground()
	var airs := _plats_air()
	for i in grounds.size():
		var p: Dictionary = grounds[i]
		if i % 2 == 1:
			continue
		_obs.add_spike(_plat_point(p, 0.35), false, 1.05, Color(1.15, 0.35, 0.55))
		match i % 6:
			0:
				_obs.add_jump_pad(_plat_point(p, 0.65) + Vector2(0, -2), 740.0, Color(1.2, 0.95, 0.35))
			2:
				_obs.add_trap(_plat_point(p, 0.65), &"spike", 1.4, Color(0.8, 0.92, 1.1))
	for i in airs.size():
		var p: Dictionary = airs[i]
		if i % 3 == 0:
			_obs.add_spike(_plat_point(p, 0.5, true), true, 0.95, Color(1.15, 0.35, 0.55))
		elif i % 3 == 1:
			_obs.add_spike(_plat_point(p, 0.5), false, 0.95, Color(1.15, 0.35, 0.55))
		if i % 5 == 0 and i + 1 < airs.size():
			var a: Dictionary = airs[i]
			var b: Dictionary = airs[mini(i + 2, airs.size() - 1)]
			var mover: Node2D = _obs.add_moving_platform(
				_plat_point(a, 0.5),
				_plat_point(b, 0.5),
				110.0,
				2.6,
				Color(0.75, 0.88, 0.98)
			)
			_obs.add_trap(Vector2(0, -12), &"spike", 1.2, Color(0.8, 0.92, 1.1), mover)


func _pattern_grave() -> void:
	# Crypt spikes on stone tops + hanging underside traps
	_obs.use_metal_spikes = true
	var grounds := _plats_ground()
	var airs := _plats_air()
	var highs := _plats_high()
	for i in grounds.size():
		var p: Dictionary = grounds[i]
		if i % 2 == 1:
			continue
		match i % 4:
			0:
				_obs.add_spike_row(_plat_point(p, 0.3), 2, 34.0, false, 0.95, Color(0.75, 0.55, 0.9))
			2:
				_obs.add_trap(_plat_point(p, 0.55), &"spike", 1.35, Color(0.85, 0.7, 1.0))
				_obs.add_jump_pad(_plat_point(p, 0.8) + Vector2(0, -2), 760.0, Color(0.7, 0.85, 1.0))
	for i in highs.size():
		_obs.add_spike_row(_plat_point(highs[i], 0.35, true), 2, 30.0, true, 0.9, Color(0.75, 0.55, 0.9))
	for i in airs.size():
		if i % 3 != 1:
			continue
		_obs.add_spike(_plat_point(airs[i], 0.5), false, 0.9, Color(0.75, 0.55, 0.9))


func _pattern_desert() -> void:
	# Wide pads + sparse sand spikes; hanging spikes on high dunes
	_obs.use_metal_spikes = false
	var grounds := _plats_ground()
	var airs := _plats_air()
	for i in grounds.size():
		var p: Dictionary = grounds[i]
		match i % 3:
			0:
				_obs.add_jump_pad(_plat_point(p, 0.45) + Vector2(0, -2), 820.0, Color(1.15, 0.85, 0.35))
			1:
				_obs.add_spike(_plat_point(p, 0.55), false, 1.0, Color(1.2, 0.45, 0.25))
			2:
				_obs.add_trap(_plat_point(p, 0.4), &"bear", 1.35, Color(1.1, 0.9, 0.6))
	for i in airs.size():
		var p: Dictionary = airs[i]
		if i % 4 == 0:
			_obs.add_spike(_plat_point(p, 0.5, true), true, 0.9, Color(1.2, 0.45, 0.25))
		elif i % 4 == 2:
			_obs.add_spike(_plat_point(p, 0.5), false, 0.9, Color(1.2, 0.45, 0.25))


func _pattern_lunar() -> void:
	# Low-grav feel via pads; compact spike tunnels on mid/high
	_obs.use_metal_spikes = true
	var grounds := _plats_ground()
	var airs := _plats_air()
	var highs := _plats_high()
	for i in grounds.size():
		var p: Dictionary = grounds[i]
		if i % 2 == 0:
			_obs.add_jump_pad(_plat_point(p, 0.5) + Vector2(0, -2), 860.0, Color(0.75, 0.95, 1.15))
		else:
			_obs.add_spike(_plat_point(p, 0.4), false, 0.9, Color(0.7, 0.85, 1.1))
	for i in highs.size():
		if i % 2 == 0:
			_obs.add_spike_row(_plat_point(highs[i], 0.3, true), 2, 28.0, true, 0.85, Color(0.7, 0.85, 1.1))
	for i in airs.size():
		if i % 3 == 0:
			_obs.add_trap(_plat_point(airs[i], 0.5), &"fire", 1.2, Color(0.85, 0.95, 1.15))


func _pattern_jungle() -> void:
	# Sparse wood spikes + pads — the tiger is the main threat
	_obs.use_metal_spikes = false
	var grounds := _plats_ground()
	var airs := _plats_air()
	for i in grounds.size():
		var p: Dictionary = grounds[i]
		if i % 3 == 0:
			_obs.add_spike(_plat_point(p, 0.45), false, 0.9, Color(1.15, 0.4, 0.25))
		elif i % 3 == 1:
			_obs.add_jump_pad(_plat_point(p, 0.5) + Vector2(0, -2), 780.0, Color(0.55, 0.9, 0.35))
		else:
			_obs.add_trap(_plat_point(p, 0.55), &"bear", 1.2, Color(0.9, 0.75, 0.4))
	for i in airs.size():
		if i % 4 == 0:
			_obs.add_spike(_plat_point(airs[i], 0.5, true), true, 0.85, Color(1.15, 0.4, 0.25))


func _spawn_chase_tiger() -> void:
	if _wheel == null:
		return
	var script: Script = load("res://scripts/chase_tiger.gd") as Script
	_tiger = Area2D.new()
	_tiger.set_script(script)
	_tiger.global_position = _spawn + Vector2(-220.0, 20.0)
	add_child(_tiger)
	var speed := float(_level.get("tiger_speed", 155.0))
	_tiger.call("setup", _wheel, _on_hazard, speed)


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
		# If the cart outruns the trail pan, accelerate scroll so they aren't braked.
		var catch_up := _wheel.global_position.x - 480.0
		if catch_up > _scroll_x:
			_scroll_x = minf(catch_up, scroll_cap)
	var cam_y := lerpf(_camera.global_position.y, clampf(_wheel.global_position.y, 280.0, 480.0), 0.08)
	_camera.global_position = Vector2(_scroll_x, cam_y)
	if _snow:
		_snow.global_position = Vector2(_scroll_x, cam_y - 380.0)

	var right_limit := _scroll_x + 560.0
	if _wheel.global_position.x > right_limit:
		_wheel.global_position.x = right_limit
		# Only kill forward speed at the hard end of the course (scroll already capped).
		if _scroll_x >= scroll_cap - 0.5:
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
		if _tiger != null and is_instance_valid(_tiger) and _tiger.monitoring:
			# Prefer a tiger-specific line when the chase is active
			var near_tiger := _wheel.global_position.distance_to(_tiger.global_position) < 70.0
			if near_tiger:
				_respawn("The tiger got you! Keep moving — it never stops.")
				return
		_respawn("Spike / trap! Redesign the wheel if this trail hates your shape.")


func _control_hint() -> String:
	return "%s · Arrows move · Space jump · keep up!\nEsc/Q exit · R retry · redraw at camp if needed" % str(
		_level.get("title", "Trail")
	)


func _respawn(msg: String) -> void:
	_dead = true
	_hint.text = msg
	var boom_at := _wheel.global_position
	_wheel.velocity = Vector2.ZERO
	if _tiger != null and is_instance_valid(_tiger):
		_tiger.call("set_active", false)
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
	if _tiger != null and is_instance_valid(_tiger):
		_tiger.global_position = _spawn + Vector2(-220.0, 20.0)
		_tiger.call("set_active", true)
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
