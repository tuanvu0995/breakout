extends Control
## Player level editor. Canvas-first layout: slim top bar, two floating tool
## panels, and a big grid in the middle with a live preview under the cursor.
## Left click / drag paints, right click erases, R rotates, 1-5 picks the brick, E erases.

const Levels = preload("res://scenes/levels/levels.gd")
const COLS := 17
const ROWS := 9
const CELL := 66.0                  # game-space spacing used by to_layout()
const SAVE_PATH := "user://custom_levels.json"
const SLOTS := 3
const TYPE_NAMES := ["1 HIT", "2 HITS", "3 HITS", "BOMB", "ENERGY"]
const ERASE := 5
const MOTIONS := ["STILL", "SPIN", "BLINK", "WAVE"]
const SHAPES := ["", "tri", "wedge", "circle", "hex", "diamond", "half", "star", "heart"]

const TOP_H := 96.0
const SIDE_W := 236.0
const PAD := 28.0

var cells := {}  # Vector2i -> [type:int, motion:String, shape:String, rot:int]
var tool_type := 0
var tool_motion := "STILL"
var tool_shape := ""
var tool_rot := 0
var slot := 0
var dirty := false

var grid_origin := Vector2.ZERO
var vs := Vector2(1920, 1080)       # real screen size (aspect "expand")
var cs := 66.0                      # on-screen cell size
var hover := Vector2i(-1, -1)
var painting := 0                   # 0 none, 1 paint, -1 erase

var type_buttons: Array[Button] = []
var shape_buttons: Array[Button] = []
var motion_buttons: Array[Button] = []
var slot_buttons: Array[Button] = []
var rot_button: Button
var hint: Label

func brick_colors() -> Array:
	return [Globals.C_CORAL, Globals.C_AMBER, Globals.C_VIOLET, Globals.C_RED, Globals.C_CYAN]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = load("res://theme/main_theme.tres")
	mouse_filter = Control.MOUSE_FILTER_STOP
	vs = get_viewport_rect().size
	# Fit the grid into the space between the two tool panels.
	var area := Rect2(PAD * 2 + SIDE_W, TOP_H + 20, vs.x - 2 * (PAD * 2 + SIDE_W), vs.y - TOP_H - 90)
	cs = floor(min(area.size.x / COLS, area.size.y / ROWS))
	grid_origin = (area.position + (area.size - Vector2(COLS, ROWS) * cs) / 2.0).floor()
	build_top_bar()
	build_left_panel()
	build_right_panel()
	hint = Label.new()
	hint.position = Vector2(0, vs.y - 56)
	hint.size = Vector2(vs.x, 40)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(Globals.C_WHITE, 0.4))
	add_child(hint)
	load_slot(0)
	select_type(0)
	select_shape(0)
	select_motion(0)
	Audio.play_music(Audio.MENU_MUSIC)
	Audio.wire_buttons(self)

# ---------------------------------------------------------------- layout

func build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(PAD, 18)
	bar.size = Vector2(vs.x - PAD * 2, 60)
	bar.add_theme_constant_override("separation", 14)
	add_child(bar)
	bar.add_child(_btn("< MENU", _back, Color(0, 0, 0, 0), Color(Globals.C_WHITE, 0.7), Vector2(130, 56)))
	var title := Label.new()
	title.text = "LEVEL EDITOR"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Globals.C_AMBER)
	bar.add_child(title)
	bar.add_child(_spacer())
	var group := ButtonGroup.new()
	for i in SLOTS:
		var b := _btn("SLOT %d" % (i + 1), load_slot.bind(i), Globals.C_FIELD, Globals.C_WHITE, Vector2(130, 56))
		b.toggle_mode = true
		b.button_group = group
		slot_buttons.append(b)
		bar.add_child(b)
	bar.add_child(_spacer())
	bar.add_child(_btn("CLEAR", _clear, Color(0, 0, 0, 0), Color(Globals.C_WHITE, 0.7), Vector2(120, 56)))
	bar.add_child(_btn("SAVE", _save_pressed, Globals.C_FIELD, Globals.C_WHITE, Vector2(120, 56)))
	bar.add_child(_btn("PLAY", play_test, Globals.C_AMBER, Globals.C_DARK, Vector2(150, 56)))

func build_left_panel() -> void:
	var v := _panel(Vector2(PAD, TOP_H + 20), "BRICK")
	var group := ButtonGroup.new()
	for i in TYPE_NAMES.size() + 1:
		var b := _btn("ERASE" if i == ERASE else TYPE_NAMES[i], select_type.bind(i),
			Color(0, 0, 0, 0), Globals.C_WHITE, Vector2(SIDE_W - 36, 66))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("h_separation", 16)
		if i != ERASE:
			b.icon = _type_icon(i)
		b.toggle_mode = true
		b.button_group = group
		type_buttons.append(b)
		v.add_child(b)

