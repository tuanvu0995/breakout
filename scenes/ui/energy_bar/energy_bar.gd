extends Control
## Horizontal energy bar, top-right. Pulses "OVERDRIVE READY" when full.

const BAR_SIZE := Vector2(380, 26)

@onready var progress: ProgressBar = $ProgressBar
var label: Label
var ready_tween: Tween

func _ready() -> void:
	$TextureRect.visible = false
	# anchored to the top-right corner of the real screen
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -40 - BAR_SIZE.x; offset_right = -40
	offset_top = 22; offset_bottom = 22 + BAR_SIZE.y + 40
	progress.fill_mode = ProgressBar.FILL_BEGIN_TO_END
	progress.set_anchors_preset(Control.PRESET_TOP_LEFT)  # fixed size, no stretching
	progress.position = Vector2(0, 34)
	progress.size = BAR_SIZE
	progress.value = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(Globals.C_WHITE, 0.1)
	bg.set_corner_radius_all(13)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Globals.C_CYAN
	fill.set_corner_radius_all(13)
	progress.add_theme_stylebox_override("background", bg)
	progress.add_theme_stylebox_override("fill", fill)
	label = Label.new()
	label.theme = load("res://theme/main_theme.tres")
	label.text = "ENERGY"
	label.size = Vector2(BAR_SIZE.x, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(Globals.C_WHITE, 0.6))
	add_child(label)

func set_energy(new_value: int) -> void:
	var was_full := progress.value >= 100
	progress.value = new_value
	var full := new_value >= 100
	if full == was_full: return
	if ready_tween: ready_tween.kill()
	if full:
		Fx.punch(progress, 0.15, 0.5)
		label.text = "OVERDRIVE READY  -  " + ("2-FINGER TAP" if DisplayServer.is_touchscreen_available() else "PRESS E")
		label.add_theme_color_override("font_color", Globals.C_AMBER)
		ready_tween = create_tween().set_loops()
		ready_tween.tween_property(label, "modulate:a", 0.35, 0.45)
		ready_tween.tween_property(label, "modulate:a", 1.0, 0.45)
	else:
		label.text = "ENERGY"
		label.modulate.a = 1.0
		label.add_theme_color_override("font_color", Color(Globals.C_WHITE, 0.6))
