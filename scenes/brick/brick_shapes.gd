class_name BrickShapes
extends RefCounted
## Brick outlines beyond the square/long defaults. One polygon per shape drives
## both the drawn texture (antialiased, flat) and the collision, so the ball
## bounces off exactly what the player sees.

const NAMES := ["tri", "wedge", "circle", "hex", "diamond", "half", "star", "heart", "bar", "pill"]
const TEX := 72  # texture size; shapes fit in about +-32 px

static var _polys := {}

## Polygon in local pixels, centered near the origin.
static func poly(shape: String) -> PackedVector2Array:
	if _polys.has(shape): return _polys[shape]
	var p := PackedVector2Array()
	match shape:
		"tri":  # equilateral, pointing up
			p = [Vector2(0, -30), Vector2(32, 26), Vector2(-32, 26)]
		"wedge":  # right triangle, slope on the left: roofs, ramps
			p = [Vector2(-30, 30), Vector2(30, 30), Vector2(30, -30)]
		"circle":
			for i in 28: p.append(Vector2.from_angle(TAU * i / 28.0) * 29.0)
		"hex":
			for i in 6: p.append(Vector2.from_angle(TAU * i / 6.0) * 31.0)
		"diamond":
			p = [Vector2(0, -32), Vector2(26, 0), Vector2(0, 32), Vector2(-26, 0)]
		"half":  # dome, flat side down
			for i in 15: p.append(Vector2.from_angle(PI + PI * i / 14.0) * 30.0 + Vector2(0, 12))
		"star":
			for i in 10:
				var r := 33.0 if i % 2 == 0 else 14.0
				p.append(Vector2.from_angle(-PI / 2.0 + TAU * i / 10.0) * r + Vector2(0, 3))
		"heart":
			for i in 32:
				var a := TAU * i / 32.0
				var x := 16.0 * pow(sin(a), 3)
				var y := -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a))
				p.append(Vector2(x, y) * 1.9 + Vector2(0, -2))
		"bar":  # thin plank
			p = [Vector2(-60, -11), Vector2(60, -11), Vector2(60, 11), Vector2(-60, 11)]
		"pill":
			for i in 12: p.append(Vector2.from_angle(PI / 2.0 + PI * i / 11.0) * 18.0 + Vector2(-26, 0))
			for i in 12: p.append(Vector2.from_angle(-PI / 2.0 + PI * i / 11.0) * 18.0 + Vector2(26, 0))
	_polys[shape] = p
	return p

static func centroid(shape: String) -> Vector2:
	var c := Vector2.ZERO
	for v in poly(shape): c += v
	return c / poly(shape).size()

static func extent(shape: String) -> Vector2:
	var m := Vector2.ZERO
	for v in poly(shape): m = Vector2(max(m.x, abs(v.x)), max(m.y, abs(v.y)))
	return m

## White antialiased texture of the shape (cached), sized to fit it.
static func texture(shape: String) -> ImageTexture:
	var pts := poly(shape)
	var ext := extent(shape)
	var size := Vector2i(int(ext.x * 2) + 8, int(ext.y * 2) + 8)
	return Globals.sdf_texture("shape_" + shape, size, func(q):
		var d := INF
		for i in pts.size():
			d = min(d, _seg_dist(q, pts[i], pts[(i + 1) % pts.size()]))
		return -d if Geometry2D.is_point_in_polygon(q, pts) else d)

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t: float = clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Collision node matching the drawn shape.
static func collider(shape: String) -> Node2D:
	if shape == "circle":
		var c := CollisionShape2D.new()
		c.shape = CircleShape2D.new()
		c.shape.radius = 29.0
		return c
	var cp := CollisionPolygon2D.new()  # handles concave shapes (star, heart) too
	cp.polygon = poly(shape)
	return cp