func build_right_panel() -> void:
	var v := _panel(Vector2(vs.x - PAD - SIDE_W, TOP_H + 20), "SHAPE")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var group := ButtonGroup.new()
	for i in SHAPES.size():
		var b := _btn("", select_shape.bind(i), Color(0, 0, 0, 0), Globals.C_WHITE, Vector2(60, 60))
		b.icon = _shape_icon(SHAPES[i])
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.expand_icon = true
		b.toggle_mode = true
		b.button_group = group
		b.tooltip_text = "square" if SHAPES[i] == "" else SHAPES[i]
		shape_buttons.append(b)
		grid.add_child(b)
	v.add_child(grid)
	rot_button = _btn("ROTATE  0°", rotate_tool, Globals.C_WALL, Globals.C_WHITE, Vector2(SIDE_W - 36, 52))
	v.add_child(rot_button)
	v.add_child(_gap(10))
	v.add_child(_caption("MOTION"))
	var mgroup := ButtonGroup.new()
	for i in MOTIONS.size():
		var b := _btn(MOTIONS[i], select_motion.bind(i), Color(0, 0, 0, 0), Globals.C_WHITE, Vector2(SIDE_W - 36, 52))
		b.toggle_mode = true
		b.button_group = mgroup
		motion_buttons.append(b)
		v.add_child(b)

func _panel(pos: Vector2, caption: String) -> VBoxContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.custom_minimum_size = Vector2(SIDE_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Globals.C_FIELD, 0.85)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(_caption(caption))
	return v

func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(Globals.C_WHITE, 0.45))
	return l

func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c

## Flat button: `bg` normal, lighter on hover, violet when toggled on.
func _btn(text: String, cb: Callable, bg: Color, fg: Color, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 24)
	var hover_bg := Color(Globals.C_WHITE, 0.08) if bg.a == 0.0 else bg.lightened(0.12)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var st := StyleBoxFlat.new()
		st.bg_color = {"normal": bg, "hover": hover_bg, "disabled": bg,
			"pressed": Color(Globals.C_VIOLET, 0.9), "hover_pressed": Globals.C_VIOLET}[state]
		st.set_corner_radius_all(14)
		st.content_margin_left = 14; st.content_margin_right = 14
		b.add_theme_stylebox_override(state, st)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, fg)
	b.pressed.connect(cb)
	return b

func _type_icon(i: int) -> Texture2D:
	var img := Globals.round_rect_tex(Vector2i(40, 40), 10).get_image()
	var pip: Image = (Globals.circle_tex(26) if i == 3 else Globals.diamond_tex() if i == 4 else Globals.pips_tex(i + 1)).get_image()
	var c: Color = brick_colors()[i]
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			img.set_pixel(x, y, Color(c, a))
	# stamp the dots/symbol in the middle, scaled to fit
	pip.resize(int(pip.get_width() * 0.55), int(pip.get_height() * 0.55))
	var off := (Vector2i(40, 40) - pip.get_size()) / 2
	var mark := Globals.C_DARK if i == 3 else Globals.C_WHITE
	for y in pip.get_height():
		for x in pip.get_width():
			var a := pip.get_pixel(x, y).a
			if a > 0.0:
				var under := img.get_pixel(off.x + x, off.y + y)
				img.set_pixel(off.x + x, off.y + y, under.lerp(Color(mark, under.a), a))
	return ImageTexture.create_from_image(img)

func _shape_icon(shape: String) -> Texture2D:
	return Globals.round_rect_tex(Vector2i(56, 56), 12) if shape == "" else BrickShapes.texture(shape)

# ---------------------------------------------------------------- tools

func select_type(i: int) -> void:
	tool_type = i
	type_buttons[i].button_pressed = true
	refresh_hint()

func select_shape(i: int) -> void:
	tool_shape = SHAPES[i]
	shape_buttons[i].button_pressed = true
	if tool_type == ERASE: select_type(0)
	refresh_hint()

func select_motion(i: int) -> void:
	tool_motion = MOTIONS[i]
	motion_buttons[i].button_pressed = true
	refresh_hint()

func rotate_tool() -> void:
	tool_rot = (tool_rot + 90) % 360
	rot_button.text = "ROTATE  %d°" % tool_rot
	queue_redraw()

func refresh_hint() -> void:
	hint.text = "%d BRICKS   -   LEFT: PAINT   RIGHT: ERASE   R: ROTATE   1-5: BRICK   E: ERASE%s" % [
		cells.size(), "   -   UNSAVED" if dirty else ""]
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo): return
	match event.keycode:
		KEY_R: rotate_tool()
		KEY_E: select_type(ERASE)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5: select_type(event.keycode - KEY_1)
		KEY_ESCAPE: _back()
		_: return
	get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- canvas

func cell_at(p: Vector2) -> Vector2i:
	var g := (p - grid_origin) / cs
	if g.x < 0 or g.y < 0 or g.x >= COLS or g.y >= ROWS: return Vector2i(-1, -1)
	return Vector2i(int(g.x), int(g.y))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: painting = 1 if event.pressed else 0
		elif event.button_index == MOUSE_BUTTON_RIGHT: painting = -1 if event.pressed else 0
		else: return
		if painting != 0: apply(event.position)
	elif event is InputEventMouseMotion:
		var c := cell_at(event.position)
		if c != hover:
			hover = c
			queue_redraw()
		if painting != 0: apply(event.position)

