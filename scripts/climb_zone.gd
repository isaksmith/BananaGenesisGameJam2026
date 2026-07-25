extends Area2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("set_climb_zone"):
		body.set_climb_zone(true)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("set_climb_zone"):
		body.set_climb_zone(false)
