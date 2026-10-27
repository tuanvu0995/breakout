extends Control
## Full-screen leaderboard for one level: period tabs, name search,
## infinite scroll (both ways from "find me"), sticky "your position" bar.

signal closed

const Levels = preload("res://scenes/levels/levels.gd")
const PAGE := 30
const PERIODS := [["ALL TIME", "all"], ["THIS WEEK", "week"], ["TODAY", "day"]]

var level := 1
var period := "all"
var query := ""
var first_offset := 0   # offset of the first loaded row
var next_offset := 0    # offset of the next row to load below
var total := 0
var loading := false
var gen := 0            # bumps on every reset so stale responses are dropped
var me: Dictionary = {}

var list: VBoxContainer
var scroll: ScrollContainer
var info: Label
var me_label: Label
var name_edit: LineEdit
var search: LineEdit
var tabs: Array[Button] = []
var search_timer: Timer

func _ready() -> void:
	theme = load("res://theme/main_theme.tres")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Globals.C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Fx.add_menu_backdrop(self, 1)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 80; root.offset_right = -80; root.offset_top = 40; root.offset_bottom = -30
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	# header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 30)
	head.add_child(_button("<  BACK", 32, close))
	head.add_child(_label("LEADERBOARD", 52, Globals.C_AMBER))
	var sub := _label(Levels.title_of(level), 36, Globals.C_CYAN)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)
	root.add_child(head)

	# filters: period tabs + search
	var filt := HBoxContainer.new()
	filt.add_theme_constant_override("separation", 12)
	for p in PERIODS:
		var b := _button(p[0], 28, set_period.bind(p[1]))
		b.toggle_mode = true
		b.button_pressed = p[1] == period
		tabs.append(b)
		filt.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filt.add_child(spacer)
	search = LineEdit.new()
	search.placeholder_text = "search name..."
	search.custom_minimum_size = Vector2(420, 0)
	search.add_theme_font_size_override("font_size", 28)
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t): search_timer.start())
	filt.add_child(search)
	root.add_child(filt)
	search_timer = Timer.new()
	search_timer.one_shot = true
	search_timer.wait_time = 0.35  # debounce typing
	search_timer.timeout.connect(func(): query = search.text.strip_edges(); reload())
	add_child(search_timer)

	# column header
	root.add_child(_row(["RANK", "PILOT", "TIME", "SCORE"], 26, Color(Globals.C_WHITE, 0.5), Color(0, 0, 0, 0)))

	# list
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.get_v_scroll_bar().value_changed.connect(_on_scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	root.add_child(scroll)
	info = _label("", 26, Color(Globals.C_WHITE, 0.5))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(info)

	# sticky "you" bar
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Globals.C_FIELD
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(16)
	bar.add_theme_stylebox_override("panel", sb)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 20)
	me_label = _label("", 32, Globals.C_CYAN)
	me_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(me_label)
	bh.add_child(_button("FIND ME", 28, find_me))
	name_edit = LineEdit.new()
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(320, 0)
	name_edit.text = Leaderboard.handle
	name_edit.placeholder_text = "your name"
	name_edit.add_theme_font_size_override("font_size", 28)
	bh.add_child(name_edit)
	bh.add_child(_button("RENAME", 28, rename))
	bar.add_child(bh)
	root.add_child(bar)

	Audio.wire_buttons(self)
	Fx.juice_buttons(self)
	reload()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	closed.emit()
	queue_free()

# ---------------------------------------------------------------- loading

func set_period(p: String) -> void:
	period = p
	for i in tabs.size(): tabs[i].button_pressed = PERIODS[i][1] == p
	reload()

func reload(start := 0) -> void:
	gen += 1
	for c in list.get_children(): c.queue_free()
	first_offset = start
	next_offset = start
	total = 0
	loading = false
	if not Leaderboard.online():
		info.text = "Online leaderboard is off"
		me_label.text = "OFFLINE"
		return
	if start > 0: list.add_child(_button("^  LOAD EARLIER", 26, load_earlier))
	await load_more()
	scroll.scroll_vertical = 0

