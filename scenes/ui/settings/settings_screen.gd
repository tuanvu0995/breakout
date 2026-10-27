extends CanvasLayer
## Settings overlay: audio, display, gameplay, data. Works over menus and over
## the paused game (process mode always). Every change is applied and saved at once.

signal closed

const ROW_W := 760.0

var card: PanelContainer
var dim: ColorRect
var reset_btn: Button
var reset_armed := false

func _ready() -> void:
	layer = 30
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
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)

	var title := _label("SETTINGS", 56, Globals.C_AMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	_section(v, "AUDIO")
	_slider_row(v, "MASTER", Globals.volume, func(x): Globals.set_volume(x))
	_slider_row(v, "MUSIC", Globals.settings["music"], func(x): Globals.settings["music"] = x; Globals.apply_settings())
	_slider_row(v, "EFFECTS", Globals.settings["sfx"], func(x): Globals.settings["sfx"] = x; Globals.apply_settings(); Audio.sfx("brick_hit", -6.0))

	_section(v, "DISPLAY")
	_toggle_row(v, "FULLSCREEN", "fullscreen")
	_toggle_row(v, "VSYNC", "vsync")
	_choice_row(v, "SCREEN SHAKE", [["OFF", 0.0], ["LOW", 0.5], ["FULL", 1.0]], "shake")

	_section(v, "GAMEPLAY")
	_toggle_row(v, "SCORE POPUPS", "popups")
	_toggle_row(v, "CONTROL HINTS", "hints")

	_section(v, "DATA")
	var data_row := _row(v, "PROGRESS")
	reset_btn = _pill("RESET", Color(Globals.C_RED, 0.85), Globals.C_WHITE, _on_reset)
	reset_btn.custom_minimum_size.x = 300
	data_row.add_child(reset_btn)

	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	v.add_child(gap)
	var back := _pill("BACK", Globals.C_AMBER, Globals.C_DARK, close)
	back.custom_minimum_size = Vector2(ROW_W, 64)
	back.add_theme_font_size_override("font_size", 34)
	v.add_child(back)

	Audio.wire_buttons(card)
	Fx.juice_buttons(card)
	await get_tree().process_frame
	card.pivot_offset = card.size / 2.0
	card.position = (Vector2(1920, 1080) - card.size) / 2.0
	card.scale = Vector2.ONE * 0.9
	card.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(dim, "color:a", 0.7, 0.2)
	tw.tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.15)
	back.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	Globals.save()
	closed.emit()
	queue_free()

# ---------------------------------------------------------------- rows

func _section(parent: Node, text: String) -> void:
	var l := _label(text, 22, Color(Globals.C_WHITE, 0.45))
	l.custom_minimum_size.y = 34
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	parent.add_child(l)

func _row(parent: Node, caption: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.custom_minimum_size.x = ROW_W
	var l := _label(caption, 28, Globals.C_WHITE)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	parent.add_child(h)
	return h

func _slider_row(parent: Node, caption: String, value: float, on_change: Callable) -> void:
	var h := _row(parent, caption)
	var s := HSlider.new()
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(380, 32)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := StyleBoxFlat.new()
	track.bg_color = Color(Globals.C_WHITE, 0.12)
	track.set_corner_radius_all(6)
	track.content_margin_top = 5; track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = Globals.C_AMBER
	fill.set_corner_radius_all(6)
	fill.content_margin_top = 5; fill.content_margin_bottom = 5
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", Globals.circle_tex(28))
	s.add_theme_icon_override("grabber_highlight", Globals.circle_tex(32))
	s.value_changed.connect(on_change)
	s.drag_ended.connect(func(_c): Globals.save())
	var pct := _label("%d%%" % int(value * 100), 24, Color(Globals.C_WHITE, 0.6))
	pct.custom_minimum_size.x = 80
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(x): pct.text = "%d%%" % int(x * 100))
	h.add_child(s)
	h.add_child(pct)

func _toggle_row(parent: Node, caption: String, key: String) -> void:
	var h := _row(parent, caption)
	var b := _pill("", Color.WHITE, Globals.C_DARK, func(): pass)
	b.custom_minimum_size.x = 140
	var paint := func():
		var on: bool = Globals.settings[key]
		b.text = "ON" if on else "OFF"
		_style(b, Globals.C_GREEN if on else Color(Globals.C_WHITE, 0.12), Globals.C_DARK if on else Globals.C_WHITE)
	paint.call()
	b.pressed.connect(func():
		Globals.set_setting(key, not Globals.settings[key])
		paint.call())
	h.add_child(b)

func _choice_row(parent: Node, caption: String, options: Array, key: String) -> void:
	var h := _row(parent, caption)
	h.add_theme_constant_override("separation", 8)
	var buttons: Array[Button] = []
	var paint := func():
		for i in options.size():
			var on: bool = is_equal_approx(float(Globals.settings[key]), float(options[i][1]))
			_style(buttons[i], Globals.C_VIOLET if on else Color(Globals.C_WHITE, 0.12), Globals.C_WHITE)
	for o in options:
		var b := _pill(o[0], Color.WHITE, Globals.C_WHITE, func(): pass)
		b.custom_minimum_size.x = 110
		var val: float = o[1]
		b.pressed.connect(func():
			Globals.set_setting(key, val)
			paint.call()
			if val > 0.0 and Globals.camera: Globals.camera.shake(0.25, 14, 10))
		buttons.append(b)
		h.add_child(b)
	paint.call()

func _on_reset() -> void:
	if not reset_armed:
		reset_armed = true
		reset_btn.text = "TAP AGAIN TO CONFIRM"
		Audio.sfx("pause", -4.0)
		await get_tree().create_timer(3.0, true, false, true).timeout
		if is_instance_valid(reset_btn) and reset_armed:
			reset_armed = false
			reset_btn.text = "RESET"
		return
	reset_armed = false
	Globals.reset_progress()
	reset_btn.text = "PROGRESS RESET"
	reset_btn.disabled = true
	Audio.sfx("life_lost", -4.0)

# ---------------------------------------------------------------- widgets

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func _pill(text: String, bg: Color, fg: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size.y = 48
	_style(b, bg, fg)
	b.pressed.connect(cb)
	return b

func _style(b: Button, bg: Color, fg: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var st := StyleBoxFlat.new()
		st.bg_color = bg.lightened(0.12) if state in ["hover", "focus"] else bg
		st.set_corner_radius_all(24)
		st.content_margin_left = 18; st.content_margin_right = 18
		b.add_theme_stylebox_override(state, st)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, fg)
