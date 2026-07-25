extends Node2D

## Draw-your-own-wheel studio — first-person cart cockpit / steering-wheel POV.

const CANVAS_SIZE := Vector2(520, 520)
const WHEEL_RADIUS := 230.0
const RIM_INNER := 198.0
const RIM_OUTER := 248.0
const MIN_POINT_DIST := 10.0
const MIN_POINTS := 8
const TEX_TRACK_BG := "res://assets/sprites/bg_wheel_track.png"
const TEX_WOOD := "res://assets/sprites/ui_wood.png"
const TEX_CART := "res://assets/sprites/banana_cart.png"
const TEX_CART_ICON := "res://assets/sprites/icon_banana_cart_frame.png"
const TEX_MONKEY := "res://assets/sprites/monkey_idle.png"
var _points: PackedVector2Array = PackedVector2Array()
var _drawing: bool = false
var _canvas: Control
var _status: Label
var _level_title: String = "Trail"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_load_existing_or_square()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)

	# Actual wheel-track resource art through the cart windshield.
	var track_bg := _texture_rect(TEX_TRACK_BG)
	track_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	track_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	track_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	track_bg.modulate = Color(0.72, 0.82, 0.72, 1)
	root.add_child(track_bg)

	var windshield_tint := ColorRect.new()
	windshield_tint.color = Color(0.04, 0.1, 0.07, 0.25)
	windshield_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	windshield_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(windshield_tint)

	var level := WheelLevels.get_level(GameProgress.selected_wheel_level)
	_level_title = str(level.get("title", "Trail"))

	var title := Label.new()
	title.text = "STEERING WHEEL — %s" % _level_title.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 18
	title.offset_left = -460
	title.offset_right = 460
	title.offset_bottom = 56
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75, 1))
	title.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 1))
	title.add_theme_constant_override("outline_size", 7)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "%s\n%s\nTrace the tire on the wheel — fill more of the rim for a bigger shape." % [
		str(level.get("blurb", "")),
		str(level.get("theme_tip", "")),
	]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint.offset_top = 58
	hint.offset_left = -480
	hint.offset_right = 480
	hint.offset_bottom = 118
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82, 1))
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 4)
	root.add_child(hint)

	# Transparent board — the canvas draws the whole steering wheel
	var board := Control.new()
	board.custom_minimum_size = CANVAS_SIZE
	board.set_anchors_preset(Control.PRESET_CENTER)
	board.offset_left = -CANVAS_SIZE.x * 0.5
	board.offset_top = -CANVAS_SIZE.y * 0.5 + 18
	board.offset_right = CANVAS_SIZE.x * 0.5
	board.offset_bottom = CANVAS_SIZE.y * 0.5 + 18
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(board)

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_on_canvas_gui_input)
	_canvas.draw.connect(_on_canvas_draw)
	board.add_child(_canvas)

	# Resource-pack wood tiled across the cart dashboard.
	var dash := _texture_rect(TEX_WOOD)
	dash.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dash.offset_top = -168
	dash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dash.stretch_mode = TextureRect.STRETCH_TILE
	dash.modulate = Color(0.82, 0.72, 0.55, 1)
	root.add_child(dash)

	# Cart body forms the lower cockpit edge instead of a drawn dashboard lip.
	var cart := _texture_rect(TEX_CART)
	cart.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cart.offset_left = -230
	cart.offset_right = 230
	cart.offset_top = -220
	cart.offset_bottom = -108
	cart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cart.modulate = Color(0.8, 0.72, 0.62, 1)
	root.add_child(cart)

	# Pack-sprite driver badge and cart badge on the dashboard.
	var monkey_badge := _texture_rect(TEX_MONKEY)
	monkey_badge.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	monkey_badge.offset_left = 22
	monkey_badge.offset_right = 118
	monkey_badge.offset_top = -154
	monkey_badge.offset_bottom = -58
	monkey_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	monkey_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(monkey_badge)

	var cart_badge := _texture_rect(TEX_CART_ICON)
	cart_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cart_badge.offset_left = -118
	cart_badge.offset_right = -22
	cart_badge.offset_top = -154
	cart_badge.offset_bottom = -58
	cart_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cart_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(cart_badge)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.offset_top = -148
	_status.offset_bottom = -118
	_status.offset_left = -360
	_status.offset_right = 360
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1))
	_status.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02, 1))
	_status.add_theme_constant_override("outline_size", 5)
	root.add_child(_status)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_top = -100
	row.offset_bottom = -36
	row.offset_left = -460
	row.offset_right = 460
	root.add_child(row)

	row.add_child(_make_btn("Clear", _on_clear, false))
	row.add_child(_make_btn("Big ○", _on_circle_big, false))
	row.add_child(_make_btn("Small ○", _on_circle_small, false))
	row.add_child(_make_btn("Square", _on_square, false))
	row.add_child(_make_btn("RIDE →", _on_ride, true))


