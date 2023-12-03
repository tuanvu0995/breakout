extends GameManager

class_name GameMaker

func _ready():
	randomize()
	
	Globals.camera = $Camera
	Globals.camera.objects = [ball, paddle]
	
	ball.attached_to = paddle.launch_point
	paddle.ball_attached = ball
	paddle.ball = ball

