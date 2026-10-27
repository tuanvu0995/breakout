extends Node2D

class_name GameManager

@export var game_over_scene: PackedScene = preload("res://scenes/ui/game_over/game_over.tscn")
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
	
	for brick in get_tree().get_nodes_in_group("Bricks"):
		brick.energy_brick_destroyed.connect(on_energy_brick_destroyed)
		
	level = Globals.start_level
	apply_flat_style()
	base_ball_speed = ball.speed
	add_pause_handler()
	# Remove for testing with predefined bricks
	remove_all_bricks()
	layout_bricks()
	flash_text("CUSTOM LEVEL" if not Globals.custom_level.is_empty() else Levels.title_of(level))


func _process(delta) -> void:
	if not started: return
	time += delta
	
const Levels = preload("res://scenes/levels/levels.gd")

func layout_bricks() -> void:
	var theme: Dictionary = Levels.theme_of(level)
	$Pattern.color = theme["field"]
	$Wall/Polygon2D.color = theme["wall"]
	Audio.play_theme_music(((level - 1) % Levels.COUNT) / 5)
	Audio.sfx("level_start", -6.0)
	if Globals.custom_level.is_empty() and level <= Levels.COUNT:
		Leaderboard.start(level)
	var layout: Array = Globals.custom_level if not Globals.custom_level.is_empty() else Levels.build(level)
	set_field_width(Levels.half_width(level, layout), theme["wall"])
	for item in layout:
		var b = add_brick(brick_container, item["pos"], item["spec"])
		# pop-in, staggered
		b.scale = Vector2.ZERO
		create_tween().tween_property(b, "scale", Vector2.ONE, 0.35) \
			.set_delay(0.008 * bricks.size()).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

var side_walls: Array = []

## Two movable walls that narrow the playfield per level.
func set_field_width(half_width: float, color: Color) -> void:
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
			body.position = Vector2(Levels.CX + side * (Levels.FULL_HALF_WIDTH + 1000), 540)
			add_child(body)
			move_child(body, $Pattern.get_index() + 1)  # under bricks, over background
			side_walls.append(body)
	for i in 2:
		var side := -1 if i == 0 else 1
		side_walls[i].get_child(1).color = color
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
	combo_lbl.text = "COMBO " + str(combo)
	combo_lbl.visible = true
	combo_lbl.add_theme_color_override("font_color", [Globals.C_AMBER, Globals.C_CORAL, Globals.C_VIOLET, Globals.C_CYAN][min(combo / 5, 3)])
	Fx.punch(combo_lbl, 0.15 + min(combo, 10) * 0.02)
	pass
	
func hide_combo() -> void:
	combo_lbl.visible = false
	pass

func apply_flat_style() -> void:
	$Pattern.material = null
	$Pattern.color = Globals.C_FIELD
	$Wall/Polygon2D.texture = null
	$Wall/Polygon2D.color = Globals.C_WALL
	combo_lbl.add_theme_color_override("font_color", Globals.C_AMBER)

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
	await get_tree().create_timer(1.5).timeout
	if not Globals.custom_level.is_empty():
		get_tree().change_scene_to_file("res://scenes/editor/level_editor.tscn")
		return
	level += 1
	var unlocked := Globals.reach_level(level)
	time = 0.0
	# ponytail: linear 8%/level ramp, swap for a curve if late levels feel unfair
	ball.speed = base_ball_speed * (1.0 + 0.08 * (level - 1))
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
			paddle.make_wide(15.0)
			flash_text("WIDE")
		PowerUp.KIND.LIFE:
			health = min(health + 1, 3)
			health_bar.set_health(health)
			flash_text("+1 LIFE")
		PowerUp.KIND.SLOW:
			ball.velocity *= 0.6
			flash_text("SLOW")
	score += 100
	score_ui.set_score(score)

func clear_drops() -> void:
	for c in get_children():
		if c is PowerUp: c.queue_free()

## Esc toggles pause. Handler runs while the tree is paused.
func add_pause_handler() -> void:
	var lbl := Label.new()
	lbl.text = "PAUSED\nEsc / II: continue   Q: menu"
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.visible = false
	$CanvasLayer.add_child(lbl)
	var handler := PauseHandler.new()
	handler.label = lbl
	add_child(handler)
	if DisplayServer.is_touchscreen_available():
		var btn := Button.new()
		btn.text = "II"
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		btn.focus_mode = Control.FOCUS_NONE
		btn.position = Vector2(1780, 60)
		btn.pressed.connect(handler.toggle)
		$CanvasLayer.add_child(btn)

class PauseHandler extends Node:
	var label: Label
	func _ready() -> void: process_mode = Node.PROCESS_MODE_ALWAYS
	func toggle() -> void:
		get_tree().paused = not get_tree().paused
		Audio.sfx("pause", -4.0)
		label.visible = get_tree().paused
	func _notification(what: int) -> void:
		# Mobile: auto-pause when the app goes to background
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not get_tree().paused and Engine.get_write_movie_path() == "": toggle()
	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"):
			toggle()
		elif get_tree().paused and event is InputEventKey and event.pressed and event.physical_keycode == KEY_Q:
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/ui/main_menu/main_menu.tscn")

func flash_text(text: String) -> void:
	combo_lbl.text = text
	combo_lbl.visible = true
	combo_lbl.add_theme_color_override("font_color", Globals.C_AMBER)
	Fx.punch(combo_lbl, 0.3, 0.4)
	combo_timer.start()

func show_game_over() -> void:
	Audio.stop_music(0.5)
	Audio.sfx("game_over")
	var instance = game_over_scene.instantiate()
	instance.score = score
	instance.level = level
	instance.new_record = Globals.submit_score(score)
	$CanvasLayer.add_child(instance)
	instance.retry.connect(on_game_over_retry)

### SIGNALS ###
func on_brick_destroyed(which) -> void:
	bricks.erase(which)
	bricks_to_destroy.erase(which)
	if randf() < POWERUP_CHANCE:
		spawn_powerup.call_deferred(which.global_position)
	
	combo += 1
	show_combo(combo)
	combo_timer.start()
	var pts: int = score_brick_destroyed * combo
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
	if block._destroyed: return
	combo += 1
	show_combo(combo)
	combo_timer.start()
	score += score_brick_touched * combo
	Globals.stats["score"] = score
	score_ui.set_score(score)

func on_energy_brick_destroyed() -> void:
	add_energy(energy_block_energy)

func _on_DeathArea_body_entered(body: Node) -> void:
	if not body.is_in_group("Ball"): return
	health -= 1
	health = int(clamp(health, 0, 3))
	
	health_bar.set_health(health)
	
	body.die()
	Audio.sfx("life_lost")
	paddle.add_gun_level(-1)
	
	if health == 0:
		paddle.game_over = true
		show_game_over()
		return
		
	reset_and_attach_ball()

func on_game_over_retry() -> void:
	reset_and_attach_ball()
	reset_health()
	reset_energy()
	reset_score()
	time = 0.0
	level = 1
	ball.speed = base_ball_speed
	paddle.add_gun_level(-paddle.MAX_GUN_LEVEL)
	clear_drops()
	flash_text(Levels.title_of(1))
	Globals.reset_stats()
	remove_all_bricks()
	layout_bricks()
	
func _on_combo_timer_timeout():
	combo = 0
	hide_combo()
	
func _on_paddle_start():
	started = true
