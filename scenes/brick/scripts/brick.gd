extends StaticBody2D

class_name Brick

signal energy_brick_destroyed()
signal destroyed(which)

@export var brick_explosion: PackedScene = preload("res://scenes/brick/brick_explode_particle.tscn")
@export var bomb_explosion: PackedScene = preload("res://scenes/brick/bomb_explode_particle.tscn")

@export var long_full: CompressedTexture2D = preload("res://assets/block/BlockLongFull.png")
@export var long_border: CompressedTexture2D = preload("res://assets/block/BlockLongBorder.png")
@export var small_full: CompressedTexture2D = preload("res://assets/block/BlockSmallFull.png")
@export var small_border: CompressedTexture2D = preload("res://assets/block/BlockSmallBorder.png")

@export var one: CompressedTexture2D = preload("res://assets/block/One.png")
@export var two: CompressedTexture2D = preload("res://assets/block/Two.png")
@export var three: CompressedTexture2D = preload("res://assets/block/Three.png")
@export var bomb: CompressedTexture2D = preload("res://assets/block/Bomb.png")
@export var energy: CompressedTexture2D = preload("res://assets/block/Energy.png")

enum TYPE {
	ONE,
	TWO,
	THREE,
	EXPLOSIVE,
	ENERGY
}

enum SIZE {
	SMALL,
	LONG
}

@export var type: TYPE = TYPE.ONE
@export var size: SIZE = SIZE.SMALL

var health_dict = {
	TYPE.ONE: 1,       # 0.35
	TYPE.TWO: 2,       # 0.3
	TYPE.THREE: 3,	   # 0.20
	TYPE.EXPLOSIVE: 1, # 0.05
	TYPE.ENERGY: 1,    # 0.1
}

@onready var health: int = health_dict[type]
@onready var explosion_area: Area2D = $ExplosionArea
@onready var size_sprite: Sprite2D = $Size
@onready var type_sprite: Sprite2D = $Type
@onready var anim: AnimationPlayer = $AnimationPlayer 

var isDestroyed: bool = false
var bounce_tween: Tween

## Set by levels before add_child. Keys (all optional): type, size, spin, move_amp,
## move_freq, phase, orbit_center, orbit_radius, orbit_angle, orbit_speed, blink, face
var spec: Dictionary = {}
var t: float = 0.0
var base_pos: Vector2
var base_layer: int
var moving: bool = false

func _ready() -> void:
	if spec.is_empty():
		choose_type_random()
		choose_size_random()
	else:
		type = spec.get("type", TYPE.ONE)
		size = spec.get("size", SIZE.SMALL)
		t = spec.get("phase", 0.0)
		moving = spec.has("spin") or spec.has("move_amp") or spec.has("orbit_radius") or spec.has("blink")
	base_pos = position
	base_layer = collision_layer
	
	health = health_dict[type]
	
	update_size_visuals()
	update_type_visuals()
	
func _physics_process(delta: float) -> void:
	if not moving or isDestroyed: return
	t += delta
	var pos := base_pos
	if spec.has("orbit_radius"):
		var a: float = spec.get("orbit_angle", 0.0) + t * spec.get("orbit_speed", 0.5)
		pos = spec["orbit_center"] + Vector2.from_angle(a) * spec["orbit_radius"]
		if spec.get("face", false): rotation = a + PI / 2.0
	if spec.has("move_amp"):
		pos += spec["move_amp"] * sin(t * spec.get("move_freq", 1.0))
	position = pos
	if spec.has("spin"):
		rotation += spec["spin"] * delta
	if spec.has("blink"):
		# Visible for 65% of the period, fades out, then becomes ghost (no collision)
		var k: float = fposmod(t, spec["blink"]) / spec["blink"]
		var shown := k < 0.65
		collision_layer = base_layer if shown else 0
		modulate.a = lerp(modulate.a, 1.0 if shown else 0.12, 10.0 * delta)

