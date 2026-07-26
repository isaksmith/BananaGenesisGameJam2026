extends Node2D

## Themed Mario-style course. Drawn wheel size/roundness changes what you can clear.

const WheelObstaclesScript := preload("res://scripts/wheel_obstacles.gd")
const LEVEL_MUSIC := "res://assets/audio/Swing_Through_the_Canopy.mp3"
const SFX_JUMP := "res://assets/audio/sfx/sfx_jump.ogg"
const SFX_DIE := "res://assets/audio/sfx/sfx_hurt.ogg"
const TRAIL_MUSIC := {
	&"gap_gorge": "res://assets/audio/trails/gap-gorge-song-1.mp3",
	&"needle_pass": "res://assets/audio/trails/needle-pass-song-1.mp3",
	&"wobble_ridge": "res://assets/audio/trails/wobble-ridge-song-1.mp3",
	&"sprint_delta": "res://assets/audio/trails/spring-delta-song.mp3",
	&"frost_fjord": "res://assets/audio/trails/frosted-fjord-song1.mp3",
	&"moon_graveyard": "res://assets/audio/trails/moon-graveyard-song.mp3",
	&"desert_sky": "res://assets/audio/trails/desert-sky-song.mp3",
	&"lunar_void": "res://assets/audio/trails/lunar-void-song.mp3",
	&"tiger_chase": "res://assets/audio/trails/tiger-trail-song.mp3",
}

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
var _tumbleweeds_enabled: bool = false
var _tumble_spawn_t: float = 0.0
var _tumble_spawn_cd: float = 2.8
var _hop_mushrooms_enabled: bool = false
var _mushroom_spawn_t: float = 0.0
var _mushroom_spawn_cd: float = 2.4
var _trip_rect: ColorRect = null
var _trip_rect_b: ColorRect = null
var _trip_intensity: float = 0.0
var _trip_hold: float = 0.0
var _trip_hue: float = 0.0

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
	_tumbleweeds_enabled = _theme == &"desert" or bool(_level.get("tumbleweeds", false))
	if _tumbleweeds_enabled:
		_tumble_spawn_t = 1.2
		_tumble_spawn_cd = float(_level.get("tumbleweed_interval", 2.8))
	_hop_mushrooms_enabled = _theme == &"mushroom" or bool(_level.get("hop_mushrooms", false))
	if _hop_mushrooms_enabled:
		_mushroom_spawn_t = 1.0
		_mushroom_spawn_cd = float(_level.get("mushroom_interval", 2.4))
	_build_camera()
	_build_ui()
	var title := str(_level.get("title", "Trail"))
	var tip := "pads launch · spikes kill"
	if bool(_level.get("chase_tiger", false)):
		tip = "tiger chases — don't get caught · spikes kill"
	elif _hop_mushrooms_enabled:
		tip = "hopping shrooms chase you — bump one for a rainbow trip · spikes kill"
	elif _tumbleweeds_enabled:
		tip = "tumbleweeds roll across ledges and fall into gaps — jump them · spikes kill"
	_hint.text = "%s · %s\n%s\nArrows · Space · Esc/Q · R" % [
		title,
		tip,
		GameProgress.wheel_fit_note(),
	]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play_level_music()


func _play_level_music() -> void:
	# Replaces hub music (which kept playing during wheel design).
	var music_path := str(TRAIL_MUSIC.get(GameProgress.selected_wheel_level, LEVEL_MUSIC))
	AudioSettings.play_music(music_path)


func _play_sfx(path: String, volume_db: float = 0.0) -> void:
	GameAudio.play(self, path, false, volume_db)


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
	_effective_jump *= float(_level.get("jump_scale", 1.0))
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
		&"mushroom":
			_build_parallax_backdrop("res://assets/sprites/parallax_mushroom/", [
				"bg_night.png", "bg_far.png", "bg_mid.png", "bg_near.png"
			], [0.55, 0.7, 0.85, 0.95], [2400.0, 2100.0, 1800.0, 1500.0])
		_:
			_build_forest_platform_backdrop()

	var rng := RandomNumberGenerator.new()
	rng.seed = int(_level.get("seed", 26))
	var gap_min := float(_level.get("gap_min", 90.0))
	var gap_max := float(_level.get("gap_max", 170.0))
	var stretch_min := float(_level.get("stretch_min", 420.0))
	var stretch_max := float(_level.get("stretch_max", 720.0))

	# Leave a solid finish runway so every lane can always roll through the line.
	var finish_runway_start := course_length - 520.0
	var x := 0.0
	while x < finish_runway_start:
		var stretch := rng.randf_range(stretch_min, stretch_max)
		if x + stretch > finish_runway_start:
			stretch = finish_runway_start - x
		# Tall textured foundation: top at y=520, extends well past the screen bottom.
		_add_ground(x, 740.0, stretch, 440.0)
		x += stretch
		if x < finish_runway_start - 200.0:
			x += rng.randf_range(gap_min, gap_max)
	# Guaranteed ground under / past the finish line.
	_add_ground(finish_runway_start, 740.0, course_length - finish_runway_start + 400.0, 440.0)

	# Three runnable levels: low / mid / high pads (floor stretches = ground).
	# Vertical gaps (~150px+) leave room for the cart to pass between lanes.
	var lane_ys: Array = [
		float(_level.get("lane_low_y", 455.0)),
		float(_level.get("lane_mid_y", 335.0)),
		float(_level.get("lane_high_y", 210.0)),
	]
	var spacing := float(_level.get("platform_spacing", 540.0))
	var platform_count := int(_level.get("platform_count", 36))
	var pattern := StringName(_level.get("pattern", &"gorge"))
	if pattern == &"sprint":
		# Explicit three-lane columns: low / mid / high with room to pass between.
		var columns := maxi(platform_count / 3, 8)
		for i in columns:
			var px := 420.0 + float(i) * spacing + rng.randf_range(-20.0, 30.0)
			if px > course_length - 200.0:
				break
			for lane_i in 3:
				# Slight X stagger so stacked lanes don't read as one thick block.
				var ox := float(lane_i - 1) * 36.0
				var py: float = float(lane_ys[lane_i])
				_add_ground(px + ox, py, rng.randf_range(130.0, 190.0), 22.0)
	else:
		for i in platform_count:
			var px := 420.0 + float(i) * spacing + rng.randf_range(-50, 70)
			if px > course_length - 200.0:
				break
			var lane_i := i % 3
			var py: float = float(lane_ys[lane_i]) + rng.randf_range(-10.0, 10.0)
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
		var rock_pos := Vector2(px, rng.randf_range(cy0, cy1))
		var rock := _add_theme_floating_rock(rock_pos, i)
		_add_hover(rock, rng.randf_range(6.0, 12.0), rng.randf_range(1.9, 3.1), rng.randf())

	match _theme:
		&"winter":
			_spawn_winter_trees()
		&"graveyard":
			_spawn_graveyard_decor(rng)
		&"desert":
			_spawn_desert_tumbleweed_props(rng)
		&"mushroom":
			_spawn_mushroom_decor(rng)
		&"lunar":
			pass
		_:
			_spawn_toffee_track_decor(rng)


