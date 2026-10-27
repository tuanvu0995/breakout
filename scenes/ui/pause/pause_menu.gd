extends CanvasLayer
## Pause menu. Runs while the tree is paused. Esc / back / RESUME closes it.

signal resumed

var title_text := ""
var info_text := ""
var card: PanelContainer
var dim: ColorRect
var closing := false

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	dim = ColorRect.new()
	dim.color = Color(Globals.C_DARK, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	card = PanelContainer.new()
	card.theme = load("res://theme/main_theme.tres")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Globals.C_FIELD
	sb.set_corner_radius_all(32)
	sb.set_content_margin_all(44)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(640, 0)
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)

	_label(v, "PAUSED", 64, Globals.C_AMBER)
	_label(v, title_text, 30, Globals.C_CYAN)
	_label(v, info_text, 26, Color(Globals.C_WHITE, 0.6))
	v.add_child(_gap(10))
	var resume := _button(v, "RESUME", Globals.C_AMBER, Globals.C_DARK, close)
	_button(v, "RESTART", Globals.C_VIOLET, Globals.C_WHITE, func(): _leave(restart_scene()))
	_button(v, "QUESTS", Globals.C_WALL, Globals.C_WHITE, func(): _leave("res://scenes/ui/level_select/level_select.tscn"))
	_button(v, "MAIN MENU", Globals.C_WALL, Globals.C_WHITE, func(): _leave("res://scenes/ui/main_menu/main_menu.tscn"))
	v.add_child(_gap(6))

	_button(v, "SETTINGS", Globals.C_WALL, Globals.C_WHITE, func():
		add_child(preload("res://scenes/ui/settings/settings_screen.gd").new()))
	_label(v, "Esc to resume", 22, Color(Globals.C_WHITE, 0.35))

	Audio.wire_buttons(card)
	Fx.juice_buttons(card)
	await get_tree().process_frame
	card.pivot_offset = card.size / 2.0
	card.position = (Vector2(1920, 1080) - card.size) / 2.0
	card.scale = Vector2.ONE * 0.85
	card.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(dim, "color:a", 0.7, 0.2)
	tw.tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.15)
	resume.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	if closing: return
	closing = true
	var tw := create_tween().set_parallel()
	tw.tween_property(dim, "color:a", 0.0, 0.15)
	tw.tween_property(card, "scale", Vector2.ONE * 0.9, 0.15)
	tw.tween_property(card, "modulate:a", 0.0, 0.15)
	await tw.finished
	resumed.emit()
	queue_free()

func restart_scene() -> String:
	return "res://scenes/game/game.tscn"

func _leave(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(path)

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c

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
