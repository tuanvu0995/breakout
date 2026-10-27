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

## n white dots in a row (brick health pips). `last` (0..1] shrinks the last dot
## so bullet chip damage (1/4 of a dot) is visible.
func pips_tex(n: int, last := 1.0) -> ImageTexture:
	return sdf_texture("pips%d_%.2f" % [n, last], Vector2i(60, 20), func(p):
		var d := 1e9
		for i in n:
			var r := 6.0 if i < n - 1 else 2.0 + 4.0 * last
			d = min(d, (p - Vector2((i - (n - 1) / 2.0) * 18.0, 0)).length() - r)
		return d)

func diamond_tex() -> ImageTexture:
	return sdf_texture("diamond", Vector2i(30, 30), func(p): return (abs(p.x) + abs(p.y) - 12.0) * 0.707)

## Kept alive for the whole run: the theme is edited in memory, and if nothing
## held it the resource cache would drop it and screens would reload the
## unstyled file from disk.
var ui_theme: Theme

func apply_ui_theme() -> void:
	ui_theme = load("res://theme/main_theme.tres")
	var theme := ui_theme
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
	"hawk": [[-1, -0.2], [-0.4, 0.2], [-0.15, -1], [0.15, -1], [0.4, 0.2], [1, -0.2], [0.7, 0.6], [0.2, 0.5], [0, 1], [-0.2, 0.5], [-0.7, 0.6]],
	"bolt": [[-1, 0.8], [-0.3, -0.2], [-0.5, -0.2], [0, -1], [0.3, -0.1], [0.5, -0.1], [1, 0.8], [0, 0.4]],
	"claw": [[-1, -1], [-0.6, 0.2], [-0.2, -0.6], [0.2, -0.6], [0.6, 0.2], [1, -1], [0.9, 0.9], [0, 0.5], [-0.9, 0.9]],
	"crescent": [[-1, -0.6], [-0.7, 0.5], [-0.3, 0.9], [0.3, 0.9], [0.7, 0.5], [1, -0.6], [0.5, 0.1], [0, -0.1], [-0.5, 0.1]],
	"orb": [[-0.5, -0.9], [0.5, -0.9], [0.95, -0.3], [1, 0.4], [0.6, 0.95], [-0.6, 0.95], [-1, 0.4], [-0.95, -0.3]],
}
## unlock: reach that level. score: reach that best score instead.
## accent: inner stripe color, trail: engine flame color.
const SKINS := [
	{"name": "ARROW", "shape": "arrow", "hull": C_WHITE, "cockpit": C_CYAN, "trail": C_CYAN, "unlock": 1},
	{"name": "DELTA", "shape": "delta", "hull": C_AMBER, "cockpit": C_DARK, "accent": C_CORAL, "trail": C_AMBER, "unlock": 10},
	{"name": "SAUCER", "shape": "saucer", "hull": C_GREEN, "cockpit": C_WHITE, "accent": C_CYAN, "trail": C_GREEN, "unlock": 20},
	{"name": "TWIN", "shape": "twin", "hull": C_VIOLET, "cockpit": C_AMBER, "trail": C_VIOLET, "unlock": 40},
	{"name": "MANTA", "shape": "manta", "hull": C_CYAN, "cockpit": C_CORAL, "accent": C_WHITE, "trail": C_CYAN, "unlock": 60},
	{"name": "EMBER", "shape": "delta", "hull": C_CORAL, "cockpit": C_AMBER, "accent": C_AMBER, "trail": C_CORAL, "unlock": 80},
	{"name": "NOVA", "shape": "manta", "hull": C_AMBER, "cockpit": C_VIOLET, "accent": C_VIOLET, "trail": C_WHITE, "unlock": 121},
	{"name": "HAWK", "shape": "hawk", "hull": C_WHITE, "cockpit": C_RED, "accent": C_RED, "trail": C_CORAL, "score": 5000},
	{"name": "VOLT", "shape": "bolt", "hull": C_AMBER, "cockpit": C_DARK, "accent": C_WHITE, "trail": C_AMBER, "score": 10000},
	{"name": "CLAW", "shape": "claw", "hull": C_RED, "cockpit": C_WHITE, "accent": C_DARK, "trail": C_RED, "score": 20000},
	{"name": "LUNA", "shape": "crescent", "hull": C_CYAN, "cockpit": C_WHITE, "accent": C_VIOLET, "trail": C_VIOLET, "score": 35000},
	{"name": "ORB", "shape": "orb", "hull": C_VIOLET, "cockpit": C_GREEN, "accent": C_GREEN, "trail": C_GREEN, "score": 50000},
	{"name": "GHOST", "shape": "hawk", "hull": Color(0.95, 0.95, 1.0, 0.55), "cockpit": C_CYAN, "accent": C_WHITE, "trail": C_WHITE, "score": 75000},
	{"name": "KING", "shape": "claw", "hull": C_AMBER, "cockpit": C_RED, "accent": C_WHITE, "trail": C_AMBER, "score": 100000},
]

func skin_unlocked(i: int) -> bool:
	var sk: Dictionary = SKINS[i]
	if sk.has("score"): return high_score >= sk["score"]
	return max_level >= sk["unlock"]

