extends Node2D

const CARDIA_ATLAS = preload("res://assets/player/cardia-player.png")
const ATTACK_DURATION := 0.24

signal died
signal damaged(amount: float)
signal dashed(origin: Vector2, direction: Vector2)

var arena_bounds := Rect2(-1200, -800, 2400, 1600)
var radius := 17.0
var max_hp := 100.0
var hp := 100.0
var armor := 0.0
var regen := 0.0
var move_speed := 245.0
var damage := 22.0
var fire_rate := 3.2
var projectile_speed := 720.0
var projectile_count := 1
var pierce := 0
var crit_chance := 0.08
var crit_multiplier := 2.0
var pickup_radius := 115.0
var dash_cooldown_max := 2.4
var dash_cooldown := 0.0
var dash_time := 0.0
var dash_direction := Vector2.RIGHT
var invulnerable := 0.0
var aim_angle := 0.0
var is_auto_aiming := false
var is_dead := false
var flash := 0.0
var visual_time := 0.0
var attack_time := 0.0
var is_moving := false

func _ready() -> void:
	add_to_group("player")
	z_index = 5

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	visual_time += delta
	flash = maxf(0.0, flash - delta)
	attack_time = maxf(0.0, attack_time - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	if regen > 0.0 and hp > 0.0:
		hp = minf(max_hp, hp + regen * delta)

	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0:
		dash_direction = input_vector.normalized() if input_vector.length_squared() > 0.01 else Vector2.RIGHT.rotated(aim_angle)
		dash_time = 0.16
		dash_cooldown = dash_cooldown_max
		invulnerable = 0.3
		dashed.emit(global_position, dash_direction)

	var velocity := input_vector * move_speed
	if dash_time > 0.0:
		dash_time -= delta
		velocity = dash_direction * 850.0
	is_moving = input_vector.length_squared() > 0.01 or dash_time > 0.0
	position += velocity * delta
	position.x = clampf(position.x, arena_bounds.position.x + radius, arena_bounds.end.x - radius)
	position.y = clampf(position.y, arena_bounds.position.y + radius, arena_bounds.end.y - radius)

	if not is_auto_aiming:
		var mouse_offset := get_global_mouse_position() - global_position
		if mouse_offset.length_squared() > 1.0:
			aim_angle = mouse_offset.angle()
	queue_redraw()

func play_attack() -> void:
	if not is_dead:
		attack_time = ATTACK_DURATION

func take_damage(amount: float) -> void:
	if is_dead or invulnerable > 0.0:
		return
	var actual_damage := maxf(1.0, amount - armor)
	hp = maxf(0.0, hp - actual_damage)
	invulnerable = 0.45
	flash = 0.15
	damaged.emit(actual_damage)
	if hp <= 0.0:
		is_dead = true
		died.emit()

func heal(amount: float) -> void:
	if not is_dead:
		hp = minf(max_hp, hp + amount)

func dash_progress() -> float:
	return 1.0 - clampf(dash_cooldown / dash_cooldown_max, 0.0, 1.0)

func _draw() -> void:
	draw_circle(Vector2(0, 8), 20, Color(0.0, 0.0, 0.0, 0.28))
	var glow_alpha := 0.08 + sin(visual_time * 4.0) * 0.025
	draw_circle(Vector2.ZERO, 27, Color(0.35, 0.95, 0.82, glow_alpha))
	if dash_cooldown > 0.0:
		draw_arc(Vector2.ZERO, 27, -PI * 0.5, -PI * 0.5 + TAU * dash_progress(), 36, Color(0.35, 0.95, 0.82, 0.65), 2.0, true)
	else:
		draw_arc(Vector2.ZERO, 27, 0, TAU, 36, Color(0.35, 0.95, 0.82, 0.35), 2.0, true)

	var animation_row := 0
	var frame_index := 0
	if flash > 0.0:
		animation_row = 3
		frame_index = int(visual_time * 10.0) % 2
	elif attack_time > 0.0:
		animation_row = 2
		var attack_progress := 1.0 - attack_time / ATTACK_DURATION
		frame_index = mini(3, int(attack_progress * 4.0))
	elif is_moving:
		animation_row = 1
		frame_index = int(visual_time * (18.0 if dash_time > 0.0 else 12.0)) % 9
	else:
		frame_index = int(visual_time * 4.0) % 4

	var facing := Vector2(-1.0, 1.0) if cos(aim_angle) < -0.01 else Vector2.ONE
	var tint := Color(1.0, 0.9, 0.65) if dash_time > 0.0 else Color.WHITE
	draw_set_transform(Vector2.ZERO, 0.0, facing)
	draw_texture_rect_region(
		CARDIA_ATLAS,
		Rect2(-32, -50, 64, 64),
		Rect2(frame_index * 64, animation_row * 64, 64, 64),
		tint
	)
	draw_set_transform(Vector2.ZERO, 0.0)

	if invulnerable > 0.0:
		draw_arc(Vector2.ZERO, 32, visual_time * 5.0, visual_time * 5.0 + PI * 1.35, 28, Color(0.75, 0.95, 1.0, 0.65), 2.0, true)
