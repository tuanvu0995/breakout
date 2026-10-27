extends Control

signal retry()

var score: int = 0
var level: int = 1
var new_record: bool = false

func _ready() -> void:
	Audio.wire_buttons(self)
	$VBoxContainer/Quit.text = "MENU"
	$Label.add_theme_font_size_override("font_size", 40)
	$Label.text = "%s\nScore %d  -  Level %d\nBest %d" % [
		"NEW RECORD!" if new_record else "Game Over", score, level, Globals.high_score]
	$VBoxContainer/Retry.grab_focus()

func _on_RetryBtn_pressed() -> void:
	emit_signal("retry")
	queue_free()

func _on_QuitBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu/main_menu.tscn")
