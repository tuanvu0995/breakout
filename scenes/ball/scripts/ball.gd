extends CharacterBody2D

class_name Ball

signal hit_block(block)

@export var bump_timing_scene: PackedScene = preload("res://scenes/effects/bump/bump_timing.tscn")
@export var bounce_particles_sence: PackedScene = preload("res://scenes/ball/bounce_particle.tscn")
@export var bump_particles_sence: PackedScene = preload("res://scenes/ball/bump_particle.tscn")
@export var explode_particles_sence: PackedScene = preload("res://scenes/ball/ball_explode_particle.tscn")

@export var speed: float = 400.0
@export var accel: float = 20.0
@export var deccel: float = 1.0
@export var max_normal_angle: float = 15.0
@export var max_speed: float = 1000.0
@export var steering_max_speed: float = 1200.0
@export var steer_force = 110.0
@export var steer_speed = 300.0
@export var max_speed_color: Color = Color.RED

var acceleration: Vector2 = Vector2.ZERO
var attached_to = null
var hit_count: int = 0
var frame_count: int = 0
var no_collision_frame: int = 4
var attracted: bool = false
var attracted_to = null
var frames_since_paddle_collison: int = 0
var max_bump_distance: float = 40.0
var boost_factor: float = 1.0
var boost_factor_perfect: float = 1.35
var boost_factor_late_early: float = 1.15

### Hitstop
var hitstop_frames = 0
var hitstop_bump_late_early = 5
var hitstop_bump_perfect = 10
var hitstop_paddle = 5
var hitstop_block = 5
var hitstop_bomb = 10

@onready var sprite = $Sprite
@onready var animationPlayer = $AnimationPlayer
@onready var sprite_base_scale: Vector2 = sprite.scale
@onready var base_radius: float = $CollisionShape.shape.radius
@onready var base_trail_width: float = $Trail.width
var size_mult := 1.0

