extends Node2D
class_name WaterSpring

signal splash

var velocity: float = 0
var force: float = 0
var height: float = 0
var target_height: float = 0

var index: int = 0
var motion_factor: float = 0.02

var collided_with = null

@onready var collision: CollisionShape2D = $Area2D/CollisionShape2D

func initialize(id: int, x_position: float) -> void:
	index = id
	height = position.y
	target_height = position.y
	velocity = 0
	position.x = x_position
	
func set_collision_width(value: float) -> void:
	var extents = collision.shape.get_size()
	var new_extents = Vector2(value / 2, extents.y)
	collision.shape.size = new_extents

func water_update(spring_constant: float, dampening: float) -> void:
	height = position.y
	var x = height - target_height
	var loss = -dampening * velocity
	force = -spring_constant * x + loss
	velocity += force
	position.y += velocity

func _on_area_2d_body_entered(body):
	if not body.is_in_group("Ball"): return
	if body == collided_with: return
	collided_with = body
	var velocity = body.velocity.y if body.velocity.y >= body.velocity.x else body.velocity.x
	var speed = (body.velocity.y / 3) * motion_factor
	emit_signal("splash", index, speed)
