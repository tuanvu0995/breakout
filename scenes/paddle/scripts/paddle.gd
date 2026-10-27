extends CharacterBody2D

class_name Paddle

signal start()

@export var speed: float = 400.0
@export var bump_force: float = 500.0
@export var accel: float = 20.0
@export var deccel: float = 10.0
@export var dash_speed: float = 1000.0
@export var dash_duration: float = 0.1
@export var max_lean_angle: float = 7.0
@export var lean_speed: float = 8.0
@export var double_tap_duration: float = 0.2

@export_category("Oscillator")
@export var spring: float = 150.0
@export var damp: float = 10.0
@export var velocity_multiplier: float = 0.2

var dashing: bool = false
var can_dash: bool = false
var last_move_key: bool = false
var ball_attached = null
var bumping: bool = false : get = get_bumping, set = set_bumping
var game_over: bool = false
var stage_clear: bool = false
var ball = null
var frames_since_bump: int = 0

## Oscillator
var displacement: float = 0.0
var oscillator_velocity: float = 0.0

### Hitstop
var hitstop_frames = 0

@onready var sprite: Sprite2D = $Sprite
@onready var dash_timer: Timer = $DashTimer
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var launch_point: Marker2D = $LaunchPoint
#@onready var laser: Area2D = $Laser
@onready var thickness: float = $CollisionShape.shape.extents.y
@onready var ghostSpawner: PaddleGhostSpwner = $PaddleGhostSpawner
@onready var doubleTapTimer: Timer = $DoubleTapTimer

var move_left_pressed: bool = false
var move_right_pressed: bool = false
var dash_direction: int = 0

const Bullet = preload("res://scenes/weapons/bullet.gd")
const FIRE_RATE := 0.22
const MAX_GUN_LEVEL := 3

var gun_level: int = 0  # 0 = no gun, 1..3 = barrels
var gun_overdrive: float = 0.0  # seconds of forced triple gun (from energy special)
var fire_cooldown: float = 0.0
var base_shape_size: Vector2
var wide_time: float = 0.0
var barrels: Node2D

func _ready() -> void:
	# The shape resource is shared, make it ours so "wide" can resize it
	$CollisionShape.shape = $CollisionShape.shape.duplicate()
	base_shape_size = $CollisionShape.shape.size
	build_ship()

## Draw the paddle as a ship over the old sprite (sprite stays for ghosts/shader).
func build_ship() -> void:
	sprite.self_modulate.a = 0.0
	sprite.material = null  # old shader ignores modulate and draws the old paddle
	var w := base_shape_size.x / 2.0
	var h := base_shape_size.y / 2.0
	var skin: Dictionary = Globals.SKINS[Globals.skin_index]
	for poly in Globals.make_ship(skin, w, h): sprite.add_child(poly)
	barrels = Node2D.new()
	sprite.add_child(barrels)
	update_barrels()

func gun_offsets() -> Array:
	var w := base_shape_size.x / 2.0
	match current_gun_level():
		1: return [0.0]
		2: return [-w * 0.55, w * 0.55]
		3: return [-w * 0.55, 0.0, w * 0.55]
	return []

func current_gun_level() -> int:
	return MAX_GUN_LEVEL if gun_overdrive > 0.0 else gun_level

func update_barrels() -> void:
	for c in barrels.get_children(): c.queue_free()
	var h := base_shape_size.y / 2.0
	for x in gun_offsets():
		var b := Polygon2D.new()
		b.polygon = PackedVector2Array([Vector2(x - 4, -h * 0.2), Vector2(x - 4, -h - 10), Vector2(x + 4, -h - 10), Vector2(x + 4, -h * 0.2)])
		b.color = Globals.C_AMBER
		barrels.add_child(b)

func add_gun_level(amount: int) -> void:
	gun_level = clamp(gun_level + amount, 0, MAX_GUN_LEVEL)
	update_barrels()

func start_overdrive(seconds: float) -> void:
	Audio.sfx("overdrive")
	gun_overdrive = seconds
	update_barrels()

func make_wide(seconds: float) -> void:
	wide_time = seconds
	$CollisionShape.shape.size = base_shape_size * Vector2(1.5, 1.0)
	sprite.scale.x = 1.5

func update_weapons(delta: float) -> void:
	if wide_time > 0.0:
		wide_time -= delta
		if wide_time <= 0.0:
			$CollisionShape.shape.size = base_shape_size
			sprite.scale.x = 1.0
	if gun_overdrive > 0.0:
		gun_overdrive -= delta
		if gun_overdrive <= 0.0: update_barrels()
	fire_cooldown -= delta
	if current_gun_level() == 0 or ball_attached or fire_cooldown > 0.0: return
	fire_cooldown = FIRE_RATE
	Audio.sfx("shoot", -12.0, 0.1)
	var h := base_shape_size.y / 2.0
	for x in gun_offsets():
		var bullet := Bullet.new()
		get_parent().add_child(bullet)
		bullet.global_position = sprite.to_global(Vector2(x, -h - 12))
	
