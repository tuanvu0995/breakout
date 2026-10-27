extends Node2D

class_name GameManager

@export var brick_scene: PackedScene = preload("res://scenes/brick/brick.tscn")
@export var block_energy: int = 10
@export var energy_block_energy: int = 100

@onready var paddle: CharacterBody2D = $Paddle
@onready var ball: CharacterBody2D = $Ball
@onready var spawn_pos_container: Node = $SpawnPos
@onready var brick_container: Node = $Bricks

## UI
@onready var energy_bar: Control = $CanvasLayer/EnergyBar
@onready var health_bar: Control = $CanvasLayer/HealthBar
@onready var score_ui = $CanvasLayer/Score
@onready var combo_timer: Timer = $ComboTimer
@onready var combo_lbl = $Combo

var health: int = 3
var energy: float = 0.0
var score_brick_destroyed: int = 200
var score_brick_touched: int = 50
var score: int = 0
var combo: int = 0
var bricks: Array
var bricks_to_destroy: Array
var time: float = 0
var started: bool = false
var level: int = 1
var base_ball_speed: float
var base_ball_max_speed: float
## FAST pickup: ball x2 speed and x2 points while it lasts.
const FAST_TIME := 10.0
var fast_time := 0.0
const PowerUp = preload("res://scenes/powerup/powerup.gd")
const POWERUP_CHANCE := 0.18

func _ready():
	randomize()
	
	hide_combo()
	
	Globals.camera = $Camera
	Globals.camera.objects = [ball, paddle]
	
	ball.attached_to = paddle.launch_point
	paddle.ball_attached = ball
	paddle.ball = ball
	balls = [ball]
	_wire_ball(ball)
	
	for brick in get_tree().get_nodes_in_group("Bricks"):
		brick.energy_brick_destroyed.connect(on_energy_brick_destroyed)
		
	level = Globals.start_level
	paddle.start.connect(_on_paddle_start)  # starts the clear timer on launch
	apply_flat_style()
	base_ball_speed = ball.speed
	base_ball_max_speed = ball.max_speed
	add_pause_handler()
	# Remove for testing with predefined bricks
	remove_all_bricks()
	layout_bricks()
	flash_text("CUSTOM LEVEL" if not Globals.custom_level.is_empty() else Levels.title_of(level))


func level_ball_speed() -> float:
	# ponytail: linear 8%/level ramp, swap for a curve if late levels feel unfair
	return base_ball_speed * (1.0 + 0.08 * (level - 1))

func set_fast(on: bool) -> void:
	fast_time = FAST_TIME if on else 0.0
	var mult := 2.0 if on else 1.0
	for b in balls:
		b.speed = level_ball_speed() * mult
		b.max_speed = base_ball_max_speed * mult
		if on: b.velocity *= 2.0

## EXPAND / SHRINK pickups move the side walls for a while.
const ARENA_TIME := 12.0
const ARENA_STEP := 130.0
const ARENA_MIN := 360.0
var level_half_width := 678.0
var arena_time := 0.0

func resize_arena(grow: bool) -> void:
	var hw: float = clamp(level_half_width + (ARENA_STEP if grow else -ARENA_STEP), ARENA_MIN, Levels.FULL_HALF_WIDTH)
	if is_equal_approx(hw, level_half_width):
		flash_text("ARENA AT LIMIT")
		return
	arena_time = ARENA_TIME
	set_field_width(hw, Levels.theme_of(level)["wall"])
	Globals.camera.shake(0.3, 14, 10)
	Audio.sfx("dash", -4.0, 0.0, 0.7 if grow else 1.3)

