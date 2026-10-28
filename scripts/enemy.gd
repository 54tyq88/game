extends Node2D

const TINKER_ATLAS = preload("res://assets/enemies/tinker-chaser.png")
const SPECTER_ATLAS = preload("res://assets/enemies/specter-swift.png")

signal died(enemy)
signal hit_taken(amount: float, critical: bool, at: Vector2)
signal projectile_requested(enemy, direction: Vector2, count: int)
signal summon_requested(enemy, count: int)

var kind := "chaser"
var player
var arena_bounds := Rect2(-1200, -800, 2400, 1600)
var radius := 16.0
var max_hp := 40.0
var hp := 40.0
var move_speed := 90.0
var damage := 10.0
var xp_reward := 5.0
var is_boss := false
var is_dying := false
var knockback := Vector2.ZERO
var aim_angle := 0.0
var attack_timer := 0.0
var fire_timer := 1.0
var summon_timer := 5.0
var flash := 0.0
var visual_time := 0.0
var tint := Color(1.0, 0.35, 0.45)

func setup(enemy_kind: String, target, difficulty: float, bounds: Rect2) -> void:
	kind = enemy_kind
	player = target
	arena_bounds = bounds
	is_boss = kind == "boss"
	match kind:
		"swift":
			radius = 12.0
			max_hp = 28.0
			move_speed = 158.0
			damage = 9.0
			xp_reward = 5.0
			tint = Color(0.72, 0.48, 1.0)
		"tank":
			radius = 25.0
			max_hp = 145.0
			move_speed = 54.0
			damage = 20.0
			xp_reward = 16.0
			tint = Color(1.0, 0.65, 0.3)
		"shooter":
			radius = 18.0
			max_hp = 68.0
			move_speed = 76.0
			damage = 11.0
			xp_reward = 12.0
			tint = Color(0.95, 0.4, 0.7)
			fire_timer = 1.2
		"boss":
			radius = 54.0
			max_hp = 1350.0
			move_speed = 48.0
			damage = 25.0
			xp_reward = 0.0
			tint = Color(1.0, 0.3, 0.4)
			fire_timer = 2.0
			summon_timer = 5.0
		_:
			radius = 16.0
			max_hp = 42.0
			move_speed = 92.0
			damage = 12.0
			xp_reward = 6.0
			tint = Color(1.0, 0.36, 0.43)
	max_hp *= difficulty
	hp = max_hp
	damage *= sqrt(difficulty)

func _ready() -> void:
	add_to_group("enemies")
	z_index = 3

func _physics_process(delta: float) -> void:
	if is_dying or not is_instance_valid(player) or player.is_dead:
		return
	visual_time += delta
	flash = maxf(0.0, flash - delta)
	attack_timer = maxf(0.0, attack_timer - delta)
	fire_timer -= delta
	summon_timer -= delta

	var offset: Vector2 = player.global_position - global_position
	var distance := offset.length()
	var direction := offset.normalized() if distance > 0.01 else Vector2.RIGHT
	aim_angle = lerp_angle(aim_angle, direction.angle(), minf(1.0, delta * 7.0))
	var desired_direction := direction

	if kind == "shooter":
		if distance < 230.0:
			desired_direction = -direction
		elif distance < 340.0:
			desired_direction = direction.orthogonal() * sin(visual_time * 1.8)
		if fire_timer <= 0.0 and distance < 720.0:
			projectile_requested.emit(self, direction, 1)
			fire_timer = 2.1
	elif is_boss:
		if fire_timer <= 0.0 and distance < 900.0:
			projectile_requested.emit(self, direction, 12)
			fire_timer = 2.35
		if summon_timer <= 0.0:
			summon_requested.emit(self, 3)
			summon_timer = 7.0

	position += (desired_direction * move_speed + knockback) * delta
	knockback = knockback.move_toward(Vector2.ZERO, delta * 520.0)
	position.x = clampf(position.x, arena_bounds.position.x + radius, arena_bounds.end.x - radius)
	position.y = clampf(position.y, arena_bounds.position.y + radius, arena_bounds.end.y - radius)

	if distance < radius + player.radius + 3.0 and attack_timer <= 0.0:
		player.take_damage(damage)
		attack_timer = 0.85 if not is_boss else 1.0
		knockback -= direction * 80.0
	queue_redraw()

func take_damage(amount: float, critical: bool, force: Vector2) -> void:
	if is_dying:
		return
	hp = maxf(0.0, hp - amount)
	flash = 0.1
	knockback += force / (2.8 if is_boss or kind == "tank" else 1.0)
	hit_taken.emit(amount, critical, global_position)
	if hp <= 0.0:
		is_dying = true
		died.emit(self)
		queue_free()