## Touch: first finger drags the ship and taps to launch/bump, second finger = special.
var touch_index: int = -1
var touch_x: float = 0.0
var touch_bump: bool = false
var touch_special: bool = false

func _touch_world_x(pos: Vector2) -> float:
	return (get_viewport().get_canvas_transform().affine_inverse() * pos).x

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_index == -1:
				touch_index = event.index
				touch_x = _touch_world_x(event.position)
				touch_bump = true
			else:
				touch_special = true
		elif event.index == touch_index:
			touch_index = -1
	elif event is InputEventScreenDrag and event.index == touch_index:
		touch_x = _touch_world_x(event.position)
	if event is InputEventKey:
		if event.is_action_pressed("move_left"):
			if move_left_pressed:
				can_dash = true
			else:
				move_left_pressed = true
				doubleTapTimer.start(double_tap_duration)
		if event.is_action_pressed("move_right"):
			if move_right_pressed:
				can_dash = true
			else:
				move_right_pressed = true
				doubleTapTimer.start(double_tap_duration)

func _process(delta: float) -> void:
	# Hitstop
	if hitstop_frames > 0:
		hitstop_frames -= 1
		if hitstop_frames <= 0:
			stop_hitstop()
		return

	if game_over or stage_clear: return
	update_weapons(delta)
	if dashing: return
	var dir: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	if touch_index != -1:
		# ponytail: proportional follow, 80px = full speed; tune if it feels floaty
		dir = clamp((touch_x - global_position.x) / 80.0, -1.0, 1.0)
		if abs(touch_x - global_position.x) < 4.0: dir = 0.0
	
	# Smooth the movement
	if dir != 0:
		velocity.x = lerp(velocity.x, dir * speed, accel * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, deccel * delta)

	# Dash
	if dir != 0 and not dashing and can_dash:
		dashing = true
		dash_timer.start(dash_duration)
		ghostSpawner.start_spawn()
		Audio.sfx("dash", -6.0, 0.1)
		velocity.x = sign(velocity.x) * dash_speed
		can_dash = false
		move_left_pressed = false
		move_right_pressed = false

	# Oscillator
	oscillator_velocity += (velocity.x / speed) * velocity_multiplier
	var force = -spring * displacement + damp * oscillator_velocity
	oscillator_velocity -= force * delta
	displacement -= oscillator_velocity * delta
	
	sprite.rotation = -displacement
		
	# sprite.rotation = lerp_angle(sprite.rotation, deg_to_rad(max_lean_angle) * dir, lean_speed * delta)
	
	var bump_now := Input.is_action_just_pressed("bump") or touch_bump
	var special_now := Input.is_action_just_pressed("special") or touch_special
	touch_bump = false
	touch_special = false
	if bump_now:
		frames_since_bump = 0
		# anim.play("bump")
		if ball_attached:
			launch_ball()
		else:
			ball.bump_boost(self)
		
	if special_now:
		if get_parent().energy == 100.0:
			start_overdrive(8.0)
			get_parent().remove_energy(100)
		
	if Input.is_action_pressed("attract"):
		if not ball: return
		if get_parent().energy > delta*5:
			get_parent().remove_energy(delta*5)
			ball.attract(position)
	
func _physics_process(delta: float) -> void:
	if game_over or stage_clear: return
	
	frames_since_bump += 1
	
	var collision = move_and_collide(velocity * delta)
	
	if not collision: return
	if collision.get_collider().is_in_group("Ball"):
		pass
		
### VISUAL ###
func start_hitstop(hitstop_amount: int) -> void:
	anim.pause()
	hitstop_frames = hitstop_amount

func stop_hitstop() -> void:
	anim.play()
	hitstop_frames = 0
		
func ball_bounce() -> void:
	anim.play("bounce")
		
func set_bumping(new_value: bool) -> void:
	bumping = new_value
	
func get_bumping() -> bool:
	return bumping
	
func launch_ball() -> void:
	emit_signal("start")
	ball_attached.launch()
	ball_attached = null
	anim.play("bump")

func _on_DashTimer_timeout() -> void:
	dashing = false
	ghostSpawner.stop_spawn()

func _on_doble_tap_timer_timeout():
	move_left_pressed = false
	move_right_pressed = false
