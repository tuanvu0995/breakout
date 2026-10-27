extends RefCounted
## 30 levels = 6 themes x 5. Each level is a list of brick specs (see Brick.spec).
## Layouts are built from code with a per-level seed, so a level is always the same.

const COUNT := 30
const CX := 683.0   # playfield center x
const CY := 330.0   # center of the brick area
const GRID := 66.0  # small brick spacing

# Brick enums (mirrors Brick.TYPE / Brick.SIZE)
const ONE := 0
const TWO := 1
const THREE := 2
const BOMB := 3
const ENERGY := 4
const SMALL := 0
const LONG := 1

const THEMES := [
	{"name": "BLOCKS", "field": Color("232850"), "wall": Color("323a72")},
	{"name": "ORBIT", "field": Color("1f2b4a"), "wall": Color("2d4a7a")},
	{"name": "TIDE", "field": Color("153a4a"), "wall": Color("1f5a6e")},
	{"name": "PHANTOM", "field": Color("2a1f45"), "wall": Color("46336e")},
	{"name": "SPIRAL", "field": Color("3a1f3a"), "wall": Color("5e2f5a")},
	{"name": "CHAOS", "field": Color("3a2420"), "wall": Color("6a3a2e")},
]

const FULL_HALF_WIDTH := 678.0
# Target half-width per step inside a theme: wide, then narrower = harder.
const WIDTH_STEPS := [678.0, 600.0, 560.0, 520.0, 480.0]

## Playfield half-width for a level: target for its step, but never narrower than the layout.
static func half_width(level: int, layout: Array) -> float:
	var need := 0.0
	for item in layout:
		var sp: Dictionary = item["spec"]
		var reach: float = abs(item["pos"].x - CX)
		if sp.has("orbit_radius"): reach = abs(sp["orbit_center"].x - CX) + sp["orbit_radius"]
		if sp.has("move_amp"): reach += abs(sp["move_amp"].x)
		var half_size := 65.0 if sp.get("size", SMALL) == LONG or sp.has("spin") else 32.0
		if sp.has("shape"): half_size = BrickShapes.extent(sp["shape"]).length()
		half_size *= sp.get("scale", 1.0)
		need = max(need, reach + half_size + 50.0)
	var target: float = WIDTH_STEPS[((level - 1) % COUNT) % 5]
	return clamp(max(target, need), 300.0, FULL_HALF_WIDTH)

static func theme_of(level: int) -> Dictionary:
	return THEMES[((level - 1) % COUNT) / 5]

static func title_of(level: int) -> String:
	var i := (level - 1) % COUNT
	return "%s  %d-%d" % [THEMES[i / 5]["name"], i / 5 + 1, i % 5 + 1]

## Returns [{pos: Vector2, spec: Dictionary}, ...]
static func build(level: int) -> Array:
	var i := (level - 1) % COUNT
	var k := i % 5  # difficulty inside the theme, 0..4
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + i
	var out := []
	if k == 4:  # last stage of every theme is a boss fight
		_boss(out, i / 5, rng)
		return out
	match i / 5:
		0: _blocks(out, k)
		1: _orbit(out, k, rng)
		2: _tide(out, k, rng)
		3: _phantom(out, k, rng)
		4: _spiral(out, k, rng)
		5: _chaos(out, k, rng)
	return out

