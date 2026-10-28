extends Node2D

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
const PickupScript = preload("res://scripts/pickup.gd")
const EffectScript = preload("res://scripts/effect.gd")
const DamageNumberScript = preload("res://scripts/damage_number.gd")

const CYAN := Color(0.38, 0.95, 0.83)
const BLUE := Color(0.35, 0.8, 1.0)
const ORANGE := Color(1.0, 0.7, 0.35)
const RED := Color(1.0, 0.35, 0.45)
const PURPLE := Color(0.75, 0.55, 1.0)
const TEXT := Color(0.9, 0.95, 1.0)
const MUTED := Color(0.52, 0.61, 0.72)

var arena_bounds := Rect2(-1200, -800, 2400, 1600)
var world: Node2D
var player
var run_camera: Camera2D
var menu_camera: Camera2D
var boss_reference
var rng := RandomNumberGenerator.new()

var state := "menu"
var game_time := 0.0
var boss_time := 180.0
var boss_spawned := false
var spawn_timer := 0.0
var fire_timer := 0.0
var kills := 0
var level := 1
var xp := 0.0
var xp_next := 35.0
var rerolls := 1
var auto_fire := true
var camera_shake := 0.0
var visual_time := 0.0
var announcement_time := 0.0

var upgrade_definitions := {}
var upgrade_levels := {}
var current_choices: Array = []

var ui_font: SystemFont
var ui_root: Control
var hud: Control
var overlay: Control
var overlay_content: VBoxContainer
var hp_label: Label
var hp_bar: ProgressBar
var xp_label: Label
var xp_bar: ProgressBar
var level_label: Label
var timer_label: Label
var wave_label: Label
var stats_label: Label
var dash_label: Label
var dash_bar: ProgressBar
var auto_label: Label
var boss_panel: PanelContainer
var boss_bar: ProgressBar
var announcement_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_setup_input()
	_build_upgrade_definitions()
	menu_camera = Camera2D.new()
	menu_camera.position = Vector2.ZERO
	add_child(menu_camera)
	menu_camera.make_current()
	_create_ui()
	show_menu()

func _setup_input() -> void:
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"dash": [KEY_SPACE],
		"pause": [KEY_ESCAPE],
		"toggle_auto": [KEY_F]
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("shoot", mouse_event)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if state == "playing" or state == "paused":
			_toggle_pause()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_auto") and state == "playing":
		auto_fire = not auto_fire
		_announce("自动锁敌：开启" if auto_fire else "自动锁敌：关闭 · 按住左键射击", CYAN)
	elif state == "upgrade" and event is InputEventKey and event.pressed and not event.echo:
		var choice_index := -1
		match event.physical_keycode:
			KEY_1:
				choice_index = 0
			KEY_2:
				choice_index = 1
			KEY_3:
				choice_index = 2
		if choice_index >= 0 and choice_index < current_choices.size():
			_on_upgrade_selected(current_choices[choice_index]["id"])

func _process(delta: float) -> void:
	visual_time += delta
	queue_redraw()
	if announcement_time > 0.0:
		announcement_time -= delta
		announcement_label.modulate.a = clampf(announcement_time * 1.8, 0.0, 1.0)
		if announcement_time <= 0.0:
			announcement_label.hide()
	if is_instance_valid(run_camera):
		if camera_shake > 0.0:
			camera_shake = maxf(0.0, camera_shake - delta * 18.0)
			run_camera.offset = Vector2(rng.randf_range(-camera_shake, camera_shake), rng.randf_range(-camera_shake, camera_shake))
		else:
			run_camera.offset = Vector2.ZERO
	if state != "playing" or get_tree().paused:
		return

	game_time += delta
	fire_timer -= delta
	spawn_timer -= delta
	if fire_timer <= 0.0:
		fire_timer = 1.0 / player.fire_rate if _try_fire() else 0.08
	if not boss_spawned and game_time >= boss_time:
		_spawn_boss()
	if spawn_timer <= 0.0:
		_spawn_wave_enemy()
		spawn_timer = maxf(0.3, 1.02 - game_time * 0.0035)
	_update_hud()

