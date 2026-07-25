extends CharacterBody2D

@export var speed: float = 280.0
@export var climb_speed: float = 220.0
@export var hub_scale: float = 1.15
@export var default_scale: float = 0.78
## Slightly snappier while defending the banana stash.
@export var chase_speed_mult: float = 1.2

const CLUB_TEX := "res://assets/sprites/stick.png"

var _start_position: Vector2
var _nearby_interactable: Node = null
var _in_climb_zone: bool = false
var _facing: float = 1.0
var _anim_t: float = 0.0
var _bob_phase: float = 0.0
var _walk_frames: Array[Texture2D] = []
var _idle_tex: Texture2D
var _sprite: Sprite2D
var _glow: Sprite2D
var _trail: CPUParticles2D
var _shadow: Polygon2D
var _hub_fx: bool = false
var _club_pivot: Node2D
var _club_spr: Sprite2D
var _club_swing_t: float = 0.0
var _club_pulse: float = 0.0


func _ready() -> void:
	add_to_group("player")
	_start_position = global_position
	_sprite = get_node_or_null("Sprite") as Sprite2D
	_shadow = get_node_or_null("Shadow") as Polygon2D
	_idle_tex = load("res://assets/sprites/monkey_idle.png") as Texture2D
	_load_walk_frames()
	_setup_club()
	GameState.round_started.connect(_on_chase_round_started)
	GameProgress.mode_changed.connect(_on_mode_changed)
	if has_node("InteractArea"):
		$InteractArea.area_entered.connect(_on_interact_area_entered)
		$InteractArea.area_exited.connect(_on_interact_area_exited)
		$InteractArea.body_entered.connect(_on_interact_body_entered)
		$InteractArea.body_exited.connect(_on_interact_body_exited)
	_on_mode_changed(GameProgress.current_mode)


func _load_walk_frames() -> void:
	_walk_frames.clear()
	for i in 4:
		var tex := load("res://assets/sprites/monkey_frame_%02d.png" % i) as Texture2D
		if tex:
			_walk_frames.append(tex)
	if _walk_frames.is_empty() and _idle_tex:
		_walk_frames.append(_idle_tex)


func _on_mode_changed(mode: StringName) -> void:
	_hub_fx = mode == GameProgress.MODE_HUB
	_setup_hub_fx(_hub_fx)
	_apply_scale()
	_set_club_visible(mode == GameProgress.MODE_CHASE)


func _setup_club() -> void:
	_club_pivot = Node2D.new()
	_club_pivot.name = "ClubPivot"
	_club_pivot.z_index = 2
	_club_pivot.visible = false
	add_child(_club_pivot)

	_club_spr = Sprite2D.new()
	_club_spr.name = "Club"
	_club_spr.texture = load(CLUB_TEX) as Texture2D
	_club_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_club_spr.centered = true
	# Stick art points up-right; offset so the handle sits near the hand.
	_club_spr.offset = Vector2(10, -14)
	_club_spr.scale = Vector2(0.95, 0.95)
	_club_pivot.add_child(_club_spr)


func _set_club_visible(on: bool) -> void:
	if _club_pivot:
		_club_pivot.visible = on
	if not on:
		_club_pulse = 0.0


func pulse_club_swing() -> void:
	_club_pulse = 1.0


func _apply_scale() -> void:
	if _sprite == null:
		return
	var s := hub_scale if _hub_fx else default_scale
	_sprite.scale = Vector2(s * _facing, s)
	if _shadow:
		var shadow_s := 1.7 if _hub_fx else 1.45
		_shadow.scale = Vector2(shadow_s, shadow_s)


func _setup_hub_fx(enabled: bool) -> void:
	if enabled:
		if _glow == null:
			_glow = Sprite2D.new()
			_glow.name = "HubGlow"
			_glow.z_index = -2
			_glow.texture = _idle_tex
			_glow.modulate = Color(1.0, 0.92, 0.35, 0.35)
			_glow.offset = Vector2(0, -8)
			add_child(_glow)
			move_child(_glow, 0)
		if _trail == null:
			_trail = CPUParticles2D.new()
			_trail.name = "MoveTrail"
			_trail.z_index = -4
			_trail.emitting = false
			_trail.amount = 28
			_trail.lifetime = 0.45
			_trail.preprocess = 0.0
			_trail.explosiveness = 0.0
			_trail.randomness = 0.4
			_trail.local_coords = false
			_trail.direction = Vector2(0, -1)
			_trail.spread = 50.0
			_trail.gravity = Vector2(0, -20)
			_trail.initial_velocity_min = 18.0
			_trail.initial_velocity_max = 55.0
			_trail.scale_amount_min = 2.5
			_trail.scale_amount_max = 5.5
			_trail.color = Color(1.0, 0.88, 0.35, 0.75)
			var grad := Gradient.new()
			grad.colors = PackedColorArray([
				Color(1.0, 0.95, 0.45, 0.8),
				Color(1.0, 0.55, 0.15, 0.35),
				Color(0.6, 0.25, 0.05, 0.0),
			])
			_trail.color_ramp = grad
			add_child(_trail)
			move_child(_trail, 0)
		_glow.visible = true
	else:
		if _glow:
			_glow.visible = false
		if _trail:
			_trail.emitting = false
		if _sprite:
			_sprite.modulate = Color.WHITE
			_sprite.offset = Vector2(0, -8)


