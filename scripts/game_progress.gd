extends Node

signal mode_changed(mode: StringName)
signal progress_changed
signal era_banner_requested(title: String, subtitle: String)
signal juice_shake(amount: float)
signal game_won(final_chase_score: int)

const MODE_HUB := &"hub"
const MODE_FIRE := &"fire"
const MODE_WHEEL := &"wheel"
const MODE_CART := &"cart"
const MODE_CHASE := &"chase"
const MODE_WIN := &"win"

const SCENES := {
	MODE_HUB: "res://scenes/levels/hub_jungle.tscn",
	MODE_FIRE: "res://scenes/levels/fire_camp.tscn",
	MODE_WHEEL: "res://scenes/levels/wheel_draw.tscn",
	MODE_CART: "res://scenes/levels/cart_run.tscn",
	MODE_CHASE: "res://scenes/levels/chase_arena.tscn",
}

const WHEEL_COURSE_SCENE := "res://scenes/levels/wheel_run.tscn"
const WHEEL_RADIUS_MIN := 14.0
const WHEEL_RADIUS_MAX := 44.0

var current_mode: StringName = MODE_HUB
var has_fire: bool = false
var has_wheel: bool = false
var has_cart: bool = false
var chase_done: bool = false
var last_chase_score: int = 0

## Selected themed wheel trail (hub level portals).
var selected_wheel_level: StringName = &"gap_gorge"
var cleared_wheel_levels: Dictionary = {}

## Normalized local polygon for the player's invented wheel (physics/visual).
var drawn_wheel: PackedVector2Array = PackedVector2Array()
## Raw canvas points for re-editing in the draw studio.
var drawn_wheel_canvas: PackedVector2Array = PackedVector2Array()
## Stats from the drawing (0–1 size / roundness, world radius).
var wheel_size_norm: float = 0.5
var wheel_roundness: float = 0.5
var wheel_radius: float = 26.0

var _stage: Node = null


func bind_stage(stage: Node) -> void:
	_stage = stage


func reset_campaign() -> void:
	has_fire = false
	has_wheel = false
	has_cart = false
	chase_done = false
	last_chase_score = 0
	drawn_wheel = PackedVector2Array()
	drawn_wheel_canvas = PackedVector2Array()
	cleared_wheel_levels.clear()
	selected_wheel_level = &"gap_gorge"
	wheel_size_norm = 0.5
	wheel_roundness = 0.5
	wheel_radius = 26.0
	current_mode = MODE_HUB
	Inventory.clear()
	GameState.set_active(false)
	progress_changed.emit()


func set_drawn_wheel(normalized: PackedVector2Array, canvas_pts: PackedVector2Array = PackedVector2Array()) -> void:
	drawn_wheel = normalized
	drawn_wheel_canvas = canvas_pts
	_compute_wheel_stats(canvas_pts if canvas_pts.size() >= 3 else normalized)


func get_drawn_wheel() -> PackedVector2Array:
	if drawn_wheel.size() >= 3:
		return drawn_wheel
	return default_square_wheel()


func get_drawn_wheel_canvas() -> PackedVector2Array:
	return drawn_wheel_canvas


func default_square_wheel() -> PackedVector2Array:
	var s := 22.0
	return PackedVector2Array([
		Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)
	])


## Keep drawing size — big canvas wheels become big world wheels.
func normalize_wheel_polygon(canvas_pts: PackedVector2Array, canvas_size: Vector2, _unused: float = 26.0) -> PackedVector2Array:
	if canvas_pts.size() < 3:
		return PackedVector2Array()
	var pts: Array[Vector2] = []
	for p in canvas_pts:
		pts.append(p)
	if pts.size() >= 2 and pts[0].distance_to(pts[pts.size() - 1]) < 1.0:
		pts.pop_back()
	var center := Vector2.ZERO
	for p in pts:
		center += p
	center /= float(pts.size())
	var max_r := 1.0
	for p in pts:
		max_r = maxf(max_r, p.distance_to(center))
	var size_norm := clampf(max_r / (minf(canvas_size.x, canvas_size.y) * 0.46), 0.08, 1.0)
	var target_radius := lerpf(WHEEL_RADIUS_MIN, WHEEL_RADIUS_MAX, size_norm)
	var scale := target_radius / max_r
	var out := PackedVector2Array()
	for p in pts:
		out.append((p - center) * scale)
	return out