const BG_COVER_H := 1100.0
const BG_CENTER_Y := 360.0


func _scale_backdrop_sprite(spr: Sprite2D, tex: Texture2D) -> void:
	# Overscan past 720 so vertical camera pan never shows empty bands.
	var s := BG_COVER_H / maxf(float(tex.get_height()), 1.0)
	spr.scale = Vector2(s, s)


func _build_forest_platform_backdrop() -> void:
	# ForestPlatform bg layers are mid-trunk crops (flat tops). Build a real canopy
	# parallax from full tree sprites instead.
	var sky := load("res://assets/sprites/forest/sky.png") as Texture2D
	if sky != null:
		var spacing := 1800.0 * (BG_COVER_H / 720.0)
		for i in 10:
			var layer := Sprite2D.new()
			layer.z_index = -18
			layer.texture = sky
			_scale_backdrop_sprite(layer, sky)
			layer.position = Vector2(float(i) * spacing, BG_CENTER_Y)
			layer.modulate = Color(1, 1, 1, 0.85)
			layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(layer)

	var far_trees: Array[String] = [
		"res://assets/sprites/forest/single_tree_0.png",
		"res://assets/sprites/forest/single_tree_1.png",
		"res://assets/sprites/forest_tree_0.png",
		"res://assets/sprites/forest_tree_1.png",
	]
	var near_trees: Array[String] = [
		"res://assets/sprites/forest/single_tree_0.png",
		"res://assets/sprites/forest/single_tree_1.png",
		"res://assets/sprites/forest/single_tree_2.png",
		"res://assets/sprites/forest_tree.png",
		"res://assets/sprites/forest_tree_2.png",
		"res://assets/sprites/forest_tree_3.png",
	]
	_spawn_forest_canopy_row(far_trees, -16, 140.0, 0.95, 1.35, Color(0.35, 0.45, 0.4, 0.55), 560.0)
	_spawn_forest_canopy_row(near_trees, -14, 105.0, 1.15, 1.75, Color(0.55, 0.7, 0.5, 0.78), 575.0)


func _spawn_forest_canopy_row(
	paths: Array[String],
	z: int,
	spacing: float,
	scale_min: float,
	scale_max: float,
	tint: Color,
	ground_y: float
) -> void:
	var course := float(_level.get("course_length", 7800.0))
	var x := -80.0
	var i := 0
	while x < course + 400.0:
		var path: String = paths[i % paths.size()]
		var tex := load(path) as Texture2D
		if tex != null:
			var spr := Sprite2D.new()
			spr.z_index = z
			spr.texture = tex
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.centered = true
			var s := lerpf(scale_min, scale_max, float((i * 37) % 10) / 9.0)
			spr.scale = Vector2(s, s)
			# Plant at the trunk base so the full canopy stays on-screen.
			var half_h := float(tex.get_height()) * s * 0.5
			spr.position = Vector2(x, ground_y - half_h)
			spr.modulate = tint
			if i % 2 == 0:
				spr.flip_h = true
			add_child(spr)
		x += spacing + float((i * 17) % 40)
		i += 1


func _build_graveyard_backdrop() -> void:
	var far := load("res://assets/sprites/moon_graveyard/Background_0.png") as Texture2D
	var mid := load("res://assets/sprites/moon_graveyard/Background_1.png") as Texture2D
	var grass := load("res://assets/sprites/moon_graveyard/Grass_background_1.png") as Texture2D
	var grass2 := load("res://assets/sprites/moon_graveyard/Grass_background_2.png") as Texture2D
	for i in 16:
		for pair in [
			[far, -18, 1100.0, 0.0, Color(1, 1, 1, 0.95)],
			[mid, -17, 1100.0, 160.0, Color(1, 1, 1, 0.88)],
			[grass, -16, 640.0, 40.0, Color(1, 1, 1, 0.92)],
			[grass2, -15, 640.0, 340.0, Color(1, 1, 1, 0.95)],
		]:
			var tex: Texture2D = pair[0]
			if tex == null:
				continue
			var spacing: float = float(pair[2])
			var spr := Sprite2D.new()
			spr.z_index = int(pair[1])
			spr.texture = tex
			_scale_backdrop_sprite(spr, tex)
			spr.position = Vector2(float(i) * spacing + float(pair[3]), BG_CENTER_Y)
			spr.modulate = pair[4]
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(spr)


