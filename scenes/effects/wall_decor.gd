extends Node2D
## Flat decoration for wall areas, one motif per level theme:
## 0 masonry, 1 ring grid, 2 waves, 3 diamond lattice, 4 chevrons, 5 hazard stripes.
## `rects` are the wall areas in local coords; `rivet_x` is the x of the edge
## that faces the arena (NAN = no rivets). Shapes are only drawn fully inside a
## rect, so nothing bleeds into the arena.

var rects: Array = []  # of Rect2
var rivet_x := NAN
var color := Color.WHITE
var motif := 5

func set_color(wall: Color, theme_index := -1) -> void:
	color = wall
	if theme_index >= 0: motif = theme_index
	queue_redraw()

func _draw() -> void:
	var ink := color.darkened(0.14)
	var light := color.lightened(0.08)
	for r: Rect2 in rects:
		var inner := r.grow(-6)
		match motif:
			0: _masonry(inner, ink)
			1: _rings(inner, light)
			2: _waves(inner, ink)
			3: _diamonds(inner, light)
			4: _chevrons(inner, ink)
			_: _stripes(r, ink)
	if not is_nan(rivet_x):
		var y := -1200.0
		while y < 1200.0:
			draw_circle(Vector2(rivet_x, y), 7, color.lightened(0.18))
			draw_circle(Vector2(rivet_x, y), 3, color.darkened(0.2))
			y += 90.0

func _masonry(r: Rect2, c: Color) -> void:
	var bw := 64.0
	var bh := 30.0
	var row := 0
	var y := r.position.y
	while y + bh <= r.end.y:
		var x := r.position.x + (bw / 2.0 if row % 2 else 0.0)
		while x + bw <= r.end.x:
			draw_rect(Rect2(x + 3, y + 3, bw - 6, bh - 6), c)
			x += bw
		y += bh
		row += 1

func _rings(r: Rect2, c: Color) -> void:
	var step := 48.0
	var y := r.position.y + step / 2.0
	var row := 0
	while y + 14 <= r.end.y:
		var x := r.position.x + step / 2.0 + (step / 2.0 if row % 2 else 0.0)
		while x + 14 <= r.end.x:
			draw_arc(Vector2(x, y), 11, 0, TAU, 20, c, 3.0, true)
			x += step
		y += step * 0.86
		row += 1

func _waves(r: Rect2, c: Color) -> void:
	var y := r.position.y + 20.0
	while y + 20 <= r.end.y:
		var pts := PackedVector2Array()
		var x := r.position.x
		while x <= r.end.x:
			pts.append(Vector2(x, y + sin(x * 0.05) * 9.0))
			x += 8.0
		if pts.size() > 1: draw_polyline(pts, c, 5.0, true)
		y += 34.0

func _diamonds(r: Rect2, c: Color) -> void:
	var s := 22.0
	var y := r.position.y + s
	var row := 0
	while y + s <= r.end.y:
		var x := r.position.x + s + (s if row % 2 else 0.0)
		while x + s <= r.end.x:
			var pts := PackedVector2Array([Vector2(x, y - s), Vector2(x + s * 0.7, y), Vector2(x, y + s), Vector2(x - s * 0.7, y), Vector2(x, y - s)])
			draw_polyline(pts, c, 3.0, true)
			x += s * 2.0
		y += s
		row += 1

func _chevrons(r: Rect2, c: Color) -> void:
	var w := 40.0
	var y := r.position.y + 24.0
	while y + 24 <= r.end.y:
		var x := r.position.x + w / 2.0
		while x + w / 2.0 <= r.end.x:
			draw_polyline(PackedVector2Array([Vector2(x - w / 2.0 + 4, y), Vector2(x, y - 14), Vector2(x + w / 2.0 - 4, y)]), c, 5.0, true)
			x += w
		y += 30.0

func _stripes(r: Rect2, c: Color) -> void:
	var x: float = r.position.x - r.size.y
	while x < r.end.x:
		var poly := PackedVector2Array([
			Vector2(x, r.end.y), Vector2(x + 26, r.end.y),
			Vector2(x + 26 + r.size.y, r.position.y), Vector2(x + r.size.y, r.position.y)])
		var clipped := Geometry2D.intersect_polygons(poly, PackedVector2Array([
			r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
		for cp in clipped: draw_colored_polygon(cp, c)
		x += 70
