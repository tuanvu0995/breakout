extends Area2D
## Bullet fired by the ship. Built in code, no .tscn needed.

const SPEED := 1100.0

func _ready() -> void:
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(6, 18)
	add_child(shape)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(-3, 9), Vector2(-3, -6), Vector2(0, -10), Vector2(3, -6), Vector2(3, 9)])
	poly.color = Globals.C_AMBER
	add_child(poly)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position.y -= SPEED * delta
	if global_position.y < -50: queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Paddle") or body.is_in_group("Ball"): return
	if body.is_in_group("Bricks") and not body.isDestroyed:
		body.damage(1)
	queue_free()