func _build_parallax_backdrop(folder: String, files: Array, alphas: Array, spacings: Array) -> void:
	for layer_i in files.size():
		var tex := load(folder + String(files[layer_i])) as Texture2D
		if tex == null:
			continue
		var base_spacing: float = float(spacings[layer_i]) if layer_i < spacings.size() else 2000.0
		# Keep horizontal coverage after vertical overscan scaling.
		var spacing := base_spacing * (BG_COVER_H / 720.0)
		var alpha: float = float(alphas[layer_i]) if layer_i < alphas.size() else 0.8
		var tiles := maxi(6, int(ceil((course_length + 1600.0) / spacing)) + 1)
		for i in tiles:
			var spr := Sprite2D.new()
			spr.z_index = -18 + layer_i
			spr.texture = tex
			_scale_backdrop_sprite(spr, tex)
			spr.position = Vector2(float(i) * spacing, BG_CENTER_Y)
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
		_tile_ground_fill(body, width, height)


func _tile_desert_platform(body: Node2D, width: float, height: float) -> void:
	# Reuse forest platform caps, tinted sandy, over desert fill.
	_tile_forest_platform(body, width, height)
	for child in body.get_children():
		if child is Sprite2D:
			(child as Sprite2D).modulate = Color(1.15, 0.95, 0.7, 1)


func _tile_mushroom_platform(body: Node2D, width: float, height: float) -> void:
	# platform.png is a 1440x480 showcase image — not a tile. Reuse forest caps
	# with a soft mystic tint so ledges read like the other trails.
	_tile_forest_platform(body, width, height)
	for child in body.get_children():
		if child is Sprite2D:
			(child as Sprite2D).modulate = Color(0.92, 0.8, 1.08, 1)


func _spawn_mushroom_decor(rng: RandomNumberGenerator) -> void:
	var grounds := _plats_ground()
	var airs := _plats_air()
	var plats: Array[Dictionary] = []
	plats.append_array(grounds)
	plats.append_array(airs)
	if plats.is_empty():
		return
	plats.shuffle()
	var tree_tex := load("res://assets/sprites/mushroom/tree.png") as Texture2D
	var static_mush := [
		"res://assets/sprites/mushroom/Mushrooms64x65.png",
		"res://assets/sprites/mushroom/Mushrooms64x68.png",
		"res://assets/sprites/mushroom/Mushrooms64x72.png",
		"res://assets/sprites/mushroom/Mushrooms64x76.png",
		"res://assets/sprites/mushroom/Mushrooms64x80.png",
	]
	var n := mini(plats.size(), 28)
	for i in n:
		var p: Dictionary = plats[i]
		if i % 5 == 0 and tree_tex != null:
			var spr := Sprite2D.new()
			spr.texture = tree_tex
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var s := rng.randf_range(0.35, 0.55)
			spr.scale = Vector2(s, s)
			spr.z_index = -1
			spr.position = _plat_point(p, rng.randf_range(0.2, 0.8)) + Vector2(0, -2)
			spr.offset = Vector2(0, -float(tree_tex.get_height()) * 0.5)
			add_child(spr)
		else:
			var path: String = static_mush[rng.randi() % static_mush.size()]
			var tex := load(path) as Texture2D
			if tex == null:
				continue
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var s := rng.randf_range(0.7, 1.05)
			spr.scale = Vector2(s, s)
			spr.z_index = 1
			spr.position = _plat_point(p, rng.randf_range(0.15, 0.85)) + Vector2(0, -2)
			spr.offset = Vector2(0, -float(tex.get_height()) * 0.5)
			add_child(spr)


func _spawn_graveyard_decor(rng: RandomNumberGenerator) -> void:
	# Sit statues / brush on platform tops — never free-float in midair.
	var plats := _platforms.duplicate()
	if plats.is_empty():
		return
	plats.shuffle()
	var count := mini(18, plats.size())
	for i in count:
		var p: Dictionary = plats[i]
		var t := rng.randf_range(0.18, 0.82)
		# Keep clear of platform edges so feet stay on the stone.
		t = clampf(t, 0.2, 0.8)
		var on_top := _plat_point(p, t, false)
		if i % 3 == 0:
			_add_platform_prop(
				on_top,
				"res://assets/sprites/moon_graveyard/Salt.png",
				0.42,
				Rect2()
			)
		else:
			# brush.png is a 2-row sheet — use one bush variant only.
			var row := 0 if i % 2 == 0 else 1
			_add_platform_prop(
				on_top,
				"res://assets/sprites/moon_graveyard/brush.png",
				0.55,
				Rect2(0, row * 96, 224, 96)
			)


func _add_platform_prop(feet: Vector2, tex_path: String, scale: float, region: Rect2 = Rect2()) -> void:
	var tex := load(tex_path) as Texture2D
	if tex == null:
		return
	var body := StaticBody2D.new()
	body.position = feet
	body.collision_layer = 4
	body.collision_mask = 0
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(scale, scale)
	var tex_h := float(tex.get_height())
	var tex_w := float(tex.get_width())
	if region.size != Vector2.ZERO:
		sprite.region_enabled = true
		sprite.region_rect = region
		tex_w = region.size.x
		tex_h = region.size.y
	# Anchor the visual bottom on the platform top.
	sprite.offset = Vector2(0, -tex_h * 0.5)
	body.add_child(sprite)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	var tw := tex_w * scale
	var th := tex_h * scale
	shape.size = Vector2(tw * 0.55, th * 0.45)
	col.shape = shape
	col.position = Vector2(0, -th * 0.35)
	body.add_child(col)
	add_child(body)


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
	if height >= 40.0:
		_tile_ground_fill(body, width, height)


