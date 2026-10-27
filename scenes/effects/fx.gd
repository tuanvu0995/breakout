class_name Fx
extends RefCounted
## One-shot juice effects built from code. Every effect frees itself.

## Square shards flying out, flat colored.
static func burst(parent: Node, pos: Vector2, color: Color, amount := 16, speed := 420.0, size := 10.0) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 900)
	p.damping_min = 80.0
	p.damping_max = 160.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.color = color
	p.texture = Globals.round_rect_tex(Vector2i(4, 4), 0)
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

## Expanding ring that fades.
static func ring(parent: Node, pos: Vector2, color: Color, radius := 90.0, time := 0.35) -> void:
	var s := Sprite2D.new()
	s.texture = Globals.sdf_texture("ring", Vector2i(128, 128), func(q): return abs(q.length() - 58.0) - 4.0)
	s.modulate = color
	s.scale = Vector2.ONE * 0.1
	parent.add_child(s)
	s.global_position = pos
	var tw := s.create_tween().set_parallel()
	tw.tween_property(s, "scale", Vector2.ONE * radius / 64.0, time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, time)
	tw.chain().tween_callback(s.queue_free)

## Solid disc that pops then vanishes (muzzle flash, impact flash).
static func flash(parent: Node, pos: Vector2, color: Color, radius := 18.0, time := 0.12) -> void:
	var s := Sprite2D.new()
	s.texture = Globals.circle_tex(64)
	s.modulate = color
	s.scale = Vector2.ONE * radius / 32.0
	parent.add_child(s)
	s.global_position = pos
	var tw := s.create_tween().set_parallel()
	tw.tween_property(s, "scale", Vector2.ZERO, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.queue_free)

## Floating text (score popups).
static func popup(parent: Node, pos: Vector2, text: String, color: Color, font_size := 34) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Globals.C_DARK)
	l.add_theme_constant_override("outline_size", 8)
	l.z_index = 50
	parent.add_child(l)
	l.reset_size()
	l.pivot_offset = l.size / 2.0
	l.global_position = pos - l.size / 2.0
	l.scale = Vector2.ZERO
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE * 1.25, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.08)
	tw.parallel().tween_property(l, "position:y", l.position.y - 70, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)

## Squash-and-stretch punch on any CanvasItem with a scale.
static func punch(node: Node, amount := 0.25, time := 0.25) -> void:
	if node is Control: node.pivot_offset = node.size / 2.0
	var base: Vector2 = node.get_meta("base_scale", node.scale)
	node.set_meta("base_scale", base)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", base * (1.0 + amount), time * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", base, time * 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Hover / focus grow for every button under root.
static func juice_buttons(root: Node) -> void:
	for b in root.find_children("*", "BaseButton", true, false):
		if b.has_meta("juiced"): continue  # already juiced by an earlier call
		b.set_meta("juiced", true)
		var grow := func(on: bool):
			b.pivot_offset = b.size / 2.0
			b.create_tween().tween_property(b, "scale", Vector2.ONE * (1.06 if on else 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		b.mouse_entered.connect(grow.bind(true))
		b.mouse_exited.connect(grow.bind(false))
		b.focus_entered.connect(grow.bind(true))
		b.focus_exited.connect(grow.bind(false))
		b.button_down.connect(func(): b.scale = Vector2.ONE * 0.94)
		b.button_up.connect(grow.bind(true))

## Shared animated backdrop for menu screens (stars + slow orbits).
static func add_menu_backdrop(parent: Node, index := 0) -> void:
	var bd = preload("res://scenes/effects/backdrop.gd").new()
	bd.full_screen = true
	bd.set_theme(1, Globals.C_BG, Globals.C_WALL)
	parent.add_child(bd)
	parent.move_child(bd, index)
