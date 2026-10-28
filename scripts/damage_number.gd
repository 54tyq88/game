extends Label

var lifetime := 0.65
var age := 0.0
var drift := Vector2.ZERO

func _ready() -> void:
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	drift = Vector2(randf_range(-12.0, 12.0), -52.0)

func _process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return
	position += drift * delta
	drift = drift.move_toward(Vector2.ZERO, delta * 35.0)
	modulate.a = 1.0 - pow(age / lifetime, 2.0)
