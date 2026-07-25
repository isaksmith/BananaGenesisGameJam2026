extends Node2D

## Banana Chef: walk to stations, press E to prep orders, and serve the queue.

const STATION_SCRIPT := preload("res://scripts/chef_station.gd")
const BANANA_TEX := preload("res://assets/sprites/banana.png")
const PEELED_TEX := preload("res://assets/sprites/banana_peeled.png")
const SMOOTHIE_TEX := preload("res://assets/sprites/chef_stations/smoothie_glass.png")
const SALAD_TEX := preload("res://assets/sprites/chef_stations/salad_bowl.png")
const MUSIC := "res://assets/audio/trails/banana-chef-song.mp3"
const ORDERS_TO_WIN := 6
const MAX_MISSES := 3
const ORDER_PATIENCE := 28.0
const INTERACT_RANGE := 110.0

const RECIPES := {
	&"plain": {
		"name": "Plain Banana",
		"steps": "Banana Crate -> Serve",
		"color": Color(1.0, 0.9, 0.2),
	},
	&"cooked": {
		"name": "Cooked Banana",
		"steps": "Banana Crate -> Fire Grill -> Serve",
		"color": Color(1.0, 0.48, 0.12),
	},
	&"salad": {
		"name": "Banana Salad",
		"steps": "Banana Crate -> Chop -> Salad Bowl -> Serve",
		"color": Color(0.45, 0.9, 0.3),
	},
	&"smoothie": {
		"name": "Banana Smoothie",
		"steps": "Banana Crate -> Blender -> Serve",
		"color": Color(0.85, 0.45, 1.0),
	},
}

const CUSTOMER_TYPES := [
	{
		"name": "Jungle Monkey",
		"texture": "res://assets/sprites/chef_customers/monkey.png",
		"scale": 0.72,
		"tint": Color(1, 1, 1),
	},
	{
		"name": "Golden Monkey",
		"texture": "res://assets/sprites/chef_customers/monkey.png",
		"scale": 0.72,
		"tint": Color(1.3, 0.9, 0.35),
	},
	{
		"name": "Monkey King",
		"texture": "res://assets/sprites/chef_customers/king_0.png",
		"scale": 1.35,
		"tint": Color(1, 1, 1),
	},
	{
		"name": "Silverback",
		"texture": "res://assets/sprites/chef_customers/gorilla.png",
		"scale": 0.72,
		"tint": Color(0.9, 0.95, 1.0),
	},
	{
		"name": "Berry Monkey",
		"texture": "res://assets/sprites/chef_customers/monkey.png",
		"scale": 0.72,
		"tint": Color(0.8, 0.55, 1.15),
	},
]

var _held: StringName = &""
var _current_order: StringName = &""
var _last_order: StringName = &""
var _served: int = 0
var _misses: int = 0
var _patience: float = ORDER_PATIENCE
var _done: bool = false
var _order_paused: bool = false
var _customer_index: int = -1
var _customer: Node2D
var _customer_sprite: Sprite2D
var _order_bubble: Panel
var _order_label: Label
var _customer_label: Label
var _player: CharacterBody2D
var _carry_sprite: Sprite2D
var _stations: Array[Area2D] = []
var _active_station: Area2D
var _interact_cooldown: float = 0.0

@onready var hint: Label = %HintLabel
@onready var score_label: Label = %ScoreLabel
@onready var held_label: Label = %HeldLabel
@onready var patience_bar: ProgressBar = %PatienceBar
@onready var customer_slot: Node2D = %CustomerSlot


func _ready() -> void:
	add_to_group("fire_camp")
	AudioSettings.play_music(MUSIC)
	_player = get_node_or_null("Monkey") as CharacterBody2D
	if _player:
		# Kitchen floor — stations sit in this band so E-interact always reaches.
		_player.global_position = Vector2(640, 560)
	_build_kitchen()
	_build_customer()
	_build_carry_visual()
	_update_hud()
	hint.text = "Banana Chef! Walk up to a station and press E  ·  Esc/Q exits"
	_next_customer()


