extends RefCounted
## 120 levels = 12 worlds x 10 stages. Worlds cycle the 6 themes twice: worlds 1-6
## are the base version, worlds 7-12 the harder "II" version. Stage 10 of every
## world is a boss; level 120 is the final boss, THE ARCHITECT.
## Layouts come from parameterised generators with a per-level seed, so a level
## is always the same, and every stage of a world plays differently.

const WORLDS := 12
const STAGES := 10
const COUNT := WORLDS * STAGES
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

const FULL_HALF_WIDTH := 970.0  # widest the arena can get (EXPAND headroom included)
const MIN_HALF_WIDTH := 560.0   # narrowest arena that still plays well
const SIDE_PADDING := 130.0     # room beside the layout for the ball to get around
const EXPAND_ROOM := 90.0       # always left free for the EXPAND pickup

# ---------------------------------------------------------------- level info

static func index_of(level: int) -> int:
	return (level - 1) % COUNT

static func world_of(level: int) -> int:
	return index_of(level) / STAGES

static func stage_of(level: int) -> int:
	return index_of(level) % STAGES

static func theme_index(level: int) -> int:
	return world_of(level) % THEMES.size()

static func tier_of(level: int) -> int:
	return world_of(level) / THEMES.size()

static func is_final(level: int) -> bool:
	return index_of(level) == COUNT - 1

## Theme colors; the II worlds use a deeper, more saturated take on the same palette.
static func theme_of(level: int) -> Dictionary:
	var th: Dictionary = THEMES[theme_index(level)].duplicate()
	if tier_of(level) == 1:
		th["name"] += " II"
		th["field"] = th["field"].darkened(0.25)
		th["wall"] = Color.from_hsv(th["wall"].h, min(th["wall"].s * 1.4, 1.0), th["wall"].v)
	return th

static func world_name(world: int) -> String:
	return THEMES[world % THEMES.size()]["name"] + (" II" if world >= THEMES.size() else "")

static func title_of(level: int) -> String:
	if is_final(level): return "FINAL  -  THE ARCHITECT"
	return "%s  %d-%d" % [theme_of(level)["name"], world_of(level) + 1, stage_of(level) + 1]

# ---------------------------------------------------------------- arena width

## Playfield half-width that hugs the layout: its widest reach (incl. motion) plus
## padding that shrinks a little through the world, so compact levels get a tight arena.
static func half_width(level: int, layout: Array) -> float:
	if is_final(level): return FULL_HALF_WIDTH - EXPAND_ROOM  # the final fight gets the whole arena
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
	var padding: float = SIDE_PADDING - min(stage_of(level), 8) * 8.0
	return clamp(need + padding, MIN_HALF_WIDTH, FULL_HALF_WIDTH - EXPAND_ROOM)

# ---------------------------------------------------------------- build

## Returns [{pos: Vector2, spec: Dictionary}, ...]
static func build(level: int) -> Array:
	var i := index_of(level)
	var s := stage_of(level)
	var tier := tier_of(level)
	var d := float(i) / (COUNT - 1)  # 0..1 over the whole campaign
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + i
	var out := []
	if is_final(level):
		_final(out)
		return out
	if s == STAGES - 1:
		_boss(out, theme_index(level), tier, rng)
		return out
	match theme_index(level):
		0: _blocks(out, s, tier, rng)
		1: _orbit(out, s, tier, d, rng)
		2: _tide(out, s, tier, d, rng)
		3: _phantom(out, s, tier, d, rng)
		4: _spiral(out, s, tier, d, rng)
		5: _chaos(out, s, tier, d, rng)
	if tier == 1: _harden(out, rng, 0.35)
	return out

## Target clear time for the 2nd star, from the layout's size and toughness.
static func par_time(level: int) -> float:
	var t := 15.0
	for item in build(level):
		var sp: Dictionary = item["spec"]
		t += sp.get("hp", sp.get("type", ONE) + 1) * 1.1 if sp.get("type", ONE) <= THREE else 0.3
	return ceil(t / 5.0) * 5.0

# ---------------------------------------------------------------- bosses

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

## Final boss. Its phases (shape / motion per HP band) are driven by the game.
const FINAL_BOSS := {"name": "THE ARCHITECT", "shape": "hex", "scale": 3.4, "hp": 140,
	"color": Color("f4f4ff"), "final": true, "move_amp": Vector2(260, 0), "move_freq": 0.5}

## Boss spec for a level ({} if none). II-world bosses are tougher and faster.
static func boss_of(level: int) -> Dictionary:
	if is_final(level): return FINAL_BOSS.duplicate()
	if stage_of(level) != STAGES - 1: return {}
	var b: Dictionary = BOSSES[theme_index(level)].duplicate()
	if tier_of(level) == 1:
		b["name"] += " II"
		b["hp"] = int(b["hp"] * 1.7)
		b["move_freq"] = b.get("move_freq", 0.6) * 1.3
		if b.has("orbit_speed"): b["orbit_speed"] *= 1.4
		if b.has("spin"): b["spin"] *= 1.5
	return b