## Keep ball, paddle and barrier inside the (possibly moving) side walls.
func keep_inside_arena() -> void:
	var left: float = Levels.CX - backdrop.half_width
	var right: float = Levels.CX + backdrop.half_width
	var pad: float = paddle.get_node("CollisionShape").shape.size.x * paddle.scale.x / 2.0 + 4.0
	paddle.position.x = clamp(paddle.position.x, left + pad, right - pad)
	for b in balls:
		if b == paddle.ball_attached: continue
		var r := 20.0
		if b.global_position.x < left + r:
			b.global_position.x = left + r
			b.velocity.x = abs(b.velocity.x)
		elif b.global_position.x > right - r:
			b.global_position.x = right - r
			b.velocity.x = -abs(b.velocity.x)
	if is_instance_valid(barrier): barrier.resize(backdrop.half_width)

# ---------------------------------------------------------------- multiball

const BallScene = preload("res://scenes/ball/ball.tscn")
const MAX_BALLS := 6
var balls: Array = []

func _wire_ball(b: Node) -> void:
	b.hit_block.connect(_on_ball_hit_block)  # energy + touch score per ball hit

## Every ball in play splits into three (fanned out), up to MAX_BALLS.
func split_balls() -> void:
	if paddle.ball_attached: paddle.launch_ball()
	for src in balls.duplicate():
		for angle in [-0.4, 0.4]:
			if balls.size() >= MAX_BALLS: return
			var b = BallScene.instantiate()
			add_child(b)
			b.global_position = src.global_position
			b.speed = src.speed
			b.max_speed = src.max_speed
			b.attached_to = null
			var v: Vector2 = src.velocity if src.velocity.length() > 10.0 else Vector2.UP * src.speed
			b.velocity = v.rotated(angle)
			_wire_ball(b)
			balls.append(b)
			Fx.flash(self, b.global_position, Globals.C_VIOLET, 30)

func clear_extra_balls() -> void:
	for b in balls:
		if b != ball: b.queue_free()
	balls = [ball]

func _process(delta) -> void:
	keep_inside_arena()
	update_boss(delta)
	if arena_time > 0.0:
		arena_time -= delta
		if arena_time <= 0.0:
			set_field_width(level_half_width, Levels.theme_of(level)["wall"])
			flash_text("ARENA RESTORED")
	if fast_time > 0.0:
		fast_time -= delta
		if fast_time <= 0.0:
			set_fast(false)
			flash_text("FAST OVER")
	if not started: return
	time += delta
	
const Levels = preload("res://scenes/levels/levels.gd")

func layout_bricks() -> void:
	var theme: Dictionary = Levels.theme_of(level)
	$Pattern.color = theme["field"]
	$Wall/Polygon2D.color = theme["wall"]
	backdrop.set_theme(((level - 1) % Levels.COUNT) / 5, theme["field"], theme["wall"])
	frame_decor.set_color(theme["wall"])
	Audio.play_theme_music(((level - 1) % Levels.COUNT) / 5)
	Audio.sfx("level_start", -6.0)
	if Globals.custom_level.is_empty() and level <= Levels.COUNT:
		Leaderboard.start(level)
	var layout: Array = Globals.custom_level if not Globals.custom_level.is_empty() else Levels.build(level)
	lives_lost = 0
	boss = null
	boss_attack = 3.0
	level_half_width = Levels.half_width(level, layout)
	arena_time = 0.0
	set_field_width(level_half_width, theme["wall"])
	for item in layout:
		var b = add_brick(brick_container, item["pos"], item["spec"])
		# pop-in, staggered
		if b.is_boss: boss = b
		var target_scale: Vector2 = b.scale
		b.scale = Vector2.ZERO
		create_tween().tween_property(b, "scale", target_scale, 0.35) \
			.set_delay(0.008 * bricks.size()).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

var side_walls: Array = []

