extends Node2D

## Draw-your-own-wheel studio. Primary entry for the wheel run.

const CANVAS_SIZE := Vector2(520, 520)
const MIN_POINT_DIST := 10.0
const MIN_POINTS := 8

var _points: PackedVector2Array = PackedVector2Array()
var _drawing: bool = false
var _canvas: Control
var _status: Label


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

	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.12, 0.1, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var level := WheelLevels.get_level(GameProgress.selected_wheel_level)
	var title := Label.new()
	title.text = "DRAW FOR: %s" % str(level.get("title", "Trail")).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 22
	title.offset_left = -420
	title.offset_right = 420
	title.offset_bottom = 64
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "%s\n%s\nDrawing SIZE matters — fill more of the canvas for bigger wheels." % [
		str(level.get("blurb", "")),
		str(level.get("theme_tip", "")),
	]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint.offset_top = 68
	hint.offset_left = -460
	hint.offset_right = 460
	hint.offset_bottom = 130
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 4)
	root.add_child(hint)

	var board := Panel.new()
	board.custom_minimum_size = CANVAS_SIZE
	board.set_anchors_preset(Control.PRESET_CENTER)
	board.offset_left = -CANVAS_SIZE.x * 0.5
	board.offset_top = -CANVAS_SIZE.y * 0.5 + 24
	board.offset_right = CANVAS_SIZE.x * 0.5
	board.offset_bottom = CANVAS_SIZE.y * 0.5 + 24
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.28, 0.2)
	sb.border_color = Color(0.95, 0.85, 0.35)
	sb.set_border_width_all(4)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	board.add_theme_stylebox_override("panel", sb)
	root.add_child(board)

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_on_canvas_gui_input)
	_canvas.draw.connect(_on_canvas_draw)
	board.add_child(_canvas)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.offset_top = -120
	_status.offset_bottom = -90
	_status.offset_left = -300
	_status.offset_right = 300
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 4)
	root.add_child(_status)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_top = -70
	row.offset_bottom = -24
	row.offset_left = -420
	row.offset_right = 420
	root.add_child(row)

	row.add_child(_make_btn("Clear", _on_clear))
	row.add_child(_make_btn("Big ○", _on_circle_big))
	row.add_child(_make_btn("Small ○", _on_circle_small))
	row.add_child(_make_btn("Square", _on_square))
	row.add_child(_make_btn("RIDE →", _on_ride))


func _make_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(130, 40)
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
	_canvas.draw_arc(center, 200, 0, TAU, 64, Color(1, 1, 1, 0.12), 2.0)
	_canvas.draw_circle(center, 4, Color(1, 0.9, 0.3, 0.5))
	if _points.size() >= 2:
		_canvas.draw_polyline(_points, Color(1.0, 0.85, 0.25, 1), 4.0, true)
	if _points.size() >= 3:
		var colors := PackedColorArray()
		colors.resize(_points.size())
		colors.fill(Color(0.95, 0.75, 0.2, 0.35))
		_canvas.draw_polygon(_points, colors)
	for p in _points:
		_canvas.draw_circle(p, 3.0, Color(1, 1, 1, 0.85))


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
		_status.text = "Points: %d  ·  need %d+ then hit RIDE" % [_points.size(), MIN_POINTS]


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
	_make_circle(210.0)


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
