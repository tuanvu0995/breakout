extends Area2D
## Falling pickup dropped by bricks. Caught by the paddle.

enum KIND { GUN, WIDE, LIFE, SLOW }
const INFO := {
	KIND.GUN: ["G", Globals.C_AMBER],
	KIND.WIDE: ["W", Globals.C_CYAN],
	KIND.LIFE: ["+", Globals.C_CORAL],
	KIND.SLOW: ["S", Globals.C_GREEN],
}
const FALL_SPEED := 220.0

var kind: int = KIND.GUN
signal collected(kind: int)

static func random_kind() -> int:
	var r := randf()
	if r < 0.4: return KIND.GUN
	if r < 0.7: return KIND.WIDE
	if r < 0.85: return KIND.SLOW
	return KIND.LIFE

func _ready() -> void:
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 20
	add_child(shape)
	var pts := PackedVector2Array()
	for i in 20: pts.append(Vector2.from_angle(TAU * i / 20.0) * 20)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = INFO[kind][1]
	add_child(poly)
	var lbl := Label.new()
	lbl.text = INFO[kind][0]
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Globals.C_DARK)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(40, 40)
	lbl.position = Vector2(-20, -20)
	add_child(lbl)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position.y += FALL_SPEED * delta
	rotation = sin(Time.get_ticks_msec() / 200.0) * 0.3
	if global_position.y > 2000: queue_free()

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("Paddle"): return
	collected.emit(kind)
	queue_free()