## Stars per level (0-3), saved locally.
var stars := {}

func get_stars(level: int) -> int:
	return int(stars.get(str(level), 0))

func submit_stars(level: int, n: int) -> void:
	if n > get_stars(level):
		stars[str(level)] = n
		save()

func total_stars() -> int:
	var t := 0
	for v in stars.values(): t += int(v)
	return t

## Best clear time per level (seconds), saved locally.
var best_times := {}

func best_time(level: int) -> float:
	return best_times.get(str(level), 0.0)

## Returns true if it's a new personal best.
func submit_time(level: int, seconds: float) -> bool:
	var old := best_time(level)
	if old > 0.0 and seconds >= old: return false
	best_times[str(level)] = seconds
	save()
	return true

static func format_time(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]

func unlock_text(i: int) -> String:
	var sk: Dictionary = SKINS[i]
	if sk.has("score"): return "LOCKED - SCORE %d" % sk["score"]
	return "LOCKED - REACH LEVEL %d" % sk["unlock"]

func make_ship(skin: Dictionary, w: float, h: float) -> Array[Polygon2D]:
	var hull := Polygon2D.new()
	var pts := PackedVector2Array()
	for p in SHAPES[skin["shape"]]: pts.append(Vector2(p[0] * w, p[1] * h))
	hull.polygon = pts
	hull.color = skin["hull"]
	var cockpit := Polygon2D.new()
	cockpit.polygon = PackedVector2Array([Vector2(-w * 0.1, -h * 0.1), Vector2(0, -h * 0.85), Vector2(w * 0.1, -h * 0.1)])
	cockpit.color = skin["cockpit"]
	if not skin.has("accent"): return [hull, cockpit]
	var accent := Polygon2D.new()
	var inner := PackedVector2Array()
	for p in pts: inner.append(Vector2(p.x * 0.6, p.y * 0.35 + h * 0.3))
	accent.polygon = inner
	accent.color = skin["accent"]
	return [hull, accent, cockpit]

## Returns the skin newly unlocked by reaching `level`, or {}.
func reach_level(level: int) -> Dictionary:
	if level <= max_level: return {}
	var before := max_level
	max_level = level
	save()
	for sk in SKINS:
		if sk.has("unlock") and sk["unlock"] > before and sk["unlock"] <= level: return sk
	return {}

## The user data folder follows the app name; carry saves over from the old
## "Breakout" folder once, so renaming the game doesn't wipe progress.
func migrate_old_saves() -> void:
	if FileAccess.file_exists(SAVE_PATH): return
	var old := OS.get_data_dir().path_join("Godot/app_userdata/Breakout")
	if not DirAccess.dir_exists_absolute(old): return
	for f in ["save.cfg", "custom_levels.json", "lb_auth.json", "lb_queue.json"]:
		if FileAccess.file_exists(old.path_join(f)):
			DirAccess.copy_absolute(old.path_join(f), "user://".path_join(f))

func _ready() -> void:
	migrate_old_saves()
	apply_ui_theme()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = cfg.get_value("game", "high_score", 0)
		set_volume(cfg.get_value("game", "volume", 0.8))
		max_level = cfg.get_value("game", "max_level", 1)
		skin_index = cfg.get_value("game", "skin", 0)
		best_times = cfg.get_value("game", "best_times", {})
		stars = cfg.get_value("game", "stars", {})
		for k in settings.keys():
			settings[k] = cfg.get_value("settings", k, settings[k])
	apply_settings()

var volume: float = 0.8  # master

## Player settings (saved in [settings]). Change them through set_setting().
var settings := {
	"music": 0.8, "sfx": 0.9,
	"fullscreen": false, "vsync": true,
	"shake": 1.0,          # 0 off, 0.5 low, 1 full
	"popups": true,        # floating score numbers
	"hints": true,         # bottom-left controls helper
}

func set_volume(v: float) -> void:
	volume = v
	AudioServer.set_bus_volume_db(0, linear_to_db(max(v, 0.0001)))

func set_setting(key: String, value) -> void:
	settings[key] = value
	apply_settings()
	save()

func _bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i == -1:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i

func apply_settings() -> void:
	AudioServer.set_bus_volume_db(_bus("Music"), linear_to_db(max(settings["music"], 0.0001)))
	AudioServer.set_bus_volume_db(_bus("SFX"), linear_to_db(max(settings["sfx"], 0.0001)))
	if DisplayServer.get_name() != "headless":
		var want_fs: bool = settings["fullscreen"]
		var is_fs := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		if want_fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings["vsync"] else DisplayServer.VSYNC_DISABLED)

## Wipe campaign progress (custom levels and the leaderboard account are kept).
func reset_progress() -> void:
	high_score = 0
	max_level = 1
	skin_index = 0
	stars = {}
	best_times = {}
	save()

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "high_score", high_score)
	cfg.set_value("game", "volume", volume)
	cfg.set_value("game", "max_level", max_level)
	cfg.set_value("game", "skin", skin_index)
	cfg.set_value("game", "best_times", best_times)
	cfg.set_value("game", "stars", stars)
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
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