func _compute_wheel_stats(pts_in: PackedVector2Array) -> void:
	if pts_in.size() < 3:
		wheel_size_norm = 0.5
		wheel_roundness = 0.35
		wheel_radius = 26.0
		return
	var pts: Array[Vector2] = []
	for p in pts_in:
		pts.append(p)
	if pts.size() >= 2 and pts[0].distance_to(pts[pts.size() - 1]) < 1.0:
		pts.pop_back()
	var center := Vector2.ZERO
	for p in pts:
		center += p
	center /= float(pts.size())
	var radii: Array[float] = []
	var max_r := 1.0
	var min_r := INF
	for p in pts:
		var r := p.distance_to(center)
		radii.append(r)
		max_r = maxf(max_r, r)
		min_r = minf(min_r, r)
	var mean := 0.0
	for r in radii:
		mean += r
	mean /= float(radii.size())
	var variance := 0.0
	for r in radii:
		var d := r - mean
		variance += d * d
	variance /= float(radii.size())
	var std := sqrt(variance)
	# Roundness: low radial variance → circle-like
	wheel_roundness = clampf(1.0 - (std / maxf(mean, 1.0)) * 2.2, 0.0, 1.0)
	# Prefer world radius from normalized poly if available
	if drawn_wheel.size() >= 3:
		var wr := 1.0
		for p in drawn_wheel:
			wr = maxf(wr, p.length())
		wheel_radius = wr
		wheel_size_norm = clampf(
			(wheel_radius - WHEEL_RADIUS_MIN) / (WHEEL_RADIUS_MAX - WHEEL_RADIUS_MIN),
			0.0,
			1.0
		)
	else:
		wheel_size_norm = clampf(max_r / 240.0, 0.08, 1.0)
		wheel_radius = lerpf(WHEEL_RADIUS_MIN, WHEEL_RADIUS_MAX, wheel_size_norm)


func wheel_fit_note(level_id: StringName = selected_wheel_level) -> String:
	var level := WheelLevels.get_level(level_id)
	var want_min := float(level.get("want_size_min", 0.0))
	var want_max := float(level.get("want_size_max", 1.0))
	var want_round := float(level.get("want_round_min", 0.0))
	var notes: PackedStringArray = []
	if wheel_size_norm < want_min:
		notes.append("wheels look small for this trail")
	elif wheel_size_norm > want_max:
		notes.append("wheels look oversized for this trail")
	if wheel_roundness < want_round:
		notes.append("shape is too jagged — rounder helps")
	if notes.is_empty():
		return "Wheel looks suited to this trail."
	return "Warning: " + ", ".join(notes) + "."


func start_wheel_level(level_id: StringName) -> void:
	if not WheelLevels.LEVELS.has(level_id):
		push_warning("Unknown wheel level: %s" % level_id)
		level_id = &"gap_gorge"
	selected_wheel_level = level_id
	var level := WheelLevels.get_level(level_id)
	_set_mode(MODE_WHEEL)
	era_banner_requested.emit(
		str(level.get("title", "Wheel Trail")),
		str(level.get("blurb", "Draw a wheel. Ride the trail."))
	)


func start_wheel_course() -> void:
	current_mode = MODE_WHEEL
	mode_changed.emit(MODE_WHEEL)
	GameState.set_active(false)
	var level := WheelLevels.get_level(selected_wheel_level)
	era_banner_requested.emit(
		str(level.get("title", "Wheel Run")),
		wheel_fit_note()
	)
	_load_scene_path(WHEEL_COURSE_SCENE)


func mark_wheel_level_cleared(level_id: StringName = selected_wheel_level) -> void:
	cleared_wheel_levels[level_id] = true
	if not has_wheel:
		has_wheel = true
		Inventory.add_item(&"square_wheel", 1)
	progress_changed.emit()


func load_hub(show_banner: bool = false) -> void:
	_set_mode(MODE_HUB)
	if show_banner:
		era_banner_requested.emit(_era_title(), _era_subtitle())


func exit_minigame() -> void:
	if current_mode == MODE_HUB or current_mode == MODE_WIN:
		return
	GameState.set_active(false)
	era_banner_requested.emit("World Map", "Pick a trail and press E.")
	load_hub(false)