func choose_type_random() -> void:
	var rand = randf()
	# 10% chance for explosives
	if rand < 0.05:
		type = TYPE.EXPLOSIVE
	elif rand >= 0.05 && rand < 0.15:
		type = TYPE.ENERGY
	elif rand >= 0.15 && rand < 0.35:
		type = TYPE.THREE
	elif rand >= 0.35 && rand < 0.65:
		type = TYPE.TWO
	else:
		type = TYPE.ONE
		
#	type = randi()%TYPE.size()
	
func choose_size_random() -> void:
	var rand = randf()
	if rand < 0.65:
		size = SIZE.LONG
	else:
		size = SIZE.SMALL

func brick_color() -> Color:
	match type:
		TYPE.ONE: return Globals.C_CORAL
		TYPE.TWO: return Globals.C_AMBER
		TYPE.THREE: return Globals.C_VIOLET
		TYPE.EXPLOSIVE: return Globals.C_RED
	return Globals.C_CYAN

func update_size_visuals() -> void:
	var small := size == SIZE.SMALL
	$CollisionShapeSmall.disabled = not small
	$CollisionShapeLong.disabled = small
	size_sprite.texture = Globals.round_rect_tex(Vector2i(56, 56) if small else Vector2i(119, 56), 12)

func update_type_visuals() -> void:
	size_sprite.self_modulate = brick_color()
	type_sprite.self_modulate = Globals.C_DARK if type == TYPE.EXPLOSIVE else Color(1, 1, 1, 0.9)
	match type:
		TYPE.ONE: type_sprite.texture = Globals.pips_tex(1)
		TYPE.TWO: type_sprite.texture = Globals.pips_tex(2)
		TYPE.THREE: type_sprite.texture = Globals.pips_tex(3)
		TYPE.EXPLOSIVE: type_sprite.texture = Globals.circle_tex(26)
		TYPE.ENERGY: type_sprite.texture = Globals.diamond_tex()
		
func bounce() -> void:
	if bounce_tween and bounce_tween.is_running():
		bounce_tween.kill()
	bounce_tween = create_tween()
	bounce_tween.tween_property(size_sprite, "scale", Vector2(1.15, 1.15), 0.15) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_ELASTIC)
	bounce_tween.parallel().tween_property(size_sprite, "rotation_degrees", randf_range(-10.0, 10.0), 0.15) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_ELASTIC )
	bounce_tween.tween_property(size_sprite, "scale", Vector2.ONE, 0.2) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_CUBIC)
	bounce_tween.parallel().tween_property(size_sprite, "rotation_degrees", 0.0, 0.2) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_CUBIC )

func damage(value: int) -> void:
	health -= value
	
	if health <= 0:
		isDestroyed = true
		match type:
			TYPE.EXPLOSIVE:
				explode()
			TYPE.ENERGY:
				give_energy()
		destroy()
	
	bounce()
	update_type_health()
	
func spawn_brick_explosion() -> void:
	var instance = brick_explosion.instantiate()
	get_tree().get_current_scene().add_child(instance)
	instance.global_position = global_position
	
func spawn_bomb_explosion() -> void:
	var instance = bomb_explosion.instantiate()
	get_tree().get_current_scene().add_child(instance)
	instance.global_position = global_position

func update_type_health() -> void:
	match health:
		3:
			type = TYPE.THREE
		2:
			type = TYPE.TWO
		1:
			type = TYPE.ONE
	update_type_visuals()
		
func give_energy() -> void:
	emit_signal("energy_brick_destroyed")

func explode() -> void:
	spawn_bomb_explosion()
	Audio.sfx("bomb", 0.0, 0.1)
	
	var bodies = explosion_area.get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("Bricks") == false: continue
		if body.isDestroyed: continue
		# Damage with a high enough value to make sure
		# they're destroyed but also trigger any eventual
		# explosive bricks
		body.damage(10)

func destroy() -> void:
	spawn_brick_explosion()
	Audio.sfx("brick_break", -8.0, 0.15)
	
	emit_signal("destroyed", self)
	queue_free()
