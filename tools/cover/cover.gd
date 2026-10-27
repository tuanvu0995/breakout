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
	# Real game bricks (same scene and art as in play), every brick kind on show:
	# 1/2/3-hit pips, bomb, energy, a fading phantom, plus a boss in the corner.
	var brick_scene := preload("res://scenes/brick/brick.tscn")
	# [shape, type (0..2 hits, 3 bomb, 4 energy), x offset, y, rot, alpha]
	var layout := [
		["", 2, -480, 470, 0, 1.0], ["tri", 1, -360, 470, 0, 1.0], ["hex", 0, -240, 470, 0, 1.0],
		["", 3, -120, 470, 0, 1.0], ["diamond", 4, 0, 470, 0, 1.0], ["", 2, 120, 470, 0, 1.0],
		["heart", 1, 240, 470, 0, 1.0], ["circle", 0, 360, 470, 0, 1.0], ["star", 2, 480, 470, 0, 1.0],
		["circle", 1, -420, 580, 0, 1.0], ["", 0, -300, 580, 0, 1.0], ["hex", 4, -180, 580, 0, 1.0],
		["", 1, -60, 580, 0, 0.35], ["tri", 2, 60, 580, 180, 1.0], ["circle", 3, 180, 580, 0, 1.0],
		["diamond", 0, 300, 580, 0, 1.0], ["", 2, 420, 580, 0, 1.0],
		["star", 0, -300, 690, 0, 1.0], ["half", 1, -180, 690, 0, 1.0], ["pill", 2, 330, 690, 0, 1.0],
	]
	for e in layout:
		var b = brick_scene.instantiate()
		var spec := {"type": e[1], "size": 0, "rot": float(e[4])}
		if e[0] != "": spec["shape"] = e[0]
		b.spec = spec
		b.position = Vector2(OX + W / 2.0 + e[2], e[3])
		add_child(b)
		b.scale = Vector2.ONE * 1.45
		b.modulate.a = e[5]
	# boss looming in the bottom-right corner
	var boss = brick_scene.instantiate()
	boss.spec = {"type": 2, "size": 0, "boss": true, "shape": "hex", "scale": 3.0, "hp": 30, "color": Globals.C_RED}
	boss.position = Vector2(OX + W - 150, 880)
	add_child(boss)
	boss.rotation_degrees = -12
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# shattering brick with shards
	for i in 18:
		var p := Sprite2D.new()
		p.texture = Globals.round_rect_tex(Vector2i(14, 14), 3)
		p.modulate = Globals.C_AMBER if i % 2 else Globals.C_CORAL
		p.position = Vector2(OX + W / 2.0 + 60, 690) + Vector2.from_angle(TAU * i / 18.0) * rng.randf_range(40, 110)
		p.rotation = rng.randf() * TAU
		add_child(p)
	# ball with trail
	var trail := Line2D.new()
	trail.points = PackedVector2Array([Vector2(OX + 560, 970), Vector2(OX + 640, 860), Vector2(OX + 735, 730)])
	trail.width = 22
	var wc := Curve.new(); wc.add_point(Vector2(0, 0.1)); wc.add_point(Vector2(1, 1))
	trail.width_curve = wc
	trail.default_color = Color(Globals.C_CYAN, 0.8)
	add_child(trail)
	var ball := Sprite2D.new()
	ball.texture = Globals.circle_tex(52)
	ball.position = Vector2(OX + 740, 722)
	add_child(ball)
	# ship firing triple shots
	var ship := Node2D.new()
	ship.position = Vector2(OX + W / 2.0 - 40, 990)
	ship.scale = Vector2.ONE * 1.25
	for poly in Globals.make_ship(Globals.SKINS[0], 75, 21): ship.add_child(poly)
	add_child(ship)
	for k in [-1, 0, 1]:
		for j in 2:
			var b := Sprite2D.new()
			b.texture = Globals.round_rect_tex(Vector2i(10, 34), 5)
			b.modulate = Globals.C_AMBER
			b.position = ship.position + Vector2(k * 52, -90 - j * 70)
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
