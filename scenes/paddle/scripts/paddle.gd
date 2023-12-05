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

func _ready() -> void:
	pass
	
func _input(event):
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

	if dashing or game_over or stage_clear: return
	var dir: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	
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
	
	if Input.is_action_just_pressed("bump"):
		frames_since_bump = 0
		# anim.play("bump")
		if ball_attached:
			launch_ball()
		else:
			ball.bump_boost(self)
		
	if Input.is_action_just_pressed("special"):
		if get_parent().energy == 100.0:
			#laser.shoot()
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
