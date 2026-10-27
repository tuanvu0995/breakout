extends Node2D
## Flat animated water at the bottom of the arena: three parallax wave layers in
## the theme's color, a foam line on top, and ripples + splashes where balls fall.

const SURFACE_Y := 1094.0  # below the ship and its engine flame
const LEFT := -700.0
const RIGHT := 2100.0
const STEP := 12.0

var color := Color("3ddcf5")
var t := 0.0
var ripples: Array = []  # [x, age]

func set_theme(wall: Color) -> void:
	color = Globals.C_CYAN.lerp(wall.lightened(0.3), 0.35)

## A ball (or anything) hit the water at x.
func splash(x: float, strength := 1.0) -> void:
	ripples.append([x, 0.0, strength])
	Fx.burst(get_parent(), Vector2(x, SURFACE_Y - 6), color.lightened(0.4), 14, 380.0 * strength, 8.0)
	Fx.burst(get_parent(), Vector2(x, SURFACE_Y - 6), Color(1, 1, 1, 0.9), 6, 300.0 * strength, 5.0)

func _process(delta: float) -> void:
	t += delta
	for r in ripples: r[1] += delta
	ripples = ripples.filter(func(r): return r[1] < 2.5)
	queue_redraw()

## Surface height offset at x for a layer.
func _wave(x: float, layer: int) -> float:
	var speed: float = [0.6, 1.0, 1.5][layer]
	var amp: float = [5.0, 7.0, 6.0][layer]
	var h := sin(x * 0.012 + t * speed + layer * 1.7) * amp + sin(x * 0.031 - t * speed * 1.3) * amp * 0.4
	if layer == 2:
		# ripples: two crests running away from the impact, fading out
		for r in ripples:
			var age: float = r[1]
			var dist: float = abs(x - r[0]) - age * 260.0
			h += -exp(-dist * dist / 900.0) * 16.0 * r[2] * (1.0 - age / 2.5)
	return h

func _layer_points(layer: int, y0: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := LEFT
	while x <= RIGHT:
		pts.append(Vector2(x, y0 + _wave(x, layer)))
		x += STEP
	return pts

func _draw() -> void:
	var offsets := [-8.0, -3.0, 0.0]
	var shades := [color.darkened(0.45), color.darkened(0.25), color]
	var alphas := [0.55, 0.75, 0.9]
	var front := PackedVector2Array()
	for layer in 3:
		var top := _layer_points(layer, SURFACE_Y + offsets[layer])
		var poly := top.duplicate()
		poly.append(Vector2(RIGHT, SURFACE_Y + 400))
		poly.append(Vector2(LEFT, SURFACE_Y + 400))
		draw_colored_polygon(poly, Color(shades[layer], alphas[layer]))
		if layer == 2: front = top
	draw_polyline(front, Color(1, 1, 1, 0.7), 4.0, true)
	# soft highlight streaks under the foam
	var x := LEFT + fmod(t * 30.0, 160.0)
	while x < RIGHT:
		var y := SURFACE_Y + 18.0 + _wave(x, 2) * 0.5
		draw_line(Vector2(x, y), Vector2(x + 46, y), Color(1, 1, 1, 0.18), 3.0)
		x += 160.0
