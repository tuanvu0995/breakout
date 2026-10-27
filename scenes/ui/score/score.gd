extends Control

@onready var score = $Score

func _ready():
	$TextureRect.visible = false
	score.add_theme_color_override("font_color", Globals.C_WHITE)

func set_score(new_score: int) -> void:
	score.text = str(new_score)