## Boss per theme: one giant brick with its theme's motion, plus a light escort.
const BOSSES := [
	{"name": "THE MONOLITH", "shape": "", "scale": 3.0, "hp": 30, "color": Color("ff6b6b"),
		"move_amp": Vector2(240, 0), "move_freq": 0.6},
	{"name": "SATELLITE KING", "shape": "circle", "scale": 3.0, "hp": 36, "color": Color("3ddcf5"),
		"orbit_center": Vector2(683, 300), "orbit_radius": 150.0, "orbit_speed": 0.55},
	{"name": "LEVIATHAN", "shape": "pill", "scale": 3.0, "hp": 42, "color": Color("5ce08a"),
		"move_amp": Vector2(300, 50), "move_freq": 0.8},
	{"name": "WRAITH", "shape": "diamond", "scale": 3.4, "hp": 48, "color": Color("9b7bff"),
		"move_amp": Vector2(220, 0), "move_freq": 0.5, "blink": 3.2},
	{"name": "VORTEX", "shape": "star", "scale": 3.2, "hp": 54, "color": Color("ffb84d"),
		"move_amp": Vector2(180, 60), "move_freq": 0.7, "spin": 1.1},
	{"name": "OMEGA", "shape": "heart", "scale": 3.2, "hp": 64, "color": Color("ff3d5e"),
		"move_amp": Vector2(280, 60), "move_freq": 1.0},
]

static func boss_of(level: int) -> Dictionary:
	var i := (level - 1) % COUNT
	return BOSSES[i / 5] if i % 5 == 4 else {}

static func _boss(out: Array, t: int, rng) -> void:
	var b: Dictionary = BOSSES[t].duplicate()
	var spec := {"type": THREE, "size": SMALL, "boss": true}
	spec.merge(b)
	if b["shape"] == "": spec.erase("shape")
	_add(out, Vector2(CX, 280), spec)
	var hard := 0.5 + t * 0.1
	match t:
		0:
			for i in 9: _s(out, "", -256 + i * 64.0, 520, _roll(rng, hard))
		1:
			_ring(out, rng, Vector2(CX, 300), 330, 14, -0.35, hard, "hex")
		2:
			_tide_row(out, rng, 520, 6, 120, 1.0, 0.0, hard, "bar")
		3:
			for i in 8: _add(out, Vector2(CX - 280 + i * 80.0, 540), {"type": _roll(rng, hard), "size": SMALL,
				"shape": "circle", "blink": 2.4, "phase": i * 0.3})
		4:
			_ring(out, rng, Vector2(CX, 300), 320, 12, 0.5, hard, "tri")
		5:
			_ring(out, rng, Vector2(CX, 320), 330, 12, 0.6, hard, "star")
			_tide_row(out, rng, 560, 6, 100, 1.2, 0.0, hard, "pill")

## Target clear time for the 2nd star, from the layout's size and toughness.
static func par_time(level: int) -> float:
	var t := 15.0
	for item in build(level):
		var sp: Dictionary = item["spec"]
		t += sp.get("hp", sp.get("type", ONE) + 1) * 1.1 if sp.get("type", ONE) <= THREE else 0.3
	return ceil(t / 5.0) * 5.0

# --- helpers -------------------------------------------------------------

static func _roll(rng: RandomNumberGenerator, hard: float) -> int:
	var r := rng.randf()
	if r < 0.06: return BOMB
	if r < 0.13: return ENERGY
	r = rng.randf()
	if r < 0.1 + 0.35 * hard: return THREE
	if r < 0.45 + 0.15 * hard: return TWO
	return ONE

static func _add(out: Array, pos: Vector2, spec: Dictionary) -> void:
	out.append({"pos": pos, "spec": spec})

static func _ring(out: Array, rng, center: Vector2, radius: float, n: int, speed: float, hard: float, shape := "") -> void:
	if shape == "": shape = ["circle", "hex", ""][int(radius / 90.0) % 3]
	for j in n:
		var a := TAU * j / n
		var spec := {
			"type": _roll(rng, hard), "size": SMALL, "face": true,
			"orbit_center": center, "orbit_radius": radius, "orbit_angle": a, "orbit_speed": speed}
		if shape != "": spec["shape"] = shape
		_add(out, center + Vector2.from_angle(a) * radius, spec)

