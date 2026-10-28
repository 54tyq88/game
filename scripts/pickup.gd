extends Node2D

signal collected(kind: String, amount: float)

var player
var kind := "xp"
var amount := 5.0
var age := 0.0
var drift := Vector2.ZERO

func _ready() -> void:
	z_index = 2
	drift = Vector2.from_angle(randf() * TAU) * randf_range(25.0, 70.0)

func _process(delta: float) -> void:
	age += delta
	if not is_instance_valid(player):
		return
	position += drift * delta
	drift = drift.move_toward(Vector2.ZERO, delta * 180.0)
	var offset: Vector2 = player.global_position - global_position
	var distance := offset.length()
	if distance < player.pickup_radius:
		var pull := clampf(1.0 - distance / player.pickup_radius, 0.0, 1.0)
		position += offset.normalized() * lerpf(170.0, 650.0, pull) * delta
	if distance < player.radius + 12.0:
		collected.emit(kind, amount)
		queue_free()
	queue_redraw()

func _draw() -> void:
	var bob := sin(age * 5.0) * 2.0
	if kind == "health":
		var green := Color(0.45, 1.0, 0.65)
		draw_circle(Vector2(0, bob), 13, Color(0.45, 1.0, 0.65, 0.12))
		draw_rect(Rect2(-3, -9 + bob, 6, 18), green)
		draw_rect(Rect2(-9, -3 + bob, 18, 6), green)
	else:
		var cyan := Color(0.35, 0.9, 1.0)
		var points := PackedVector2Array([Vector2(0, -9 + bob), Vector2(7, bob), Vector2(0, 9 + bob), Vector2(-7, bob)])
		draw_circle(Vector2(0, bob), 14, Color(0.35, 0.9, 1.0, 0.1))
		draw_colored_polygon(points, Color(0.08, 0.28, 0.4))
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, cyan, 2.0, true)
