extends Node2D

var kind := "ring"
var tint := Color(0.4, 0.95, 0.85)
var duration := 0.35
var start_radius := 8.0
var end_radius := 45.0
var age := 0.0

func _ready() -> void:
	z_index = 6

func _process(delta: float) -> void:
	age += delta
	if age >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := clampf(age / duration, 0.0, 1.0)
	var color := tint
	color.a *= 1.0 - progress
	match kind:
		"burst":
			var length := lerpf(start_radius, end_radius, progress)
			for index in range(8):
				var direction := Vector2.from_angle(TAU * float(index) / 8.0)
				draw_line(direction * length * 0.35, direction * length, color, 2.0, true)
		"dash":
			var points := PackedVector2Array([Vector2(24, 0), Vector2(-12, -13), Vector2(-6, 0), Vector2(-12, 13)])
			draw_colored_polygon(points, color)
		_:
			draw_arc(Vector2.ZERO, lerpf(start_radius, end_radius, progress), 0, TAU, 40, color, 2.5, true)
