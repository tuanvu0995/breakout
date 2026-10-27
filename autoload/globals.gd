extends Node

enum BUMP {
	TOO_FAR,
	EARLY,
	LATE,
	PERFECT
}

var stats = {
	"score": 0,
	"bumps_late": 0,
	"bumps_perfect": 0,
	"bumps_early": 0,
	"time": 0.0,
	"ball_bounces": 0
}

var camera: Camera2D

## Flat palette - one place to restyle the whole game.
const C_BG := Color("1b1f3b")
const C_FIELD := Color("232850")
const C_WALL := Color("323a72")
const C_WHITE := Color("f4f4ff")
const C_CORAL := Color("ff6b6b")
const C_AMBER := Color("ffb84d")
const C_VIOLET := Color("9b7bff")
const C_CYAN := Color("3ddcf5")
const C_RED := Color("ff3d5e")
const C_GREEN := Color("5ce08a")
const C_DARK := Color("12142a")

var _tex_cache := {}

## Rasterize a shape from a signed distance function (negative = inside), antialiased, cached.
func sdf_texture(key: String, size: Vector2i, sdf: Callable) -> ImageTexture:
	if _tex_cache.has(key): return _tex_cache[key]
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var c := Vector2(size) / 2.0
	for y in size.y:
		for x in size.x:
			var d: float = sdf.call(Vector2(x + 0.5, y + 0.5) - c)
			img.set_pixel(x, y, Color(1, 1, 1, clamp(0.5 - d, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

static func sd_round_rect(p: Vector2, half: Vector2, r: float) -> float:
	var q := p.abs() - half + Vector2(r, r)
	return Vector2(max(q.x, 0.0), max(q.y, 0.0)).length() + min(max(q.x, q.y), 0.0) - r

func round_rect_tex(size: Vector2i, radius: float) -> ImageTexture:
	return sdf_texture("rr%s_%s" % [size, radius], size,
		func(p): return sd_round_rect(p, Vector2(size) / 2.0 - Vector2.ONE, radius))

func circle_tex(diameter: int) -> ImageTexture:
	return sdf_texture("c%d" % diameter, Vector2i(diameter, diameter),
		func(p): return p.length() - diameter / 2.0 + 1.0)

## n white dots in a row (brick health pips)
func pips_tex(n: int) -> ImageTexture:
	return sdf_texture("pips%d" % n, Vector2i(60, 20), func(p):
		var d := 1e9
		for i in n: d = min(d, (p - Vector2((i - (n - 1) / 2.0) * 18.0, 0)).length() - 6.0)
		return d)

func diamond_tex() -> ImageTexture:
	return sdf_texture("diamond", Vector2i(30, 30), func(p): return (abs(p.x) + abs(p.y) - 12.0) * 0.707)

func apply_ui_theme() -> void:
	var theme: Theme = load("res://theme/main_theme.tres")
	theme.set_color("font_color", "Label", C_WHITE)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": C_FIELD, "hover": C_VIOLET, "pressed": C_CORAL, "focus": C_VIOLET}[state]
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 32; sb.content_margin_right = 32
		sb.content_margin_top = 10; sb.content_margin_bottom = 10
		theme.set_stylebox(state, "Button", sb)
	for col in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(col, "Button", C_WHITE)
	RenderingServer.set_default_clear_color(C_BG)

const SAVE_PATH := "user://save.cfg"
var high_score: int = 0
var start_level: int = 1
## Layout from the level editor; when non-empty the game plays it instead of the campaign.
var custom_level: Array = []
var max_level: int = 1
var skin_index: int = 0

## Ship outlines in unit space (x: -1..1 = half width, y: -1..1 = half height).
const SHAPES := {
	"arrow": [[-1, 1], [-0.75, 0], [-0.3, -0.3], [-0.12, -1], [0.12, -1], [0.3, -0.3], [0.75, 0], [1, 1], [0.3, 0.6], [-0.3, 0.6]],
	"delta": [[-1, 1], [-0.15, -1], [0.15, -1], [1, 1], [0, 0.45]],
	"saucer": [[-1, 0.3], [-0.6, -0.5], [-0.2, -0.9], [0.2, -0.9], [0.6, -0.5], [1, 0.3], [0.6, 0.8], [-0.6, 0.8]],
	"twin": [[-1, 1], [-0.85, -1], [-0.55, -1], [-0.4, 0], [0.4, 0], [0.55, -1], [0.85, -1], [1, 1], [0, 0.6]],
	"manta": [[-1, 0.6], [-0.5, -0.4], [0, -1], [0.5, -0.4], [1, 0.6], [0.4, 0.3], [0, 0.8], [-0.4, 0.3]],
}
const SKINS := [
	{"name": "ARROW", "shape": "arrow", "hull": C_WHITE, "cockpit": C_CYAN, "unlock": 1},
	{"name": "DELTA", "shape": "delta", "hull": C_AMBER, "cockpit": C_DARK, "unlock": 5},
	{"name": "SAUCER", "shape": "saucer", "hull": C_GREEN, "cockpit": C_WHITE, "unlock": 10},
	{"name": "TWIN", "shape": "twin", "hull": C_VIOLET, "cockpit": C_AMBER, "unlock": 15},
	{"name": "MANTA", "shape": "manta", "hull": C_CYAN, "cockpit": C_CORAL, "unlock": 20},
	{"name": "EMBER", "shape": "delta", "hull": C_CORAL, "cockpit": C_AMBER, "unlock": 25},
	{"name": "NOVA", "shape": "manta", "hull": C_AMBER, "cockpit": C_VIOLET, "unlock": 31},
]

func skin_unlocked(i: int) -> bool:
	return max_level >= SKINS[i]["unlock"]

## Builds hull + cockpit polygons for a skin, sized to half-extents w/h.
func make_ship(skin: Dictionary, w: float, h: float) -> Array[Polygon2D]:
	var hull := Polygon2D.new()
	var pts := PackedVector2Array()
	for p in SHAPES[skin["shape"]]: pts.append(Vector2(p[0] * w, p[1] * h))
	hull.polygon = pts
	hull.color = skin["hull"]
	var cockpit := Polygon2D.new()
	cockpit.polygon = PackedVector2Array([Vector2(-w * 0.1, -h * 0.1), Vector2(0, -h * 0.85), Vector2(w * 0.1, -h * 0.1)])
	cockpit.color = skin["cockpit"]
	return [hull, cockpit]

## Returns the skin newly unlocked by reaching `level`, or {}.
func reach_level(level: int) -> Dictionary:
	if level <= max_level: return {}
	var before := max_level
	max_level = level
	save()
	for sk in SKINS:
		if sk["unlock"] > before and sk["unlock"] <= level: return sk
	return {}

func _ready() -> void:
	apply_ui_theme()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = cfg.get_value("game", "high_score", 0)
		set_volume(cfg.get_value("game", "volume", 0.8))
		max_level = cfg.get_value("game", "max_level", 1)
		skin_index = cfg.get_value("game", "skin", 0)

var volume: float = 0.8

func set_volume(v: float) -> void:
	volume = v
	AudioServer.set_bus_volume_db(0, linear_to_db(max(v, 0.0001)))

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "high_score", high_score)
	cfg.set_value("game", "volume", volume)
	cfg.set_value("game", "max_level", max_level)
	cfg.set_value("game", "skin", skin_index)
	cfg.save(SAVE_PATH)

## Returns true if it's a new record.
func submit_score(value: int) -> bool:
	if value <= high_score: return false
	high_score = value
	save()
	return true

func reset_stats() -> void:
	for key in stats.keys():
		stats[key] = 0
