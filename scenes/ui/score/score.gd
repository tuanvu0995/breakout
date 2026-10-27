extends Control

@onready var score = $Score

func _ready():
	$TextureRect.visible = false
	score.add_theme_color_override("font_color", Globals.C_WHITE)

var shown := 0

## Count up toward the new score with a punch.
func set_score(new_score: int) -> void:
	if new_score > shown:
		Fx.punch(score, 0.3)
	var tw := create_tween()
	tw.tween_method(func(v): shown = int(v); score.text = str(shown), float(shown), float(new_score), 0.35)