func _process(delta: float) -> void:
	if _done:
		return
	_interact_cooldown = maxf(_interact_cooldown - delta, 0.0)
	if _player:
		_player.global_position.x = clampf(_player.global_position.x, 60.0, 1220.0)
		# Let the chef walk around and above the raised prep-station row.
		_player.global_position.y = clampf(_player.global_position.y, 160.0, 680.0)
	_update_nearest_station()
	if _order_paused:
		return
	_patience = maxf(_patience - delta, 0.0)
	patience_bar.value = (_patience / ORDER_PATIENCE) * 100.0
	if _order_bubble:
		_order_bubble.modulate = Color.WHITE.lerp(Color(1.0, 0.35, 0.25), 1.0 - _patience / ORDER_PATIENCE)
	if _patience <= 0.0:
		_customer_missed()


func _unhandled_input(event: InputEvent) -> void:
	if _done or _order_paused:
		return
	if event.is_action_pressed("interact"):
		_try_use_nearest_station()
		get_viewport().set_input_as_handled()


func _build_kitchen() -> void:
	# Raise the prep row to leave walking room both above and below it.
	var defs := [
		[&"bananas", "Banana Crate", "Pick up a plain banana", Color(1.0, 0.85, 0.2), Vector2(150, 315)],
		[&"grill", "Fire Grill", "Cook a plain banana", Color(1.0, 0.35, 0.1), Vector2(370, 315)],
		[&"chop", "Chopping Board", "Chop a plain banana", Color(0.65, 0.85, 0.4), Vector2(590, 315)],
		[&"salad", "Salad Bowl", "Mix chopped banana salad", Color(0.35, 0.85, 0.35), Vector2(810, 315)],
		[&"blender", "Blender", "Blend a plain banana", Color(0.75, 0.4, 1.0), Vector2(1030, 315)],
		[&"serve", "Serve Counter", "Give the order to the customer", Color(1.0, 0.72, 0.15), Vector2(640, 455)],
		[&"trash", "Compost", "Discard what you are carrying", Color(0.45, 0.35, 0.25), Vector2(1120, 560)],
	]
	for def: Array in defs:
		var station := Area2D.new()
		station.set_script(STATION_SCRIPT)
		station.position = def[4]
		add_child(station)
		station.setup(def[0], def[1], def[2], def[3])
		_stations.append(station)


func _build_customer() -> void:
	_customer = Node2D.new()
	_customer.name = "ChefCustomer"
	_customer.position = customer_slot.position
	add_child(_customer)

	var shadow := Polygon2D.new()
	shadow.z_index = -1
	shadow.color = Color(0, 0, 0, 0.35)
	shadow.polygon = PackedVector2Array([
		Vector2(-36, 25), Vector2(36, 25), Vector2(26, 36), Vector2(-26, 36),
	])
	_customer.add_child(shadow)

	_customer_sprite = Sprite2D.new()
	_customer_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_customer.add_child(_customer_sprite)

	_customer_label = Label.new()
	_customer_label.position = Vector2(-100, 46)
	_customer_label.size = Vector2(200, 25)
	_customer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_customer_label.add_theme_font_size_override("font_size", 15)
	_customer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_customer_label.add_theme_constant_override("outline_size", 4)
	_customer.add_child(_customer_label)

	_order_bubble = Panel.new()
	# Keep instructions beside the customer, clear of the centered Serve Counter.
	_order_bubble.position = Vector2(100, -145)
	_order_bubble.size = Vector2(430, 94)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1.0, 0.97, 0.84, 0.97)
	box.border_color = Color(0.2, 0.1, 0.05)
	box.set_border_width_all(4)
	box.set_corner_radius_all(14)
	_order_bubble.add_theme_stylebox_override("panel", box)
	_customer.add_child(_order_bubble)

	_order_label = Label.new()
	_order_label.position = Vector2(14, 8)
	_order_label.size = Vector2(402, 78)
	_order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_order_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_order_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_order_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_order_label.clip_text = true
	_order_label.add_theme_font_size_override("font_size", 15)
	_order_label.add_theme_color_override("font_color", Color(0.16, 0.08, 0.03))
	_order_bubble.add_child(_order_label)


func _build_carry_visual() -> void:
	if _player == null:
		return
	_carry_sprite = Sprite2D.new()
	_carry_sprite.name = "ChefCarry"
	_carry_sprite.texture = BANANA_TEX
	_carry_sprite.position = Vector2(0, -54)
	_carry_sprite.scale = Vector2(0.75, 0.75)
	_carry_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_carry_sprite.visible = false
	_carry_sprite.z_index = 5
	_player.add_child(_carry_sprite)