func load_more() -> void:
	if loading or (total > 0 and next_offset >= total): return
	loading = true
	var my_gen := gen
	info.text = "loading..."
	var d := await Leaderboard.board(level, PAGE, next_offset, period, query)
	if my_gen != gen: return
	loading = false
	if not d.get("ok", false):
		info.text = "Offline - pull again later"
		return
	total = int(d["total"])
	for e in d["entries"]: list.add_child(_entry(e))
	next_offset += d["entries"].size()
	info.text = "" if total > 0 else ("No pilot named \"%s\"" % query if query != "" else "No times yet. Be the first!")
	if next_offset >= total and total > 0: info.text = "-  %d pilots  -" % total
	update_me(d.get("me"))

func load_earlier() -> void:
	if loading or first_offset == 0: return
	loading = true
	var my_gen := gen
	var start: int = max(0, first_offset - PAGE)
	var d := await Leaderboard.board(level, first_offset - start, start, period, query)
	if my_gen != gen: return
	loading = false
	if not d.get("ok", false): return
	var top: Node = list.get_child(0)  # the "load earlier" button
	var h_before := list.size.y
	var i := 1
	for e in d["entries"]:
		var row := _entry(e)
		list.add_child(row)
		list.move_child(row, i)
		i += 1
	first_offset = start
	if first_offset == 0: top.queue_free()
	# keep the view on the same rows after inserting above
	await get_tree().process_frame
	scroll.scroll_vertical += int(list.size.y - h_before)

func _on_scroll(v: float) -> void:
	var bar := scroll.get_v_scroll_bar()
	if v >= bar.max_value - bar.page - 300: load_more()

func find_me() -> void:
	search.text = ""
	query = ""
	var rank: int = me.get("rank", 0) if me.get("rank") != null else 0
	if rank <= 0:
		Fx.popup(self, me_label.global_position + Vector2(200, -20), "No time on this board yet", Globals.C_CORAL, 26)
		return
	await reload(max(0, rank - 6))
	for c in list.get_children():
		if c.has_meta("mine"):
			await get_tree().process_frame
			scroll.ensure_control_visible(c)
			Fx.punch(c, 0.05)
			break

func update_me(m) -> void:
	if not m is Dictionary: return
	me = m
	if m.get("rank") != null:
		me_label.text = "YOU  #%d  of %d    %s" % [int(m["rank"]), total if query == "" else int(m["rank"]), Globals.format_time(m["best_time_ms"] / 1000.0)]
	else:
		me_label.text = "YOU  -  no time %s" % ("yet" if period == "all" else "in this period")

func rename() -> void:
	var err := await Leaderboard.set_handle(name_edit.text.strip_edges())
	Fx.popup(self, name_edit.global_position + Vector2(160, -24), err if err != "" else "SAVED", Globals.C_CORAL if err != "" else Globals.C_GREEN, 26)
	if err == "": reload(first_offset)
	else: name_edit.text = Leaderboard.handle

# ---------------------------------------------------------------- widgets

func _entry(e: Dictionary) -> Control:
	var rank := int(e["rank"])
	var mine: bool = e["handle"] == Leaderboard.handle
	var medal: Color = [Globals.C_AMBER, Globals.C_WHITE, Globals.C_CORAL][rank - 1] if rank <= 3 else Globals.C_WHITE
	var bg := Color(Globals.C_CYAN, 0.25) if mine else (Color(Globals.C_FIELD, 1.0) if rank % 2 else Color(Globals.C_FIELD, 0.5))
	var row := _row(["#%d" % rank, e["handle"], Globals.format_time(e["time_ms"] / 1000.0), str(int(e["score"]))], 30, medal, bg)
	if mine: row.set_meta("mine", true)
	return row

func _row(cols: Array, font_size: int, color: Color, bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 24; sb.content_margin_right = 24
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	var widths := [160, 0, 260, 240]
	for i in cols.size():
		var l := _label(cols[i], font_size, color)
		if widths[i] > 0: l.custom_minimum_size.x = widths[i]
		else: l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i >= 2: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(l)
	p.add_child(h)
	return p

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, font_size: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(cb)
	return b
