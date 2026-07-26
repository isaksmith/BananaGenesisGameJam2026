extends Node

## On-screen touch controls for mobile / touchscreen web (itch.io).
## Injects the same input actions the desktop keyboard uses.

const LAYER := 20
const STICK_RADIUS := 64.0
const STICK_DEADZONE := 0.18
const MOVE_ACTIONS := ["move_left", "move_right", "move_up", "move_down"]

var _layer: CanvasLayer
var _root: Control
var _stick_pad: Control
var _stick_base: Panel
var _stick_knob: Panel
var _actions: Control
var _btn_interact: Button
var _btn_jump: Button
var _btn_exit: Button
var _btn_restart: Button
var _btn_craft: Button

var _active: bool = false
var _stick_finger: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_vec: Vector2 = Vector2.ZERO
var _stick_driving: bool = false
var _owned_moves: Dictionary = {} # action -> bool


func _ready() -> void:
	# Phones/tablets report a touchscreen; desktop itch browsers usually don't.
	var force := "--touch-controls" in OS.get_cmdline_user_args()
	var touchscreen := DisplayServer.is_touchscreen_available()
	_active = force or touchscreen
	_build_ui()
	_set_overlay_visible(false)
	if force or touchscreen:
		call_deferred("_refresh")
	elif OS.has_feature("web"):
		# Desktop web: reveal only after the first real finger press.
		set_process_input(true)
	if GameProgress:
		GameProgress.mode_changed.connect(_on_mode_changed)


func _input(event: InputEvent) -> void:
	# First finger on a desktop-web session → enable the overlay permanently.
	if _active:
		return
	if event is InputEventScreenTouch and event.pressed:
		_active = true
		set_process_input(false)
		_refresh()


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "TouchControlsLayer"
	_layer.layer = LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	_root = Control.new()
	_root.name = "TouchRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)

	_stick_pad = Control.new()
	_stick_pad.name = "StickPad"
	_stick_pad.anchor_left = 0.0
	_stick_pad.anchor_top = 1.0
	_stick_pad.anchor_right = 0.0
	_stick_pad.anchor_bottom = 1.0
	_stick_pad.offset_left = 16.0
	_stick_pad.offset_top = -220.0
	_stick_pad.offset_right = 196.0
	_stick_pad.offset_bottom = -40.0
	_stick_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	_stick_pad.gui_input.connect(_on_stick_gui_input)
	_root.add_child(_stick_pad)

	_stick_base = _make_circle_panel(Color(0.08, 0.1, 0.08, 0.38), Color(1, 1, 1, 0.22))
	_stick_base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_pad.add_child(_stick_base)

	_stick_knob = _make_circle_panel(Color(1.0, 0.85, 0.25, 0.75), Color(0.2, 0.12, 0.02, 0.9))
	_stick_knob.custom_minimum_size = Vector2(56, 56)
	_stick_knob.size = Vector2(56, 56)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_pad.add_child(_stick_knob)
	_recenter_knob()

	_actions = Control.new()
	_actions.name = "ActionCluster"
	_actions.anchor_left = 1.0
	_actions.anchor_top = 1.0
	_actions.anchor_right = 1.0
	_actions.anchor_bottom = 1.0
	_actions.offset_left = -210.0
	_actions.offset_top = -280.0
	_actions.offset_right = -16.0
	_actions.offset_bottom = -40.0
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_actions)

	_btn_interact = _make_action_button("E", Vector2(108, 108), Color(1.0, 0.78, 0.2, 0.88))
	_btn_interact.position = Vector2(70, 110)
	_btn_interact.button_down.connect(func() -> void: _pulse_action("interact", true))
	_btn_interact.button_up.connect(func() -> void: _pulse_action("interact", false))
	_actions.add_child(_btn_interact)

	_btn_jump = _make_action_button("JUMP", Vector2(108, 108), Color(0.45, 0.85, 1.0, 0.88))
	_btn_jump.position = Vector2(70, 0)
	_btn_jump.button_down.connect(func() -> void: _pulse_action("jump", true))
	_btn_jump.button_up.connect(func() -> void: _pulse_action("jump", false))
	_actions.add_child(_btn_jump)

	_btn_exit = _make_action_button("EXIT", Vector2(84, 48), Color(0.95, 0.45, 0.4, 0.85))
	_btn_exit.position = Vector2(0, 180)
	_btn_exit.button_down.connect(func() -> void: _pulse_action("exit_minigame", true))
	_btn_exit.button_up.connect(func() -> void: _pulse_action("exit_minigame", false))
	_actions.add_child(_btn_exit)

	_btn_restart = _make_action_button("R", Vector2(84, 48), Color(0.7, 0.7, 0.75, 0.85))
	_btn_restart.position = Vector2(0, 120)
	_btn_restart.button_down.connect(func() -> void: _pulse_action("restart", true))
	_btn_restart.button_up.connect(func() -> void: _pulse_action("restart", false))
	_actions.add_child(_btn_restart)

	_btn_craft = _make_action_button("BOOK", Vector2(84, 48), Color(0.85, 0.7, 0.45, 0.85))
	_btn_craft.position = Vector2(0, 60)
	_btn_craft.button_down.connect(func() -> void: _pulse_action("craft_menu", true))
	_btn_craft.button_up.connect(func() -> void: _pulse_action("craft_menu", false))
	_actions.add_child(_btn_craft)


func _make_circle_panel(fill: Color, border: Color) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(999)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _make_action_button(label: String, size: Vector2, color: Color) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = size
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = Color(0, 0, 0, 0.55)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(999 if size.x == size.y else 14)
	b.add_theme_stylebox_override("normal", sb)
	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = color.lightened(0.15)
	b.add_theme_stylebox_override("pressed", sb_p)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.06, 0.02, 1))
	b.add_theme_font_size_override("font_size", 18 if size.y >= 80 else 14)
	return b