func _texture_rect(path: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = load(path) as Texture2D
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _make_btn(text: String, cb: Callable, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(128, 44)
	var sb := StyleBoxTexture.new()
	sb.texture = load(TEX_WOOD) as Texture2D
	sb.modulate_color = Color(1.15, 0.95, 0.65, 1) if primary else Color(0.7, 0.58, 0.42, 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate() as StyleBoxTexture
	sb_h.modulate_color = sb.modulate_color.lightened(0.15)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_h)
	b.add_theme_color_override("font_color", Color(1, 0.96, 0.85, 1))
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	return b

func _load_existing_or_square() -> void:
	var existing := GameProgress.get_drawn_wheel_canvas()
	if existing.size() >= 3:
		_points = existing
	else:
		_on_square()
	_refresh_status()
	_canvas.queue_redraw()


func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drawing = true
				_points.clear()
				_add_point(mb.position)
			else:
				_drawing = false
				_finalize_stroke()
			_canvas.queue_redraw()
			_canvas.accept_event()
	elif event is InputEventMouseMotion and _drawing:
		_add_point((event as InputEventMouseMotion).position)
		_canvas.queue_redraw()
		_canvas.accept_event()


func _add_point(local_pos: Vector2) -> void:
	var center := CANVAS_SIZE * 0.5
	var from_c := local_pos - center
	# Keep strokes on the wheel face (inside the rim)
	if from_c.length() > RIM_INNER:
		from_c = from_c.normalized() * RIM_INNER
		local_pos = center + from_c
	var p := local_pos.clamp(Vector2(8, 8), CANVAS_SIZE - Vector2(8, 8))
	if _points.is_empty() or _points[_points.size() - 1].distance_to(p) >= MIN_POINT_DIST:
		_points.append(p)
		_refresh_status()


func _finalize_stroke() -> void:
	if _points.size() < 3:
		return
	if _points[0].distance_to(_points[_points.size() - 1]) > 20.0:
		_points.append(_points[0])
	_refresh_status()


func _on_canvas_draw() -> void:
	var center := CANVAS_SIZE * 0.5
	_draw_steering_wheel(center)

	# User tire shape sits on the wheel face
	if _points.size() >= 2:
		_canvas.draw_polyline(_points, Color(0.95, 0.78, 0.22, 1), 5.0, true)
	if _points.size() >= 3:
		var colors := PackedColorArray()
		colors.resize(_points.size())
		colors.fill(Color(0.9, 0.7, 0.18, 0.4))
		_canvas.draw_polygon(_points, colors)
	for p in _points:
		_canvas.draw_circle(p, 2.8, Color(1, 0.95, 0.7, 0.9))


func _draw_steering_wheel(center: Vector2) -> void:
	# Cabin hole through the wheel — soft jungle tint
	_canvas.draw_circle(center, RIM_INNER - 4.0, Color(0.22, 0.38, 0.28, 0.55))

	# Guide ring (where size matters)
	_canvas.draw_arc(center, 200, 0, TAU, 72, Color(1, 1, 1, 0.1), 2.0)

	# Three spokes
	var spoke := Color(0.32, 0.2, 0.1, 1)
	var spoke_hi := Color(0.55, 0.38, 0.18, 1)
	for i in 3:
		var a := -PI * 0.5 + TAU * float(i) / 3.0
		var tip := center + Vector2(cos(a), sin(a)) * (RIM_INNER - 8.0)
		_canvas.draw_line(center, tip, spoke, 18.0, true)
		_canvas.draw_line(center, tip, spoke_hi, 8.0, true)

	# Outer rim (leather / wood)
	_canvas.draw_arc(center, (RIM_OUTER + RIM_INNER) * 0.5, 0, TAU, 96, Color(0.18, 0.1, 0.05, 1), RIM_OUTER - RIM_INNER + 6.0)
	_canvas.draw_arc(center, (RIM_OUTER + RIM_INNER) * 0.5, 0, TAU, 96, Color(0.42, 0.26, 0.12, 1), RIM_OUTER - RIM_INNER - 6.0)
	_canvas.draw_arc(center, RIM_OUTER - 2.0, 0, TAU, 96, Color(0.65, 0.45, 0.22, 0.7), 3.0)
	_canvas.draw_arc(center, RIM_INNER + 2.0, 0, TAU, 96, Color(0.55, 0.35, 0.16, 0.55), 2.5)

	# Grip bumps on rim
	for i in 12:
		var a := TAU * float(i) / 12.0
		var p := center + Vector2(cos(a), sin(a)) * ((RIM_OUTER + RIM_INNER) * 0.5)
		_canvas.draw_circle(p, 5.0, Color(0.28, 0.16, 0.08, 0.85))

	# Center hub.
	_canvas.draw_circle(center, 36, Color(0.25, 0.15, 0.08, 1))
	_canvas.draw_circle(center, 28, Color(0.48, 0.3, 0.12, 1))

	# Subtle "MONKEY WHEEL Co." stamp
	# (drawn as tiny marks — labels can't sit in draw easily without Font)
	_canvas.draw_arc(center, 48, -0.8, 0.8, 16, Color(0.2, 0.12, 0.06, 0.5), 2.0)


func _refresh_status() -> void:
	var size_pct := 0
	if _points.size() >= 3:
		var preview := GameProgress.normalize_wheel_polygon(_points, CANVAS_SIZE)
		GameProgress.set_drawn_wheel(preview, _points)
		size_pct = int(GameProgress.wheel_size_norm * 100.0)
		_status.text = "Size %d%% · Round %d%% · %s" % [
			size_pct,
			int(GameProgress.wheel_roundness * 100.0),
			GameProgress.wheel_fit_note(),
		]
	else:
		_status.text = "Grip the wheel and draw · need %d+ points · then RIDE" % MIN_POINTS


func _on_clear() -> void:
	_points.clear()
	_refresh_status()
	_canvas.queue_redraw()


func _on_square() -> void:
	var c := CANVAS_SIZE * 0.5
	var s := 150.0
	_points = PackedVector2Array([
		c + Vector2(-s, -s), c + Vector2(s, -s), c + Vector2(s, s), c + Vector2(-s, s), c + Vector2(-s, -s)
	])
	_refresh_status()
	_canvas.queue_redraw()


func _on_circle_big() -> void:
	_make_circle(200.0)


func _on_circle_small() -> void:
	_make_circle(70.0)


func _make_circle(r: float) -> void:
	var c := CANVAS_SIZE * 0.5
	_points = PackedVector2Array()
	for i in 28:
		var a := TAU * float(i) / 28.0
		_points.append(c + Vector2(cos(a), sin(a)) * r)
	_points.append(_points[0])
	_refresh_status()
	_canvas.queue_redraw()


func _on_ride() -> void:
	if _points.size() < MIN_POINTS:
		_status.text = "Too abstract — draw more (need %d+ points)." % MIN_POINTS
		return
	var normalized := GameProgress.normalize_wheel_polygon(_points, CANVAS_SIZE)
	if normalized.size() < 3:
		_status.text = "Shape failed — try a simpler closed loop."
		return
	GameProgress.set_drawn_wheel(normalized, _points)
	GameProgress.start_wheel_course()
