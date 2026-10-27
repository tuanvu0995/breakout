extends CanvasLayer
## Lose dialog: dims the game, shows the run summary, offers retry / quests / menu.
## RETRY restarts the SAME level (or the same custom level).

var level_title := ""
var score := 0
var best := 0
var new_record := false
var level := 1

var card: PanelContainer
var dim: ColorRect

func _ready() -> void:
	layer = 20
	dim = ColorRect.new()
	dim.color = Color(Globals.C_DARK, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	card = PanelContainer.new()
	card.theme = load("res://theme/main_theme.tres")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Globals.C_FIELD
	sb.set_corner_radius_all(32)
	sb.set_content_margin_all(48)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(680, 0)
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)

	_label(v, "NEW RECORD!" if new_record else "GAME OVER", 68, Globals.C_AMBER if new_record else Globals.C_CORAL)
	_label(v, level_title, 30, Globals.C_CYAN)
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 60)
	_stat(stats, "SCORE", str(score))
	_stat(stats, "BEST", str(best))
	v.add_child(stats)
	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	v.add_child(gap)
	var retry := _button(v, "RETRY", Globals.C_AMBER, Globals.C_DARK, _retry)
	_button(v, "QUESTS", Globals.C_WALL, Globals.C_WHITE, func(): _go("res://scenes/ui/level_select/level_select.tscn"))
	_button(v, "MAIN MENU", Globals.C_WALL, Globals.C_WHITE, func(): _go("res://scenes/ui/main_menu/main_menu.tscn"))

	Audio.wire_buttons(card)
	Fx.juice_buttons(card)
	await get_tree().process_frame
	card.pivot_offset = card.size / 2.0
	card.position = (Vector2(1920, 1080) - card.size) / 2.0
	card.scale = Vector2.ONE * 0.8
	card.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(dim, "color:a", 0.75, 0.35)
	tw.tween_property(card, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.15)
	tw.tween_property(card, "modulate:a", 1.0, 0.2).set_delay(0.15)
	retry.grab_focus()

func _retry() -> void:
	Globals.start_level = level   # custom_level is kept, so a custom level retries itself
	_go("res://scenes/game/game.tscn")

func _go(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _stat(parent: Node, caption: String, value: String) -> void:
	var v := VBoxContainer.new()
	_label(v, caption, 22, Color(Globals.C_WHITE, 0.5))
	_label(v, value, 44, Globals.C_WHITE)
	parent.add_child(v)

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _button(parent: Node, text: String, bg: Color, fg: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 38)
	for state in ["normal", "hover", "pressed", "focus"]:
		var st := StyleBoxFlat.new()
		st.bg_color = bg.lightened(0.15 if state in ["hover", "focus"] else 0.0)
		st.set_corner_radius_all(18)
		st.set_content_margin_all(14)
		b.add_theme_stylebox_override(state, st)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fg)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