static func _boss_spec(b: Dictionary) -> Dictionary:
	var spec := {"type": THREE, "size": SMALL, "boss": true}
	spec.merge(b)
	if b.get("shape", "") == "": spec.erase("shape")
	return spec

static func _boss(out: Array, t: int, tier: int, rng) -> void:
	var b: Dictionary = BOSSES[t].duplicate()
	if tier == 1: b = boss_of((t + THEMES.size()) * STAGES + STAGES)  # same theme, II world
	_add(out, Vector2(CX, 280), _boss_spec(b))
	var hard := 0.5 + t * 0.08 + tier * 0.3
	match t:
		0:
			for i in 9: _s(out, "", -256 + i * 64.0, 520, _roll(rng, hard))
		1:
			_ring(out, rng, Vector2(CX, 340), 290, 14, -0.35 - tier * 0.2, hard, "hex")
		2:
			_tide_row(out, rng, 520, 6, 120, 1.0 + tier * 0.4, 0.0, hard, "bar")
		3:
			for i in 8: _add(out, Vector2(CX - 280 + i * 80.0, 540), {"type": _roll(rng, hard), "size": SMALL,
				"shape": "circle", "blink": 2.4, "phase": i * 0.3})
		4:
			_ring(out, rng, Vector2(CX, 340), 290, 12, 0.5 + tier * 0.2, hard, "tri")
		5:
			_ring(out, rng, Vector2(CX, 340), 290, 12, 0.6 + tier * 0.2, hard, "star")
			_tide_row(out, rng, 560, 6, 100, 1.2, 0.0, hard, "pill")

## Level 120: the Architect alone; it summons its own escorts as it changes phase.
static func _final(out: Array) -> void:
	_add(out, Vector2(CX, 280), _boss_spec(FINAL_BOSS))

# ---------------------------------------------------------------- helpers

static func _roll(rng: RandomNumberGenerator, hard: float) -> int:
	var r := rng.randf()
	if r < 0.06: return BOMB
	if r < 0.13: return ENERGY
	r = rng.randf()
	if r < 0.1 + 0.35 * hard: return THREE
	if r < 0.45 + 0.15 * hard: return TWO
	return ONE

## II worlds: bump some bricks one hit tougher.
static func _harden(out: Array, rng, p: float) -> void:
	for item in out:
		var sp: Dictionary = item["spec"]
		var t: int = sp.get("type", ONE)
		if t < THREE and not sp.has("boss") and rng.randf() < p: sp["type"] = t + 1

static func _add(out: Array, pos: Vector2, spec: Dictionary) -> void:
	out.append({"pos": pos, "spec": spec})

## Shape brick at (x from center, y). shape "" = classic square.
static func _s(out: Array, shape: String, x: float, y: float, type: int, rot := 0.0, extra := {}) -> void:
	var spec := {"type": type, "size": SMALL, "rot": rot}
	if shape != "": spec["shape"] = shape
	spec.merge(extra)
	_add(out, Vector2(CX + x, y), spec)

static func _ring(out: Array, rng, center: Vector2, radius: float, n: int, speed: float, hard: float, shape := "") -> void:
	if shape == "": shape = ["circle", "hex", ""][int(radius / 90.0) % 3]
	for j in n:
		var a := TAU * j / n
		var spec := {
			"type": _roll(rng, hard), "size": SMALL, "face": true,
			"orbit_center": center, "orbit_radius": radius, "orbit_angle": a, "orbit_speed": speed}
		if shape != "": spec["shape"] = shape
		_add(out, center + Vector2.from_angle(a) * radius, spec)

static func _tide_row(out: Array, rng, y: float, n: int, amp: float, freq: float, phase: float, hard: float, shape := "", bob := 0.0) -> void:
	var gap := 140.0
	for j in n:
		var spec := {"type": _roll(rng, hard), "size": LONG,
			"move_amp": Vector2(amp, bob), "move_freq": freq, "phase": phase}
		if shape != "": spec["shape"] = shape
		_add(out, Vector2(CX + (j - (n - 1) / 2.0) * gap, y), spec)

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

## Mirror a layout left-right (positions and rotations).
static func _mirror(out: Array) -> void:
	for item in out:
		item["pos"].x = 2.0 * CX - item["pos"].x
		var sp: Dictionary = item["spec"]
		if sp.has("rot"): sp["rot"] = -sp["rot"]

# ---------------------------------------------------------------- themes