func _draw() -> void:
	draw_rect(arena_bounds, Color(0.025, 0.038, 0.07), true)
	for x in range(-1200, 1201, 64):
		var color := Color(0.12, 0.22, 0.3, 0.2) if x % 256 == 0 else Color(0.1, 0.17, 0.25, 0.11)
		draw_line(Vector2(x, -800), Vector2(x, 800), color, 1.0, true)
	for y in range(-800, 801, 64):
		var color := Color(0.12, 0.22, 0.3, 0.2) if y % 256 == 0 else Color(0.1, 0.17, 0.25, 0.11)
		draw_line(Vector2(-1200, y), Vector2(1200, y), color, 1.0, true)
	var pulse := sin(visual_time * 0.8) * 5.0
	draw_arc(Vector2(-780, -440), 170 + pulse, 0.2, PI * 1.65, 80, Color(0.2, 0.7, 0.75, 0.09), 2.0, true)
	draw_arc(Vector2(790, 430), 230 - pulse, PI, TAU * 0.85, 80, Color(0.65, 0.35, 0.8, 0.08), 2.0, true)
	draw_circle(Vector2(850, -480), 90, Color(0.25, 0.65, 0.8, 0.025))
	draw_rect(arena_bounds, Color(0.25, 0.65, 0.7, 0.35), false, 3.0)

func _clear_world() -> void:
	get_tree().paused = false
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = null
	player = null
	run_camera = null
	boss_reference = null

func start_run() -> void:
	_clear_world()
	world = Node2D.new()
	world.name = "RunWorld"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	player = PlayerScript.new()
	player.arena_bounds = arena_bounds
	player.position = Vector2.ZERO
	world.add_child(player)
	player.died.connect(_on_player_died)
	player.damaged.connect(_on_player_damaged)
	player.dashed.connect(_on_player_dashed)
	run_camera = Camera2D.new()
	run_camera.position_smoothing_enabled = true
	run_camera.position_smoothing_speed = 7.0
	run_camera.limit_left = int(arena_bounds.position.x)
	run_camera.limit_top = int(arena_bounds.position.y)
	run_camera.limit_right = int(arena_bounds.end.x)
	run_camera.limit_bottom = int(arena_bounds.end.y)
	player.add_child(run_camera)
	run_camera.make_current()

	game_time = 0.0
	boss_spawned = false
	spawn_timer = 0.35
	fire_timer = 0.15
	kills = 0
	level = 1
	xp = 0.0
	xp_next = 35.0
	rerolls = 1
	camera_shake = 0.0
	upgrade_levels.clear()
	for id in upgrade_definitions:
		upgrade_levels[id] = 0
	state = "playing"
	overlay.hide()
	hud.show()
	boss_panel.hide()
	_announce("生存 03:00 · 击败随后抵达的监管者", CYAN)
	_update_hud()

func show_menu() -> void:
	_clear_world()
	state = "menu"
	hud.hide()
	menu_camera.make_current()
	_prepare_overlay()
	_overlay_label("R O G U E L I T E   / /   A R E N A   S U R V I V A L", 14, CYAN)
	_overlay_label("余 烬 协 议", 50, TEXT)
	_overlay_label("EMBER PROTOCOL", 16, MUTED)
	_overlay_label("在失控星港中，构筑最后一条生路。", 19, TEXT)
	var separator := HSeparator.new()
	overlay_content.add_child(separator)
	var features := HBoxContainer.new()
	features.add_theme_constant_override("separation", 12)
	overlay_content.add_child(features)
	features.add_child(_feature_card("01  自动锁敌", "专注走位与冲刺"))
	features.add_child(_feature_card("02  随机构筑", "升级模块三选一"))
	features.add_child(_feature_card("03  监管者", "3 分钟后决战"))
	_overlay_label("WASD / 方向键移动    ·    SPACE 冲刺    ·    鼠标瞄准\n自动射击，按住左键手动瞄准    ·    F 切换自动锁敌    ·    ESC 暂停", 15, MUTED)
	var start_button := _button("开始行动   →", start_run, CYAN)
	overlay_content.add_child(start_button)
	var quit_button := _button("退出游戏", _quit_game, MUTED)
	quit_button.custom_minimum_size.y = 40
	overlay_content.add_child(quit_button)
	start_button.grab_focus()

