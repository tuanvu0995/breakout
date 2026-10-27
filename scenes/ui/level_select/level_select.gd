extends Control
## Quest map: 12 worlds on the left, the selected world's 10 stages on the right.
## Cleared / next / locked tiles are styled very differently.

const Levels = preload("res://scenes/levels/levels.gd")
const TILE := Vector2(170, 110)

func _ready() -> void:
	theme = load("res://theme/main_theme.tres")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Globals.C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Fx.add_menu_backdrop(self, 1)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 40)
	var back := Button.new()
	back.text = "<  BACK"
	back.add_theme_font_size_override("font_size", 32)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/main_menu/main_menu.tscn"))
	head.add_child(back)
	var title := Label.new()
	title.text = "QUESTS   %d / %d" % [min(Globals.max_level - 1, Levels.COUNT), Levels.COUNT]
	var total := HBoxContainer.new()
	total.add_theme_constant_override("separation", 8)
	var ic := TextureRect.new()
	ic.texture = BrickShapes.texture("star")
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(40, 40)
	ic.modulate = Globals.C_AMBER
	total.add_child(ic)
	var tl := Label.new()
	tl.text = "%d / %d" % [Globals.total_stars(), Levels.COUNT * 3]
	tl.add_theme_font_size_override("font_size", 36)
	tl.add_theme_color_override("font_color", Globals.C_AMBER)
	total.add_child(tl)
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Globals.C_AMBER)
	head.add_child(title)
	head.add_child(total)
	root.add_child(head)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 40)
	root.add_child(body)
	world_list = VBoxContainer.new()
	world_list.add_theme_constant_override("separation", 6)
	body.add_child(world_list)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 18)
	body.add_child(right)
	world_title = Label.new()
	world_title.add_theme_font_size_override("font_size", 44)
	right.add_child(world_title)
	world_info = Label.new()
	world_info.add_theme_font_size_override("font_size", 24)
	world_info.add_theme_color_override("font_color", Color(Globals.C_WHITE, 0.6))
	right.add_child(world_info)
	tile_grid = GridContainer.new()
	tile_grid.columns = 5
	tile_grid.add_theme_constant_override("h_separation", 14)
	tile_grid.add_theme_constant_override("v_separation", 14)
	right.add_child(tile_grid)

	var group := ButtonGroup.new()
	for w in Levels.WORLDS:
		world_list.add_child(make_world_button(w, group))
	var current_world: int = min(Globals.max_level, Levels.COUNT) - 1
	show_world(current_world / Levels.STAGES)

	await get_tree().process_frame
	root.position = (size - root.size) / 2.0
	Audio.play_music(Audio.MENU_MUSIC)
	Audio.wire_buttons(self)
	Fx.juice_buttons(self)

var world_list: VBoxContainer
var world_title: Label
var world_info: Label
var tile_grid: GridContainer
var world_buttons: Array[Button] = []

func world_open(w: int) -> bool:
	return Globals.max_level > w * Levels.STAGES

func world_stars(w: int) -> int:
	var n := 0
	for i in Levels.STAGES: n += Globals.get_stars(w * Levels.STAGES + i + 1)
	return n

func make_world_button(w: int, group: ButtonGroup) -> Button:
	var first := w * Levels.STAGES + 1
	var th: Dictionary = Levels.theme_of(first)
	var open := world_open(w)
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(380, 62)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 24)
	b.text = "%2d  %s" % [w + 1, Levels.world_name(w)]
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		var base: Color = th["wall"] if open else Color(Globals.C_FIELD, 0.5)
		sb.bg_color = {"pressed": base.lightened(0.25), "hover_pressed": base.lightened(0.3),
			"hover": base.lightened(0.1)}.get(state, base)
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 18
		b.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, Globals.C_WHITE if open else Color(Globals.C_WHITE, 0.3))
	if open:
		# star count on the right edge of the button
		var st := Label.new()
		st.text = "%d/%d" % [world_stars(w), Levels.STAGES * 3]
		st.add_theme_font_size_override("font_size", 20)
		st.add_theme_color_override("font_color", Globals.C_AMBER)
		st.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		st.position.x -= 70
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(st)
	else:
		var lock := TextureRect.new()
		lock.texture = lock_tex()
		lock.modulate = Color(Globals.C_WHITE, 0.3)
		lock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		lock.position += Vector2(-56, -22)
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(lock)
	b.disabled = not open
	b.pressed.connect(show_world.bind(w))
	world_buttons.append(b)
	return b

