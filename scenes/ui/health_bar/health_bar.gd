extends Control

var health: int = 3
@onready var h_box: HBoxContainer = $HBoxContainer

func _ready() -> void:
	position = Vector2(40, 30)
	h_box.scale = Vector2.ONE
	h_box.add_theme_constant_override("separation", 14)
	for c in h_box.get_children():
		c.texture = Globals.circle_tex(40)
		c.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	set_health(health)

func set_health(new_health) -> void:
	if new_health != health and h_box.get_child_count() > 0:
		Fx.punch(h_box.get_child(clamp(min(new_health, health), 0, h_box.get_child_count() - 1)), 0.6, 0.4)
	health = new_health
	for i in range(h_box.get_child_count()):
		h_box.get_child(i).self_modulate = Globals.C_CORAL if i < health else Color(Globals.C_WHITE, 0.15)
