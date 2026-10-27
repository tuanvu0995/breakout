extends VBoxContainer
## Bottom-left keyboard helper. Rows react to the game state:
## SPACE says LAUNCH / BUMP, E lights up when overdrive is ready, Q dims with no energy.

var game: Node
var rows := {}   # key -> {row, action label}
var pulse := 0.0

func _ready() -> void:
	theme = load("res://theme/main_theme.tres")
	add_theme_constant_override("separation", 8)
	modulate.a = 0.0
	if DisplayServer.is_touchscreen_available():
		_row("DRAG", "MOVE")
		_row("TAP", "LAUNCH / BUMP")
		_row("2 FINGERS", "OVERDRIVE")
	else:
		_row("SPACE", "LAUNCH")
		_row("E", "OVERDRIVE")
		_row("Q", "PULL BALL")
		_row("A  D", "MOVE")

func _row(key: String, action: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Globals.C_WHITE, 0.14)
	sb.set_corner_radius_all(8)
	sb.border_width_bottom = 3  # keycap lip
	sb.border_color = Color(0, 0, 0, 0.35)
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 2; sb.content_margin_bottom = 2
	cap.add_theme_stylebox_override("panel", sb)
	cap.custom_minimum_size.x = 44
	var k := Label.new()
	k.text = key
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.add_theme_font_size_override("font_size", 20)
	k.add_theme_color_override("font_color", Globals.C_WHITE)
	cap.add_child(k)
	var a := Label.new()
	a.text = action
	a.add_theme_font_size_override("font_size", 18)
	a.add_theme_color_override("font_color", Color(Globals.C_WHITE, 0.7))
	h.add_child(cap)
	h.add_child(a)
	add_child(h)
	rows[key] = {"row": h, "label": a, "cap": sb}

func _process(delta: float) -> void:
	if not game or not is_instance_valid(game): return
	pulse += delta
	# Only shown while the ball waits on the ship, so it never covers the arena in play.
	var want := 1.0 if Globals.settings["hints"] and game.paddle.ball_attached and not game.paddle.game_over else 0.0
	modulate.a = move_toward(modulate.a, want, delta * 3.0)
	var energy: float = game.energy
	if rows.has("SPACE"):
		rows["SPACE"]["label"].text = "LAUNCH" if game.paddle.ball_attached else "BUMP / BOOST"
	if rows.has("E"):
		var ready := energy >= 100.0
		rows["E"]["row"].modulate.a = 1.0 if ready else 0.35
		rows["E"]["label"].text = "OVERDRIVE!" if ready else "OVERDRIVE"
		rows["E"]["label"].add_theme_color_override("font_color", Globals.C_AMBER if ready else Color(Globals.C_WHITE, 0.7))
		rows["E"]["cap"].bg_color = Color(Globals.C_AMBER, 0.35 + 0.25 * sin(pulse * 6.0)) if ready else Color(Globals.C_WHITE, 0.14)
	if rows.has("Q"):
		rows["Q"]["row"].modulate.a = 1.0 if energy > 1.0 and not game.paddle.ball_attached else 0.35
