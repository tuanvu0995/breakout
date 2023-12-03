extends Area2D

func _ready():
	$Polygon.scale = $CollisionShape.shape.size