static func _tide_row(out: Array, rng, y: float, n: int, amp: float, freq: float, phase: float, hard: float, shape := "") -> void:
	var gap := 140.0
	for j in n:
		var spec := {"type": _roll(rng, hard), "size": LONG,
			"move_amp": Vector2(amp, 0), "move_freq": freq, "phase": phase}
		if shape != "": spec["shape"] = shape
		_add(out, Vector2(CX + (j - (n - 1) / 2.0) * gap, y), spec)

# --- themes --------------------------------------------------------------

## Shape brick at (x from center, y). shape "" = classic square.
static func _s(out: Array, shape: String, x: float, y: float, type: int, rot := 0.0, extra := {}) -> void:
	var spec := {"type": type, "size": SMALL, "rot": rot}
	if shape != "": spec["shape"] = shape
	spec.merge(extra)
	_add(out, Vector2(CX + x, y), spec)

## Band of alternating up/down triangles: n triangles starting at x0.
static func _tri_band(out: Array, x0: float, y: float, n: int, type: int) -> void:
	for i in n:
		_s(out, "tri", x0 + i * 32.0, y, type, 0.0 if i % 2 == 0 else 180.0)

## Triangle tree: rows of 1, 3, 5... triangles, top at (x, y).
static func _tree(out: Array, x: float, y: float, rows: int, type: int) -> void:
	for r in rows:
		var n := 1 + r * 2
		_tri_band(out, x - (n - 1) * 16.0, y + r * 54.0, n, type)
	_s(out, "", x, y + rows * 54.0 + 12, ONE)  # trunk

## Shapes on a circle, each pointing outward.
static func _burst(out: Array, shape: String, c: Vector2, r: float, n: int, type: int, rot_off := 90.0) -> void:
	for i in n:
		var a := TAU * i / n
		_s(out, shape, c.x + cos(a) * r, c.y + sin(a) * r, type, rad_to_deg(a) + rot_off)

