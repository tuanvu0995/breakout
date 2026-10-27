extends Area2D
## Bullet fired by the ship. Behaviour comes from a weapon dict (see Paddle.WEAPONS).

var velocity := Vector2.UP * 1100.0
var color := Color.WHITE
var pierce := 0       # bricks it can pass through
var homing := 0.0     # turn rate (rad/s), 0 = straight
var splash := 0.0     # radius of area damage on hit
var size := Vector2(6, 18)
var round_shape := false
var hit_bricks := {}

func setup(w: Dictionary, dir: Vector2) -> void:
	velocity = dir * w["speed"]
	color = w["color"]
	pierce = w.get("pierce", 0)
	homing = w.get("homing", 0.0)
	splash = w.get("splash", 0.0)
	size = w.get("size", size)
	round_shape = w.get("round", false)

func _ready() -> void:
	var shape := CollisionShape2D.new()
	if round_shape:
		shape.shape = CircleShape2D.new()
		shape.shape.radius = size.x / 2.0
	else:
		shape.shape = RectangleShape2D.new()
		shape.shape.size = size
	add_child(shape)
	var s := Sprite2D.new()
	s.texture = Globals.circle_tex(int(size.x)) if round_shape else Globals.round_rect_tex(Vector2i(size), size.x / 2.0)
	s.modulate = color
	add_child(s)
	# glow halo
	var glow := Sprite2D.new()
	glow.texture = s.texture
	glow.modulate = Color(color, 0.3)
	glow.scale = Vector2(1.8, 1.3)
	glow.show_behind_parent = true
	s.add_child(glow)
	rotation = velocity.angle() + PI / 2.0
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if homing > 0.0:
		var target := nearest_brick()
		if target:
			var want := (target.global_position - global_position).angle()
			var a := rotate_toward(velocity.angle(), want, homing * delta)
			velocity = Vector2.from_angle(a) * velocity.length()
			rotation = a + PI / 2.0
	position += velocity * delta
	if homing > 0.0 and Engine.get_physics_frames() % 3 == 0:
		Fx.flash(get_parent(), global_position - velocity.normalized() * 14, Color(Globals.C_WHITE, 0.5), 7, 0.25)
	if global_position.y < -100 or global_position.y > 1300: queue_free()

func nearest_brick() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("Bricks"):
		if b.isDestroyed or b.collision_layer == 0 or hit_bricks.has(b): continue
		var d := global_position.distance_squared_to(b.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Paddle") or body.is_in_group("Ball"): return
	var scene := get_tree().current_scene
	Fx.flash(scene, global_position, color, 14 + splash * 0.2)
	if body.is_in_group("Bricks"):
		if hit_bricks.has(body): return
		hit_bricks[body] = true
		if not body.isDestroyed: body.damage(1)
		Fx.burst(scene, global_position, color, 6, 260.0, 7.0)
		if splash > 0.0:
			explode_area(scene)
			queue_free()
			return
		if pierce > 0:
			pierce -= 1
			return
	elif splash > 0.0:
		explode_area(scene)
	queue_free()

func explode_area(scene: Node) -> void:
	Fx.ring(scene, global_position, color, splash)
	Globals.camera.shake(0.2, 10, 8)
	for b in get_tree().get_nodes_in_group("Bricks"):
		if b.isDestroyed or hit_bricks.has(b): continue
		if b.global_position.distance_to(global_position) <= splash:
			b.damage(1)