## Two movable walls that narrow the playfield per level.
func set_field_width(half_width: float, color: Color) -> void:
	create_tween().tween_property(backdrop, "half_width", half_width, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if side_walls.is_empty():
		for side in [-1, 1]:
			var body := StaticBody2D.new()
			var shape := CollisionShape2D.new()
			shape.shape = RectangleShape2D.new()
			shape.shape.size = Vector2(1000, 2400)
			shape.position.x = side * 500.0  # inner edge sits at body.position
			body.add_child(shape)
			var poly := Polygon2D.new()
			var x0 := 0.0 if side > 0 else -1000.0
			poly.polygon = PackedVector2Array([Vector2(x0, -1200), Vector2(x0 + 1000, -1200), Vector2(x0 + 1000, 1200), Vector2(x0, 1200)])
			body.add_child(poly)
			var decor := WallDecor.new()
			decor.rects = [Rect2(x0, -1200, 1000, 2400)]
			decor.rivet_x = side * 22.0  # just inside the arena-facing edge
			body.add_child(decor)
			body.position = Vector2(Levels.CX + side * (Levels.FULL_HALF_WIDTH + 1000), 540)
			add_child(body)
			move_child(body, backdrop.get_index() + 1)  # under bricks, over the backdrop
			side_walls.append(body)
	for i in 2:
		var side := -1 if i == 0 else 1
		side_walls[i].get_child(1).color = color
		side_walls[i].get_child(2).set_color(color)
		create_tween().tween_property(side_walls[i], "position:x", Levels.CX + side * half_width, 0.6) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func add_brick(parent: Node, pos: Vector2, spec: Dictionary = {}) -> Node:
	var instance = brick_scene.instantiate()
	instance.spec = spec
	instance.position = pos
	parent.add_child(instance)
	instance.energy_brick_destroyed.connect(on_energy_brick_destroyed)
	instance.destroyed.connect(on_brick_destroyed)
	bricks.append(instance)
	if instance.type != instance.TYPE.EXPLOSIVE and instance.type != instance.TYPE.ENERGY:
		bricks_to_destroy.append(instance)
	return instance

func remove_all_bricks() -> void:
	bricks.clear()
	bricks_to_destroy.clear()
	for brick in brick_container.get_children():
		brick.queue_free()

func reset_and_attach_ball() -> void:
	clear_extra_balls()
	ball.velocity = Vector2.ZERO
	ball.attached_to = paddle.launch_point
	ball.appear()
	paddle.ball_attached = ball
	paddle.game_over = false
	paddle.stage_clear = false

func add_energy(value: float) -> void:
	energy += value
	energy = clamp(energy, 0, 100)
	energy_bar.set_energy(energy)
	
func remove_energy(value: float) -> void:
	energy -= value
	energy = clamp(energy, 0, 100)
	energy_bar.set_energy(energy)

func reset_energy() -> void:
	energy = 0
	energy_bar.set_energy(energy)
	
func reset_health() -> void:
	health = 3
	health_bar.set_health(health)
	
func reset_score() -> void:
	score = 0
	score_ui.set_score(score)
	
func show_combo(combo: int) -> void:
	combo_lbl.text = "COMBO x%d" % combo
	combo_lbl.visible = true
	place_combo()
	combo_lbl.add_theme_color_override("font_color", [Globals.C_AMBER, Globals.C_CORAL, Globals.C_VIOLET, Globals.C_CYAN][min(combo / 5, 3)])
	Fx.punch(combo_lbl, 0.15 + min(combo, 10) * 0.02)
	pass
	
func hide_combo() -> void:
	combo_lbl.visible = false
	pass

const Backdrop = preload("res://scenes/effects/backdrop.gd")
const WallDecor = preload("res://scenes/effects/wall_decor.gd")
var backdrop: Node2D
var frame_decor: Node2D

func apply_flat_style() -> void:
	$Pattern.material = null
	$Pattern.color = Globals.C_FIELD
	$Wall/Polygon2D.texture = null
	$Wall/Polygon2D.color = Globals.C_WALL
	backdrop = Backdrop.new()
	backdrop.add_to_group("backdrop")
	add_child(backdrop)
	move_child(backdrop, $Pattern.get_index() + 1)
	# outer frame: left, right and top bands of the static wall polygon (wall-local coords)
	var hint := preload("res://scenes/ui/controls_hint/controls_hint.gd").new()
	hint.game = self
	hint.position = Vector2(32, 1080 - 32 - (150 if not DisplayServer.is_touchscreen_available() else 112))
	$CanvasLayer.add_child(hint)
	frame_decor = WallDecor.new()
	frame_decor.rects = [Rect2(-460, -400, 460, 1500), Rect2(1356, -400, 400, 1500), Rect2(0, -400, 1356, 400)]
	$Wall.add_child(frame_decor)
	combo_lbl.add_theme_color_override("font_color", Globals.C_AMBER)
	# Combo / announcements live in the HUD under the score, on a dark pill,
	# so they never blend into the bricks behind them.
	combo_lbl.reparent($CanvasLayer, false)
	combo_lbl.add_theme_font_size_override("font_size", 40)
	combo_lbl.add_theme_constant_override("outline_size", 0)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(Globals.C_DARK, 0.85)
	pill.set_corner_radius_all(26)
	pill.content_margin_left = 32; pill.content_margin_right = 32
	pill.content_margin_top = 6; pill.content_margin_bottom = 6
	combo_lbl.add_theme_stylebox_override("normal", pill)

## Shrink-wrap the pill to the text and keep it centered under the score.
func place_combo() -> void:
	combo_lbl.size = Vector2.ZERO
	combo_lbl.reset_size()
	combo_lbl.position = Vector2(960 - combo_lbl.size.x / 2.0, 88)

func next_level() -> void:
	# Clear bonus: faster clears earn more
	var bonus: int = 1000 * level + int(max(0.0, 120.0 - time) * 50)
	score += bonus
	Globals.stats["score"] = score
	score_ui.set_score(score)
	flash_text("CLEAR! +%d" % bonus)
	if Globals.custom_level.is_empty() and level <= Levels.COUNT:
		var clear_time := time
		if Globals.submit_time(level, clear_time):
			Fx.popup(self, Vector2(Levels.CX, 520), "BEST TIME %s" % Globals.format_time(clear_time), Globals.C_CYAN, 44)
		Leaderboard.submit(level, clear_time, score)
	Audio.sfx("level_clear", -2.0)
	var wait := 1.5
	if Globals.custom_level.is_empty() and level <= Levels.COUNT:
		var par := Levels.par_time(level)
		var got := [true, time <= par, lives_lost == 0]
		Globals.submit_stars(level, got.count(true))
		show_stars(got, par)
		wait = 3.0
	await get_tree().create_timer(wait).timeout
	if not Globals.custom_level.is_empty():
		get_tree().change_scene_to_file("res://scenes/editor/level_editor.tscn")
		return
	level += 1
	var unlocked := Globals.reach_level(level)
	time = 0.0
	set_fast(false)
	health = min(health + 1, 3)
	health_bar.set_health(health)
	clear_drops()
	remove_all_bricks()
	layout_bricks()
	if not unlocked.is_empty():
		flash_text("NEW SHIP: %s" % unlocked["name"])
	elif level == Levels.COUNT + 1:
		flash_text("ALL 30 CLEARED!  LOOP 2")
	else:
		flash_text(Levels.title_of(level))

var lives_lost := 0

## Three stars pop in one by one: CLEAR / UNDER PAR / NO LIFE LOST.
func show_stars(got: Array, par: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	var captions := ["CLEAR", "UNDER %s" % Globals.format_time(par).trim_suffix(".00"), "NO LIFE LOST"]
	for i in 3:
		var x := 960.0 + (i - 1) * 190.0
		var star := Sprite2D.new()
		star.texture = BrickShapes.texture("star")
		star.position = Vector2(x, 380 - (20 if i == 1 else 0))
		star.modulate = Globals.C_AMBER if got[i] else Color(Globals.C_WHITE, 0.15)
		star.scale = Vector2.ZERO
		layer.add_child(star)
		var cap := Label.new()
		cap.text = captions[i]
		cap.theme = load("res://theme/main_theme.tres")
		cap.size = Vector2(240, 30)
		cap.position = Vector2(x - 120, 460)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_size_override("font_size", 20)
		cap.add_theme_color_override("font_color", Globals.C_WHITE if got[i] else Color(Globals.C_WHITE, 0.35))
		cap.modulate.a = 0.0
		layer.add_child(cap)
		var tw := create_tween()
		tw.tween_interval(0.35 + i * 0.35)
		tw.tween_callback(func():
			if got[i]:
				Audio.sfx("powerup", -4.0, 0.0, 1.0 + i * 0.12)
				Fx.burst(self, star.position, Globals.C_AMBER, 14, 380.0)
		)
		tw.tween_property(star, "scale", Vector2.ONE * (2.3 if got[i] else 1.8), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cap, "modulate:a", 1.0, 0.2)
	var out := create_tween()
	out.tween_interval(2.7)
	out.tween_property(layer, "offset:y", -40.0, 0.25)
	out.tween_callback(layer.queue_free)

# ---------------------------------------------------------------- boss

const Debris = preload("res://scenes/effects/boss_debris.gd")
var boss: Node2D
var boss_attack := 3.0
var boss_bar: Control

func update_boss(delta: float) -> void:
	var alive: bool = is_instance_valid(boss) and not boss.isDestroyed
	if alive and boss_bar == null: _build_boss_bar()
	if boss_bar:
		boss_bar.visible = alive
		if alive:
			boss_bar.get_node("Bar").value = boss.health / boss.max_health * 100.0
	if not alive or not started: return
	boss_attack -= delta
	if boss_attack <= 0.0 and boss.collision_layer != 0:
		# attacks speed up as the boss loses health
		boss_attack = lerp(1.4, 3.0, boss.health / boss.max_health)
		var d := Debris.new()
		d.color = boss.spec.get("color", Globals.C_RED)
		d.hit.connect(on_debris_hit)
		add_child(d)
		d.global_position = boss.global_position + Vector2(0, 60)

func _build_boss_bar() -> void:
	boss_bar = VBoxContainer.new()
	boss_bar.position = Vector2(960 - 360, 150)
	boss_bar.custom_minimum_size = Vector2(720, 0)
	var name_lbl := Label.new()
	name_lbl.text = boss.spec.get("name", "BOSS")
	name_lbl.theme = load("res://theme/main_theme.tres")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 26)
	name_lbl.add_theme_color_override("font_color", boss.spec.get("color", Globals.C_RED))
	boss_bar.add_child(name_lbl)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(720, 16)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(Globals.C_DARK, 0.7)
	bg.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = boss.spec.get("color", Globals.C_RED)
	fill.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	boss_bar.add_child(bar)
	$CanvasLayer.add_child(boss_bar)
	flash_text("BOSS: " + name_lbl.text)

func on_debris_hit() -> void:
	var tier: String = paddle.add_gun_level(-1)
	paddle.start_hitstop(8)
	Globals.camera.shake(0.4, 20, 14)
	Audio.sfx("life_lost", -6.0)
	flash_text("HIT!  GUN: " + tier)

func boss_defeated(b: Node2D) -> void:
	var pos: Vector2 = b.global_position
	var col: Color = b.spec.get("color", Globals.C_RED)
	for i in 5:
		var off := Vector2(randf_range(-90, 90), randf_range(-70, 70))
		Fx.burst(self, pos + off, col, 30, 800.0, 16.0)
		Fx.ring(self, pos + off, [col, Globals.C_WHITE, Globals.C_AMBER][i % 3], 260 + i * 40, 0.6)
	Fx.flash(self, pos, Globals.C_WHITE, 260, 0.35)
	Audio.sfx("bomb", 2.0)
	Globals.camera.shake(1.2, 30, 24)
	score += 5000
	score_ui.set_score(score)
	Fx.popup(self, pos, "BOSS DOWN  +5000", Globals.C_AMBER, 56)
	for d in get_children():
		if d is Debris: d.queue_free()
	# brief slow motion for the finishing blow
	Engine.time_scale = 0.25
	await get_tree().create_timer(0.6, true, false, true).timeout
	Engine.time_scale = 1.0

func spawn_powerup(pos: Vector2) -> void:
	var p := PowerUp.new()
	p.kind = PowerUp.random_kind()
	p.collected.connect(on_powerup_collected)
	add_child(p)
	p.global_position = pos

func on_powerup_collected(kind: int) -> void:
	Audio.sfx("powerup", -2.0)
	Fx.ring(self, paddle.global_position, PowerUp.INFO[kind][1], 160)
	Fx.burst(self, paddle.global_position, PowerUp.INFO[kind][1], 20, 500.0)
	match kind:
		PowerUp.KIND.GUN:
			flash_text(paddle.add_gun_level(1))
		PowerUp.KIND.WIDE:
			var w: float = paddle.make_wide(15.0)
			flash_text("WIDE x%.1f" % w if w < paddle.WIDE_MAX else "MAX WIDE")
		PowerUp.KIND.BARRIER:
			add_barrier()
			flash_text("BARRIER  %ds" % int(Barrier.DURATION))
		PowerUp.KIND.EXPAND:
			resize_arena(true)
			flash_text("WIDE ARENA  %ds" % int(ARENA_TIME))
		PowerUp.KIND.SHRINK:
			resize_arena(false)
			score += 400  # risk reward (+100 below = 500)
			flash_text("TIGHT ARENA  +500")
		PowerUp.KIND.LIFE:
			health = min(health + 1, 3)
			health_bar.set_health(health)
			flash_text("+1 LIFE")
		PowerUp.KIND.SLOW:
			if fast_time > 0.0: set_fast(false)
			for b in balls: b.velocity *= 0.6
			flash_text("SLOW")
		PowerUp.KIND.MULTI:
			split_balls()
			flash_text("MULTIBALL x%d" % balls.size())
		PowerUp.KIND.FAST:
			set_fast(true)
			flash_text("FAST x2  -  POINTS x2")
			Globals.camera.shake(0.4, 18, 12)
	score += 100
	score_ui.set_score(score)

const Barrier = preload("res://scenes/effects/barrier.gd")
var barrier: Node2D

func add_barrier() -> void:
	if is_instance_valid(barrier) and barrier.time_left > 0.0:
		barrier.refresh()
		return
	barrier = Barrier.new()
	barrier.color = Levels.theme_of(level)["wall"].lightened(0.5)
	barrier.half_width = backdrop.half_width
	barrier.position = Vector2(Levels.CX, 1052)
	add_child(barrier)
	Globals.camera.shake(0.2, 8, 6)

func clear_drops() -> void:
	if is_instance_valid(barrier): barrier.queue_free()
	for c in get_children():
		if c is PowerUp: c.queue_free()

## Esc toggles pause. Handler runs while the tree is paused.
const PauseMenu = preload("res://scenes/ui/pause/pause_menu.gd")

## Esc / II button / app going to background opens the pause menu.
func add_pause_handler() -> void:
	var handler := PauseHandler.new()
	handler.game = self
	add_child(handler)
	if DisplayServer.is_touchscreen_available():
		var btn := Button.new()
		btn.text = "II"
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 36)
		btn.custom_minimum_size = Vector2(80, 70)
		btn.position = Vector2(1920 - 40 - 380 - 110, 22)
		btn.pressed.connect(handler.open)
		$CanvasLayer.add_child(btn)