## Pictures built from shaped bricks. Teaches brick types while looking like something.
static func _blocks(out: Array, k: int) -> void:
	match k:
		0:  # HOUSE & SUN
			var hx := -120.0
			for r in 3:
				for c in 4:
					var x := hx + (c - 1.5) * 64.0
					var y := 400.0 + r * 64.0
					if r == 0 and (c == 0 or c == 3): _s(out, "circle", x, y, ENERGY)  # windows
					elif r == 2 and (c == 1 or c == 2): continue                     # doorway
					else: _s(out, "", x, y, ONE)
			_s(out, "half", hx, 540, TWO)  # arched door
			for row in 4:  # triangle roof
				var n := 9 - row * 2
				_tri_band(out, hx - (n - 1) * 16.0, 336.0 - row * 54.0, n, TWO)
			_s(out, "circle", 230, 190, THREE)  # sun
			_burst(out, "tri", Vector2(230, 190), 74, 8, ONE)
			_s(out, "pill", 300, 340, ONE); _s(out, "pill", 380, 380, ONE)  # clouds
			_s(out, "", 60, 528, BOMB)  # mailbox (it explodes)
			for i in 5: _s(out, "bar", -250 + i * 124.0, 600, ONE)  # ground
		1:  # FISH
			var c := Vector2(-20, 330)
			for col in range(-4, 5):
				for row in range(-3, 4):
					var x := col * 47.0
					var y := row * 54.0 + (27.0 if col % 2 != 0 else 0.0)
					if pow(x / 215.0, 2) + pow(y / 135.0, 2) > 1.0: continue
					if Vector2(x, y).distance_to(Vector2(140, -30)) < 40: continue  # room for the eye
					_s(out, "hex", c.x + x, c.y + y, TWO if (row + col) % 3 == 0 else ONE)
			_s(out, "circle", c.x + 140, c.y - 30, BOMB)  # eye
			_s(out, "tri", c.x - 250, c.y - 34, TWO, 90)   # tail
			_s(out, "tri", c.x - 250, c.y + 34, TWO, 90)
			_s(out, "tri", c.x - 10, c.y - 168, ONE)        # dorsal fin
			_s(out, "tri", c.x - 10, c.y + 168, ONE, 180)   # belly fin
			for b in [Vector2(250, 250), Vector2(285, 175), Vector2(260, 100)]:
				_s(out, "circle", b.x, b.y, ENERGY)  # bubbles
			_s(out, "bar", -330, 520, ONE, 90); _s(out, "bar", 330, 540, ONE, 90)  # seaweed
		2:  # ROCKET
			_s(out, "tri", 0, 120, THREE)
			_tri_band(out, -32, 176, 3, THREE)
			for y in [240.0, 368.0, 432.0]:
				_s(out, "", -32, y, TWO); _s(out, "", 32, y, TWO)
			_s(out, "circle", 0, 304, ENERGY)  # porthole
			_s(out, "wedge", -96, 432, TWO); _s(out, "wedge", 96, 432, TWO, 90)  # fins
			_s(out, "wedge", -96, 368, ONE); _s(out, "wedge", 96, 368, ONE, 90)
			_s(out, "star", 0, 510, BOMB)  # engine flame
			_s(out, "diamond", -40, 575, ONE); _s(out, "diamond", 40, 575, ONE); _s(out, "diamond", 0, 610, ONE)
			for st in [Vector2(-300, 140), Vector2(270, 210), Vector2(-250, 420), Vector2(310, 470), Vector2(-360, 280), Vector2(360, 330)]:
				_s(out, "star", st.x, st.y, ONE)
		3:  # PINE FOREST UNDER THE MOON
			_tree(out, 0, 110, 4, THREE)
			_tree(out, -300, 230, 3, TWO)
			_tree(out, 300, 230, 3, TWO)
			_s(out, "half", 400, 100, THREE, 90)  # moon
			for st in [Vector2(-200, 100), Vector2(-420, 150), Vector2(200, 150), Vector2(150, 70)]:
				_s(out, "star", st.x, st.y, ONE)
			_s(out, "star", -120, 60, BOMB)  # falling star
			for i in 7: _s(out, "bar", -372 + i * 124.0, 520, ONE)  # snow
		4:  # FLOWER GARDEN
			for fx in [-220.0, 220.0]:
				var fc := Vector2(fx, 230)
				_s(out, "circle", fc.x, fc.y, THREE)
				_burst(out, "half", fc, 62, 8, TWO)
				_s(out, "bar", fc.x, 400, ONE, 90)
				_s(out, "diamond", fc.x - 44, 420, ONE, -40); _s(out, "diamond", fc.x + 44, 450, ONE, 40)
			_s(out, "heart", 0, 140, THREE)
			_s(out, "heart", -60, 300, TWO); _s(out, "heart", 60, 330, TWO)
			_s(out, "pill", -380, 120, ENERGY); _s(out, "pill", 380, 160, ENERGY)  # bees
			_s(out, "circle", 0, 470, BOMB)  # ladybug
			for i in 7: _s(out, "bar", -372 + i * 124.0, 560, ONE)  # grass

## Rings of bricks orbiting a center.
static func _orbit(out: Array, k: int, rng) -> void:
	var hard := k / 4.0
	var c := Vector2(CX, CY)
	match k:
		0:
			_ring(out, rng, c, 200, 12, 0.35, hard)
		1:
			_ring(out, rng, c, 140, 9, 0.5, hard)
			_ring(out, rng, c, 260, 16, -0.35, hard)
		2:
			_ring(out, rng, c, 100, 6, 0.7, hard)
			_ring(out, rng, c, 190, 12, -0.5, hard)
			_ring(out, rng, c, 280, 18, 0.35, hard)
		3:
			for side in [-1, 1]:
				var cc := Vector2(CX + side * 300, CY)
				_ring(out, rng, cc, 110, 8, 0.6 * side, hard)
				_ring(out, rng, cc, 210, 13, -0.4 * side, hard)
		4:
			for j in 4: _add(out, c + Vector2.from_angle(TAU * j / 4) * 40, {"type": BOMB, "shape": "circle"})
			_ring(out, rng, c, 130, 9, 0.8, hard)
			_ring(out, rng, c, 220, 14, -0.6, hard)
			_ring(out, rng, c, 300, 20, 0.45, hard)