func _update_nearest_station() -> void:
	if _player == null:
		return
	var best: Area2D = null
	var best_d := INTERACT_RANGE
	for station in _stations:
		if not is_instance_valid(station):
			continue
		var d := _player.global_position.distance_to(station.global_position)
		if d < best_d:
			best_d = d
			best = station
	if _active_station != best:
		if _active_station and is_instance_valid(_active_station) and _active_station.has_method("set_prompt_visible"):
			_active_station.set_prompt_visible(false)
		_active_station = best
		if _active_station and _active_station.has_method("set_prompt_visible"):
			_active_station.set_prompt_visible(true)


func _try_use_nearest_station() -> void:
	_update_nearest_station()
	if _active_station == null:
		_station_feedback("Walk closer to a station, then press E.")
		return
	if _active_station.has_method("interact"):
		_active_station.interact(_player)


func use_chef_station(station_id: StringName) -> void:
	if _done or _order_paused or _interact_cooldown > 0.0:
		return
	_interact_cooldown = 0.18
	match station_id:
		&"bananas":
			if _held.is_empty():
				_set_held(&"plain")
				_station_feedback("Picked up a plain banana.")
			else:
				_station_feedback("Hands full! Serve or compost it first.")
		&"grill":
			if _held == &"plain":
				_set_held(&"cooked")
				_station_feedback("Sizzle! Cooked banana ready.")
				_spawn_sparks(Vector2(370, 380))
			else:
				_need_message("a plain banana")
		&"chop":
			if _held == &"plain":
				_set_held(&"chopped")
				_station_feedback("Chop chop! Now take it to the Salad Bowl.")
			else:
				_need_message("a plain banana")
		&"salad":
			if _held == &"chopped":
				_set_held(&"salad")
				_station_feedback("Banana salad mixed!")
			else:
				_need_message("chopped banana")
		&"blender":
			if _held == &"plain":
				_set_held(&"smoothie")
				_station_feedback("Whirr! Banana smoothie ready.")
				GameProgress.juice_shake.emit(0.08)
			else:
				_need_message("a plain banana")
		&"serve":
			_try_serve()
		&"trash":
			if _held.is_empty():
				_station_feedback("Nothing to compost.")
			else:
				_set_held(&"")
				_station_feedback("Composted. Start the order again.")


func _try_serve() -> void:
	if _held.is_empty():
		_station_feedback("Bring the customer's meal here first.")
		return
	if _held != _current_order:
		var wanted := str(RECIPES[_current_order]["name"])
		var got := _held_name()
		_station_feedback("Wrong order: %s wanted, not %s." % [wanted, got])
		GameProgress.juice_shake.emit(0.08)
		return

	_served += 1
	_set_held(&"")
	_station_feedback("Order served! %d/%d happy customers" % [_served, ORDERS_TO_WIN])
	GameProgress.juice_shake.emit(0.2)
	_spawn_food_burst(_customer.global_position + Vector2(0, -20))
	if _served >= ORDERS_TO_WIN:
		_succeed()
	else:
		_animate_customer_exit(true)


func _next_customer() -> void:
	if _done:
		return
	_customer_index = (_customer_index + 1) % CUSTOMER_TYPES.size()
	var customer: Dictionary = CUSTOMER_TYPES[_customer_index]
	_customer_sprite.texture = load(str(customer["texture"])) as Texture2D
	_customer_sprite.scale = Vector2.ONE * float(customer["scale"])
	_customer_sprite.modulate = customer["tint"]
	_customer_label.text = str(customer["name"])

	var keys := RECIPES.keys()
	var next: StringName = keys[randi() % keys.size()]
	if next == _last_order and keys.size() > 1:
		next = keys[(keys.find(next) + 1) % keys.size()]
	_current_order = next
	_last_order = next
	_patience = ORDER_PATIENCE
	var recipe: Dictionary = RECIPES[_current_order]
	_order_label.text = "One %s, please!\n%s" % [recipe["name"], recipe["steps"]]
	_order_bubble.modulate = Color.WHITE
	_customer.position = customer_slot.position + Vector2(260, 0)
	_customer.visible = true
	var tw := create_tween()
	tw.tween_property(_customer, "position", customer_slot.position, 0.5).set_trans(Tween.TRANS_BACK)
	_update_hud()


