extends Area2D
## Falling shard dropped by a boss. Hitting the ship knocks one gun tier off.

signal hit

const SPEED := 330.0
var color := Color.WHITE

func _ready() -> void:
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 16
	add_child(shape)
	var s := Sprite2D.new()
	s.texture = BrickShapes.texture("tri")
	s.rotation_degrees = 180  # points down
	s.scale = Vector2.ONE * 0.6
	s.modulate = color
	add_child(s)
	var glow := Sprite2D.new()
	glow.texture = Globals.circle_tex(64)
	glow.modulate = Color(color, 0.25)
	glow.show_behind_parent = true
	s.add_child(glow)
	body_entered.connect(_on_body)

func _physics_process(delta: float) -> void:
	position.y += SPEED * delta
	rotation = sin(Time.get_ticks_msec() / 120.0) * 0.25
	if global_position.y > 1150: queue_free()

func _on_body(body: Node) -> void:
	if not body.is_in_group("Paddle"): return
	Fx.burst(get_parent(), global_position, color, 16, 420.0)
	hit.emit()
	queue_free()