class PauseHandler extends Node:
	var game: Node
	var menu: CanvasLayer
	func _ready() -> void: process_mode = Node.PROCESS_MODE_ALWAYS
	func open() -> void:
		if menu or game.paddle.game_over: return
		get_tree().paused = true
		Audio.sfx("pause", -4.0)
		menu = PauseMenu.new()
		Globals.start_level = game.level
		menu.title_text = "CUSTOM LEVEL" if not Globals.custom_level.is_empty() else Levels.title_of(game.level)
		menu.info_text = "TIME %s    SCORE %d" % [Globals.format_time(game.time), game.score]
		menu.resumed.connect(func():
			menu = null
			get_tree().paused = false)
		game.add_child.call_deferred(menu)  # may run while the scene is still setting up
	func _notification(what: int) -> void:
		# Auto-pause when the app goes to background, but only mid-rally:
		# losing focus before the ball is launched shouldn't throw a menu up.
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT and game.started and Engine.get_write_movie_path() == "": open()
	func _unhandled_input(event: InputEvent) -> void:
		if not menu and event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			open()

func flash_text(text: String) -> void:
	combo_lbl.text = text
	combo_lbl.visible = true
	place_combo()
	combo_lbl.add_theme_color_override("font_color", Globals.C_AMBER)
	Fx.punch(combo_lbl, 0.3, 0.4)
	combo_timer.start()