func _build_winter_backdrop() -> void:
	# IcePlatform pack fjord sky / mountains.
	var far := load("res://assets/sprites/ice_platform/bg_layer_0.png") as Texture2D
	var mid := load("res://assets/sprites/ice_platform/bg_layer_1.png") as Texture2D
	var near := load("res://assets/sprites/ice_platform/bg_wide.png") as Texture2D
	var spacing := 1800.0 * (BG_COVER_H / 720.0)
	for i in 12:
		if far != null or near != null:
			var layer_far := Sprite2D.new()
			layer_far.z_index = -16
			var far_tex: Texture2D = far if far != null else near
			layer_far.texture = far_tex
			_scale_backdrop_sprite(layer_far, far_tex)
			layer_far.position = Vector2(float(i) * spacing, BG_CENTER_Y)
			layer_far.modulate = Color(1, 1, 1, 0.65)
			layer_far.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(layer_far)
		var mid_tex: Texture2D = mid if mid != null else near
		if mid_tex != null:
			var layer_mid := Sprite2D.new()
			layer_mid.z_index = -15
			layer_mid.texture = mid_tex
			_scale_backdrop_sprite(layer_mid, mid_tex)
			layer_mid.position = Vector2(float(i) * spacing + 160.0, BG_CENTER_Y)
			layer_mid.modulate = Color(1, 1, 1, 0.8)
			layer_mid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(layer_mid)
		if near != null:
			var layer_near := Sprite2D.new()
			layer_near.z_index = -14
			layer_near.texture = near
			_scale_backdrop_sprite(layer_near, near)
			layer_near.position = Vector2(float(i) * spacing, BG_CENTER_Y)
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
	# Trees stay readable scenery. Ice cubes / pillars / rocks reuse the same
	# platform tiles as landable pads, so at full opacity they look solid —
	# keep those as faded background silhouettes only.
	var pines := [
		"res://assets/sprites/ice_platform/tree_0.png",
		"res://assets/sprites/ice_platform/pillar_1.png",
		"res://assets/sprites/ice_platform/cube_0.png",
		"res://assets/sprites/toffee/ice_rock.png",
		"res://assets/sprites/ice_platform/tree_1.png",
	]
	for i in 48:
		var tree := Sprite2D.new()
		tree.texture = load(pines[i % pines.size()]) as Texture2D
		tree.position = Vector2(160 + i * 180.0, 470)
		var path_str := str(pines[i % pines.size()])
		var is_block := "cube" in path_str or "pillar" in path_str or "ice_rock" in path_str
		var s := 1.25
		if "pillar" in path_str:
			s = 1.45
		if "cube" in path_str:
			s = 1.6
			tree.position.y = 520
		elif "ice_rock" in path_str:
			s = 1.15
			tree.position.y = 500
		tree.scale = Vector2(s, s)
		tree.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if is_block:
			tree.z_index = -9
			tree.modulate = Color(0.82, 0.9, 1.0, 0.32)
		else:
			tree.z_index = -5
			tree.modulate = Color(1, 1, 1, 0.92)
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
			# Distant silhouettes only — full bright tree icons read as UI stickers.
			trees = [
				"res://assets/sprites/toffee/fern.png",
				"res://assets/sprites/toffee/rock_grey.png",
				"res://assets/sprites/toffee/rock_brown.png",
				"res://assets/sprites/forest_platform/trunk_2.png",
			]
		&"gorge":
			# Full canopy trees — forest_platform trunks are top-less mid cuts.
			trees = [
				"res://assets/sprites/forest/single_tree_0.png",
				"res://assets/sprites/forest/single_tree_1.png",
				"res://assets/sprites/forest_tree_1.png",
				"res://assets/sprites/toffee/tree_pine_warm.png",
				"res://assets/sprites/toffee/tree_birch.png",
			]
	for i in 40:
		var prop := Sprite2D.new()
		prop.z_index = -5
		var path_str := str(trees[i % trees.size()])
		var tex := load(path_str) as Texture2D
		prop.texture = tex
		prop.position = Vector2(200 + i * 220.0, 480)
		var s := 1.05
		if "trunk" in path_str:
			s = 1.4
			prop.position.y = 430
		elif pattern == &"gorge":
			s = 1.35 if "single_tree" in path_str or "forest_tree" in path_str else 1.15
			if tex != null:
				prop.position.y = 555.0 - float(tex.get_height()) * s * 0.5
			prop.z_index = -6
		elif pattern == &"chaos":
			s = 1.35
		elif pattern == &"sprint":
			s = 0.85 if "fern" in path_str else 0.7
			if "trunk" in path_str:
				s = 1.1
				prop.position.y = 500
			prop.z_index = -8
		prop.scale = Vector2(s, s)
		if pattern == &"sprint":
			# Push props into the background as muted silhouettes.
			prop.modulate = Color(0.28, 0.36, 0.3, 0.45)
		else:
			prop.modulate = Color(1, 1, 1, 0.92)
		prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if i % 2 == 0:
			prop.flip_h = true
		add_child(prop)
		if pattern == &"gorge":
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
	# Dark underlay; tall bottom blocks get a real tile fill on top of this.
	visual.color = Color(_ground_color.r * 0.45, _ground_color.g * 0.4, _ground_color.b * 0.35, 1)
	visual.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)
	])
	visual.z_index = -2
	body.add_child(visual)

	if _theme == &"winter" or _icy > 0.4:
		_tile_snow_caps(body, width, height)
	elif _theme == &"graveyard" or _theme == &"lunar":
		_tile_graveyard_platform(body, width, height)
	elif _theme == &"desert":
		_tile_desert_platform(body, width, height)
	elif _theme == &"mushroom":
		_tile_mushroom_platform(body, width, height)
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
		_tile_ground_fill(body, width, height)


func _tile_ground_fill(body: Node2D, width: float, height: float) -> void:
	## Textured foundation under the grass/snow/stone caps (bottom runway block).
	var path := "res://assets/sprites/ground_dirt_fill.png"
	var tint := Color(1, 1, 1, 1)
	match _theme:
		&"winter":
			path = "res://assets/sprites/ice_platform/cube_1.png"
			tint = Color(0.92, 0.97, 1.0, 1)
		&"graveyard":
			path = "res://assets/sprites/toffee/rock_grey.png"
			tint = Color(0.75, 0.72, 0.7, 1)
		&"lunar":
			path = "res://assets/sprites/toffee/rock_grey_b.png"
			tint = Color(0.7, 0.72, 0.85, 1)
		&"desert":
			path = "res://assets/sprites/ground_dirt_fill.png"
			tint = Color(1.2, 1.0, 0.72, 1)
		&"mushroom":
			path = "res://assets/sprites/ground_dirt_fill.png"
			tint = Color(0.95, 0.88, 1.0, 1)
		_:
			path = "res://assets/sprites/ground_dirt_fill.png"
			tint = Color(1.0, 0.95, 0.85, 1)
	var tex := load(path) as Texture2D
	if tex == null:
		return
	_tile_fill_grid(body, width, height, tex, tint)