func start_minigame(minigame_id: StringName) -> void:
	match minigame_id:
		MODE_FIRE:
			_set_mode(MODE_FIRE)
			era_banner_requested.emit("Stone Age Primates", "Invent fire. Or toast a banana. Same thing.")
		MODE_WHEEL:
			selected_wheel_level = &"gap_gorge"
			_set_mode(MODE_WHEEL)
			era_banner_requested.emit("The Wheel Era", "Draw any wheel. Then survive the trail.")
		MODE_CART:
			_set_mode(MODE_CART)
			era_banner_requested.emit("Banana Logistics", "Deliver bananas. Drop as few as possible.")
		MODE_CHASE:
			_set_mode(MODE_CHASE)
			era_banner_requested.emit("Sacred Banana Raid", "Grab them before time runs out!")
		_:
			# Treat unknown ids as wheel level keys if present
			if WheelLevels.LEVELS.has(minigame_id):
				start_wheel_level(minigame_id)
			else:
				push_warning("Unknown minigame: %s" % minigame_id)


func complete_minigame(minigame_id: StringName) -> void:
	match minigame_id:
		MODE_FIRE:
			if not has_fire:
				has_fire = true
				Inventory.add_item(&"fire_kit", 1)
			juice_shake.emit(0.35)
			progress_changed.emit()
			era_banner_requested.emit("Fire Discovered!", "The tribe is slightly less cold and slightly more smug.")
			await get_tree().create_timer(1.4).timeout
			load_hub()
		MODE_WHEEL:
			mark_wheel_level_cleared(selected_wheel_level)
			juice_shake.emit(0.45)
			era_banner_requested.emit(
				"%s Cleared!" % WheelLevels.title_of(selected_wheel_level),
				"Your wheel reinvented reinventing."
			)
			await get_tree().create_timer(1.4).timeout
			load_hub()
		MODE_CART:
			if not has_cart:
				has_cart = true
				Inventory.add_item(&"banana_cart_frame", 1)
			juice_shake.emit(0.4)
			progress_changed.emit()
			era_banner_requested.emit("Banana Cart Online!", "Raid whenever you like.")
			await get_tree().create_timer(1.4).timeout
			load_hub()
		MODE_CHASE:
			chase_done = true
			progress_changed.emit()
			_finish_game()
		_:
			load_hub()


func report_chase_finished(score: int) -> void:
	last_chase_score = score
	complete_minigame(MODE_CHASE)


func can_enter(minigame_id: StringName) -> bool:
	match minigame_id:
		MODE_FIRE, MODE_WHEEL, MODE_CART, MODE_CHASE:
			return true
		_:
			return WheelLevels.LEVELS.has(minigame_id)


func shrine_status(minigame_id: StringName) -> String:
	match minigame_id:
		MODE_FIRE:
			return "done" if has_fire else "open"
		MODE_WHEEL:
			return "done" if has_wheel else "open"
		MODE_CART:
			return "done" if has_cart else "open"
		MODE_CHASE:
			return "done" if chase_done else "open"
		_:
			if WheelLevels.LEVELS.has(minigame_id):
				return "done" if cleared_wheel_levels.get(minigame_id, false) else "open"
			return "open"


func _finish_game() -> void:
	current_mode = MODE_WIN
	mode_changed.emit(MODE_WIN)
	game_won.emit(last_chase_score)
	if _stage:
		for child in _stage.get_children():
			child.queue_free()


func _set_mode(mode: StringName) -> void:
	current_mode = mode
	mode_changed.emit(mode)
	if mode == MODE_CHASE:
		GameState.set_active(true)
	else:
		GameState.set_active(false)
	_load_scene_for_mode(mode)


func _load_scene_for_mode(mode: StringName) -> void:
	var path: String = SCENES.get(mode, "")
	_load_scene_path(path)
	if mode == MODE_CHASE:
		GameState.call_deferred("start_round")


func _load_scene_path(path: String) -> void:
	if _stage == null or path.is_empty():
		return
	for child in _stage.get_children():
		child.queue_free()
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("Failed to load scene: %s" % path)
		return
	var instance := packed.instantiate()
	_stage.add_child(instance)


func _era_title() -> String:
	return "Banana Genesis"


func _era_subtitle() -> String:
	return "Explore the jungle · enter a shrine · Esc/Q exits"


