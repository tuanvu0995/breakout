extends Area2D
## Falling pickup dropped by bricks. Caught by the paddle.

enum KIND { GUN, WIDE, LIFE, SLOW, FAST, BARRIER, EXPAND, SHRINK, MULTI }
const INFO := {
	KIND.GUN: ["G", Globals.C_AMBER],
	KIND.WIDE: ["W", Globals.C_CYAN],
	KIND.LIFE: ["+", Globals.C_CORAL],
	KIND.SLOW: ["S", Globals.C_GREEN],
	KIND.FAST: ["F", Globals.C_RED],
	KIND.BARRIER: ["=", Globals.C_WHITE],
	KIND.EXPAND: ["<>", Globals.C_GREEN],
	KIND.SHRINK: ["><", Globals.C_CORAL],
	KIND.MULTI: ["x3", Globals.C_VIOLET],
}
const FALL_SPEED := 220.0

var kind: int = KIND.GUN
signal collected(kind: int)

static func random_kind() -> int:
	var r := randf()
	if r < 0.08: return KIND.MULTI
	if r < 0.32: return KIND.GUN
	if r < 0.47: return KIND.WIDE
	if r < 0.55: return KIND.SLOW
	if r < 0.65: return KIND.FAST
	if r < 0.76: return KIND.BARRIER
	if r < 0.84: return KIND.EXPAND
	if r < 0.92: return KIND.SHRINK
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
	lbl.add_theme_font_size_override("font_size", 24 if INFO[kind][0].length() == 1 else 18)
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