func _tile_fill_grid(body: Node2D, width: float, height: float, tex: Texture2D, tint: Color) -> void:
	var tile_w := float(tex.get_width())
	var tile_h := float(tex.get_height())
	if tile_w < 1.0 or tile_h < 1.0:
		return
	# Scale so a few rows cover the tall bottom block without looking tiny.
	var s := clampf(height / (tile_h * 2.4), 0.85, 2.2)
	var step_x := tile_w * s
	var step_y := tile_h * s
	var left := -width * 0.5
	var top := -height * 0.5 + 6.0
	var bottom := height * 0.5
	var y := top
	while y < bottom - 0.5:
		var row_h := minf(step_y, bottom - y)
		var x := left
		while x < left + width - 0.5:
			var cell_w := minf(step_x, left + width - x)
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.modulate = tint
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.z_index = -1
			if cell_w < step_x - 0.5 or row_h < step_y - 0.5:
				spr.region_enabled = true
				var rw := tile_w * (cell_w / step_x)
				var rh := tile_h * (row_h / step_y)
				spr.region_rect = Rect2(0, 0, rw, rh)
				spr.scale = Vector2(s, s)
				spr.position = Vector2(x + cell_w * 0.5, y + row_h * 0.5)
			else:
				spr.scale = Vector2(s, s)
				spr.position = Vector2(x + step_x * 0.5, y + step_y * 0.5)
			body.add_child(spr)
			x += step_x
		y += step_y


## Gentle vertical bob for floating props. Returns immediately for null nodes.
func _add_hover(node: Node2D, amplitude: float = 8.0, period: float = 2.4, phase: float = 0.0) -> void:
	if node == null or not is_instance_valid(node):
		return
	var base_y := node.position.y
	var tw := create_tween()
	tw.set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Phase offset keeps a row of rocks from bobbing in lockstep.
	if phase > 0.01:
		tw.tween_interval(period * phase * 0.5)
	tw.tween_property(node, "position:y", base_y - amplitude, period * 0.5)
	tw.tween_property(node, "position:y", base_y, period * 0.5)


## karsiori Rock Pile 8 BIG — colors matched to trail themes.
func _theme_floating_rock_paths() -> Array[String]:
	match _theme:
		&"winter":
			return [
				"res://assets/sprites/rock_piles/pile8_white.png",
				"res://assets/sprites/rock_piles/pile8_azure.png",
			]
		&"desert":
			return [
				"res://assets/sprites/rock_piles/pile8_beige.png",
				"res://assets/sprites/rock_piles/pile8_orange.png",
			]
		&"graveyard":
			return [
				"res://assets/sprites/rock_piles/pile8_silver.png",
				"res://assets/sprites/rock_piles/pile8_white.png",
			]
		&"lunar":
			return [
				"res://assets/sprites/rock_piles/pile8_azure.png",
				"res://assets/sprites/rock_piles/pile8_silver.png",
			]
		&"mushroom":
			return [
				"res://assets/sprites/rock_piles/pile8_silver.png",
				"res://assets/sprites/rock_piles/pile8_mossy.png",
			]
		_:
			# Forest / tiger jungle trails
			return [
				"res://assets/sprites/rock_piles/pile8_mossy.png",
				"res://assets/sprites/rock_piles/pile8_beige.png",
			]


func _add_theme_floating_rock(pos: Vector2, variant: int = 0) -> Node2D:
	var paths := _theme_floating_rock_paths()
	var path := paths[variant % paths.size()]
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 4
	var tex := load(path) as Texture2D
	if tex == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			tex = ImageTexture.create_from_image(img)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	# Pile 8 is 60x40 — scale up so it reads as a floating boulder.
	var scale := 2.2
	sprite.scale = Vector2(scale, scale)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if tex:
		sprite.offset = Vector2(0, -float(tex.get_height()) * 0.35)
	body.add_child(sprite)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	var tw := float(tex.get_width()) * scale if tex else 120.0
	var th := float(tex.get_height()) * scale if tex else 80.0
	shape.size = Vector2(tw * 0.7, th * 0.5)
	col.shape = shape
	col.position = Vector2(0, -th * 0.2)
	body.add_child(col)
	add_child(body)
	return body


func _add_rock(pos: Vector2, deadly: bool = false, variant: int = -1) -> Node2D:
	if _icy > 0.4:
		var snow_paths := [
			"res://assets/sprites/ice_platform/cube_1.png",
			"res://assets/sprites/ice_platform/cube_2.png",
			"res://assets/sprites/ice_platform/pillar_2.png",
			"res://assets/sprites/toffee/ice_rock.png",
		]
		var idx := variant if variant >= 0 else int(absf(pos.x))
		return _add_snow_prop(pos, snow_paths[idx % snow_paths.size()], 1.35)

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
	return body