func _toggle_pause() -> void:
	if state == "playing":
		state = "paused"
		get_tree().paused = true
		_prepare_overlay()
		_overlay_label("SYSTEM / STANDBY", 14, CYAN)
		_overlay_label("行动暂停", 40, TEXT)
		_overlay_label("战场时间已冻结", 17, MUTED)
		overlay_content.add_child(_button("继续行动", _resume_run, CYAN))
		overlay_content.add_child(_button("重新开始", start_run, ORANGE))
		overlay_content.add_child(_button("返回主菜单", show_menu, MUTED))
	elif state == "paused":
		_resume_run()

func _resume_run() -> void:
	state = "playing"
	get_tree().paused = false
	overlay.hide()

func _end_run(victory: bool) -> void:
	if state == "game_over" or state == "victory":
		return
	state = "victory" if victory else "game_over"
	get_tree().paused = true
	_prepare_overlay()
	_overlay_label("PROTOCOL / COMPLETE" if victory else "SIGNAL / LOST", 14, CYAN if victory else RED)
	_overlay_label("星港已净化" if victory else "余烬已熄灭", 42, CYAN if victory else RED)
	_overlay_label("监管者已被摧毁，航道重新开放。" if victory else "本次构筑已终止，调整模块后再试一次。", 17, MUTED)
	var score := kills * 10 + level * 100 + int(game_time) * 5 + (1500 if victory else 0)
	_overlay_label("行动得分  %06d" % score, 26, ORANGE)
	_overlay_label("存活时间  %s      击杀  %d      同步等级  %d" % [_format_time(game_time), kills, level], 18, TEXT)
	overlay_content.add_child(_button("再次行动", start_run, CYAN))
	overlay_content.add_child(_button("返回主菜单", show_menu, MUTED))

func _quit_game() -> void:
	get_tree().quit()

func _nearest_enemy():
	var nearest
	var best_distance := INF
	if not is_instance_valid(player):
		return null
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_dying:
			continue
		var distance: float = player.global_position.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = enemy
	return nearest

func _try_fire() -> bool:
	if not is_instance_valid(player) or player.is_dead:
		return false
	var manual := Input.is_action_pressed("shoot")
	if not auto_fire and not manual:
		player.is_auto_aiming = false
		return false
	var target_position: Vector2 = player.get_global_mouse_position()
	if auto_fire and not manual:
		var target = _nearest_enemy()
		if target == null:
			player.is_auto_aiming = false
			return false
		target_position = target.global_position
		player.is_auto_aiming = true
	else:
		player.is_auto_aiming = false
	var direction: Vector2 = (target_position - player.global_position).normalized()
	if direction.length_squared() < 0.1:
		return false
	player.aim_angle = direction.angle()
	player.play_attack()
	for index in range(player.projectile_count):
		var spread := (float(index) - float(player.projectile_count - 1) * 0.5) * 0.14
		var critical: bool = rng.randf() < player.crit_chance
		var bullet = ProjectileScript.new()
		bullet.position = player.position + direction * 29.0
		bullet.velocity = direction.rotated(spread) * player.projectile_speed
		bullet.damage = player.damage * (player.crit_multiplier if critical else 1.0)
		bullet.pierce = player.pierce
		bullet.friendly = true
		bullet.lifetime = 1.8
		bullet.is_critical = critical
		bullet.tint = ORANGE if critical else CYAN
		bullet.radius = 5.0 if critical else 4.0
		world.add_child(bullet)
	_spawn_effect("ring", player.position + direction * 30.0, CYAN, 0.12, 3.0, 15.0)
	return true

