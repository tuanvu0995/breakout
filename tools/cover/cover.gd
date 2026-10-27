extends Node2D
## Renders the itch.io cover art (run with --write-movie, then crop to 630x500).
## Composition lives in a 1360x1080 frame centered on screen (ratio 1.26 = 630:500).

const W := 1360.0
const OX := (1920.0 - W) / 2.0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Globals.C_BG)
	var bd = preload("res://scenes/effects/backdrop.gd").new()
	bd.full_screen = true
	bd.set_theme(1, Globals.C_BG, Globals.C_WALL)
	add_child(bd)
	# bricks: a burst of shapes in the top half
	var shapes := ["", "tri", "circle", "hex", "diamond", "star", "heart", "half", "pill"]
	var colors := [Globals.C_CORAL, Globals.C_AMBER, Globals.C_VIOLET, Globals.C_CYAN, Globals.C_RED]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for row in 3:
		var n := 9 - row
		for i in n:
			var x := OX + W / 2.0 + (i - (n - 1) / 2.0) * 120.0
			var y := 430.0 + row * 105.0
			var sh: String = shapes[(i + row * 2) % shapes.size()]
			var s := Sprite2D.new()
			s.texture = Globals.round_rect_tex(Vector2i(84, 84), 18) if sh == "" else BrickShapes.texture(sh)
			s.scale = Vector2.ONE * (1.0 if sh == "" else 1.35)
			s.rotation_degrees = rng.randf_range(-14, 14)
			s.modulate = colors[(i + row) % colors.size()]
			s.position = Vector2(x, y)
			add_child(s)
	# shattering brick with shards
	for i in 18:
		var p := Sprite2D.new()
		p.texture = Globals.round_rect_tex(Vector2i(14, 14), 3)
		p.modulate = Globals.C_AMBER if i % 2 else Globals.C_CORAL
		p.position = Vector2(OX + W / 2.0 + 150, 640) + Vector2.from_angle(TAU * i / 18.0) * rng.randf_range(40, 110)
		p.rotation = rng.randf() * TAU
		add_child(p)
	# ball with trail
	var trail := Line2D.new()
	trail.points = PackedVector2Array([Vector2(OX + 540, 960), Vector2(OX + 640, 820), Vector2(OX + 760, 680)])
	trail.width = 22
	var wc := Curve.new(); wc.add_point(Vector2(0, 0.1)); wc.add_point(Vector2(1, 1))
	trail.width_curve = wc
	trail.default_color = Color(Globals.C_CYAN, 0.8)
	add_child(trail)
	var ball := Sprite2D.new()
	ball.texture = Globals.circle_tex(52)
	ball.position = Vector2(OX + 765, 672)
	add_child(ball)
	# ship firing triple shots
	var ship := Node2D.new()
	ship.position = Vector2(OX + W / 2.0 - 40, 990)
	ship.scale = Vector2.ONE * 1.25
	for poly in Globals.make_ship(Globals.SKINS[0], 75, 21): ship.add_child(poly)
	add_child(ship)
	for k in [-1, 0, 1]:
		for j in 3:
			var b := Sprite2D.new()
			b.texture = Globals.round_rect_tex(Vector2i(10, 34), 5)
			b.modulate = Globals.C_AMBER
			b.position = ship.position + Vector2(k * 52, -90 - j * 95)
			add_child(b)
	# title
	var title := Label.new()
	title.text = "BRICKSTELLAR"
	title.add_theme_font_override("font", load("res://assets/font/Kenney Blocks.ttf"))
	title.add_theme_font_size_override("font_size", 124)
	title.add_theme_color_override("font_color", Globals.C_AMBER)
	title.add_theme_color_override("font_shadow_color", Color(Globals.C_DARK, 0.9))
	title.add_theme_constant_override("shadow_offset_y", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(W, 160)
	title.position = Vector2(OX, 120)
	add_child(title)
	var sub := Label.new()
	sub.text = "120 LEVELS  -  12 WORLDS  -  1 ARCHITECT"
	sub.theme = load("res://theme/main_theme.tres")
	sub.add_theme_font_size_override("font_size", 34)
	sub.add_theme_color_override("font_color", Globals.C_CYAN)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(W, 50)
	sub.position = Vector2(OX, 290)
	add_child(sub)