## BIG pickup: scale the ball (collision, sprite, trail). Big balls hit twice as hard.
func set_size(mult: float) -> void:
	if not is_inside_tree(): await ready
	if mult == size_mult: return
	size_mult = mult
	$CollisionShape.shape = $CollisionShape.shape.duplicate()  # shared resource otherwise
	$CollisionShape.shape.radius = base_radius * mult
	create_tween().tween_property(sprite, "scale", sprite_base_scale * mult, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	$Trail.width = base_trail_width * mult

func _ready() -> void:
	randomize()
	sprite.material = null
	sprite.texture = Globals.circle_tex(int(sprite.texture.get_width()))
	$Trail.default_color = Globals.C_CYAN
	$Trail.gradient = null
	
func _process(delta) -> void:
	color_based_on_velocity()

## Anti-stuck: moving/rotating bricks are teleported each frame and can end up
## overlapping the ball, which then "collides" every frame and jitters in place.
## Repeated hits on the same brick within a few frames let the ball pass through
## that brick briefly; a watchdog relaunches a ball that barely moved for 2 s.
const STUCK_HITS := 3
const PASS_FRAMES := 15
var last_hit: Object = null
var last_hit_pos := Vector2.INF
var repeat_hits := 0
var pass_through := {}  # brick -> frames left
var watch_pos := Vector2.ZERO
var watch_time := 0.0

func _track_stuck(collider: Object) -> void:
	# same brick again while the ball has barely moved (hitstop pauses make frame
	# gaps unreliable, so measure distance instead)
	if collider == last_hit and global_position.distance_to(last_hit_pos) < 24.0:
		repeat_hits += 1
	else:
		repeat_hits = 1
	last_hit = collider
	last_hit_pos = global_position
	if repeat_hits >= STUCK_HITS and collider is PhysicsBody2D:
		# pass through every brick around the ball: in dense clusters getting out of
		# one brick usually means being inside its neighbour
		for b in get_tree().get_nodes_in_group("Bricks"):
			if b is PhysicsBody2D and b.global_position.distance_to(global_position) < 120.0:
				add_collision_exception_with(b)
				pass_through[b] = PASS_FRAMES
		repeat_hits = 0

func _update_unstuck(delta: float) -> void:
	for b in pass_through.keys():
		pass_through[b] -= 1
		if pass_through[b] <= 0 or not is_instance_valid(b):
			if is_instance_valid(b): remove_collision_exception_with(b)
			pass_through.erase(b)
	if attached_to:
		watch_time = 0.0
		return
	if global_position.distance_to(watch_pos) > 40.0:
		watch_pos = global_position
		watch_time = 0.0
		return
	watch_time += delta
	if watch_time > 2.0:
		watch_time = 0.0
		velocity = Vector2.UP.rotated(randf_range(-0.6, 0.6)) * speed
		for b in get_tree().get_nodes_in_group("Bricks"):  # likely wedged in a cluster
			if b is PhysicsBody2D and b.global_position.distance_to(global_position) < 140.0:
				add_collision_exception_with(b)
				pass_through[b] = PASS_FRAMES * 2

## Bounces never leave the ball skimming flat: right after a bounce, a path
## shallower than MIN_ANGLE is lifted to MIN_ANGLE, keeping speed and both
## directions (left/right, up/down). It only happens at a contact, so the ball
## never turns in mid-air.
const MIN_ANGLE := deg_to_rad(15.0)

func _enforce_min_angle() -> void:
	var v := velocity.length()
	if v < 10.0: return
	var ang := atan2(abs(velocity.y), abs(velocity.x))  # 0 = flat, 90 = vertical
	if ang >= MIN_ANGLE: return
	var sx := 1.0 if velocity.x >= 0.0 else -1.0
	var sy := 1.0 if velocity.y > 0.0 else -1.0  # exactly flat: send it up, away from the ship
	velocity = Vector2(sx * cos(MIN_ANGLE), sy * sin(MIN_ANGLE)) * v

func _physics_process(delta: float) -> void:
	# Hitstop
	if hitstop_frames > 0:
		hitstop_frames -= 1
		if hitstop_frames <= 0:
			stop_hitstop()
		return
	_update_unstuck(delta)  # after hitstop, so pass-through time isn't spent frozen
	
	
	# $VelocityLine.rotation = velocity.angle()
	frames_since_paddle_collison += 1
	
	# ponytail: speed always eases back to cruise (up or down), so it never drifts
	if velocity.length() > 1.0 and not attracted:
		velocity = velocity.normalized() * move_toward(velocity.length(), speed, speed * 1.5 * delta)
	
	if attached_to:
		# a BIG ball sits higher so it doesn't overlap the ship it rests on
		global_position = attached_to.global_position + Vector2.UP * (base_radius * scale.y * (size_mult - 1.0) + (2.0 if size_mult > 1.0 else 0.0))
		return
		
	if attracted:
		var steer = Vector2.ZERO
		var desired = (attracted_to - position).normalized() * steer_speed
		steer = (desired - velocity).normalized() * steer_force
		acceleration += steer
		velocity += acceleration * delta
		velocity = velocity.limit_length(steering_max_speed)
#		rotation = velocity.angle()

	attracted = false
	var velocity_before_collision = velocity
	var collision = move_and_collide(velocity * delta)
	if not collision: return
	
	var normal = collision.get_normal()
	
	# Update the normal with the paddle's velocity if we collide with
	# the paddle
	if collision.get_collider().is_in_group("Paddle"):
		var ship: Node2D = collision.get_collider()
		if global_position.y > ship.global_position.y:
			# ended up inside / under the ship (e.g. grew while touching it): pop out
			# on top and always head up instead of being pushed down into the water
			global_position.y = ship.global_position.y - 30.0 - base_radius * scale.y * size_mult
			velocity = Vector2(velocity.x, -abs(velocity.y) - 200.0)
			_enforce_min_angle()
			return
		ship.ball_bounce()
		frames_since_paddle_collison = 0
		Globals.camera.shake(0.3, 10, 5)
#		print("Normal:", normal)
#		print("Dot:", normal.dot(Vector2.UP))
		spawn_bump_particles(collision.get_position(), normal)
		Audio.sfx("paddle", -3.0, 0.06)
		
		# no bump boost == small hitstop 
		if boost_factor == 1.0:
			start_hitstop(hitstop_paddle)
			collision.get_collider().start_hitstop(hitstop_paddle)
		
		# Collision from the top, most of the cases
		if normal.dot(Vector2.UP) > 0.0:
#			print("HIT TOP: ", Globals.stats["ball_bounces"])
			
			# Paddle is moving
			if collision.get_collider().velocity.length() > 0:
				var length_before_collison = velocity.length()
				
				velocity.y = -velocity.y
				velocity.x += collision.get_collider().velocity.x * 0.6
				velocity = velocity.normalized()
				velocity *= length_before_collison

			else:
				## Tilt the normal near the edge
				# Calculate the distance between the collision point and the center of the paddle
				var distance = collision.get_position() - collision.get_collider().global_position
				var amount = distance.x / 96.0
				normal = normal.rotated(deg_to_rad(max_normal_angle) * amount)
				velocity = velocity.bounce(normal)
		else:
#			print("HIT SIDE: ", Globals.stats["ball_bounces"])
			# Check if below half of the thickness
			if collision.get_position().y > collision.get_collider().global_position.y:
#				print("BELOW HALF")
				velocity = velocity.bounce(normal)
			else:
				# Lateral normal respecting the sign checked the collision
				normal = Vector2(sign(normal.x), 0)
				# Rotate the normal upward
				var normal_rotated = normal.rotated(-sign(normal.x)*deg_to_rad(20.0))
				
				# Create the new velocity using the velocity length and the normal direction
				velocity = normal_rotated * velocity.length()

		# leave the ship at cruise speed; a timed bump adds a small, short-lived kick
		velocity = velocity.normalized() * speed * boost_factor
		# Reset bump boost
		boost_factor = 1.0
	elif collision.get_collider().is_in_group("Bricks"):
		_track_stuck(collision.get_collider())
		Audio.sfx("brick_hit", -5.0, 0.05)
		
		if collision.get_collider().type == collision.get_collider().TYPE.ENERGY or collision.get_collider().type == collision.get_collider().TYPE.EXPLOSIVE:
			velocity = velocity_before_collision
			Globals.camera.shake(1.5, 25, 20)
		else:
			velocity = velocity.bounce(normal)
			Globals.camera.shake(0.3, 15, 10)
	else:
#		print("HIT OTHER: ", Globals.stats["ball_bounces"])
		Audio.sfx("wall", -4.0, 0.08)
		get_tree().call_group("backdrop", "wall_hit", collision.get_position())
		spawn_bounce_particles(collision.get_position(), normal)
		velocity = velocity.bounce(normal)
	
	velocity = velocity.limit_length(max_speed)
	_enforce_min_angle()
	
	if collision.get_collider().is_in_group("Bricks"):
		if repeat_hits <= 1: start_hitstop(hitstop_block)  # no freeze while escaping an overlap
		spawn_bounce_particles(collision.get_position(), normal)
		collision.get_collider().damage(2.0 if size_mult > 1.0 else 1.0)
		emit_signal("hit_block", collision.get_collider())
		
### VISUALS ###
func appear() -> void:
	animationPlayer.play("RESET")
	animationPlayer.play("appear")

func die() -> void:
	#spawn_explode_particles(global_position)
	#Globals.camera.shake(1.5, 25, 20)
	$Trail.visible = false

func color_based_on_velocity() -> void:
	var val: float = clamp(remap(velocity.length(), speed, max_speed, 0.0, 1.0), 0.0, 1.0)
	sprite.self_modulate = lerp(Globals.C_WHITE, Globals.C_CORAL, val)
	$Trail.self_modulate = lerp(Globals.C_WHITE, Globals.C_CORAL, val)

func spawn_bounce_particles(pos: Vector2, normal: Vector2) -> void:
	var instance = bounce_particles_sence.instantiate()
	get_tree().get_current_scene().add_child(instance)
	instance.global_position = pos
	instance.rotation = normal.angle()

func spawn_bump_particles(pos: Vector2, normal: Vector2) -> void:
	var instance = bump_particles_sence.instantiate()
	get_tree().get_current_scene().add_child(instance)
	instance.global_position = pos
	instance.rotation = normal.angle()

func spawn_explode_particles(pos: Vector2) -> void:
	var instance = explode_particles_sence.instantiate()
	get_tree().get_current_scene().add_child(instance)
	instance.global_position = pos

func spawn_bump_timing(type) -> void:
	var instance = bump_timing_scene.instantiate()
	instance.type = type
	get_parent().add_child(instance)
	instance.global_position = global_position
	
func start_hitstop(hitstop_amount: int) -> void:
	animationPlayer.pause()
	hitstop_frames = hitstop_amount

func stop_hitstop() -> void:
	# resume only a paused animation (e.g. "appear"); nothing to resume otherwise
	if animationPlayer.assigned_animation != "": animationPlayer.play()
	hitstop_frames = 0
	

### ACTIONS
func bump_boost(who) -> void:
	var distance = who.global_position.distance_to(global_position)
	var contact_distance = distance - $CollisionShape.shape.radius - (who.thickness / 2.0)
	
	# If we're too far, we don't bump
	if contact_distance > max_bump_distance: 
		print("BUMP TOO FAR")
		boost_factor = 1.0
		spawn_bump_timing(Globals.BUMP.TOO_FAR)
		return
	
	# We had a collision recently and we're now boosting: LATE
	if frames_since_paddle_collison > 5 and frames_since_paddle_collison < 20:
		print("BUMP LATE")
		velocity = velocity.normalized() * speed * boost_factor_late_early  # already bounced: kick now
		boost_factor = 1.0
		Globals.stats["bumps_late"] += 1
		spawn_bump_timing(Globals.BUMP.LATE)
		start_hitstop(hitstop_bump_late_early)
		who.start_hitstop(hitstop_bump_late_early)
	
	# Bump perfect
	elif frames_since_paddle_collison < 5:
		print("BUMP PERFECT")
		boost_factor = boost_factor_perfect
		Globals.stats["bumps_perfect"] += 1
		spawn_bump_timing(Globals.BUMP.PERFECT)
		start_hitstop(hitstop_bump_perfect)
		who.start_hitstop(hitstop_bump_perfect)
	
	# Bump early
	else:
		print("BUMP EARLY")
		boost_factor = boost_factor_late_early
		Globals.stats["bumps_early"] += 1
		spawn_bump_timing(Globals.BUMP.EARLY)
		start_hitstop(hitstop_bump_late_early)
		who.start_hitstop(hitstop_bump_late_early)

func attract(target: Vector2) -> void:
	attracted = true
	attracted_to = target

func launch() -> void:
	#velocity = (-global_transform.y).rotated(randf_range(-PI/3.0, PI/3.0)) * speed * 6
	# direction only: the ball node is scaled, so global_transform.y isn't unit length
	velocity = -global_transform.y.normalized() * speed * 1.3  # brisk launch, eases back to cruise
	attached_to = null
	# Trail is hidden when a life is lost; bring it back fresh on every launch
	# (no stale line from where the ball fell).
	$Trail.clear_points()
	$Trail.visible = true


func _on_animation_player_animation_finished(anim_name):
	if anim_name == "appear":
		$Trail.visible = true