const GameOverDialog = preload("res://scenes/ui/game_over/game_over_dialog.gd")

func show_game_over() -> void:
	Audio.stop_music(0.5)
	Audio.sfx("game_over")
	var d := GameOverDialog.new()
	d.score = score
	d.level = level
	d.new_record = Globals.submit_score(score)
	d.best = Globals.high_score
	d.level_title = "CUSTOM LEVEL" if not Globals.custom_level.is_empty() else Levels.title_of(level)
	add_child(d)

### SIGNALS ###
func on_brick_destroyed(which) -> void:
	if which.is_boss: boss_defeated(which)
	bricks.erase(which)
	bricks_to_destroy.erase(which)
	if randf() < POWERUP_CHANCE:
		spawn_powerup.call_deferred(which.global_position)
	
	combo += 1
	show_combo(combo)
	combo_timer.start()
	Audio.sfx("brick_break", -3.0, 0.02, Audio.combo_pitch(combo))  # rises with the combo
	var pts: int = score_brick_destroyed * combo * (2 if fast_time > 0.0 else 1)
	score += pts
	var hot: Color = [Globals.C_WHITE, Globals.C_AMBER, Globals.C_CORAL, Globals.C_VIOLET][min(combo / 4, 3)]
	Fx.popup(self, which.global_position, "+%d" % pts, hot, 30 + min(combo, 10) * 2)
	Globals.camera.shake(0.15, 8, 6)
	Globals.stats["score"] = score
	score_ui.set_score(score)
	
	if bricks_to_destroy.is_empty():
		started = false
		paddle.stage_clear = true
		Globals.stats["time"] = time
		reset_and_attach_ball()
		next_level()

