extends Path2D
class_name SmoothPath

@export var spline_length: float = 100
@export var width: float = 8
@export var color: Color = Color(1,1,1,1)
@export var _smooth: bool = false:
	get:
		return _smooth
	set(value):
		_smooth = value
		var point_count = curve.get_point_count()
		for i in point_count:
			var spline = _get_spline(i)
			curve.set_point_in(i, -spline)
			curve.set_point_out(i, spline)

@export var _straighten: bool = false:
	get:
		return _straighten
	set(value):
		_straighten = value
		for i in range(curve.get_point_count()):
			curve.set_point_in(i, Vector2())
			curve.set_point_out(i, Vector2())

func straighten(value):
	if not value: return
	for i in range(curve.get_point_count()):
		curve.set_point_in(i, Vector2())
		curve.set_point_out(i, Vector2())

func smooth(value):
	if not value: return

	var point_count = curve.get_point_count()
	for i in point_count:
		if i >0 and i < point_count-1:
			var spline = _get_spline(i)
			curve.set_point_in(i, -spline)
			curve.set_point_out(i, spline)

func _get_spline(i):
	var last_point = _get_point(i - 1)
	var next_point = _get_point(i + 1)
	var spline = last_point.direction_to(next_point) * spline_length
	return spline

func _get_point(i):
	var point_count = curve.get_point_count()
	i = wrapi(i, 0, point_count )
	if i >1 and i < point_count-1:
		return curve.get_point_position(i)
	elif i <= 1:
		return Vector2(curve.get_point_position(1).x - spline_length,curve.get_point_position(1).y)
	elif i >= point_count-1:
		return Vector2(curve.get_point_position(point_count-1).x + spline_length,curve.get_point_position(point_count-1).y)

func _draw():
	var points = curve.get_baked_points()
	if points:
		draw_polyline(points, color, width, true)
