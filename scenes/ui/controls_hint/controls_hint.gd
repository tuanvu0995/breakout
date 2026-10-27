extends VBoxContainer
## Bottom-left controls helper. Shows keyboard, gamepad or touch labels for the
## device the player last used, and reacts to the game state: LAUNCH vs BUMP,
## overdrive lights up when energy is full, pull dims with no energy.

var game: Node
var rows := {}   # id -> {row, label, cap}
var pulse := 0.0
var mode := ""

## id -> [label for the button, action text] per input mode
const LABELS := {
	"kb": {"launch": "SPACE", "overdrive": "E", "pull": "Q", "move": "A  D"},
	"pad": {"launch": "A", "overdrive": "Y", "pull": "X", "move": "L-STICK"},
	"touch": {"launch": "TAP", "overdrive": "2 FINGERS", "move": "DRAG"},
}

func _ready() -> void:
	theme = load("res://theme/main_theme.tres")
	add_theme_constant_override("separation", 8)
	modulate.a = 0.0
	_build(Globals.input_mode)
	Globals.input_mode_changed.connect(_build)

func _build(new_mode: String) -> void:
	if new_mode == mode: return
	mode = new_mode
	for c in get_children(): c.queue_free()
	rows.clear()
	var keys: Dictionary = LABELS.get(mode, LABELS["kb"])
	for id in ["launch", "overdrive", "pull", "move"]:
		if keys.has(id): _row(id, keys[id], {"launch": "LAUNCH", "overdrive": "OVERDRIVE", "pull": "PULL BALL", "move": "MOVE"}[id])

func _row(id: String, key: String, action: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Globals.C_WHITE, 0.14)
	sb.set_corner_radius_all(8 if mode != "pad" else 14)  # round caps for pad buttons
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
	rows[id] = {"row": h, "label": a, "cap": sb}

func _process(delta: float) -> void:
	if not game or not is_instance_valid(game): return
	pulse += delta
	# Only shown while the ball waits on the ship, so it never covers the arena in play.
	var want := 1.0 if Globals.settings["hints"] and game.paddle.ball_attached and not game.paddle.game_over else 0.0
	modulate.a = move_toward(modulate.a, want, delta * 3.0)
	var energy: float = game.energy
	if rows.has("launch"):
		rows["launch"]["label"].text = "LAUNCH" if game.paddle.ball_attached else "BUMP / BOOST"
	if rows.has("overdrive"):
		var ready := energy >= 100.0
		rows["overdrive"]["row"].modulate.a = 1.0 if ready else 0.35
		rows["overdrive"]["label"].text = "OVERDRIVE!" if ready else "OVERDRIVE"
		rows["overdrive"]["label"].add_theme_color_override("font_color", Globals.C_AMBER if ready else Color(Globals.C_WHITE, 0.7))
		rows["overdrive"]["cap"].bg_color = Color(Globals.C_AMBER, 0.35 + 0.25 * sin(pulse * 6.0)) if ready else Color(Globals.C_WHITE, 0.14)
	if rows.has("pull"):
		rows["pull"]["row"].modulate.a = 1.0 if energy > 1.0 and not game.paddle.ball_attached else 0.35