func _on_mode_changed(_mode: StringName) -> void:
	# Scene swaps use queue_free — wait a couple frames so Stage children settle.
	call_deferred("_refresh_after_scene_swap")


func _refresh_after_scene_swap() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_refresh()


func _refresh() -> void:
	if _layer == null:
		return
	if not _active:
		_set_overlay_visible(false)
		_clear_stick_input()
		return

	var mode := GameProgress.current_mode if GameProgress else &"hub"
	var wheel_run := _stage_has_script("wheel_run.gd")
	var wheel_draw := _stage_has_script("wheel_draw.gd") and not wheel_run
	var win := mode == GameProgress.MODE_WIN
	var book_open := _recipe_book_open()

	# Drawing studio has its own full-screen drag UI — stay out of the way.
	if win or wheel_draw or book_open:
		_set_overlay_visible(false)
		_clear_stick_input()
		return

	_set_overlay_visible(true)

	var hub := mode == GameProgress.MODE_HUB
	var chef := mode == GameProgress.MODE_FIRE
	var maze := mode == GameProgress.MODE_CART
	var defense := mode == GameProgress.MODE_CHASE

	_stick_pad.visible = hub or chef or maze or defense or wheel_run
	_btn_interact.visible = hub or chef
	_btn_jump.visible = wheel_run
	_btn_exit.visible = chef or maze or defense or wheel_run
	_btn_restart.visible = wheel_run
	_btn_craft.visible = hub

	# Trails only need horizontal movement.
	if wheel_run and _stick_driving:
		_stick_vec.y = 0.0


func _stage_has_script(script_file: String) -> bool:
	var stage := get_tree().root.get_node_or_null("Main/Stage")
	if stage == null:
		return false
	for child in stage.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var script: Script = child.get_script() as Script
		if script == null:
			continue
		if String(script.resource_path).ends_with(script_file):
			return true
	return false


func _recipe_book_open() -> bool:
	var book := get_tree().root.get_node_or_null("Main/UI/RecipeBook")
	if book == null:
		return false
	var panel := book.get_node_or_null("Panel") as CanvasItem
	return panel != null and panel.visible


func _set_overlay_visible(v: bool) -> void:
	if _root:
		_root.visible = v
	if not v:
		_stick_finger = -1
		_stick_vec = Vector2.ZERO
		_recenter_knob()


func _pulse_action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0
	Input.parse_input_event(ev)
	# Also mirror into the action state so pollers see it immediately.
	if pressed:
		Input.action_press(action, 1.0)
	else:
		Input.action_release(action)


func _on_stick_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _stick_finger < 0:
			_stick_finger = st.index
			_stick_origin = _stick_pad.size * 0.5
			_update_stick(st.position)
			_stick_pad.accept_event()
		elif not st.pressed and st.index == _stick_finger:
			_stick_finger = -1
			_stick_vec = Vector2.ZERO
			_recenter_knob()
			_clear_stick_input()
			_stick_pad.accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _stick_finger:
			_update_stick(sd.position)
			_stick_pad.accept_event()
		return
	# Mouse fallback for `--touch-controls` desktop testing only.
	if DisplayServer.is_touchscreen_available():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_stick_finger = 0
				_stick_origin = _stick_pad.size * 0.5
				_update_stick(mb.position)
			else:
				_stick_finger = -1
				_stick_vec = Vector2.ZERO
				_recenter_knob()
				_clear_stick_input()
			_stick_pad.accept_event()
	elif event is InputEventMouseMotion and _stick_finger == 0:
		_update_stick((event as InputEventMouseMotion).position)
		_stick_pad.accept_event()


func _update_stick(local_pos: Vector2) -> void:
	var delta := local_pos - _stick_origin
	if delta.length() > STICK_RADIUS:
		delta = delta.normalized() * STICK_RADIUS
	_stick_vec = delta / STICK_RADIUS
	if GameProgress and GameProgress.current_mode == GameProgress.MODE_WHEEL and _stage_has_script("wheel_run.gd"):
		_stick_vec.y = 0.0
	_stick_knob.position = _stick_origin + delta - _stick_knob.size * 0.5
	_stick_driving = true
	_apply_stick_input()


func _recenter_knob() -> void:
	if _stick_pad == null or _stick_knob == null:
		return
	var c := _stick_pad.size * 0.5
	if c == Vector2.ZERO:
		c = Vector2(90, 90)
	_stick_knob.position = c - _stick_knob.size * 0.5
	_stick_driving = false


func _apply_stick_input() -> void:
	var v := _stick_vec
	if v.length() < STICK_DEADZONE:
		_clear_stick_input()
		return
	# Normalize outside deadzone so light tilts still register.
	var strength := clampf((v.length() - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 0.0, 1.0)
	var dir := v.normalized() * strength
	_set_move("move_right", maxf(dir.x, 0.0))
	_set_move("move_left", maxf(-dir.x, 0.0))
	_set_move("move_down", maxf(dir.y, 0.0))
	_set_move("move_up", maxf(-dir.y, 0.0))


func _set_move(action: String, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
		_owned_moves[action] = true
	elif _owned_moves.get(action, false):
		Input.action_release(action)
		_owned_moves[action] = false


func _clear_stick_input() -> void:
	for action in MOVE_ACTIONS:
		if _owned_moves.get(action, false):
			Input.action_release(action)
			_owned_moves[action] = false
	_stick_driving = false


func _process(_delta: float) -> void:
	if not _active or _root == null or not _root.visible:
		return
	# Keep stick strengths fresh for pollers; also hide if recipe book opens mid-frame.
	if _recipe_book_open():
		_refresh()
		return
	if _stick_driving:
		_apply_stick_input()
