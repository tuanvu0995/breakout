extends Node2D

class_name GameManager

@export var brick_scene: PackedScene = preload("res://scenes/brick/brick.tscn")
@export var energy_block_energy: int = 100

@onready var paddle: CharacterBody2D = $Paddle
@onready var ball: CharacterBody2D = $Ball
@onready var spawn_pos_container: Node = $SpawnPos
@onready var brick_container: Node = $Bricks

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

func _ready():
	randomize()
	
	Globals.camera = $Camera
	Globals.camera.objects = [ball]
	
	ball.attached_to = paddle.launch_point
	paddle.ball_attached = ball
	paddle.ball = ball
	
	for brick in get_tree().get_nodes_in_group("Bricks"):
		brick.energy_brick_destroyed.connect(on_energy_brick_destroyed)
		
	# Remove for testing with predefined bricks
	remove_all_bricks()
	layout_bricks()


func _process(delta) -> void:
	if not started: return
	time += delta
	
func layout_bricks() -> void:
	var bricks_tween: Tween = create_tween()
	var max_bricks: int = spawn_pos_container.get_child_count()
	for i in range(max_bricks):
		# 90% chance of having a block
		if randf() < 0.1: continue
		bricks_tween.tween_callback(add_brick.bind(brick_container, spawn_pos_container.get_child(i).global_position))
		bricks_tween.tween_interval(0.1)
		
func add_brick(parent: Node, pos: Vector2) -> void:
	var instance = brick_scene.instantiate()
	parent.add_child(instance)
	instance.energy_brick_destroyed.connect(on_energy_brick_destroyed)
	instance.destroyed.connect(on_brick_destroyed)
	instance.global_position = pos
	bricks.append(instance)
	if instance.type != instance.TYPE.EXPLOSIVE and instance.type != instance.TYPE.ENERGY:
		bricks_to_destroy.append(instance)
		
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
	#energy_bar.set_energy(energy)
	
func remove_energy(value: float) -> void:
	energy -= value
	energy = clamp(energy, 0, 100)
	#energy_bar.set_energy(energy)

func reset_energy() -> void:
	energy = 0
	#energy_bar.set_energy(energy)
	
func reset_health() -> void:
	health = 3
	#health_bar.set_health(health)
	
func reset_score() -> void:
	score = 0
	#score_ui.set_score(score)
	
func show_combo(combo: int) -> void:
	#combo_lbl.text = "COMBO " + str(combo)
	#combo_lbl.visible = true
	pass
	
func hide_combo() -> void:
	#combo_lbl.visible = false
	pass

### SIGNALS ###
func on_brick_destroyed(which) -> void:
	bricks.erase(which)
	bricks_to_destroy.erase(which)
	
	combo += 1
	show_combo(combo)
	#combo_timer.start()
	score += score_brick_destroyed * combo
	Globals.stats["score"] = score
	#score_ui.set_score(score)
	
	if bricks_to_destroy.is_empty():
		started = false
		paddle.stage_clear = true
		Globals.stats["time"] = time
		reset_and_attach_ball()
		#show_stage_clear()

func _on_ball_hit_block(block) -> void:
	#add_energy(block_energy)
	if block._destroyed: return
	combo += 1
	show_combo(combo)
	#combo_timer.start()
	score += score_brick_touched * combo
	Globals.stats["score"] = score
	#score_ui.set_score(score)

func on_energy_brick_destroyed() -> void:
	add_energy(energy_block_energy)

func _on_DeathArea_body_entered(body: Node) -> void:
	if not body.is_in_group("Ball"): return
	health -= 1
	health = int(clamp(health, 0, 3))
	
	#health_bar.set_health(health)
	
	body.die()
	
	if health == 0:
		paddle.game_over = true
		#show_game_over()
		return
		
	reset_and_attach_ball()