func _spawn_wave_enemy() -> void:
	if get_tree().get_nodes_in_group("enemies").size() >= 135:
		return
	var roll := rng.randf()
	var kind := "chaser"
	if game_time < 30.0:
		kind = "swift" if game_time > 10.0 and roll < 0.28 else "chaser"
	elif game_time < 75.0:
		if roll < 0.16:
			kind = "tank"
		elif roll < 0.48:
			kind = "swift"
	else:
		if roll < 0.16:
			kind = "tank"
		elif roll < 0.36:
			kind = "shooter"
		elif roll < 0.62:
			kind = "swift"
	_spawn_enemy(kind, _spawn_position())

func _spawn_position() -> Vector2:
	for attempt in range(12):
		var direction := Vector2.from_angle(rng.randf() * TAU)
		var point: Vector2 = player.position + direction * rng.randf_range(730.0, 930.0)
		point.x = clampf(point.x, arena_bounds.position.x + 50.0, arena_bounds.end.x - 50.0)
		point.y = clampf(point.y, arena_bounds.position.y + 50.0, arena_bounds.end.y - 50.0)
		if point.distance_to(player.position) > 540.0:
			return point
	return player.position + Vector2(700, 0)

func _spawn_enemy(kind: String, at: Vector2):
	var enemy = EnemyScript.new()
	enemy.setup(kind, player, 1.0 + game_time / 240.0, arena_bounds)
	enemy.position = at
	world.add_child(enemy)
	enemy.died.connect(_on_enemy_died)
	enemy.hit_taken.connect(_on_enemy_hit_taken)
	enemy.projectile_requested.connect(_on_enemy_projectile)
	enemy.summon_requested.connect(_on_enemy_summon)
	return enemy

func _spawn_boss() -> void:
	boss_spawned = true
	boss_reference = _spawn_enemy("boss", _spawn_position())
	_spawn_effect("ring", boss_reference.position, RED, 1.2, 20.0, 180.0)
	_announce("警告：监管者已抵达", RED)
	camera_shake = 12.0

func _on_enemy_died(enemy) -> void:
	kills += 1
	_spawn_effect("burst", enemy.position, enemy.tint, 0.42, 10.0, enemy.radius * 2.4)
	_spawn_effect("ring", enemy.position, enemy.tint, 0.35, enemy.radius, enemy.radius * 2.0)
	if enemy.is_boss:
		boss_reference = null
		_end_run(true)
		return
	_spawn_pickup("xp", enemy.xp_reward, enemy.position)
	if rng.randf() < 0.055 and player.hp < player.max_hp * 0.8:
		_spawn_pickup("health", 18.0, enemy.position + Vector2(12, 0))

func _on_enemy_hit_taken(amount: float, critical: bool, at: Vector2) -> void:
	var number = DamageNumberScript.new()
	number.text = "%d!" % roundi(amount) if critical else str(roundi(amount))
	number.position = at + Vector2(-12, -24)
	number.add_theme_font_override("font", ui_font)
	number.add_theme_font_size_override("font_size", 20 if critical else 15)
	number.add_theme_color_override("font_color", ORANGE if critical else TEXT)
	number.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	number.add_theme_constant_override("outline_size", 3)
	world.add_child(number)

func _on_enemy_projectile(enemy, direction: Vector2, count: int) -> void:
	if state != "playing":
		return
	for index in range(count):
		var angle := direction.angle() + TAU * float(index) / float(count) if count > 1 else direction.angle()
		var bullet = ProjectileScript.new()
		bullet.position = enemy.position + Vector2.from_angle(angle) * (enemy.radius + 8.0)
		bullet.velocity = Vector2.from_angle(angle) * (230.0 if count > 1 else 330.0)
		bullet.damage = enemy.damage * (0.55 if count > 1 else 0.9)
		bullet.friendly = false
		bullet.lifetime = 4.5
		bullet.tint = RED if count > 1 else Color(1.0, 0.45, 0.72)
		bullet.radius = 6.0 if count > 1 else 5.0
		world.add_child(bullet)

func _on_enemy_summon(enemy, count: int) -> void:
	if state != "playing":
		return
	for index in range(count):
		var at: Vector2 = enemy.position + Vector2.from_angle(TAU * float(index) / float(count)) * 95.0
		_spawn_enemy("swift" if index % 2 == 0 else "chaser", at)
	_spawn_effect("ring", enemy.position, PURPLE, 0.65, 30.0, 120.0)