func _customer_missed() -> void:
	_misses += 1
	_station_feedback("Too slow! The customer left hungry. Strike %d/%d" % [_misses, MAX_MISSES])
	GameProgress.juice_shake.emit(0.12)
	_set_held(&"")
	if _misses >= MAX_MISSES:
		# Keep the jam flow forgiving: reset the shift rather than ejecting the player.
		_misses = 0
		_served = maxi(_served - 1, 0)
		hint.text = "Kitchen reset! Serve %d more customers." % (ORDERS_TO_WIN - _served)
	_animate_customer_exit(false)


func _animate_customer_exit(happy: bool) -> void:
	_order_paused = true
	_order_label.text = "Delicious!" if happy else "Too slow!"
	var tw := create_tween()
	tw.tween_property(_customer, "position", customer_slot.position + Vector2(-300, 0), 0.45)
	tw.tween_callback(func() -> void:
		_order_paused = false
		_next_customer()
	)


func _set_held(item: StringName) -> void:
	_held = item
	_update_hud()
	if _carry_sprite == null:
		return
	_carry_sprite.visible = not item.is_empty()
	_carry_sprite.modulate = Color.WHITE
	match item:
		&"cooked":
			_carry_sprite.texture = PEELED_TEX
			_carry_sprite.modulate = Color(1.0, 0.55, 0.2)
			_carry_sprite.scale = Vector2(0.75, 0.75)
		&"chopped":
			_carry_sprite.texture = PEELED_TEX
			_carry_sprite.modulate = Color(1.0, 0.95, 0.45)
			_carry_sprite.scale = Vector2(0.7, 0.7)
		&"salad":
			_carry_sprite.texture = SALAD_TEX
			_carry_sprite.scale = Vector2(0.7, 0.7)
		&"smoothie":
			_carry_sprite.texture = SMOOTHIE_TEX
			_carry_sprite.scale = Vector2(0.7, 0.7)
		&"plain":
			_carry_sprite.texture = BANANA_TEX
			_carry_sprite.scale = Vector2(0.75, 0.75)
		_:
			_carry_sprite.texture = BANANA_TEX
			_carry_sprite.scale = Vector2(0.75, 0.75)


func _held_name() -> String:
	if _held.is_empty():
		return "Nothing"
	if _held == &"chopped":
		return "Chopped Banana"
	return str(RECIPES.get(_held, {"name": str(_held).capitalize()})["name"])


func _update_hud() -> void:
	score_label.text = "Orders: %d/%d  ·  Misses: %d/%d" % [_served, ORDERS_TO_WIN, _misses, MAX_MISSES]
	held_label.text = "Carrying: %s" % _held_name()


func _station_feedback(text: String) -> void:
	hint.text = text


func _need_message(required: String) -> void:
	_station_feedback("That station needs %s. You have %s." % [required, _held_name()])


func _succeed() -> void:
	if _done:
		return
	_done = true
	_order_paused = true
	hint.text = "Shift complete! Banana Chef is open for business!"
	_order_label.text = "BEST CHEF!"
	_spawn_food_burst(Vector2(640, 380))
	GameProgress.juice_shake.emit(0.5)
	await get_tree().create_timer(1.2).timeout
	GameProgress.complete_minigame(GameProgress.MODE_FIRE)


func _spawn_sparks(at: Vector2) -> void:
	var sparks := CPUParticles2D.new()
	sparks.position = at
	sparks.one_shot = true
	sparks.explosiveness = 0.85
	sparks.amount = 24
	sparks.lifetime = 0.6
	sparks.direction = Vector2(0, -1)
	sparks.spread = 180.0
	sparks.initial_velocity_min = 60.0
	sparks.initial_velocity_max = 160.0
	sparks.gravity = Vector2(0, 180)
	sparks.color = Color(1.0, 0.6, 0.15, 1)
	add_child(sparks)
	sparks.emitting = true
	sparks.finished.connect(sparks.queue_free)


func _spawn_food_burst(at: Vector2) -> void:
	for i in 10:
		var banana := Sprite2D.new()
		banana.texture = BANANA_TEX
		banana.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		banana.scale = Vector2(0.45, 0.45)
		banana.global_position = at
		banana.z_index = 30
		add_child(banana)
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / 10.0)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(banana, "global_position", at + dir * randf_range(65, 130), 0.5)
		tw.tween_property(banana, "rotation", randf_range(-5, 5), 0.5)
		tw.tween_property(banana, "modulate:a", 0.0, 0.5).set_delay(0.18)
		tw.chain().tween_callback(banana.queue_free)