func _on_ball_hit_block(block) -> void:
	add_energy(block_energy)
	if not is_instance_valid(block) or block.isDestroyed: return
	combo += 1
	show_combo(combo)
	combo_timer.start()
	score += score_brick_touched * combo * (2 if fast_time > 0.0 else 1)
	Globals.stats["score"] = score
	score_ui.set_score(score)

func on_energy_brick_destroyed() -> void:
	add_energy(energy_block_energy)

func _on_DeathArea_body_entered(body: Node) -> void:
	if not body.is_in_group("Ball") or paddle.game_over: return
	if balls.size() > 1:
		# one of several balls fell: no life lost, promote another as the main ball
		balls.erase(body)
		if body == ball:
			ball = balls[0]
			paddle.ball = ball
			Globals.camera.objects = [ball, paddle]
		body.queue_free()
		return
	lives_lost += 1
	health -= 1
	health = int(clamp(health, 0, 3))
	
	health_bar.set_health(health)
	
	body.die()
	Audio.sfx("life_lost")
	paddle.add_gun_level(-1)
	
	if health == 0:
		paddle.game_over = true
		started = false
		# Freeze the ball: it must not keep breaking bricks (and clear the level)
		# behind the game over dialog.
		for b in balls:
			b.velocity = Vector2.ZERO
			b.visible = false
			b.process_mode = Node.PROCESS_MODE_DISABLED
		show_game_over()
		return
		
	reset_and_attach_ball()

func _on_combo_timer_timeout():
	combo = 0
	hide_combo()
	
func _on_paddle_start():
	started = true
