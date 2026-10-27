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

const MAPS := [
	[ # pyramid
		"........1........",
		".......111.......",
		"......11E11......",
		".....1122211.....",
		"....112222211....",
		"...11122B22111...",
		"..1111111111111..",
	],
	[ # heart
		".11111...11111.",
		"1122211.1122211",
		"112E2211122E211",
		"111222111222111",
		".1112221222111.",
		"..11122B22111..",
		"...111222111...",
		"....1112111....",
		".....11111.....",
		"......111......",
	],
	[ # invader
		"..2.......2..",
		"...2.....2...",
		"..222222222..",
		".22B22222B22.",
		"2222222222222",
		"2.222333222.2",
		"2.2.......2.2",
		"...E11.11E...",
	],
	[ # rocket
		"......3......",
		".....333.....",
		"....22222....",
		"....2E1E2....",
		"....21112....",
		"....22222....",
		"...3222223...",
		"..33.2B2.33..",
		".3...111...3.",
		".....1.1.....",
	],
	[ # skull
		"...3333333...",
		"..333333333..",
		".33322222333.",
		".33B..2..B33.",
		".33B..2..B33.",
		".33322E22333.",
		"..333222333..",
		"...2.2.2.2...",
		"...2222222...",
	],
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
	match i / 5:
		0: _blocks(out, k)
		1: _orbit(out, k, rng)
		2: _tide(out, k, rng)
		3: _phantom(out, k, rng)
		4: _spiral(out, k, rng)
		5: _chaos(out, k, rng)
	return out

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

static func _ring(out: Array, rng, center: Vector2, radius: float, n: int, speed: float, hard: float) -> void:
	for j in n:
		var a := TAU * j / n
		_add(out, center + Vector2.from_angle(a) * radius, {
			"type": _roll(rng, hard), "size": SMALL, "face": true,
			"orbit_center": center, "orbit_radius": radius, "orbit_angle": a, "orbit_speed": speed})

static func _tide_row(out: Array, rng, y: float, n: int, amp: float, freq: float, phase: float, hard: float) -> void:
	var gap := 140.0
	for j in n:
		_add(out, Vector2(CX + (j - (n - 1) / 2.0) * gap, y), {
			"type": _roll(rng, hard), "size": LONG,
			"move_amp": Vector2(amp, 0), "move_freq": freq, "phase": phase})

# --- themes --------------------------------------------------------------

## Pixel-art shapes, static. Teaches brick types.
static func _blocks(out: Array, k: int) -> void:
	var rows: Array = MAPS[k]
	var cols: int = rows[0].length()
	for r in rows.size():
		for c in cols:
			var ch: String = rows[r][c]
			if ch == ".": continue
			var type: int = {"1": ONE, "2": TWO, "3": THREE, "B": BOMB, "E": ENERGY}[ch]
			_add(out, Vector2(CX + (c - (cols - 1) / 2.0) * GRID, 100 + r * GRID), {"type": type, "size": SMALL})

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
			for j in 4: _add(out, c + Vector2.from_angle(TAU * j / 4) * 40, {"type": BOMB})
			_ring(out, rng, c, 130, 9, 0.8, hard)
			_ring(out, rng, c, 220, 14, -0.6, hard)
			_ring(out, rng, c, 300, 20, 0.45, hard)

## Long bricks swaying side to side like waves.
static func _tide(out: Array, k: int, rng) -> void:
	var hard := k / 4.0
	var rows := 3 + k
	for r in rows:
		var row_k := r % 2
		_tide_row(out, rng, 110 + r * 80, 7 - row_k, 60 + 20 * k, 0.8 + 0.15 * k, r * 0.8, hard)
	if k >= 3:
		# bobbing small bricks between the rows
		for j in 6:
			_add(out, Vector2(CX - 375 + j * 150, 150 + rows * 80), {
				"type": _roll(rng, hard), "size": SMALL,
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
			var spec := {"type": _roll(rng, hard), "size": SMALL}
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
			var spec := {"type": _roll(rng, hard), "size": SMALL if j < 5 else LONG, "spin": 1.5 + 0.3 * k}
			if speed != 0.0:
				spec.merge({"orbit_center": c, "orbit_radius": r, "orbit_angle": a, "orbit_speed": speed})
			_add(out, c + Vector2.from_angle(a) * r, spec)

## Everything at once.
static func _chaos(out: Array, k: int, rng) -> void:
	var hard := 0.6 + k / 10.0
	_ring(out, rng, Vector2(CX, CY + 40), 150 + 20 * k, 10 + 2 * k, 0.5 + 0.1 * k, hard)
	_tide_row(out, rng, 90, 7, 80 + 10 * k, 1.0 + 0.1 * k, 0.0, hard)
	if k >= 1:
		_tide_row(out, rng, 600, 6, 100, 1.2, 1.5, hard)
	# blinking core
	for j in range(-1, 2):
		for m in range(-1, 2):
			_add(out, Vector2(CX + j * GRID, CY + 40 + m * GRID), {
				"type": _roll(rng, hard), "size": SMALL, "blink": 2.5 - 0.2 * k, "phase": (j + m) * 0.4})
	if k >= 2:
		for side in [-1, 1]:
			for j in 2 + k / 2:
				_add(out, Vector2(CX + side * 520, 200 + j * 110), {"type": _roll(rng, hard), "size": LONG, "spin": side * (1.0 + 0.2 * k)})