## Pictures (stages 1-5) then generated pixel creatures (stages 6-9). II worlds
## show the pictures mirrored.
static func _blocks(out: Array, s: int, tier: int, rng) -> void:
	if s < 5:
		_picture(out, s)
		if tier == 1: _mirror(out)
	else:
		_creature(out, rng, s, tier)

## Symmetric pixel creature built from one shape family, with eyes and antennae.
static func _creature(out: Array, rng, s: int, tier: int) -> void:
	var half_w := 3 + (s - 5) / 2          # columns on each side of the spine
	var rows := 5 + (s - 5)                 # 5..8
	var cell := 60.0
	var body: String = ["", "hex", "circle", "diamond"][rng.randi() % 4]
	var top := 110.0
	var mask := {}
	for r in rows:
		for c in half_w + 1:
			# denser near the spine and the middle rows, so it reads as a body
			var p: float = 0.85 - c * 0.12 - abs(r - rows / 2.0) * 0.06
			if rng.randf() < p: mask[Vector2i(c, r)] = true
	var eye_row: int = 1 + rng.randi() % 2
	var eye_col: int = 1 + rng.randi() % max(1, half_w - 1)
	for key in mask:
		for side in ([1, -1] if key.x != 0 else [1]):
			var x: float = key.x * side * cell
			var y: float = top + key.y * cell
			var is_eye: bool = key.y == eye_row and key.x == eye_col
			var t := ENERGY if is_eye else (THREE if key.y == 0 else (TWO if rng.randf() < 0.35 + tier * 0.2 else ONE))
			_s(out, "circle" if is_eye else body, x, y, t)
	# antennae and feet
	for side in [-1, 1]:
		_s(out, "tri", side * cell * (half_w - 0.5), top - cell * 0.9, TWO)
		_s(out, "wedge", side * cell * half_w, top + rows * cell, ONE, 0.0 if side < 0 else 90.0)
	if rng.randf() < 0.6: _s(out, "", 0, top + rows * cell, BOMB)

static func _picture(out: Array, k: int) -> void:
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
			_s(out, "star", -120, 70, BOMB)  # falling star
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

## Rings orbiting one or two centers; more rings and speed through the world.
static func _orbit(out: Array, s: int, tier: int, d: float, rng) -> void:
	var hard := d
	var systems := 1 if s < (4 - tier * 2) else 2
	var rings: int = (2 + s % 2) if systems == 1 else (1 + s % 2)
	var shape_sets := [["circle", "hex", "", "diamond"], ["star", "diamond", "circle", "tri"]]
	var shapes: Array = shape_sets[tier]
	var cy := CY + 30.0
	var centers := [Vector2(CX, cy)] if systems == 1 else [Vector2(CX - 300, cy), Vector2(CX + 300, cy)]
	if systems == 2 and s % 3 == 1: centers = [Vector2(CX - 300, cy - 40), Vector2(CX + 300, cy + 40)]
	for ci in centers.size():
		for r in rings:
			var radius := (110.0 + r * 90.0) if systems == 1 else (90.0 + r * 90.0)
			var n := int(radius / 15.0) + 2 + s % 3
			var dir := 1.0 if (r + ci + s) % 2 == 0 else -1.0
			_ring(out, rng, centers[ci], radius, n, dir * (0.3 + d * 0.6), hard, shapes[(s + r + ci) % shapes.size()])
	if s % 3 == 2:  # explosive core
		for c in centers:
			for j in 4: _add(out, c + Vector2.from_angle(TAU * j / 4) * 36, {"type": BOMB, "shape": "circle"})

## Long bricks swaying like waves; II worlds bob them vertically too.
static func _tide(out: Array, s: int, tier: int, d: float, rng) -> void:
	var rows: int = min(3 + s / 2 + tier, 7)
	var amp := 60.0 + d * 120.0
	var freq := 0.7 + d * 0.9
	var shapes := ["bar", "pill", ""]
	for r in rows:
		var n: int
		match s % 3:
			0: n = 7 - r % 2                    # even bands
			1: n = max(2, 7 - r)                # V: shrinking rows
			_: n = 4 + (r * 2 + s) % 4          # zigzag lengths
		_tide_row(out, rng, 100 + r * 78, n, amp, freq, r * (0.5 + rng.randf() * 0.6), d,
			shapes[(r + s + tier) % 3], 24.0 * tier * (r % 2))
	if s >= 3:  # bobbing domes under the rows
		for j in 6:
			_add(out, Vector2(CX - 375 + j * 150, 140 + rows * 78), {
				"type": _roll(rng, d), "size": SMALL, "shape": "half",
				"move_amp": Vector2(0, 40), "move_freq": 1.5, "phase": j * 0.7})