func show_world(w: int) -> void:
	world_buttons[w].button_pressed = true
	var first := w * Levels.STAGES + 1
	var th: Dictionary = Levels.theme_of(first)
	world_title.text = "WORLD %d  -  %s" % [w + 1, Levels.world_name(w)]
	world_title.add_theme_color_override("font_color", th["wall"].lightened(0.55))
	var cleared := 0
	for i in Levels.STAGES:
		if first + i < Globals.max_level: cleared += 1
	world_info.text = "%d / %d CLEARED      %d / %d STARS      STAGE 10: BOSS" % [cleared, Levels.STAGES, world_stars(w), Levels.STAGES * 3]
	for c in tile_grid.get_children(): c.queue_free()
	for i in Levels.STAGES:
		tile_grid.add_child(make_tile(first + i, th))
	Audio.wire_buttons(tile_grid)
	Fx.juice_buttons(tile_grid)

func make_tile(level: int, th: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = TILE
	b.add_theme_font_size_override("font_size", 40)
	var cleared := level < Globals.max_level
	var current: bool = level == min(Globals.max_level, Levels.COUNT) and not cleared
	var locked := level > Globals.max_level
	var bg: Color
	var fg: Color
	if cleared:
		bg = th["wall"]; fg = Globals.C_WHITE
	elif current:
		bg = Globals.C_AMBER; fg = Globals.C_DARK
	else:
		bg = Color(Globals.C_FIELD, 0.5); fg = Color(Globals.C_WHITE, 0.15)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg.lightened(0.15) if state in ["hover", "focus"] and not locked else bg
		sb.set_corner_radius_all(16)
		b.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, fg)
	var is_boss := not Levels.boss_of(level).is_empty()
	var sub := ""
	if current: sub = "BOSS" if is_boss else "PLAY"
	elif not cleared and is_boss: sub = "BOSS"
	if Levels.is_final(level) and not cleared: sub = "FINAL"
	b.text = str(level) + ("\n" + sub if sub != "" else "")
	b.add_theme_font_size_override("font_size", 30 if sub != "" else 36)
	if cleared:
		# number on top, earned stars underneath
		b.text = str(level) + "\n "
		b.add_child(star_row(Globals.get_stars(level), 22, Vector2(0, TILE.y - 40)))
	if locked:
		b.disabled = true
		b.text = ""
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lock := TextureRect.new()
		lock.texture = lock_tex()
		lock.modulate = Color(Globals.C_WHITE, 0.25)
		center.add_child(lock)
		b.add_child(center)
	else:
		b.pressed.connect(select.bind(level))
	if current:
		b.ready.connect(func():
			b.pivot_offset = TILE / 2.0
			var tw := b.create_tween().set_loops()
			tw.tween_property(b, "scale", Vector2.ONE * 1.08, 0.5).set_trans(Tween.TRANS_SINE)
			tw.tween_property(b, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
			b.grab_focus())
	return b

# ---------------------------------------------------------------- quest dialog

const THEME_TIPS := [
	"Still bricks shaped into pictures. Learn the brick types.",
	"Rings of bricks orbit a center. Time your shots.",
	"Long bricks sway like waves. Aim ahead of them.",
	"Bricks fade out - when faded, your ball passes through.",
	"Spinning bricks on spiral arms that turn.",
	"Everything at once. Good luck, pilot.",
]
const LeaderboardScreen = preload("res://scenes/ui/leaderboard/leaderboard_screen.gd")

var dialog: Control
var selected := 0

func select(level: int) -> void:
	selected = level
	if dialog: dialog.queue_free()
	var t: int = Levels.theme_index(level)
	var th: Dictionary = Levels.theme_of(level)

	# dim overlay, click outside closes
	dialog = ColorRect.new()
	dialog.color = Color(0, 0, 0, 0.6)
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close_dialog())
	add_child(dialog)

	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = th["field"].lightened(0.08)
	sb.set_corner_radius_all(28)
	sb.set_content_margin_all(40)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(720, 0)
	dialog.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)

	_label(v, ("FINAL QUEST" if Levels.is_final(level) else th["name"] + "  -  QUEST %d" % level), 52, Globals.C_AMBER)
	_label(v, "World %d  -  Stage %d of %d" % [Levels.world_of(level) + 1, Levels.stage_of(level) + 1, Levels.STAGES], 28, th["wall"].lightened(0.5))
	# star goals
	var par := Levels.par_time(level)
	var have := Globals.get_stars(level)
	var goals := VBoxContainer.new()
	goals.add_theme_constant_override("separation", 6)
	for i in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var ic := TextureRect.new()
		ic.texture = BrickShapes.texture("star")
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(30, 30)
		ic.modulate = Globals.C_AMBER if i < have else Color(Globals.C_WHITE, 0.2)
		row.add_child(ic)
		var goal: String = ["CLEAR THE QUEST", "FINISH UNDER %s" % Globals.format_time(par).trim_suffix(".00"), "LOSE NO LIFE"][i]
		_label(row, goal, 24, Globals.C_WHITE if i < have else Color(Globals.C_WHITE, 0.6))
		goals.add_child(row)
	v.add_child(goals)
	var boss: Dictionary = Levels.boss_of(level)
	if not boss.is_empty():
		_label(v, "BOSS:  " + boss["name"], 28, boss["color"])
	# one compact line: your best time, then your online rank once it loads
	var best := Globals.best_time(level)
	var best_text := ("BEST  " + Globals.format_time(best)) if best > 0.0 else ""
	var online_rank := _label(v, best_text, 24, Globals.C_CYAN)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var play := _dialog_button(row, "PLAY", Globals.C_AMBER, Globals.C_DARK, func(): start(selected))
	_dialog_button(row, "LEADERBOARD", Globals.C_VIOLET, Globals.C_WHITE, open_leaderboard)
	_dialog_button(row, "CLOSE", Globals.C_FIELD, Globals.C_WHITE, close_dialog)
	v.add_child(row)

	Audio.wire_buttons(dialog)
	Fx.juice_buttons(dialog)
	Audio.sfx("pause", -6.0)
	await get_tree().process_frame
	card.position = (size - card.size) / 2.0
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2.ONE * 0.85
	card.create_tween().tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	play.grab_focus()

	# your online position, if any
	if Leaderboard.online():
		var d := await Leaderboard.board(level, 1)
		if selected == level and is_instance_valid(online_rank) and d.get("ok", false):
			var me = d.get("me")
			var rank_text := ""
			if me is Dictionary and me.get("rank") != null:
				rank_text = "ONLINE  #%d / %d" % [int(me["rank"]), int(d["total"])]
			online_rank.text = "      ".join([best_text, rank_text].filter(func(x): return x != ""))