func _add_snow_prop(pos: Vector2, tex_path: String, scale: float = 1.4) -> Node2D:
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
	return body


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

	# Banana chassis: wheels bolted underneath, monkey riding on top.
	var visual_spread := clampf(radius * 0.72, 14.0, 24.0)
	var poly := GameProgress.get_drawn_wheel()

	# Top of the drawn tire, so the banana can rest right on the axle line.
	var poly_min_y := 0.0
	for p in poly:
		poly_min_y = minf(poly_min_y, p.y)
	var wheel_top := _axle_y + poly_min_y * wheel_vis

	_wheel_l = _make_drawn_wheel_visual(poly, Vector2(-visual_spread, _axle_y))
	_wheel_r = _make_drawn_wheel_visual(poly, Vector2(visual_spread, _axle_y))
	_wheel_l.scale = Vector2(wheel_vis, wheel_vis)
	_wheel_r.scale = Vector2(wheel_vis, wheel_vis)
	_wheel_l.z_index = 0
	_wheel_r.z_index = 0
	_visual.add_child(_wheel_l)
	_visual.add_child(_wheel_r)

	var cart := Sprite2D.new()
	cart.name = "BananaBody"
	cart.texture = load("res://assets/sprites/banana.png") as Texture2D
	var cart_scale := clampf(1.05 + radius / 180.0, 1.15, 1.65)
	# Flip so the stem points left / tip leads right (forward).
	cart.scale = Vector2(-cart_scale, cart_scale * 0.92)
	cart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# banana.png art occupies y 7..57 of a 64px canvas → 25px half-height.
	var banana_half := 25.0 * absf(cart.scale.y)
	cart.position = Vector2(0, wheel_top + 8.0 - banana_half)
	cart.z_index = 1
	_visual.add_child(cart)

	var monkey := Sprite2D.new()
	monkey.texture = load("res://assets/sprites/monkey_idle.png") as Texture2D
	# Visual-only size boost — collision stays compact (body_w / body_h above).
	monkey.scale = Vector2(1.05, 1.05)
	# monkey_idle art sits low in its canvas: content bottom is +48px from origin.
	# Place feet just into the banana's top curve so the monkey reads as seated.
	var banana_top := cart.position.y - banana_half
	monkey.position = Vector2(2, banana_top + 42.0 - 48.0 * monkey.scale.y)
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
	if poly.size() < 3:
		return hub

	# Dark "tire tread" underlay — slightly inflated so it reads as a rim.
	var tread := Polygon2D.new()
	tread.z_index = -1
	tread.color = Color(0.14, 0.1, 0.07, 1)
	tread.polygon = _inflate_poly(poly, 3.2)
	hub.add_child(tread)

	# Wood-plank wheel face.
	var fill := Polygon2D.new()
	fill.color = Color(1.0, 0.92, 0.78, 1)
	fill.polygon = poly
	var wood := load("res://assets/sprites/wood_planks.png") as Texture2D
	if wood == null:
		wood = load("res://assets/sprites/ui_wood.png") as Texture2D
	if wood != null:
		fill.texture = wood
		fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		fill.uv = _poly_uvs(poly, wood.get_size())
	else:
		fill.color = Color(0.72, 0.5, 0.26, 1)
	hub.add_child(fill)

	# Inner wood grain ring (carved rim).
	var rim := Line2D.new()
	rim.width = 4.5
	rim.default_color = Color(0.38, 0.22, 0.1, 0.95)
	rim.closed = true
	rim.joint_mode = Line2D.LINE_JOINT_ROUND
	rim.begin_cap_mode = Line2D.LINE_CAP_ROUND
	rim.end_cap_mode = Line2D.LINE_CAP_ROUND
	for p in poly:
		rim.add_point(p)
	hub.add_child(rim)

	# Outer tire edge.
	var outline := Line2D.new()
	outline.width = 2.4
	outline.default_color = Color(0.08, 0.05, 0.03, 1)
	outline.closed = true
	for p in poly:
		outline.add_point(p)
	hub.add_child(outline)

	# Axle hub — nails the "wooden wheel" look.
	var axle_dark := Polygon2D.new()
	axle_dark.color = Color(0.22, 0.12, 0.06, 1)
	axle_dark.polygon = _circle_poly(7.5, 12)
	hub.add_child(axle_dark)
	var axle := Polygon2D.new()
	axle.color = Color(0.55, 0.36, 0.16, 1)
	axle.polygon = _circle_poly(4.5, 12)
	hub.add_child(axle)
	return hub


