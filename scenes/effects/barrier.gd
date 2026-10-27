extends StaticBody2D
## Temporary safety net under the paddle: the ball bounces off it instead of
## falling into the water. Lasts DURATION seconds, blinks for the last 3, then
## fades away. Picking another one while active just refreshes the timer.

const DURATION := 12.0
const THICK := 16.0

var time_left := DURATION
var half_width := 600.0
var color := Color.WHITE
var shape: RectangleShape2D

func _ready() -> void:
	var cs := CollisionShape2D.new()
	shape = RectangleShape2D.new()
	cs.shape = shape
	add_child(cs)
	resize(half_width)
	scale = Vector2(0.0, 1.0)
	create_tween().tween_property(self, "scale:x", 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func resize(hw: float) -> void:
	half_width = hw
	shape.size = Vector2(hw * 2.0, THICK)
	queue_redraw()

func refresh() -> void:
	time_left = DURATION
	modulate.a = 1.0
	Fx.punch(self, 0.1)

func _process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		set_process(false)
		collision_layer = 0
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.25)
		tw.tween_callback(queue_free)
		return
	# blink faster and faster in the last 3 seconds
	if time_left < 3.0:
		modulate.a = 0.35 + 0.65 * float(sin(Time.get_ticks_msec() / (60.0 + time_left * 40.0)) > 0.0)
	queue_redraw()

func _draw() -> void:
	var w := half_width * 2.0
	draw_rect(Rect2(-half_width, -THICK / 2.0 - 6, w, THICK + 12), Color(color, 0.18))
	draw_rect(Rect2(-half_width, -THICK / 2.0, w, THICK), Color(color, 0.85))
	# chevrons moving along the bar
	var off := fmod(Time.get_ticks_msec() / 10.0, 40.0)
	var x := -half_width - 40.0 + off
	while x < half_width:
		draw_line(Vector2(x, 5), Vector2(x + 8, -5), Color(1, 1, 1, 0.55), 3.0)
		x += 40.0
	# remaining time as a thin bar on top
	var k := time_left / DURATION
	draw_rect(Rect2(-half_width, -THICK / 2.0 - 4, w * k, 3), Color(1, 1, 1, 0.9))