## Kept as paint() for tests/tools that place bricks programmatically.
func paint(p: Vector2) -> void:
	painting = 1
	apply(p)
	painting = 0

func apply(p: Vector2) -> void:
	var c := cell_at(p)
	if c.x < 0: return
	var erase := painting < 0 or tool_type == ERASE
	if erase:
		if not cells.has(c): return
		cells.erase(c)
	else:
		var v := [tool_type, tool_motion, tool_shape, tool_rot]
		if cells.get(c) == v: return
		cells[c] = v
		Audio.sfx("ui_focus", -16.0, 0.2)
	dirty = true
	refresh_hint()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Globals.C_BG)
	var board := Rect2(grid_origin - Vector2(14, 14), Vector2(COLS, ROWS) * cs + Vector2(28, 28))
	draw_style_box(_rounded(Globals.C_FIELD, 22), board)
	for r in ROWS:
		for c in COLS:
			draw_circle(grid_origin + Vector2(c + 0.5, r + 0.5) * cs, 2.5, Color(Globals.C_WHITE, 0.12))
	for c in cells:
		_draw_brick(c, cells[c], 1.0)
	# live preview of the current tool under the cursor
	if hover.x >= 0 and painting == 0:
		if tool_type == ERASE:
			var r := Rect2(grid_origin + Vector2(hover) * cs, Vector2(cs, cs)).grow(-4)
			draw_style_box(_rounded(Color(Globals.C_RED, 0.25), 12), r)
		elif not cells.has(hover):
			_draw_brick(hover, [tool_type, tool_motion, tool_shape, tool_rot], 0.4)

func _draw_brick(c: Vector2i, v: Array, alpha: float) -> void:
	var center := grid_origin + (Vector2(c) + Vector2(0.5, 0.5)) * cs
	var col: Color = brick_colors()[v[0]]
	col.a = alpha
	var tex: Texture2D = _shape_icon(v[2])
	var k: float = (cs - 10.0) / max(tex.get_width(), tex.get_height())
	draw_set_transform(center, deg_to_rad(v[3]), Vector2.ONE * k)
	draw_texture(tex, -Vector2(tex.get_size()) / 2.0, col)
	draw_set_transform(Vector2.ZERO)
	if v[1] != "STILL":  # small motion badge
		var badge := center + Vector2(cs, -cs) * 0.3
		draw_circle(badge, 11, Color(Globals.C_DARK, alpha))
		draw_string(get_theme_default_font(), badge + Vector2(-11, 7), v[1][0],
			HORIZONTAL_ALIGNMENT_CENTER, 22, 18, Color(Globals.C_WHITE, alpha))

func _rounded(col: Color, r: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(r)
	return sb

# ---------------------------------------------------------------- actions

func _toast(text: String, col: Color) -> void:
	Fx.popup(self, Vector2(vs.x / 2.0, TOP_H + 60), text, col, 30)

func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu/main_menu.tscn")

func _clear() -> void:
	if cells.is_empty(): return
	cells.clear()
	dirty = true
	refresh_hint()

func _save_pressed() -> void:
	save_slot()
	_toast("SAVED TO SLOT %d" % (slot + 1), Globals.C_GREEN)

# ---------------------------------------------------------------- save / load / play

func read_all() -> Array:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f else null
	if data is Array and data.size() == SLOTS: return data
	return [[], [], []]

func save_slot() -> void:
	var all := read_all()
	var list := []
	for c in cells: list.append([c.x, c.y] + cells[c])
	all[slot] = list
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(all))
	dirty = false
	refresh_hint()

func load_slot(i: int) -> void:
	slot = i
	slot_buttons[i].button_pressed = true
	cells.clear()
	for e in read_all()[i]:
		cells[Vector2i(int(e[0]), int(e[1]))] = [int(e[2]), str(e[3]),
			str(e[4]) if e.size() > 4 else "", int(e[5]) if e.size() > 5 else 0]
	dirty = false
	refresh_hint()

func play_test() -> void:
	var has_normal := false
	for c in cells: has_normal = has_normal or cells[c][0] < 3
	if not has_normal:
		_toast("ADD AT LEAST ONE 1-3 HIT BRICK", Globals.C_CORAL)
		Audio.sfx("life_lost", -6.0)
		return
	save_slot()
	Globals.custom_level = to_layout()
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")

## Grid cells -> the same layout format Levels.build() returns.
func to_layout() -> Array:
	var out := []
	for c in cells:
		var spec := {"type": cells[c][0], "size": Levels.SMALL, "rot": float(cells[c][3])}
		if cells[c][2] != "": spec["shape"] = cells[c][2]
		match cells[c][1]:
			"SPIN": spec["spin"] = 1.5
			"BLINK": spec.merge({"blink": 2.6, "phase": (c.x + c.y) * 0.25})
			"WAVE": spec.merge({"move_amp": Vector2(50, 0), "move_freq": 1.2, "phase": c.y * 0.6})
		out.append({"pos": Vector2(Levels.CX + (c.x - (COLS - 1) / 2.0) * CELL, 100 + c.y * CELL), "spec": spec})
	return out