## Fading bricks in three formations: diamond, bands, or twin diamonds.
static func _phantom(out: Array, s: int, tier: int, d: float, rng) -> void:
	var period := 3.4 - d * 1.4
	var blink_ratio: float = clamp(0.3 + d * 0.5 + tier * 0.1, 0.0, 0.85)
	var cells := []
	match s % 3:
		0:  # diamond
			var radius: int = min(3 + s / 2, 5)
			for y in range(-radius, radius + 1):
				for x in range(-radius - 3, radius + 4):
					if abs(x) * 0.6 + abs(y) <= radius: cells.append(Vector2i(x, y))
		1:  # horizontal bands with gaps; more bands and a different gap rhythm per stage
			var gap := 3 + s % 3
			for y in range(-(1 + s / 3), 2 + s / 3, 2):
				for x in range(-6, 7):
					if posmod(x + y + s, gap) != 0: cells.append(Vector2i(x, y))
		2:  # twin diamonds, growing; hollow in later stages
			var r2: int = 2 + s / 3
			for cx in [-(r2 + 1), r2 + 1]:
				for y in range(-r2, r2 + 1):
					for x in range(-r2, r2 + 1):
						var m: int = abs(x) + abs(y)
						if m <= r2 and not (s >= 5 and m < r2 - 1): cells.append(Vector2i(cx + x, y))
	for c in cells:
		var spec := {"type": _roll(rng, d), "size": SMALL, "shape": "diamond" if (c.x + c.y) % 2 == 0 else "circle"}
		if rng.randf() < blink_ratio:
			spec["blink"] = period
			spec["phase"] = (c.x + c.y) * 0.25
		elif s >= 3 and rng.randf() < 0.3:
			spec["spin"] = 1.2
		_add(out, Vector2(CX + c.x * GRID, CY + 45 + c.y * GRID * 0.8), spec)

## Spinning triangles on spiral arms; later the whole spiral turns, twin spirals at the end.
static func _spiral(out: Array, s: int, tier: int, d: float, rng) -> void:
	var arms: int = min(2 + s / 3 + tier, 5)
	var speed := 0.0 if (s < 2 and tier == 0) else (0.15 + d * 0.4) * (1.0 if rng.randf() < 0.5 else -1.0)
	var centers := [Vector2(CX, CY + 45)] if s < 7 else [Vector2(CX - 280, CY + 40), Vector2(CX + 280, CY + 40)]
	var length := (7 + s % 3) if centers.size() == 1 else 6
	var twist := 0.32 + 0.12 * (s % 3)
	var tip_shape: String = ["star", "heart", "diamond"][(s + tier) % 3]
	for ci in centers.size():
		var c: Vector2 = centers[ci]
		for arm in arms:
			for j in length:
				var r := 60.0 + j * 32.0
				var a := TAU * arm / arms + j * twist * (1 if ci == 0 else -1)
				var spec := {"type": _roll(rng, d), "size": SMALL, "shape": ("tri" if (j + s) % 4 != 0 else "wedge") if j < length - 2 else tip_shape,
					"spin": 1.2 + d * 2.0}
				if speed != 0.0:
					spec.merge({"orbit_center": c, "orbit_radius": r, "orbit_angle": a, "orbit_speed": speed * (1 if ci == 0 else -1)})
				_add(out, c + Vector2.from_angle(a) * r, spec)

## A remix of every theme's pieces; more of them deeper in the world.
static func _chaos(out: Array, s: int, tier: int, d: float, rng) -> void:
	var hard: float = clamp(0.5 + d * 0.5, 0.0, 1.0)
	var parts := [0, 1, 2, 3, 4]
	# deterministic shuffle per level
	for i in range(parts.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp = parts[i]; parts[i] = parts[j]; parts[j] = tmp
	var count: int = min(2 + s / 3 + tier, 5)
	for p in parts.slice(0, count):
		match p:
			0: _ring(out, rng, Vector2(CX, CY + 40), 150 + 15 * s, 10 + s, 0.5 + d * 0.5, hard, "star")
			1: _tide_row(out, rng, 90, 7, 80 + 10 * s, 1.0 + d * 0.6, 0.0, hard, "pill")
			2: _tide_row(out, rng, 600, 6, 100, 1.2, 1.5, hard, "bar")
			3:  # blinking core
				for j in range(-1, 2):
					for m in range(-1, 2):
						_add(out, Vector2(CX + j * GRID, CY + 40 + m * GRID), {
							"type": _roll(rng, hard), "size": SMALL, "shape": "hex", "blink": 2.6 - d, "phase": (j + m) * 0.4})
			4:  # spinners on both sides
				for side in [-1, 1]:
					for j in 3:
						_add(out, Vector2(CX + side * 520, 200 + j * 110), {"type": _roll(rng, hard), "size": LONG,
							"shape": "bar", "spin": side * (1.0 + d)})
	if out.is_empty(): _ring(out, rng, Vector2(CX, CY), 200, 12, 0.5, hard, "star")