## Row of 3 star icons, `n` lit. Positioned in parent space, centered horizontally on the tile.
func star_row(n: int, icon: int, pos: Vector2) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		var t := TextureRect.new()
		t.texture = BrickShapes.texture("star")
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(icon, icon)
		t.modulate = Globals.C_AMBER if i < n else Color(Globals.C_DARK, 0.6)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(t)
	h.position = pos + Vector2((TILE.x - icon * 3 - 8) / 2.0, 0)
	return h

func _dialog_button(parent: Node, text: String, bg: Color, fg: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 34)
	for state in ["normal", "hover", "pressed", "focus"]:
		var st := StyleBoxFlat.new()
		st.bg_color = bg.lightened(0.12 if state != "normal" else 0.0)
		st.set_corner_radius_all(16)
		st.set_content_margin_all(16)
		b.add_theme_stylebox_override(state, st)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fg)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func close_dialog() -> void:
	if dialog:
		dialog.queue_free()
		dialog = null

func open_leaderboard() -> void:
	var lb := LeaderboardScreen.new()
	lb.level = selected
	add_child(lb)

func _unhandled_input(event: InputEvent) -> void:
	if dialog and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_dialog()

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func lock_tex() -> ImageTexture:
	return Globals.sdf_texture("lock", Vector2i(40, 44), func(p):
		var body := Globals.sd_round_rect(p - Vector2(0, 8), Vector2(15, 11), 4)
		var q: Vector2 = p - Vector2(0, -4)
		var shackle: float = abs(q.length() - 10.0) - 3.0
		if q.y > 0: shackle = 1e9
		return min(body, shackle))

func start(level: int) -> void:
	Globals.start_level = level
	Globals.custom_level = []
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")
