extends Control
## Player level editor: paint bricks on a grid, pick a motion, save to 3 slots, play-test.

const Levels = preload("res://scenes/levels/levels.gd")
const COLS := 17
const ROWS := 9
const CELL := 66.0
const SAVE_PATH := "user://custom_levels.json"
const SLOTS := 3
const TYPES := ["1", "2", "3", "BOMB", "ENERGY", "ERASE"]
const MOTIONS := ["STILL", "SPIN", "BLINK", "WAVE"]

var cells := {}  # Vector2i -> [type:int, motion:String]
var tool_type := 0
var tool_motion := "STILL"
var slot := 0
var grid_origin := Vector2(400, 150)
var grid_scale := 1.0
var painting := false
var status: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = load("res://theme/main_theme.tres")
	grid_origin = Vector2((1920 - COLS * CELL) / 2.0, 170)
	build_ui()
	load_slot(0)
	Audio.play_music(Audio.MENU_MUSIC)
	Audio.wire_buttons(self)

func build_ui() -> void:
	var title := Label.new()
	title.text = "LEVEL EDITOR"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Globals.C_AMBER)
	title.position = Vector2(grid_origin.x, 40)
	add_child(title)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 28)
	status.position = Vector2(grid_origin.x + 700, 60)
	add_child(status)

	var bottom_y := grid_origin.y + ROWS * CELL + 40
	_row(TYPES, Vector2(grid_origin.x, bottom_y), func(i): tool_type = i; refresh_status())
	_row(MOTIONS, Vector2(grid_origin.x, bottom_y + 90), func(i): tool_motion = MOTIONS[i]; refresh_status())
	_row(["SLOT 1", "SLOT 2", "SLOT 3", "SAVE", "CLEAR", "PLAY", "MENU"], Vector2(grid_origin.x, bottom_y + 180), on_action)

func _row(labels: Array, pos: Vector2, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.position = pos
	row.add_theme_constant_override("separation", 12)
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.add_theme_font_size_override("font_size", 34)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(cb.bind(i))
		row.add_child(b)
	add_child(row)

func on_action(i: int) -> void:
	match i:
		0, 1, 2: load_slot(i)
		3: save_slot(); status.text = "SAVED TO SLOT %d" % (slot + 1)
		4: cells.clear(); queue_redraw()
		5: play_test()
		6: get_tree().change_scene_to_file("res://scenes/ui/main_menu/main_menu.tscn")

func refresh_status() -> void:
	status.text = "SLOT %d   TOOL: %s   MOTION: %s" % [slot + 1, TYPES[tool_type], tool_motion]

# --- painting ------------------------------------------------------------

func cell_at(p: Vector2) -> Vector2i:
	var g := (p - grid_origin) / CELL
	if g.x < 0 or g.y < 0 or g.x >= COLS or g.y >= ROWS: return Vector2i(-1, -1)
	return Vector2i(int(g.x), int(g.y))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		painting = event.pressed
		if painting: paint(event.position)
	elif event is InputEventMouseMotion and painting:
		paint(event.position)

func paint(p: Vector2) -> void:
	var c := cell_at(p)
	if c.x < 0: return
	if TYPES[tool_type] == "ERASE": cells.erase(c)
	else: cells[c] = [tool_type, tool_motion]
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Globals.C_BG)
	draw_rect(Rect2(grid_origin - Vector2(8, 8), Vector2(COLS, ROWS) * CELL + Vector2(16, 16)), Globals.C_FIELD)
	for r in ROWS:
		for c in COLS:
			var center := grid_origin + Vector2(c + 0.5, r + 0.5) * CELL
			draw_circle(center, 3, Color(Globals.C_WHITE, 0.15))
	var brick_colors := [Globals.C_CORAL, Globals.C_AMBER, Globals.C_VIOLET, Globals.C_RED, Globals.C_CYAN]
	var tex := Globals.round_rect_tex(Vector2i(56, 56), 12)
	var font := get_theme_default_font()
	for c in cells:
		var rect := Rect2(grid_origin + Vector2(c) * CELL + Vector2(5, 5), Vector2(56, 56))
		draw_texture_rect(tex, rect, false, brick_colors[cells[c][0]])
		var m: String = cells[c][1]
		if m != "STILL":
			draw_string(font, rect.position + Vector2(0, 40), m[0], HORIZONTAL_ALIGNMENT_CENTER, 56, 28, Globals.C_DARK)

# --- save / load / play ---------------------------------------------------

func read_all() -> Array:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f else null
	if data is Array and data.size() == SLOTS: return data
	return [[], [], []]

func save_slot() -> void:
	var all := read_all()
	var list := []
	for c in cells: list.append([c.x, c.y, cells[c][0], cells[c][1]])
	all[slot] = list
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(all))

func load_slot(i: int) -> void:
	slot = i
	cells.clear()
	for e in read_all()[i]:
		cells[Vector2i(int(e[0]), int(e[1]))] = [int(e[2]), str(e[3])]
	refresh_status()
	queue_redraw()

func play_test() -> void:
	var has_normal := false
	for c in cells: has_normal = has_normal or cells[c][0] < 3
	if not has_normal:
		status.text = "ADD AT LEAST ONE 1/2/3 BRICK"
		Audio.sfx("life_lost", -6.0)
		return
	save_slot()
	Globals.custom_level = to_layout()
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")

## Grid cells -> the same layout format Levels.build() returns.
func to_layout() -> Array:
	var out := []
	for c in cells:
		var spec := {"type": cells[c][0], "size": Levels.SMALL}
		match cells[c][1]:
			"SPIN": spec["spin"] = 1.5
			"BLINK": spec.merge({"blink": 2.6, "phase": (c.x + c.y) * 0.25})
			"WAVE": spec.merge({"move_amp": Vector2(50, 0), "move_freq": 1.2, "phase": c.y * 0.6})
		out.append({"pos": Vector2(Levels.CX + (c.x - (COLS - 1) / 2.0) * CELL, 100 + c.y * CELL), "spec": spec})
	return out