func _spawn_pickup(kind: String, amount: float, at: Vector2) -> void:
	var pickup = PickupScript.new()
	pickup.player = player
	pickup.kind = kind
	pickup.amount = amount
	pickup.position = at
	world.add_child(pickup)
	pickup.collected.connect(_on_pickup_collected)

func _on_pickup_collected(kind: String, amount: float) -> void:
	if state != "playing":
		return
	if kind == "health":
		player.heal(amount)
		_spawn_effect("ring", player.position, Color(0.45, 1.0, 0.65), 0.35, 10.0, 48.0)
	else:
		xp += amount
		_check_level_up()

func _check_level_up() -> void:
	if state != "playing" or xp < xp_next:
		return
	xp -= xp_next
	level += 1
	xp_next = roundi(32.0 * pow(1.24, float(level - 1)) + level * 4.0)
	if level % 4 == 0:
		rerolls = mini(2, rerolls + 1)
	current_choices = _roll_upgrades()
	state = "upgrade"
	get_tree().paused = true
	_show_upgrade_overlay()

func _build_upgrade_definitions() -> void:
	upgrade_definitions = {
		"payload": {"code": "DMG", "name": "过载弹芯", "description": "弹丸伤害 +25%", "max_level": 6, "color": ORANGE},
		"rapid": {"code": "RATE", "name": "超频枪机", "description": "射击速度 +20%", "max_level": 6, "color": CYAN},
		"multishot": {"code": "+1", "name": "分岔协议", "description": "额外发射 1 枚弹丸", "max_level": 3, "color": PURPLE},
		"pierce": {"code": "PEN", "name": "相位穿透", "description": "弹丸穿透 +1 个目标", "max_level": 3, "color": BLUE},
		"hull": {"code": "HP", "name": "强化舱体", "description": "生命上限 +25 并修复", "max_level": 5, "color": Color(0.45, 1.0, 0.65)},
		"thrusters": {"code": "SPD", "name": "矢量推进", "description": "移动速度 +12%", "max_level": 5, "color": CYAN},
		"magnet": {"code": "MAG", "name": "引力采集器", "description": "拾取范围 +50", "max_level": 4, "color": BLUE},
		"armor": {"code": "DEF", "name": "反应装甲", "description": "每次受击伤害 -2", "max_level": 5, "color": ORANGE},
		"critical": {"code": "CRIT", "name": "弱点解析", "description": "暴击几率 +10%", "max_level": 5, "color": ORANGE},
		"regen": {"code": "REG", "name": "纳米修复", "description": "每秒恢复 0.75 生命", "max_level": 4, "color": Color(0.45, 1.0, 0.65)},
		"dash": {"code": "DASH", "name": "闪避电容", "description": "冲刺冷却时间 -15%", "max_level": 4, "color": PURPLE},
		"velocity": {"code": "VEL", "name": "磁轨加速器", "description": "弹速 +18%，伤害 +8%", "max_level": 4, "color": BLUE}
	}

func _roll_upgrades() -> Array:
	var available: Array = []
	for id in upgrade_definitions:
		if upgrade_levels[id] < upgrade_definitions[id]["max_level"]:
			available.append(id)
	var choices: Array = []
	while choices.size() < 3 and not available.is_empty():
		var index := rng.randi_range(0, available.size() - 1)
		var id = available.pop_at(index)
		var definition: Dictionary = upgrade_definitions[id].duplicate()
		definition["id"] = id
		definition["level"] = upgrade_levels[id]
		choices.append(definition)
	return choices

func _show_upgrade_overlay() -> void:
	_prepare_overlay()
	_overlay_label("SYNCHRONIZATION / LEVEL %02d" % level, 14, CYAN)
	_overlay_label("选择一项强化模块", 32, TEXT)
	_overlay_label("时间已冻结 · 点击卡片或按 1 / 2 / 3", 15, MUTED)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_content.add_child(cards)
	for choice in current_choices:
		var card := _button("%s  %s\n\n%s\n\nLv.%d  →  Lv.%d" % [choice["code"], choice["name"], choice["description"], choice["level"], choice["level"] + 1], Callable(), choice["color"])
		card.custom_minimum_size = Vector2(240, 190)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.pressed.connect(_on_upgrade_selected.bind(choice["id"]))
		cards.add_child(card)
	var reroll_button := _button("重新校准（剩余 %d 次）" % rerolls, _reroll_upgrades, PURPLE)
	reroll_button.disabled = rerolls <= 0
	overlay_content.add_child(reroll_button)

