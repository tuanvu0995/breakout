extends Node2D
## Flat decoration for wall areas: diagonal stripes plus a rivet column along
## an inner edge. `rects` are the wall areas in local coords; `rivet_x` is the
## x of the edge that faces the arena (NAN = no rivets).

var rects: Array = []  # of Rect2
var rivet_x := NAN
var color := Color.WHITE

func set_color(wall: Color) -> void:
	color = wall
	queue_redraw()

func _draw() -> void:
	var stripe := color.darkened(0.12)
	for r: Rect2 in rects:
		var x: float = r.position.x - r.size.y
		while x < r.end.x:
			var poly := PackedVector2Array([
				Vector2(x, r.end.y), Vector2(x + 26, r.end.y),
				Vector2(x + 26 + r.size.y, r.position.y), Vector2(x + r.size.y, r.position.y)])
			var clipped := Geometry2D.intersect_polygons(poly, PackedVector2Array([
				r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
			for c in clipped: draw_colored_polygon(c, stripe)
			x += 70
	if not is_nan(rivet_x):
		var y := -1200.0
		while y < 1200.0:
			draw_circle(Vector2(rivet_x, y), 7, color.lightened(0.18))
			draw_circle(Vector2(rivet_x, y), 3, color.darkened(0.2))
			y += 90.0