func _inflate_poly(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	if n < 3:
		return poly
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= float(n)
	for p in poly:
		var d := p - c
		if d.length_squared() < 0.001:
			out.append(p)
		else:
			out.append(c + d.normalized() * (d.length() + amount))
	return out


func _poly_uvs(poly: PackedVector2Array, tex_size: Vector2) -> PackedVector2Array:
	var min_v := poly[0]
	var max_v := poly[0]
	for p in poly:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	var size := (max_v - min_v)
	size.x = maxf(size.x, 1.0)
	size.y = maxf(size.y, 1.0)
	var uvs := PackedVector2Array()
	# Tile the plank texture across the wheel face.
	var tile := Vector2(maxf(tex_size.x, 1.0), maxf(tex_size.y, 1.0)) * 0.55
	for p in poly:
		var n := (p - min_v) / size
		uvs.append(n * tile)
	return uvs


func _circle_poly(radius: float, segments: int = 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


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
		# Movers between mid/high — safe rideable platforms (no spikes attached).
		if i % 4 == 0 and i + 1 < airs.size():
			var a: Dictionary = airs[i]
			var b: Dictionary = airs[i + 1]
			_obs.add_moving_platform(
				_plat_point(a, 0.5),
				_plat_point(b, 0.5),
				120.0,
				2.0 + float(i % 3) * 0.35,
				Color(0.55, 0.4, 0.22)
			)


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
		# Movers stay rideable — never attach spikes/traps to them.
		if i % 5 == 0 and i + 1 < airs.size():
			var a: Dictionary = airs[i]
			var b: Dictionary = airs[mini(i + 2, airs.size() - 1)]
			_obs.add_moving_platform(
				_plat_point(a, 0.5),
				_plat_point(b, 0.5),
				110.0,
				4.2,
				Color(0.75, 0.88, 0.98)
			)


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
				_obs.add_jump_pad(_plat_point(p, 0.45) + Vector2(0, -2), 640.0, Color(1.15, 0.85, 0.35))
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


func _spawn_desert_tumbleweed_props(rng: RandomNumberGenerator) -> void:
	## Static tumbleweeds along the dunes for flavor.
	var tex := load("res://assets/sprites/hazards/tumbleweed.png") as Texture2D
	if tex == null:
		return
	var grounds := _plats_ground()
	for i in grounds.size():
		if i % 4 != 0:
			continue
		var p: Dictionary = grounds[i]
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var s := rng.randf_range(0.7, 1.0)
		spr.scale = Vector2(s, s)
		spr.modulate = Color(0.95, 0.85, 0.65, 0.9)
		spr.rotation = rng.randf_range(-0.4, 0.4)
		spr.z_index = 1
		# Sit slightly above the sand top so they read as on the ground, not sunk in.
		spr.position = _plat_point(p, rng.randf_range(0.15, 0.85)) + Vector2(0, -14)
		add_child(spr)


func _clear_tumbleweeds() -> void:
	for n in get_tree().get_nodes_in_group("tumbleweed"):
		if is_instance_valid(n):
			n.queue_free()


func _clear_hop_mushrooms() -> void:
	for n in get_tree().get_nodes_in_group("hop_mushroom"):
		if is_instance_valid(n):
			n.queue_free()


func _spawn_rolling_tumbleweed() -> void:
	if _camera == null:
		return
	var script: Script = load("res://scripts/tumbleweed.gd") as Script
	var weed := CharacterBody2D.new()
	weed.set_script(script)
	var speed := float(_level.get("tumbleweed_speed", 68.0)) * randf_range(0.85, 1.15)
	var scale_mul := randf_range(0.75, 1.05)
	weed.global_position = _pick_ahead_platform_spawn(70.0)
	add_child(weed)
	weed.call("setup", _on_hazard, speed, scale_mul)


func _spawn_hop_mushroom() -> void:
	if _camera == null or _wheel == null:
		return
	var script: Script = load("res://scripts/hop_mushroom.gd") as Script
	var shroom := CharacterBody2D.new()
	shroom.set_script(script)
	var speed := float(_level.get("mushroom_speed", 100.0)) * randf_range(0.85, 1.2)
	var scale_mul := randf_range(0.85, 1.1)
	shroom.global_position = _pick_ahead_platform_spawn(60.0)
	add_child(shroom)
	shroom.call("setup", _on_mushroom_hit, _wheel, speed, scale_mul)


func _pick_ahead_platform_spawn(min_width: float = 70.0) -> Vector2:
	## Prefer a platform under the right side of the camera at any lane height.
	var x_min := _scroll_x + 420.0
	var x_max := _scroll_x + 780.0
	var candidates: Array[Dictionary] = []
	for p in _platforms:
		var left := float(p["left"])
		var right := float(p["right"])
		if right < x_min or left > x_max:
			continue
		if float(p["w"]) < min_width:
			continue
		candidates.append(p)

	if candidates.is_empty():
		return Vector2(_scroll_x + 720.0, float(_level.get("lane_mid_y", 335.0)))

	var plat: Dictionary = candidates[randi() % candidates.size()]
	var left := float(plat["left"])
	var right := float(plat["right"])
	var t := randf_range(0.55, 0.95)
	var x := lerpf(left + 18.0, right - 14.0, t)
	x = clampf(x, left + 14.0, right - 10.0)
	var top := float(plat["top"])
	return Vector2(x, top - 12.0)


func _on_mushroom_hit(body: Node2D, _shroom: Node) -> void:
	if _done or _dead:
		return
	if body != _wheel and not body.is_in_group("player"):
		return
	_trip_hold = maxf(_trip_hold, 3.4)
	_trip_intensity = maxf(_trip_intensity, 0.8)
	_apply_trip_visual()
	GameProgress.juice_shake.emit(0.12)
	_hint.text = "Whoa… rainbow waves! Ride it out — spikes still kill."


func _update_trip(delta: float) -> void:
	if _trip_rect == null:
		return
	if _trip_hold > 0.0:
		_trip_hold -= delta
		_trip_intensity = move_toward(_trip_intensity, 0.95, delta * 1.2)
	else:
		_trip_intensity = move_toward(_trip_intensity, 0.0, delta * 0.7)
	_trip_hue = fmod(_trip_hue + delta * 0.55, 1.0)
	_apply_trip_visual()


func _apply_trip_visual() -> void:
	if _trip_rect == null:
		return
	var on := _trip_intensity > 0.02
	_trip_rect.visible = on
	if _trip_rect_b:
		_trip_rect_b.visible = on
	if not on:
		return
	# No shader — plain translucent ColorRects. Safe on Metal / all backends.
	var pulse := 0.5 + 0.5 * sin(_time * 7.0)
	var a := clampf(0.16 + 0.22 * _trip_intensity * (0.75 + 0.25 * pulse), 0.0, 0.42)
	_trip_rect.color = Color.from_hsv(_trip_hue, 0.75, 1.0, a)
	if _trip_rect_b:
		_trip_rect_b.color = Color.from_hsv(fmod(_trip_hue + 0.33, 1.0), 0.7, 1.0, a * 0.65)


func _spawn_finish() -> void:
	# Place finish where the camera can still pan to it, with room to drive through.
	_finish_x = course_length - 320.0
	var finish := Area2D.new()
	finish.name = "FinishLine"
	finish.position = Vector2(_finish_x, 360)
	finish.collision_layer = 0
	finish.collision_mask = 1
	finish.monitoring = true
	finish.monitorable = false
	finish.body_entered.connect(_on_finish)

	# Full-height yellow strip (covers every lane / camera pan).
	var banner := Polygon2D.new()
	banner.z_index = 8
	banner.color = Color(1.0, 0.88, 0.2, 0.62)
	banner.polygon = PackedVector2Array([
		Vector2(-14, -520), Vector2(14, -520), Vector2(14, 520), Vector2(-14, 520)
	])
	finish.add_child(banner)
	# Bright edge lines so it reads as a checkered finish pole.
	var edge_l := Line2D.new()
	edge_l.z_index = 9
	edge_l.width = 3.0
	edge_l.default_color = Color(1.0, 0.95, 0.45, 0.95)
	edge_l.add_point(Vector2(-14, -520))
	edge_l.add_point(Vector2(-14, 520))
	finish.add_child(edge_l)
	var edge_r := Line2D.new()
	edge_r.z_index = 9
	edge_r.width = 3.0
	edge_r.default_color = Color(1.0, 0.75, 0.15, 0.95)
	edge_r.add_point(Vector2(14, -520))
	edge_r.add_point(Vector2(14, 520))
	finish.add_child(edge_r)

	var pile := Sprite2D.new()
	pile.texture = load("res://assets/sprites/bananas_pile.png") as Texture2D
	pile.position = Vector2(48, 40)
	pile.scale = Vector2(2.0, 2.0)
	pile.z_index = 10
	pile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	finish.add_child(pile)
	var label := Label.new()
	label.text = "FINISH"
	label.position = Vector2(-48, -280)
	label.z_index = 10
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.4, 1))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	finish.add_child(label)

	# Tall trigger — any lane crossing the line counts.
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(64, 1100)
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
	layer.layer = 20
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
	if _hop_mushrooms_enabled:
		# Own layer above the world, below/with UI sibling ordering handled by layer index.
		_build_trip_overlay()


