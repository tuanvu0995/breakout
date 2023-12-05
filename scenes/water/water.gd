extends Node2D

@onready var water_spring_scene = preload("res://scenes/water/water_spring.tscn")
@onready var water_splash_particle_scene = preload("res://scenes/water/water_splash_particle.tscn")

@export var k: float = 0.015
@export var d: float = 0.03
@export var spread: float = 0.02
@export var passes: int = 8
@export var distance_between_springs: int = 32
@export var spring_number: int = 6
@export var depth: int = 1000
@export var border_thinkness: float = 1.1

var water_length: int = distance_between_springs * spring_number

var springs = []
var target_height = global_position.y
var bottom = target_height + depth

@onready var water_border: SmoothPath = $WaterBorder
@onready var water_polygon: Polygon2D = $WaterPolygon
@onready var water_area: Area2D = $WaterArea
@onready var water_collision: CollisionShape2D = $WaterArea/CollisionShape2D

func _ready() -> void:
	water_border.width = border_thinkness
	spread = spread / 1000
	
	for i in range(spring_number):
		var x_position = distance_between_springs * i
		var w: WaterSpring = water_spring_scene.instantiate()
		add_child(w)
		springs.append(w)
		w.initialize(i, x_position)
		w.set_collision_width(distance_between_springs)
		w.connect("splash", splash, 1)
		
	var total_lenght = distance_between_springs * (spring_number - 1)
	var rectangle = RectangleShape2D.new().duplicate()
	var rect_position = Vector2(total_lenght / 2, depth / 2)
	var rect_extents = Vector2(total_lenght / 2, depth / 2)
	
	water_area.position = rect_position
	rectangle.size = rect_extents
	water_collision.set_shape(rectangle)

func _physics_process(delta) -> void:
	for i in springs:
		i.water_update(k, d)
	
	var left_deltas = []
	var right_deltas = []
	
	for i in range (springs.size()):
		left_deltas.append(0)
		right_deltas.append(0)
		pass

	for j in range(passes):
		for i in range (springs.size()):
			if i > 0:
				left_deltas[i] = spread * (springs[i].height - springs[i-1].height)
				springs[i-1].velocity += left_deltas[i]
			if i < springs.size() - 1:
				right_deltas[i] = spread * (springs[i].height - springs[i+1].height)
				springs[i+1].velocity += right_deltas[i]
	
	new_border()
	draw_water_body()

func splash(index: int, speed: float) -> void:
	if index >= 0 and index < springs.size():
		springs[index].velocity += speed
		pass

func draw_water_body() -> void:
	var points = Array(water_border.curve.get_baked_points())
	var water_polygon_points = points
	
	var first_index = 0
	var last_index = water_polygon_points.size() - 1
	
	water_polygon_points.append(Vector2(water_polygon_points[last_index].x, bottom))
	water_polygon_points.append(Vector2(water_polygon_points[first_index].x, bottom))
	water_polygon_points = PackedVector2Array(water_polygon_points)
	water_polygon.set_polygon(water_polygon_points)
	water_polygon.set_uv(water_polygon_points)
	
func new_border() -> void:
	var curve = Curve2D.new().duplicate()
	
	var surface_points = []
	for i in range(springs.size()):
		surface_points.append(springs[i].position)
	
	for i in range(surface_points.size()):
		curve.add_point(surface_points[i])
		
	water_border.curve = curve
	water_border.smooth(true)
	water_border.queue_redraw()

func _on_water_area_body_entered(body):
	#body.in_water()
	var s = water_splash_particle_scene.instantiate()
	get_tree().current_scene.add_child(s)
	s.global_position = body.global_position