func _reroll_upgrades() -> void:
	if state != "upgrade" or rerolls <= 0:
		return
	rerolls -= 1
	current_choices = _roll_upgrades()
	_show_upgrade_overlay()

func _on_upgrade_selected(id: String) -> void:
	if state != "upgrade" or not upgrade_definitions.has(id):
		return
	upgrade_levels[id] += 1
	match id:
		"payload":
			player.damage *= 1.25
		"rapid":
			player.fire_rate *= 1.2
		"multishot":
			player.projectile_count += 1
		"pierce":
			player.pierce += 1
		"hull":
			player.max_hp += 25.0
			player.heal(25.0)
		"thrusters":
			player.move_speed *= 1.12
		"magnet":
			player.pickup_radius += 50.0
		"armor":
			player.armor += 2.0
		"critical":
			player.crit_chance = minf(0.65, player.crit_chance + 0.1)
		"regen":
			player.regen += 0.75
		"dash":
			player.dash_cooldown_max *= 0.85
			player.dash_cooldown = minf(player.dash_cooldown, player.dash_cooldown_max)
		"velocity":
			player.projectile_speed *= 1.18
			player.damage *= 1.08
	state = "playing"
	get_tree().paused = false
	overlay.hide()
	_spawn_effect("ring", player.position, CYAN, 0.55, 12.0, 85.0)
	_announce("模块装载：%s" % upgrade_definitions[id]["name"], CYAN)
	_update_hud()
	call_deferred("_check_level_up")

func _on_player_died() -> void:
	_spawn_effect("burst", player.position, CYAN, 0.8, 20.0, 120.0)
	camera_shake = 15.0
	_end_run(false)

func _on_player_damaged(_amount: float) -> void:
	_spawn_effect("ring", player.position, RED, 0.25, 14.0, 48.0)
	camera_shake = maxf(camera_shake, 7.0)
	_update_hud()

func _on_player_dashed(origin: Vector2, direction: Vector2) -> void:
	var effect = _spawn_effect("dash", origin, CYAN, 0.28, 0.0, 0.0)
	effect.rotation = direction.angle()

func _spawn_effect(kind: String, at: Vector2, tint: Color, duration: float, start_radius: float, end_radius: float):
	var effect = EffectScript.new()
	effect.kind = kind
	effect.position = at
	effect.tint = tint
	effect.duration = duration
	effect.start_radius = start_radius
	effect.end_radius = end_radius
	world.add_child(effect)
	return effect

func _update_hud() -> void:
	if not is_instance_valid(player):
		return
	hp_label.text = "舱体完整度  %d / %d" % [ceili(player.hp), roundi(player.max_hp)]
	hp_bar.value = player.hp / player.max_hp * 100.0
	level_label.text = "LV.%02d" % level
	xp_label.text = "同步进度  %d / %d" % [floori(xp), roundi(xp_next)]
	xp_bar.value = xp / xp_next * 100.0
	timer_label.text = _format_time(game_time)
	wave_label.text = _wave_name()
	stats_label.text = "击杀  %04d\n强化  %02d" % [kills, level - 1]
	dash_bar.value = player.dash_progress() * 100.0
	dash_label.text = "冲刺  [SPACE]  " + ("就绪" if player.dash_cooldown <= 0.0 else "%.1fs" % player.dash_cooldown)
	auto_label.text = "自动锁敌 [F]  " + ("ON" if auto_fire else "OFF")
	auto_label.add_theme_color_override("font_color", CYAN if auto_fire else MUTED)
	if is_instance_valid(boss_reference) and not boss_reference.is_dying:
		boss_panel.show()
		boss_bar.value = boss_reference.hp / boss_reference.max_hp * 100.0
	else:
		boss_panel.hide()

