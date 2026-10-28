extends Node2D

var velocity := Vector2.ZERO
var damage := 10.0
var friendly := true
var pierce := 0
var radius := 4.0
var lifetime := 2.0
var is_critical := false
var tint := Color(0.45, 0.95, 0.85)
var hit_targets := {}

func _ready() -> void:
	z_index = 4
	rotation = velocity.angle()

func _process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	position += velocity * delta

	if friendly:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy.is_dying:
				continue
			var target_id: int = enemy.get_instance_id()
			if hit_targets.has(target_id):
				continue
			var hit_radius: float = radius + enemy.radius
			if global_position.distance_squared_to(enemy.global_position) <= hit_radius * hit_radius:
				hit_targets[target_id] = true
				enemy.take_damage(damage, is_critical, velocity.normalized() * 85.0)
				if pierce > 0:
					pierce -= 1
				else:
					queue_free()
					return
	else:
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			var player = players[0]
			var hit_radius: float = radius + player.radius
			if global_position.distance_squared_to(player.global_position) <= hit_radius * hit_radius:
				player.take_damage(damage)
				queue_free()

func _draw() -> void:
	var trail_color := tint
	trail_color.a = 0.25
	draw_line(Vector2(-18, 0), Vector2.ZERO, trail_color, radius * 1.4, true)
	draw_circle(Vector2.ZERO, radius + 3.0, Color(tint.r, tint.g, tint.b, 0.12))
	draw_circle(Vector2.ZERO, radius, tint)
	if is_critical:
		draw_arc(Vector2.ZERO, radius + 5.0, 0, TAU, 12, Color(1.0, 0.85, 0.35, 0.8), 1.5, true)