func _physics_process(delta: float) -> void:
	if GameProgress.current_mode == GameProgress.MODE_WIN:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_visuals(delta, false)
		return

	# During chase, freeze when round is over.
	if GameProgress.current_mode == GameProgress.MODE_CHASE and not GameState.is_playing:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_visuals(delta, false)
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_spd := speed
	if GameProgress.current_mode == GameProgress.MODE_CHASE:
		move_spd *= chase_speed_mult
	if _in_climb_zone:
		velocity = direction * climb_speed
	else:
		velocity = direction * move_spd
	move_and_slide()
	_update_visuals(delta, direction.length() > 0.15)


func _update_visuals(delta: float, moving: bool) -> void:
	if _sprite == null:
		return

	if absf(velocity.x) > 12.0:
		_facing = signf(velocity.x)

	var s := hub_scale if _hub_fx else default_scale
	_sprite.scale = Vector2(s * _facing, s)

	_bob_phase += delta * (7.0 if moving else 3.2)
	var bob := sin(_bob_phase) * (4.5 if _hub_fx else 1.5)
	if moving:
		bob += sin(_bob_phase * 2.0) * (2.0 if _hub_fx else 0.8)
	_sprite.offset = Vector2(0, -8 + bob)

	if moving and not _walk_frames.is_empty():
		_anim_t += delta * (14.0 if _hub_fx else 11.0)
		var frame_i := int(_anim_t) % _walk_frames.size()
		_sprite.texture = _walk_frames[frame_i]
	else:
		_anim_t = 0.0
		if _idle_tex:
			_sprite.texture = _idle_tex

	_update_club(delta, moving)

	if not _hub_fx:
		return

	# Soft pulse so the monkey pops against the busy jungle video.
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
	_sprite.modulate = Color(1.08, 1.04, 0.92).lerp(Color(1.2, 1.12, 0.75), pulse * 0.35)

	if _glow:
		_glow.texture = _sprite.texture
		_glow.scale = Vector2(s * 1.28 * _facing, s * 1.28)
		_glow.offset = _sprite.offset
		_glow.modulate = Color(1.0, 0.9, 0.3, 0.18 + pulse * 0.22)

	if _trail:
		_trail.emitting = moving
		if moving:
			_trail.direction = -velocity.normalized() if velocity.length() > 1.0 else Vector2(0, -1)
			# Leave sparkling banana-dust afterimages behind the monkey.
			if randf() < delta * 18.0:
				_spawn_afterimage()


func _update_club(delta: float, moving: bool) -> void:
	if _club_pivot == null or not _club_pivot.visible:
		return

	_club_swing_t += delta * (10.5 if moving else 6.5)
	_club_pulse = maxf(_club_pulse - delta * 3.2, 0.0)

	# Hand sits slightly forward of the monkey body.
	_club_pivot.position = Vector2(14.0 * _facing, -6.0 + sin(_bob_phase) * 1.5)
	_club_pivot.scale = Vector2(_facing, 1.0)

	var idle_swing := sin(_club_swing_t) * (0.55 if moving else 0.28)
	var strike := sin(_club_swing_t * 1.7) * _club_pulse * 1.15
	# Local rest angle; scale.x mirrors for left-facing.
	_club_pivot.rotation = -0.55 + idle_swing + strike


func _spawn_afterimage() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = _sprite.texture
	ghost.global_position = _sprite.global_position
	ghost.scale = _sprite.scale * 0.95
	ghost.offset = _sprite.offset
	ghost.modulate = Color(1.0, 0.85, 0.35, 0.45)
	ghost.z_index = z_index - 1
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_parent().add_child(ghost)
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.28)
	tw.parallel().tween_property(ghost, "scale", ghost.scale * 1.15, 0.28)
	tw.tween_callback(ghost.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()


func _try_interact() -> void:
	if _nearby_interactable and _nearby_interactable.has_method("interact"):
		_nearby_interactable.interact(self)


func set_climb_zone(active: bool) -> void:
	_in_climb_zone = active


func _on_chase_round_started() -> void:
	if GameProgress.current_mode == GameProgress.MODE_CHASE:
		global_position = _start_position
		velocity = Vector2.ZERO


func _on_interact_area_entered(area: Area2D) -> void:
	if area.is_in_group("interactable"):
		_nearby_interactable = area
	elif area.get_parent() and area.get_parent().is_in_group("interactable"):
		_nearby_interactable = area.get_parent()


func _on_interact_area_exited(area: Area2D) -> void:
	var candidate: Node = area
	if area.get_parent() and area.get_parent().is_in_group("interactable"):
		candidate = area.get_parent()
	if _nearby_interactable == candidate or _nearby_interactable == area:
		_nearby_interactable = null


func _on_interact_body_entered(body: Node2D) -> void:
	if body.is_in_group("interactable"):
		_nearby_interactable = body


func _on_interact_body_exited(body: Node2D) -> void:
	if _nearby_interactable == body:
		_nearby_interactable = null