func _build_trip_overlay() -> void:
	var trip_layer := CanvasLayer.new()
	trip_layer.name = "TripLayer"
	# Above the world, under the HUD labels (HUD is layer 20).
	trip_layer.layer = 15
	add_child(trip_layer)

	# Shader-free translucent wash — ColorRect.color alpha is what you see.
	_trip_rect = ColorRect.new()
	_trip_rect.name = "TripOverlay"
	_trip_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_trip_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trip_rect.color = Color(1, 0, 1, 0.0)
	_trip_rect.visible = false
	trip_layer.add_child(_trip_rect)

	_trip_rect_b = ColorRect.new()
	_trip_rect_b.name = "TripOverlayB"
	_trip_rect_b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_trip_rect_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trip_rect_b.color = Color(0, 1, 1, 0.0)
	_trip_rect_b.visible = false
	trip_layer.add_child(_trip_rect_b)


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
		_play_sfx(SFX_JUMP, -4.0)
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

	# Keep finish on-screen and always driveable: scroll can follow past the line.
	var scroll_cap := _finish_x + 120.0
	if _scroll_x < scroll_cap:
		var player_lead := _wheel.global_position.x - _scroll_x
		var pan_speed := scroll_speed
		if _wheel.velocity.x > scroll_speed and player_lead > 260.0:
			# Blend up to the player's actual forward speed as they approach the
			# right side. This preserves their world speed and their lead on a chase.
			var follow_weight := smoothstep(260.0, 480.0, player_lead)
			pan_speed = lerpf(scroll_speed, _wheel.velocity.x, follow_weight)
		_scroll_x = minf(_scroll_x + pan_speed * delta, scroll_cap)
		# Never let a fast frame put the player into the hard screen-edge clamp.
		_scroll_x = maxf(_scroll_x, minf(_wheel.global_position.x - 500.0, scroll_cap))
	var cam_y := lerpf(_camera.global_position.y, clampf(_wheel.global_position.y, 280.0, 480.0), 0.08)
	_camera.global_position = Vector2(_scroll_x, cam_y)
	if _snow:
		_snow.global_position = Vector2(_scroll_x, cam_y - 380.0)

	if _tumbleweeds_enabled:
		_tumble_spawn_t -= delta
		if _tumble_spawn_t <= 0.0:
			_spawn_rolling_tumbleweed()
			_tumble_spawn_t = _tumble_spawn_cd * randf_range(0.75, 1.35)

	if _hop_mushrooms_enabled:
		_mushroom_spawn_t -= delta
		if _mushroom_spawn_t <= 0.0:
			_spawn_hop_mushroom()
			_mushroom_spawn_t = _mushroom_spawn_cd * randf_range(0.7, 1.3)
		_update_trip(delta)

	# Soft right rail — always past the finish so the player can cross it.
	var right_limit := maxf(_scroll_x + 560.0, _finish_x + 80.0)
	if _wheel.global_position.x > right_limit:
		_wheel.global_position.x = right_limit
		if _scroll_x >= scroll_cap - 0.5 and _wheel.global_position.x > _finish_x + 40.0:
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
	_play_sfx(SFX_JUMP, -2.0)
	GameProgress.juice_shake.emit(0.08)


func _on_hazard(body: Node2D) -> void:
	# Spikes / saws / tumbleweeds — never used for platform underside bonks.
	if _done or _dead:
		return
	if body == _wheel or body.is_in_group("player"):
		if _tiger != null and is_instance_valid(_tiger) and _tiger.monitoring:
			# Prefer a tiger-specific line when the chase is active
			var near_tiger := _wheel.global_position.distance_to(_tiger.global_position) < 70.0
			if near_tiger:
				_respawn("The tiger got you! Keep moving — it never stops.")
				return
		for n in get_tree().get_nodes_in_group("tumbleweed"):
			if is_instance_valid(n) and _wheel.global_position.distance_to(n.global_position) < 80.0:
				_respawn("Tumbleweed! Jump over — they roll off ledges and into gaps.")
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
	_play_sfx(SFX_DIE, -2.0)
	if _tiger != null and is_instance_valid(_tiger):
		_tiger.call("set_active", false)
	_clear_tumbleweeds()
	_clear_hop_mushrooms()
	_trip_hold = 0.0
	_trip_intensity = 0.0
	_apply_trip_visual()
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
	_tumble_spawn_t = 1.6
	_mushroom_spawn_t = 1.2
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