func _wave_name() -> String:
	if boss_spawned:
		return "最终波次 · 监管者"
	if game_time < 30.0:
		return "波次 01 · 失控重启"
	if game_time < 75.0:
		return "波次 02 · 猎杀协议"
	if game_time < 120.0:
		return "波次 03 · 交叉火力"
	return "波次 04 · 临界崩溃"

func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), floori(fmod(seconds, 60.0))]

func _announce(text: String, color: Color) -> void:
	announcement_label.text = text
	announcement_label.add_theme_color_override("font_color", color)
	announcement_label.modulate.a = 1.0
	announcement_label.show()
	announcement_time = 2.8

func _create_ui() -> void:
	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	var theme := Theme.new()
	theme.default_font = ui_font
	theme.default_font_size = 18
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	layer.add_child(ui_root)
	_full_rect(ui_root)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = theme
	_create_hud()
	overlay = Control.new()
	ui_root.add_child(overlay)
	_full_rect(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.008, 0.015, 0.035, 0.9)
	overlay.add_child(dim)
	_full_rect(dim)
	var center := CenterContainer.new()
	overlay.add_child(center)
	_full_rect(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(800, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	overlay_content = VBoxContainer.new()
	overlay_content.add_theme_constant_override("separation", 14)
	panel.add_child(overlay_content)
	overlay.hide()

func _create_hud() -> void:
	hud = Control.new()
	ui_root.add_child(hud)
	_full_rect(hud)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var status_panel := PanelContainer.new()
	status_panel.position = Vector2(24, 20)
	status_panel.custom_minimum_size = Vector2(320, 0)
	status_panel.add_theme_stylebox_override("panel", _small_panel_style())
	hud.add_child(status_panel)
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 6)
	status_panel.add_child(status_box)
	var header := HBoxContainer.new()
	status_box.add_child(header)
	hp_label = _label("舱体完整度", 15, TEXT)
	header.add_child(hp_label)
	level_label = _label("LV.01", 16, CYAN)
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(level_label)
	hp_bar = _progress_bar(CYAN, Vector2(290, 12))
	status_box.add_child(hp_bar)
	xp_bar = _progress_bar(BLUE, Vector2(290, 7))
	status_box.add_child(xp_bar)
	xp_label = _label("同步进度", 12, MUTED)
	status_box.add_child(xp_label)

	timer_label = _label("00:00", 30, TEXT)
	hud.add_child(timer_label)
	timer_label.anchor_left = 0.5
	timer_label.anchor_right = 0.5
	timer_label.offset_left = -120
	timer_label.offset_right = 120
	timer_label.offset_top = 16
	timer_label.offset_bottom = 54
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label = _label("波次 01", 13, MUTED)
	hud.add_child(wave_label)
	wave_label.anchor_left = 0.5
	wave_label.anchor_right = 0.5
	wave_label.offset_left = -150
	wave_label.offset_right = 150
	wave_label.offset_top = 54
	wave_label.offset_bottom = 78
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	stats_label = _label("击杀  0000", 16, TEXT)
	hud.add_child(stats_label)
	stats_label.anchor_left = 1.0
	stats_label.anchor_right = 1.0
	stats_label.offset_left = -200
	stats_label.offset_right = -28
	stats_label.offset_top = 24
	stats_label.offset_bottom = 86
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	boss_panel = PanelContainer.new()
	hud.add_child(boss_panel)
	boss_panel.anchor_left = 0.5
	boss_panel.anchor_right = 0.5
	boss_panel.offset_left = -260
	boss_panel.offset_right = 260
	boss_panel.offset_top = 88
	boss_panel.offset_bottom = 140
	boss_panel.add_theme_stylebox_override("panel", _small_panel_style())
	var boss_box := VBoxContainer.new()
	boss_box.add_theme_constant_override("separation", 4)
	boss_panel.add_child(boss_box)
	var boss_name := _label("监管者  //  HARBINGER", 13, RED)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_name)
	boss_bar = _progress_bar(RED, Vector2(480, 9))
	boss_box.add_child(boss_bar)
	boss_panel.hide()

	var dash_panel := PanelContainer.new()
	hud.add_child(dash_panel)
	dash_panel.anchor_top = 1.0
	dash_panel.anchor_bottom = 1.0
	dash_panel.offset_left = 24
	dash_panel.offset_right = 270
	dash_panel.offset_top = -82
	dash_panel.offset_bottom = -22
	dash_panel.add_theme_stylebox_override("panel", _small_panel_style())
	var dash_box := VBoxContainer.new()
	dash_box.add_theme_constant_override("separation", 5)
	dash_panel.add_child(dash_box)
	dash_label = _label("冲刺 [SPACE]", 13, TEXT)
	dash_box.add_child(dash_label)
	dash_bar = _progress_bar(PURPLE, Vector2(205, 7))
	dash_box.add_child(dash_bar)

	var hint := _label("WASD 移动    ·    SPACE 冲刺    ·    ESC 暂停", 13, MUTED)
	hud.add_child(hint)
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -240
	hint.offset_right = 240
	hint.offset_top = -40
	hint.offset_bottom = -16
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	auto_label = _label("自动锁敌 [F] ON", 13, CYAN)
	hud.add_child(auto_label)
	auto_label.anchor_left = 1.0
	auto_label.anchor_right = 1.0
	auto_label.anchor_top = 1.0
	auto_label.anchor_bottom = 1.0
	auto_label.offset_left = -260
	auto_label.offset_right = -24
	auto_label.offset_top = -40
	auto_label.offset_bottom = -16
	auto_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	announcement_label = _label("", 23, CYAN)
	hud.add_child(announcement_label)
	announcement_label.anchor_left = 0.5
	announcement_label.anchor_right = 0.5
	announcement_label.offset_left = -420
	announcement_label.offset_right = 420
	announcement_label.offset_top = 154
	announcement_label.offset_bottom = 194
	announcement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announcement_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06))
	announcement_label.add_theme_constant_override("outline_size", 5)
	announcement_label.hide()

