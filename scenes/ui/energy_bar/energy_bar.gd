extends Control

@onready var progress: ProgressBar = $ProgressBar

func _ready() -> void:
	progress.value = 0.0
	$TextureRect.visible = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(Globals.C_WHITE, 0.1)
	bg.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Globals.C_CYAN
	fill.set_corner_radius_all(8)
	progress.add_theme_stylebox_override("background", bg)
	progress.add_theme_stylebox_override("fill", fill)

func set_energy(new_value: int) -> void:
	progress.value = new_value
