extends Control

@export var health_empty: CompressedTexture2D = preload("res://assets/ui/HeartEmpty.png")
@export var health_full: CompressedTexture2D = preload("res://assets/ui/HeartFull.png")

var health: int = 3
@onready var h_box: HBoxContainer = $HBoxContainer

func _ready() -> void:
	pass
	
func set_health(new_health) -> void:
	health = new_health
	for i in range(h_box.get_child_count()):
		if i < health:
			h_box.get_child(i).texture = health_full
		else:
			h_box.get_child(i).texture = health_empty
