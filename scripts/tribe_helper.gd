extends CharacterBody2D

## "Helpful" tribe monkey — Hurry Curry energy: bumps you, steals cargo/pickups, reduces fire progress.

enum Mood { WANDER, CHASE_PLAYER, STEAL_CARGO, HELP_FIRE }

@export var speed: float = 120.0
@export var mood: Mood = Mood.WANDER
@export var steal_radius: float = 40.0
@export var label_text: String = "Helper?"

var _target: Node2D = null
var _wander_dir: Vector2 = Vector2.RIGHT
var _wander_timer: float = 0.0
var _cooldown: float = 0.0
var _carry_visual: Sprite2D = null

@onready var label: Label = get_node_or_null("Label")


func _ready() -> void:
	add_to_group("tribe_helper")
	if label:
		label.text = label_text
	_pick_wander()
	_carry_visual = get_node_or_null("StolenBanana") as Sprite2D
	if _carry_visual:
		_carry_visual.visible = false


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	match mood:
		Mood.WANDER:
			_do_wander(delta)
		Mood.CHASE_PLAYER:
			if not _chase_group("cart", delta):
				_chase_group("player", delta)
		Mood.STEAL_CARGO:
			_steal_loop(delta)
		Mood.HELP_FIRE:
			_help_fire(delta)
	move_and_slide()
	_clamp_to_arena()


func set_mood(new_mood: Mood) -> void:
	mood = new_mood


func _do_wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_wander()
	velocity = _wander_dir * speed
	# Occasionally bump nearby player.
	if _cooldown <= 0.0:
		var player := _nearest_in_group("player")
		if player and global_position.distance_to(player.global_position) < 36.0:
			_bump(player)
			_cooldown = 1.4


func _chase_group(group_name: String, delta: float) -> bool:
	var target := _nearest_in_group(group_name)
	if target == null:
		return false
	var dir := (target.global_position - global_position).normalized()
	velocity = dir * speed * 1.15
	if _cooldown <= 0.0 and global_position.distance_to(target.global_position) < 34.0:
		_bump(target)
		_cooldown = 1.2
	return true


func _steal_loop(delta: float) -> void:
	# Prefer cart cargo area, else wander and bump.
	var cart := get_tree().get_first_node_in_group("cart") as Node2D
	if cart == null:
		_do_wander(delta)
		return
	var dir := (cart.global_position - global_position).normalized()
	velocity = dir * speed * 1.1
	if _carry_visual and _carry_visual.visible and _cooldown < 1.3:
		_carry_visual.visible = false
		if label:
			label.text = label_text
	if _cooldown <= 0.0 and global_position.distance_to(cart.global_position) < steal_radius:
		var run := cart.get_parent()
		if run and run.has_method("tribe_steal_cargo") and run.tribe_steal_cargo():
			if _carry_visual:
				_carry_visual.visible = true
			if label:
				label.text = "Helping!"
			_cooldown = 2.5


func _help_fire(delta: float) -> void:
	# Stand near fire stump and "help" by reducing progress via parent API.
	var camp := get_tree().get_first_node_in_group("fire_camp")
	var stump_pos := Vector2(640, 480)
	var dir := (stump_pos - global_position).normalized()
	velocity = dir * speed * 0.8
	if _cooldown <= 0.0 and global_position.distance_to(stump_pos) < 80.0:
		if camp and camp.has_method("tribe_interfere"):
			camp.tribe_interfere(0.08)
			if label:
				label.text = "I help rub!"
			_cooldown = 0.8


func _bump(target: Node2D) -> void:
	if target is CharacterBody2D:
		var cb := target as CharacterBody2D
		var push := (cb.global_position - global_position).normalized()
		if push == Vector2.ZERO:
			push = Vector2.RIGHT
		cb.velocity += push * 260.0
	GameProgress.juice_shake.emit(0.1)
	if label:
		label.text = "Oops!"


func _nearest_in_group(group_name: String) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(group_name):
		if n is Node2D:
			var d := global_position.distance_to((n as Node2D).global_position)
			if d < best_d:
				best_d = d
				best = n
	return best


func _pick_wander() -> void:
	_wander_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	if _wander_dir == Vector2.ZERO:
		_wander_dir = Vector2.RIGHT
	_wander_timer = randf_range(0.8, 2.0)


func _clamp_to_arena() -> void:
	global_position.x = clampf(global_position.x, 40.0, 1240.0)
	global_position.y = clampf(global_position.y, 40.0, 680.0)
