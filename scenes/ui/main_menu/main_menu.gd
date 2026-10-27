extends Control


func _ready():
	theme = load("res://theme/main_theme.tres")
	Fx.add_menu_backdrop(self)
	var ver := Label.new()
	ver.text = "v" + str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	ver.add_theme_font_size_override("font_size", 20)
	ver.add_theme_color_override("font_color", Color(Globals.C_WHITE, 0.3))
	add_child(ver)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -140; ver.offset_top = -50; ver.offset_right = -20; ver.offset_bottom = -20
	resized.connect(center_menu)  # window / fullscreen changes
	$MarginContainer/VBoxContainer/Play.grab_focus()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$MarginContainer/VBoxContainer.add_theme_constant_override("separation", 20)
	for b in $MarginContainer/VBoxContainer.get_children():
		b.add_theme_font_size_override("font_size", 48)
		b.custom_minimum_size.x = 460
	var title := Label.new()
	title.text = "BRICKSTELLAR"
	title.add_theme_font_override("font", load("res://assets/font/Kenney Blocks.ttf"))
	title.add_theme_font_size_override("font_size", 118)
	title.add_theme_color_override("font_color", Globals.C_AMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var best := Label.new()
	best.text = "BEST %d" % Globals.high_score
	best.add_theme_font_size_override("font_size", 40)
	best.add_theme_color_override("font_color", Globals.C_CYAN)
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$MarginContainer/VBoxContainer.add_child(best)
	$MarginContainer/VBoxContainer.move_child(best, 0)
	$MarginContainer/VBoxContainer.add_child(title)
	$MarginContainer/VBoxContainer.move_child(title, 0)
	var create := Button.new()
	create.text = "CREATE"
	create.add_theme_font_size_override("font_size", 48)
	create.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/editor/level_editor.tscn"))
	$MarginContainer/VBoxContainer.add_child(create)
	$MarginContainer/VBoxContainer.move_child(create, $MarginContainer/VBoxContainer/Play.get_index() + 1)
	build_skin_picker()
	center_menu.call_deferred()
	Audio.play_music(Audio.MENU_MUSIC)
	Ota.check_for_updates()
	Audio.wire_buttons(self)
	Fx.juice_buttons(self)

func center_menu() -> void:
	var box := $MarginContainer
	box.size = box.get_combined_minimum_size()
	box.position = (size - box.size) / 2.0

var skin_preview: Control
var skin_label: Label

func build_skin_picker() -> void:
	var vb := $MarginContainer/VBoxContainer
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	var prev := Button.new(); prev.text = "<"; prev.custom_minimum_size = Vector2(80, 80)
	var next := Button.new(); next.text = ">"; next.custom_minimum_size = Vector2(80, 80)
	skin_preview = Control.new()
	skin_preview.custom_minimum_size = Vector2(220, 90)
	prev.pressed.connect(cycle_skin.bind(-1))
	next.pressed.connect(cycle_skin.bind(1))
	row.add_child(prev); row.add_child(skin_preview); row.add_child(next)
	skin_label = Label.new()
	skin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skin_label.add_theme_font_size_override("font_size", 28)
	vb.add_child(row)
	vb.move_child(row, 2)
	vb.add_child(skin_label)
	vb.move_child(skin_label, 3)
	show_skin(Globals.skin_index)

var shown_skin := 0

func cycle_skin(dir: int) -> void:
	show_skin(posmod(shown_skin + dir, Globals.SKINS.size()))

func show_skin(i: int) -> void:
	shown_skin = i
	for c in skin_preview.get_children(): c.queue_free()
	var sk: Dictionary = Globals.SKINS[i]
	var unlocked := Globals.skin_unlocked(i)
	for poly in Globals.make_ship(sk, 100, 34):
		poly.position = Vector2(110, 45)
		if not unlocked: poly.color = Color(Globals.C_WHITE, 0.12)
		skin_preview.add_child(poly)
	Fx.punch(skin_preview, 0.2)
	if unlocked:
		Globals.skin_index = i
		Globals.save()
		skin_label.text = "%s   %d/%d" % [sk["name"], i + 1, Globals.SKINS.size()]
		skin_label.add_theme_color_override("font_color", Globals.C_WHITE)
	else:
		skin_label.text = Globals.unlock_text(i)
		skin_label.add_theme_color_override("font_color", Color(Globals.C_WHITE, 0.4))

func _on_play_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/level_select/level_select.tscn")

func _on_options_pressed():
	add_child(preload("res://scenes/ui/settings/settings_screen.gd").new())

func _on_credit_pressed():
	var vb := $MarginContainer/VBoxContainer
	var lbl: Label = vb.get_node_or_null("CreditText")
	if lbl:
		lbl.queue_free()
	else:
		lbl = Label.new()
		lbl.name = "CreditText"
		lbl.text = "Music & SFX: CC0 (Shapeforms Audio, Space Music Pack)\nFonts: Kenney (CC0)"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 22)
		vb.add_child(lbl)
		vb.move_child(lbl, $MarginContainer/VBoxContainer/Credit.get_index() + 1)
	center_menu.call_deferred()

func _on_quit_pressed():
	get_tree().quit()