## Long bricks swaying side to side like waves.
static func _tide(out: Array, k: int, rng) -> void:
	var hard := k / 4.0
	var rows := 3 + k
	for r in rows:
		var row_k := r % 2
		_tide_row(out, rng, 110 + r * 80, 7 - row_k, 60 + 20 * k, 0.8 + 0.15 * k, r * 0.8, hard, ["bar", "pill", ""][r % 3])
	if k >= 3:
		# bobbing small bricks between the rows
		for j in 6:
			_add(out, Vector2(CX - 375 + j * 150, 150 + rows * 80), {
				"type": _roll(rng, hard), "size": SMALL, "shape": "half",
				"move_amp": Vector2(0, 40), "move_freq": 1.5, "phase": j * 0.7})

## Bricks that fade out and become intangible on a rolling wave.
static func _phantom(out: Array, k: int, rng) -> void:
	var hard := k / 4.0
	var radius := 4 + (k + 1) / 2  # diamond size
	var period := 3.2 - 0.3 * k
	var blink_ratio := 0.4 + 0.15 * k
	for y in range(-radius, radius + 1):
		for x in range(-radius - 3, radius + 4):
			if abs(x) * 0.6 + abs(y) > radius: continue
			var spec := {"type": _roll(rng, hard), "size": SMALL, "shape": "diamond" if (x + y) % 2 == 0 else "circle"}
			if rng.randf() < blink_ratio:
				spec["blink"] = period
				spec["phase"] = (x + y) * 0.25
			elif k >= 2 and rng.randf() < 0.3:
				spec["spin"] = 1.2
			_add(out, Vector2(CX + x * GRID, CY + 30 + y * GRID * 0.8), spec)

## Spinning bricks laid along spiral arms; later the whole spiral turns.
static func _spiral(out: Array, k: int, rng) -> void:
	var hard := k / 4.0
	var arms := 2 + k / 2
	var speed := 0.0 if k < 2 else 0.2 + 0.1 * k
	var c := Vector2(CX, CY)
	for arm in arms:
		for j in 9:
			var r := 60.0 + j * 32.0
			var a := TAU * arm / arms + j * 0.45
			var spec := {"type": _roll(rng, hard), "size": SMALL, "shape": "tri" if j < 7 else "star", "spin": 1.5 + 0.3 * k}
			if speed != 0.0:
				spec.merge({"orbit_center": c, "orbit_radius": r, "orbit_angle": a, "orbit_speed": speed})
			_add(out, c + Vector2.from_angle(a) * r, spec)

## Everything at once.
static func _chaos(out: Array, k: int, rng) -> void:
	var hard := 0.6 + k / 10.0
	_ring(out, rng, Vector2(CX, CY + 40), 150 + 20 * k, 10 + 2 * k, 0.5 + 0.1 * k, hard, "star")
	_tide_row(out, rng, 90, 7, 80 + 10 * k, 1.0 + 0.1 * k, 0.0, hard, "pill")
	if k >= 1:
		_tide_row(out, rng, 600, 6, 100, 1.2, 1.5, hard, "bar")
	# blinking core
	for j in range(-1, 2):
		for m in range(-1, 2):
			_add(out, Vector2(CX + j * GRID, CY + 40 + m * GRID), {
				"type": _roll(rng, hard), "size": SMALL, "shape": "hex", "blink": 2.5 - 0.2 * k, "phase": (j + m) * 0.4})
	if k >= 2:
		for side in [-1, 1]:
			for j in 2 + k / 2:
				_add(out, Vector2(CX + side * 520, 200 + j * 110), {"type": _roll(rng, hard), "size": LONG, "shape": "bar", "spin": side * (1.0 + 0.2 * k)})
