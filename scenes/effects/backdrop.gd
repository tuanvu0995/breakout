extends Node2D
## Animated playfield background, one motif per level theme, drawn flat with
## low contrast so bricks always read on top. Also draws the glowing inner edge
## of the arena (top + both side walls) and flashes it where the ball hits.

var FIELD := Rect2(683.0 - 970.0, 27, 1940, 1100)  # widest arena (Levels.FULL_HALF_WIDTH)
## Menu mode: covers the whole screen and skips the arena edge.
var full_screen := false

var theme_index := 0
var field_color := Color("232850")
var accent := Color.WHITE
var half_width := 678.0
var cx := 683.0
var t := 0.0
var stars: Array = []          # [pos, size, phase]
var hits: Array = []           # [pos, life]

func _ready() -> void:
	if full_screen:
		FIELD = Rect2(0, 0, 1920, 1080)
		cx = 960.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in (70 if not full_screen else 120):
		stars.append([Vector2(rng.randf_range(FIELD.position.x, FIELD.end.x), rng.randf_range(FIELD.position.y, FIELD.end.y)),
			rng.randf_range(1.0, 2.6), rng.randf() * TAU])

func set_theme(index: int, field: Color, wall: Color) -> void:
	theme_index = index
	field_color = field
	accent = wall.lightened(0.55)

## Called by the ball when it bounces off a wall.
func wall_hit(pos: Vector2) -> void:
	hits.append([pos, 1.0])

func _process(delta: float) -> void:
	t += delta
	for h in hits: h[1] -= delta * 2.5
	hits = hits.filter(func(h): return h[1] > 0.0)
	queue_redraw()

func _draw() -> void:
	var soft := field_color.lightened(0.06)
	var softer := field_color.lightened(0.03)
	match theme_index:
		0: _tiles(softer)
		1: _orbits(soft, softer)
		2: _waves(soft, softer)
		3: _fog(soft)
		4: _rays(softer)
		5: _stripes(softer)
	for s in stars:
		var a: float = 0.25 + 0.25 * sin(t * 1.7 + s[2])
		draw_circle(s[0], s[1], Color(1, 1, 1, a))
	if not full_screen: _edges()

# -------------------------------------------------------------- motifs

func _tiles(c: Color) -> void:
	var step := 96.0
	var off := fmod(t * 12.0, step)
	var y := FIELD.position.y - step + off
	while y < FIELD.end.y:
		var x := FIELD.position.x - step + fmod(t * 6.0, step)
		while x < FIELD.end.x:
			draw_rect(Rect2(x + 8, y + 8, step - 16, step - 16), c)
			x += step
		y += step

func _orbits(c: Color, c2: Color) -> void:
	var center := Vector2(cx, 380 if not full_screen else 540)
	for i in 6:
		var r := 120.0 + i * 110.0
		draw_arc(center, r, 0, TAU, 96, c, 3.0, true)
		var a := t * (0.25 - i * 0.03) + i * 1.3
		draw_circle(center + Vector2.from_angle(a) * r, 10.0 + i * 2.0, c2.lightened(0.05))

func _waves(c: Color, c2: Color) -> void:
	for band in 9:
		var y0 := FIELD.position.y + 80 + band * 120.0
		var pts := PackedVector2Array()
		var x := FIELD.position.x
		while x <= FIELD.end.x + 20:
			pts.append(Vector2(x, y0 + sin(x * 0.01 + t * 1.2 + band) * 22.0))
			x += 20
		draw_polyline(pts, c if band % 2 == 0 else c2, 10.0, true)

func _fog(c: Color) -> void:
	for i in 9:
		var p := Vector2(fposmod(i * 230.0 + t * (14 + i * 3), FIELD.size.x + 400) - 200 + FIELD.position.x,
			160 + (i * 137) % 900)
		draw_circle(p, 120.0 + (i % 3) * 50.0, Color(c, 0.55))

func _rays(c: Color) -> void:
	var center := Vector2(cx, 380)
	for i in 12:
		var a := t * 0.15 + TAU * i / 12.0
		var tri := PackedVector2Array([center,
			center + Vector2.from_angle(a - 0.08) * 1400, center + Vector2.from_angle(a + 0.08) * 1400])
		draw_colored_polygon(tri, c)

func _stripes(c: Color) -> void:
	var step := 140.0
	var off := fmod(t * 40.0, step)
	var x := FIELD.position.x - 1200 + off
	while x < FIELD.end.x:
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, FIELD.end.y), Vector2(x + 60, FIELD.end.y),
			Vector2(x + 60 + 1100, FIELD.position.y), Vector2(x + 1100, FIELD.position.y)]), c)
		x += step

# -------------------------------------------------------------- arena edge

func _edges() -> void:
	var left := cx - half_width
	var right := cx + half_width
	var top := FIELD.position.y
	var pulse := 0.55 + 0.15 * sin(t * 2.0)
	var glow := Color(accent, 0.18)
	var line := Color(accent, pulse)
	for g in [[left, 1], [right, -1]]:
		draw_rect(Rect2(g[0] + (0 if g[1] > 0 else -14), top, 14, FIELD.size.y), glow)
		draw_line(Vector2(g[0], top), Vector2(g[0], FIELD.end.y), line, 3.0)
	draw_rect(Rect2(left, top, right - left, 14), glow)
	draw_line(Vector2(left, top), Vector2(right, top), line, 3.0)
	for h in hits:
		var k: float = h[1]
		draw_circle(h[0], 50.0 * (1.2 - k), Color(accent, 0.5 * k))
		draw_circle(h[0], 14.0 * k, Color(1, 1, 1, k))
