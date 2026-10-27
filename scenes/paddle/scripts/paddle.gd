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
## Hold-to-boost replaces the old double-tap dash.
const BOOST_MULT := 1.9
var boosting := false
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
## Bullet types, fed to Bullet.setup().
var WEAPONS := {
	"BLASTER": {"rate": 0.25, "speed": 1100.0, "color": Globals.C_AMBER, "size": Vector2(6, 18)},
	"LASER": {"rate": 0.3, "speed": 1900.0, "color": Globals.C_CYAN, "size": Vector2(5, 60), "pierce": 2},
	"BIG_LASER": {"rate": 0.35, "speed": 2100.0, "color": Globals.C_VIOLET, "size": Vector2(18, 120), "pierce": 6},
	"MISSILE": {"rate": 0.5, "speed": 520.0, "color": Globals.C_CORAL, "size": Vector2(12, 28), "homing": 4.0, "splash": 110.0},
}
## Upgrade path: every G pickup moves one tier up, losing a life moves one down.
## barrels = x offsets as a fraction of the ship half-width.
const TIERS := [
	{"name": "SINGLE", "weapon": "BLASTER", "barrels": [0.0]},
	{"name": "DOUBLE", "weapon": "BLASTER", "barrels": [-0.55, 0.55]},
	{"name": "TRIPLE", "weapon": "BLASTER", "barrels": [-0.55, 0.0, 0.55]},
	{"name": "LASER", "weapon": "LASER", "barrels": [-0.55, 0.55]},
	{"name": "BIG LASER", "weapon": "BIG_LASER", "barrels": [0.0]},
	{"name": "MISSILE", "weapon": "MISSILE", "barrels": [-0.6, 0.6]},
]
const MAX_GUN_LEVEL := 6

var gun_level: int = 1  # tier 1..6, you always have a gun
var gun_overdrive: float = 0.0  # seconds of forced max tier (energy special)
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
	$Sprite/ThrustParticle.modulate = skin.get("trail", Globals.C_CYAN)
	barrels = Node2D.new()
	sprite.add_child(barrels)
	update_barrels()

func tier() -> Dictionary:
	return TIERS[current_gun_level() - 1]

func gun_offsets() -> Array:
	var w := base_shape_size.x / 2.0
	return tier()["barrels"].map(func(f): return f * w)

func current_gun_level() -> int:
	return MAX_GUN_LEVEL if gun_overdrive > 0.0 else gun_level

func update_barrels() -> void:
	for c in barrels.get_children(): c.queue_free()
	var h := base_shape_size.y / 2.0
	var w: Dictionary = WEAPONS[tier()["weapon"]]
	var bw: float = max(4.0, w["size"].x * 0.5)
	for x in gun_offsets():
		var b := Polygon2D.new()
		b.polygon = PackedVector2Array([Vector2(x - bw, -h * 0.2), Vector2(x - bw, -h - 10), Vector2(x + bw, -h - 10), Vector2(x + bw, -h * 0.2)])
		b.color = w["color"]
		barrels.add_child(b)

## Returns the tier name after the change.
func add_gun_level(amount: int) -> String:
	var before := gun_level
	gun_level = clamp(gun_level + amount, 1, MAX_GUN_LEVEL)
	update_barrels()
	if gun_level > before:
		Fx.ring(get_parent(), global_position, WEAPONS[tier()["weapon"]]["color"], 160)
		Fx.punch(barrels, 0.5)
	return TIERS[gun_level - 1]["name"]

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
	if ball_attached or fire_cooldown > 0.0: return
	var w: Dictionary = WEAPONS[tier()["weapon"]]
	fire_cooldown = w["rate"]
	Audio.sfx("shoot", -12.0, 0.1)
	var h := base_shape_size.y / 2.0
	for x in gun_offsets():
		var muzzle := sprite.to_global(Vector2(x, -h - 12))
		var bullet := Bullet.new()
		# missiles leave at an angle, then curve in
		var dir := Vector2.UP.rotated(sign(x) * 0.5) if w.has("homing") else Vector2.UP
		bullet.setup(w, dir)
		get_parent().add_child(bullet)
		bullet.global_position = muzzle
		Fx.flash(get_parent(), muzzle, w["color"], 12 + w["size"].x * 0.4, 0.09)
	recoil()

func recoil() -> void:
	sprite.position.y = 5.0
	create_tween().tween_property(sprite, "position:y", 0.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	
	# Hold Space (the bump key) while moving to boost. A tap still launches / bumps.
	var want_boost: bool = dir != 0 and Input.is_action_pressed("bump") and not ball_attached
	if want_boost != boosting:
		boosting = want_boost
		if boosting:
			ghostSpawner.start_spawn()
			Audio.sfx("dash", -8.0, 0.1)
		else:
			ghostSpawner.stop_spawn()
	var top_speed := speed * (BOOST_MULT if boosting else 1.0)

	# Smooth the movement
	if dir != 0:
		velocity.x = lerp(velocity.x, dir * top_speed, accel * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, deccel * delta)

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
