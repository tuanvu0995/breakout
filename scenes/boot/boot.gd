extends Node
## Main scene, kept tiny on purpose. Godot loads the main scene before autoloads
## enter the tree, and Ota mounts the OTA patch in its _enter_tree. So the real
## menu (and everything it preloads) is loaded here, after the patch is mounted.
## Never change this file in a patch: it always runs from the installed build.

func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/main_menu/main_menu.tscn")