func _prepare_overlay() -> void:
	overlay.show()
	for child in overlay_content.get_children():
		overlay_content.remove_child(child)
		child.queue_free()

func _overlay_label(text: String, font_size: int, color: Color) -> void:
	var label := _label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_content.add_child(label)

func _feature_card(title: String, subtitle: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(235, 72)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _small_panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var title_label := _label(title, 15, CYAN)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	var subtitle_label := _label(subtitle, 13, MUTED)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle_label)
	return panel

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, callback: Callable, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 50)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.35, 0.4, 0.48))
	button.add_theme_stylebox_override("normal", _style(Color(0.055, 0.085, 0.14, 0.95), Color(color.r, color.g, color.b, 0.35), 8, 1))
	button.add_theme_stylebox_override("hover", _style(Color(0.09, 0.15, 0.22, 1.0), color, 8, 2))
	button.add_theme_stylebox_override("pressed", _style(Color(0.12, 0.2, 0.27, 1.0), color, 8, 2))
	button.add_theme_stylebox_override("disabled", _style(Color(0.04, 0.055, 0.08), Color(0.15, 0.18, 0.23), 8, 1))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), color, 8, 2))
	if callback.is_valid():
		button.pressed.connect(callback)
	return button

func _progress_bar(color: Color, minimum: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = minimum
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.add_theme_stylebox_override("background", _style(Color(0.025, 0.045, 0.075), Color(0.12, 0.18, 0.25), 4, 1))
	bar.add_theme_stylebox_override("fill", _style(color, color, 4, 0))
	return bar

func _style(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border_width)
	return style

func _small_panel_style() -> StyleBoxFlat:
	var style := _style(Color(0.035, 0.055, 0.095, 0.94), Color(0.18, 0.32, 0.4, 0.7), 9, 1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _panel_style() -> StyleBoxFlat:
	var style := _style(Color(0.025, 0.045, 0.08, 0.98), Color(0.25, 0.75, 0.72, 0.45), 14, 1)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 26
	style.content_margin_bottom = 26
	return style

func _full_rect(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
