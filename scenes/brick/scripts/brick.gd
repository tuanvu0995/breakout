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

@onready var health: float = health_dict[type]
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
var shape := ""  # "" = square/long; otherwise a BrickShapes name
var is_boss := false
var custom_collider: Node2D
var home_pos: Vector2

## Final boss phase change: new outline, motion and color, keeping position and HP.
func morph(new_shape: String, motion: Dictionary, color: Color) -> void:
	for k in ["move_amp", "move_freq", "orbit_center", "orbit_radius", "orbit_angle", "orbit_speed", "spin", "blink", "phase"]:
		spec.erase(k)
	spec.merge(motion, true)
	spec["color"] = color
	shape = new_shape
	rotation = 0.0
	modulate.a = 1.0
	collision_layer = base_layer
	base_pos = home_pos  # each phase moves around the boss's original spot
	position = home_pos
	t = 0.0
	moving = true
	update_size_visuals()
	update_type_visuals()
	hit_flash()
var max_health := 1.0

func _ready() -> void:
	if spec.is_empty():
		choose_type_random()
		choose_size_random()
	else:
		type = spec.get("type", TYPE.ONE)
		size = spec.get("size", SIZE.SMALL)
		t = spec.get("phase", 0.0)
		shape = spec.get("shape", "")
		rotation_degrees = spec.get("rot", 0.0)
		moving = spec.has("spin") or spec.has("move_amp") or spec.has("orbit_radius") or spec.has("blink")
	base_pos = position
	home_pos = position
	base_layer = collision_layer
	
	health = spec.get("hp", health_dict[type])
	max_health = health
	is_boss = spec.get("boss", false)
	if is_boss: scale = Vector2.ONE * spec.get("scale", 3.0)
	
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
	if shape != "":
		$CollisionShapeSmall.disabled = true
		$CollisionShapeLong.disabled = true
		if custom_collider: custom_collider.queue_free()
		custom_collider = BrickShapes.collider(shape)
		add_child(custom_collider)
		size_sprite.texture = BrickShapes.texture(shape)
		# pips sit on the visual center, kept upright and scaled to the shape
		type_sprite.position = BrickShapes.centroid(shape)
		type_sprite.scale = Vector2.ONE * (0.75 if shape in ["tri", "wedge", "diamond", "star", "half"] else 0.9)
		return
	var small := size == SIZE.SMALL
	$CollisionShapeSmall.disabled = not small
	$CollisionShapeLong.disabled = small
	size_sprite.texture = Globals.round_rect_tex(Vector2i(56, 56) if small else Vector2i(119, 56), 12)

func update_type_visuals() -> void:
	size_sprite.self_modulate = brick_color()
	if is_boss:
		# a single dark "eye" instead of health dots; the HUD shows the boss bar
		size_sprite.self_modulate = spec.get("color", Globals.C_RED)
		type_sprite.texture = Globals.circle_tex(26)
		type_sprite.self_modulate = Globals.C_DARK
		type_sprite.scale = Vector2.ONE * 0.8
		return
	type_sprite.self_modulate = Globals.C_DARK if type == TYPE.EXPLOSIVE else Color(1, 1, 1, 0.9)
	match type:
		TYPE.ONE, TYPE.TWO, TYPE.THREE:
			# dots = ball hits left; the last dot shrinks with partial (bullet) damage
			var hp := health if is_inside_tree() else float(health_dict[type])
			var n := int(ceil(hp))
			type_sprite.texture = Globals.pips_tex(n, hp - (n - 1))
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

func damage(value: float) -> void:
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
	hit_flash()
	
func hit_flash() -> void:
	size_sprite.modulate = Color(2.5, 2.5, 2.5)
	create_tween().tween_property(size_sprite, "modulate", Color.WHITE, 0.15)

func spawn_brick_explosion() -> void:
	var scene := get_tree().get_current_scene()
	var c := brick_color()
	Fx.burst(scene, global_position, c, 18 if size == SIZE.SMALL else 28)
	Fx.burst(scene, global_position, Globals.C_WHITE, 6, 520.0, 6.0)
	Fx.ring(scene, global_position, c, 80)
	Fx.flash(scene, global_position, Globals.C_WHITE, 40, 0.1)
	
func spawn_bomb_explosion() -> void:
	var scene := get_tree().get_current_scene()
	Fx.flash(scene, global_position, Globals.C_WHITE, 120, 0.18)
	Fx.ring(scene, global_position, Globals.C_RED, 220, 0.45)
	Fx.ring(scene, global_position, Globals.C_AMBER, 140, 0.3)
	Fx.burst(scene, global_position, Globals.C_RED, 40, 700.0, 14.0)
	Fx.burst(scene, global_position, Globals.C_AMBER, 24, 500.0, 10.0)

func update_type_health() -> void:
	if is_boss:
		update_type_visuals()
		return
	match int(ceil(health)):
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
	Audio.sfx("bomb", 0.0, 0.08)
	
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
	
	emit_signal("destroyed", self)
	queue_free()