func _shape(sides: int, size: float, phase: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(sides):
		points.append(Vector2.from_angle(phase + TAU * float(index) / float(sides)) * size)
	return points

func _draw_tinker_chaser() -> void:
	var animation_row := 1
	var frame_index := int(visual_time * 10.0) % 4
	if flash > 0.0:
		animation_row = 3
		frame_index = 0
	elif attack_timer > 0.6:
		animation_row = 2
		var attack_progress := clampf((0.85 - attack_timer) / 0.25, 0.0, 0.999)
		frame_index = mini(3, int(attack_progress * 4.0))

	var facing := Vector2(-1.0, 1.0) if cos(aim_angle) < -0.01 else Vector2.ONE
	draw_set_transform(Vector2.ZERO, 0.0, facing)
	draw_texture_rect_region(
		TINKER_ATLAS,
		Rect2(-24, -31, 48, 40),
		Rect2(frame_index * 48, animation_row * 40, 48, 40)
	)
	draw_set_transform(Vector2.ZERO, 0.0)

func _draw_specter_swift() -> void:
	var animation_row := 1
	var frame_index := int(visual_time * 14.0) % 4
	if flash > 0.0:
		animation_row = 3
		frame_index = 0
	elif attack_timer > 0.6:
		animation_row = 2
		var attack_progress := clampf((0.85 - attack_timer) / 0.25, 0.0, 0.999)
		frame_index = mini(3, int(attack_progress * 4.0))

	var facing := Vector2(-1.0, 1.0) if cos(aim_angle) < -0.01 else Vector2.ONE
	draw_set_transform(Vector2.ZERO, 0.0, facing)
	draw_texture_rect_region(
		SPECTER_ATLAS,
		Rect2(-24, -34, 48, 44),
		Rect2(frame_index * 48, animation_row * 44, 48, 44)
	)
	draw_set_transform(Vector2.ZERO, 0.0)

func _draw() -> void:
	draw_circle(Vector2(0, radius * 0.45), radius * 0.95, Color(0.0, 0.0, 0.0, 0.25))
	var body_color := tint if flash <= 0.0 else Color.WHITE
	if kind == "chaser":
		_draw_tinker_chaser()
	elif kind == "swift":
		_draw_specter_swift()
	else:
		var dark_color := Color(tint.r * 0.2, tint.g * 0.2, tint.b * 0.25)
		draw_set_transform(Vector2.ZERO, aim_angle)
		var points := PackedVector2Array()
		match kind:
			"swift":
				points = _shape(4, radius, PI * 0.25)
			"tank":
				points = _shape(6, radius, PI / 6.0)
			"shooter":
				points = _shape(4, radius, 0.0)
			"boss":
				points = _shape(8, radius, visual_time * 0.25)
			_:
				points = PackedVector2Array([Vector2(radius, 0), Vector2(-radius * 0.75, -radius * 0.8), Vector2(-radius * 0.4, 0), Vector2(-radius * 0.75, radius * 0.8)])
		draw_colored_polygon(points, dark_color)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, body_color, 2.5 if not is_boss else 4.0, true)

		if kind == "shooter":
			draw_line(Vector2(2, 0), Vector2(radius + 10, 0), body_color, 4.0, true)
			draw_circle(Vector2.ZERO, 5, body_color)
		elif is_boss:
			draw_circle(Vector2.ZERO, 29, Color(tint.r, tint.g, tint.b, 0.12))
			draw_arc(Vector2.ZERO, 34, -visual_time, -visual_time + PI * 1.5, 36, body_color, 4.0, true)
			draw_circle(Vector2.ZERO, 13 + sin(visual_time * 4.0) * 2.0, body_color)
			draw_circle(Vector2.ZERO, 6, Color(1.0, 0.92, 0.85))
		else:
			draw_circle(Vector2(radius * 0.2, 0), maxf(3.0, radius * 0.22), body_color)
		draw_set_transform(Vector2.ZERO, 0.0)

	if hp < max_hp or is_boss:
		var width := radius * 2.0
		var bar_y := -42.0 if kind == "swift" else -radius - 13.0
		draw_rect(Rect2(-width * 0.5, bar_y, width, 4), Color(0.02, 0.03, 0.06, 0.85))
		draw_rect(Rect2(-width * 0.5, bar_y, width * (hp / max_hp), 4), body_color)
