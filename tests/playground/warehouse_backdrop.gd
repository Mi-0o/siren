extends Node2D
## Backdrop for the test arena: the inside of a huge abandoned warehouse, drawn in code at
## native pixel scale on two parallax layers that repeat sideways.
##
## Far layer: roof trusses, a band of high windows with broken panes, corrugated wall panels
## streaked with rust, slim columns and a couple of amber emergency lamps. Near layer: heavy
## I-beam columns, a catwalk with a collapsed section, sagging cables and chains, and hanging
## lamps: one dead, one flickering amber, one dim and buzzing, one shorted out that sparks now
## and then. The lamps' light cones carry drifting dust. Everything else stays dark.
##
## Each layer is static art drawn once plus a light overlay redrawn every frame.

const FAR_W: int = 576
const MID_W: int = 832
const FAR_SCALE: float = 0.3
const MID_SCALE: float = 0.6
## Ground line the layers are drawn down to (the arena floor covers it).
const GROUND_Y: int = 206
const TOP_Y: int = -90
const BOTTOM_Y: int = 330

const VOID_TOP := Color(0.012, 0.014, 0.02)
const VOID_LOW := Color(0.035, 0.038, 0.047)
const WALL := Color(0.05, 0.053, 0.062)
const WALL_RIB := Color(0.063, 0.066, 0.076)
const WALL_DARK := Color(0.032, 0.034, 0.041)
const ROOF := Color(0.018, 0.02, 0.026)
const FAR_STEEL := Color(0.04, 0.042, 0.05)
const GLASS := Color(0.07, 0.085, 0.108)
const GLASS_LIT := Color(0.1, 0.12, 0.15)
const STEEL := Color(0.085, 0.085, 0.095)
const STEEL_LIGHT := Color(0.15, 0.145, 0.15)
const STEEL_DARK := Color(0.04, 0.04, 0.047)
const RIVET := Color(0.2, 0.19, 0.19)
const RUST: Array[Color] = [
	Color(0.22, 0.11, 0.05), Color(0.15, 0.08, 0.04), Color(0.28, 0.14, 0.05)
]
const HAZARD := Color(0.3, 0.21, 0.05)
const AMBER := Color(1.0, 0.6, 0.18)
const COLD := Color(0.72, 0.85, 0.95)
const SPARK := Color(1.0, 0.85, 0.5)

## Hanging lamps on the near layer: x, how far down they hang, and what's wrong with them.
const LAMPS: Array[Dictionary] = [
	{"x": 70, "y": 52, "kind": "dim"},
	{"x": 290, "y": 66, "kind": "flicker"},
	{"x": 470, "y": 48, "kind": "dead"},
	{"x": 700, "y": 60, "kind": "spark"},
]
## Emergency lamps on the far wall.
const WALL_LAMPS: Array[Vector2i] = [Vector2i(96, 150), Vector2i(380, 132)]
const MID_COLUMNS: Array[int] = [150, 560]


## One layer of the backdrop: calls its painter with the time, every frame if animated.
class Layer extends Node2D:
	var painter: Callable
	var animated: bool = false
	var time: float = 0.0

	func _process(delta: float) -> void:
		if animated:
			time += delta
			queue_redraw()

	func _draw() -> void:
		painter.call(self, time)


func _ready() -> void:
	z_index = -50
	# Darkness behind everything, so zooming far out shows no gaps above, below or past the ends.
	var void_fill := Layer.new()
	void_fill.painter = _paint_void
	add_child(void_fill)
	_add_layer(FAR_SCALE, FAR_W, _paint_far, false)
	_add_layer(FAR_SCALE, FAR_W, _paint_far_lights, true)
	_add_layer(MID_SCALE, MID_W, _paint_mid, false)
	_add_layer(MID_SCALE, MID_W, _paint_mid_lights, true)


func _add_layer(scroll: float, tile_w: int, painter: Callable, animated: bool) -> void:
	var parallax := Parallax2D.new()
	parallax.scroll_scale = Vector2(scroll, scroll)
	parallax.repeat_size = Vector2(tile_w, 0)
	# Enough copies either side to cover the screen even with the dev menu zoomed far out.
	parallax.repeat_times = 6
	add_child(parallax)
	var layer := Layer.new()
	layer.painter = painter
	layer.animated = animated
	parallax.add_child(layer)


func _paint_void(ci: CanvasItem, _t: float) -> void:
	ci.draw_rect(Rect2(-100000, -100000, 200000, 200000), VOID_TOP)


# --- Far layer --------------------------------------------------------------------------------


func _paint_far(ci: CanvasItem, _t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001
	# The dark above and around everything.
	for y in range(TOP_Y, BOTTOM_Y, 4):
		var f := clampf(float(y - TOP_Y) / float(GROUND_Y - TOP_Y), 0.0, 1.0)
		ci.draw_rect(Rect2(0, y, FAR_W, 4), VOID_TOP.lerp(VOID_LOW, f))

	# Corrugated back wall.
	ci.draw_rect(Rect2(0, 34, FAR_W, GROUND_Y - 34), WALL)
	for x in range(0, FAR_W, 4):
		ci.draw_rect(Rect2(x, 78, 1, GROUND_Y - 78), WALL_RIB)
		ci.draw_rect(Rect2(x + 2, 78, 1, GROUND_Y - 78), WALL_DARK)
	for sy in [78, 120, 162]:
		ci.draw_rect(Rect2(0, sy, FAR_W, 1), WALL_DARK)
		ci.draw_rect(Rect2(0, sy + 1, FAR_W, 1), WALL_RIB.lightened(0.05))
	# Missing panels: the dark behind shows through.
	for k in 5:
		var px := rng.randi_range(0, FAR_W - 30)
		var py := [79, 121, 163][rng.randi_range(0, 2)] as int
		var pw := rng.randi_range(10, 26)
		var ph := rng.randi_range(12, 40)
		for y in range(py + 1, mini(py + ph, GROUND_Y)):
			var jag := rng.randi_range(-1, 1)
			ci.draw_rect(Rect2(px + jag, y, pw + rng.randi_range(-1, 1), 1), VOID_TOP)
	# Rust running down from the seams.
	for k in 34:
		var rx := rng.randi_range(0, FAR_W - 1)
		var ry := [80, 122, 164][rng.randi_range(0, 2)] as int
		var c: Color = RUST[rng.randi_range(0, RUST.size() - 1)]
		var length := rng.randi_range(5, 38)
		for y in length:
			c.a = 0.45 * (1.0 - float(y) / length)
			ci.draw_rect(Rect2(rx, ry + y, 1, 1), c)

	# High windows, most panes broken or blacked out.
	ci.draw_rect(Rect2(0, 36, FAR_W, 40), WALL_DARK)
	for wx in range(6, FAR_W - 20, 28):
		for pane in 4:
			var r := Rect2i(wx + (pane % 2) * 12, 40 + floori(pane / 2.0) * 17, 11, 16)
			var roll := rng.randf()
			if roll < 0.3:
				ci.draw_rect(Rect2(r), VOID_TOP)
				# A shard still stuck in the corner.
				for s in 5:
					ci.draw_rect(Rect2(r.position.x, r.position.y + s, 5 - s, 1), GLASS)
			elif roll < 0.45:
				ci.draw_rect(Rect2(r), WALL_DARK.darkened(0.3))
			else:
				ci.draw_rect(Rect2(r), GLASS)
				ci.draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 3, 1), GLASS_LIT)
				# A crack.
				if rng.randf() < 0.4:
					var cx := r.position.x + rng.randi_range(2, 9)
					for cy in range(r.position.y, r.end.y, 2):
						ci.draw_rect(Rect2(cx + (cy >> 2) % 2, cy, 1, 1), GLASS_LIT)

	# Roof and its trusses.
	ci.draw_rect(Rect2(0, TOP_Y, FAR_W, 14 - TOP_Y), ROOF)
	ci.draw_rect(Rect2(0, 14, FAR_W, 1), FAR_STEEL)
	ci.draw_rect(Rect2(0, 32, FAR_W, 2), FAR_STEEL)
	var bay := 24
	for bx in range(0, FAR_W, bay):
		for p in Geometry2D.bresenham_line(Vector2i(bx, 32), Vector2i(bx + (bay >> 1), 15)):
			ci.draw_rect(Rect2(p, Vector2.ONE), FAR_STEEL)
		for p in Geometry2D.bresenham_line(Vector2i(bx + (bay >> 1), 15), Vector2i(bx + bay, 32)):
			ci.draw_rect(Rect2(p, Vector2.ONE), FAR_STEEL)

	# Slim columns.
	for cx in range(40, FAR_W, 144):
		ci.draw_rect(Rect2(cx, 14, 7, GROUND_Y - 14), FAR_STEEL)
		ci.draw_rect(Rect2(cx, 14, 1, GROUND_Y - 14), WALL_RIB.lightened(0.1))
		ci.draw_rect(Rect2(cx - 2, GROUND_Y - 6, 11, 6), FAR_STEEL)

	# Emergency lamp housings (their glow is in the light layer).
	for lamp in WALL_LAMPS:
		ci.draw_rect(Rect2(lamp.x - 3, lamp.y - 2, 7, 5), STEEL_DARK)
		ci.draw_rect(Rect2(lamp.x - 3, lamp.y - 2, 7, 1), FAR_STEEL.lightened(0.15))

	# Floor line and some heaps of junk against the wall.
	ci.draw_rect(Rect2(0, GROUND_Y - 6, FAR_W, BOTTOM_Y - GROUND_Y + 6), VOID_TOP)
	for k in 6:
		var hx := rng.randi_range(0, FAR_W - 40)
		var hw := rng.randi_range(14, 40)
		var hh := rng.randi_range(4, 12)
		for x in hw:
			var top := int(hh * sin(PI * x / float(hw))) + rng.randi_range(-1, 0)
			ci.draw_rect(Rect2(hx + x, GROUND_Y - 6 - top, 1, top), WALL_DARK)


func _paint_far_lights(ci: CanvasItem, t: float) -> void:
	for i in WALL_LAMPS.size():
		var lamp := WALL_LAMPS[i]
		# A slow pulse, out of step with each other; the second one is half dead.
		var level := 0.55 + 0.45 * sin(t * 1.7 + i * 2.1)
		if i == 1:
			level *= 0.3 if hash(int(t * 6.0)) % 7 == 0 else 0.6
		var c := AMBER
		c.a = level
		ci.draw_rect(Rect2(lamp.x - 2, lamp.y - 1, 5, 3), c)
		for k in 3:
			var g := AMBER
			g.a = 0.06 * level * (3 - k)
			var r := 4 + k * 5
			ci.draw_rect(Rect2(lamp.x - r, lamp.y - r + 1, r * 2 + 1, r * 2 - 1), g)


# --- Near layer ------------------------------------------------------------------------------


func _paint_mid(ci: CanvasItem, _t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9132

	# Cables sagging between the columns, high up.
	var cables: Array = [
		[Color(0.05, 0.05, 0.06), 26, 30], [Color(0.13, 0.04, 0.04), 32, 22],
		[Color(0.04, 0.09, 0.1), 22, 40],
	]
	for cable in cables:
		var a := MID_COLUMNS[0] + 20
		var b := MID_COLUMNS[1]
		for x in range(a, b):
			var f := float(x - a) / float(b - a)
			var y := int(cable[1]) + int(float(cable[2]) * 4.0 * f * (1.0 - f))
			ci.draw_rect(Rect2(x, y, 1, 1), cable[0])
	# One more hanging loose off the right column.
	var loose_x := MID_COLUMNS[1] + 24
	for y in range(30, 74):
		ci.draw_rect(Rect2(loose_x + int(3.0 * sin(y * 0.15)), y, 1, 1), Color(0.13, 0.04, 0.04))
	ci.draw_rect(Rect2(loose_x + int(3.0 * sin(74 * 0.15)) - 1, 74, 3, 2), Color(0.5, 0.3, 0.12))

	# Catwalk between the columns, with a collapsed stretch.
	var walk_y := 104
	var gap_a := 390
	var gap_b := 432
	var c0 := MID_COLUMNS[0] + 20
	var c1 := MID_COLUMNS[1]
	for x in range(c0, c1):
		if x >= gap_a and x < gap_b:
			continue
		ci.draw_rect(Rect2(x, walk_y, 1, 3), STEEL)
		ci.draw_rect(Rect2(x, walk_y, 1, 1), STEEL_LIGHT)
		if (x - c0) % 14 == 0:
			ci.draw_rect(Rect2(x, walk_y - 10, 1, 10), STEEL)
			# Lattice under the deck.
			_line(ci, Vector2i(x, walk_y + 3), Vector2i(x + 7, walk_y + 8), STEEL_DARK)
			_line(ci, Vector2i(x + 7, walk_y + 8), Vector2i(x + 14, walk_y + 3), STEEL_DARK)
		ci.draw_rect(Rect2(x, walk_y - 10, 1, 1), STEEL)
		ci.draw_rect(Rect2(x, walk_y - 5, 1, 1), STEEL_DARK)
	# The broken piece hangs down from one end, its railing bent.
	_line(ci, Vector2i(gap_a, walk_y), Vector2i(gap_a + 16, walk_y + 34), STEEL, 2)
	_line(ci, Vector2i(gap_a - 1, walk_y - 10), Vector2i(gap_a + 9, walk_y + 18), STEEL_DARK)
	_line(ci, Vector2i(gap_b, walk_y - 10), Vector2i(gap_b - 6, walk_y - 4), STEEL)

	# Heavy I-beam columns.
	for cx in MID_COLUMNS:
		_column(ci, cx, rng)

	# A chain and hook hanging from the roof.
	for y in range(TOP_Y, 82):
		if y % 3 != 0:
			ci.draw_rect(Rect2(250 + (y % 2), y, 1, 1), STEEL_DARK.lightened(0.05))
	ci.draw_rect(Rect2(249, 82, 3, 1), STEEL)
	ci.draw_rect(Rect2(251, 83, 1, 3), STEEL)
	ci.draw_rect(Rect2(248, 85, 3, 1), STEEL)

	# Lamp housings and their chains.
	for lamp in LAMPS:
		var lx: int = lamp.x
		var ly: int = lamp.y
		for y in range(TOP_Y, ly - 3):
			if y % 3 != 1:
				ci.draw_rect(Rect2(lx, y, 1, 1), STEEL_DARK)
		ci.draw_rect(Rect2(lx - 2, ly - 3, 5, 2), STEEL)
		ci.draw_rect(Rect2(lx - 6, ly - 1, 13, 2), STEEL)
		ci.draw_rect(Rect2(lx - 7, ly + 1, 15, 1), STEEL_DARK)
		ci.draw_rect(Rect2(lx - 6, ly - 1, 13, 1), STEEL_LIGHT)
		if str(lamp.kind) == "dead":
			# Smashed: an empty socket and a dangling wire.
			for y in range(ly + 2, ly + 12):
				ci.draw_rect(Rect2(lx + 3 + int(y > ly + 7), y, 1, 1), Color(0.12, 0.05, 0.03))
		else:
			ci.draw_rect(Rect2(lx - 5, ly + 2, 11, 1), STEEL_DARK)

	# Junk on the floor: a toppled crate, a barrel, a pallet.
	ci.draw_rect(Rect2(610, GROUND_Y - 18, 26, 18), STEEL_DARK)
	ci.draw_rect(Rect2(610, GROUND_Y - 18, 26, 1), STEEL)
	for p in Geometry2D.bresenham_line(Vector2i(611, GROUND_Y - 17), Vector2i(635, GROUND_Y - 1)):
		ci.draw_rect(Rect2(p, Vector2.ONE), STEEL)
	ci.draw_rect(Rect2(644, GROUND_Y - 14, 11, 14), Color(0.07, 0.05, 0.04))
	for by in [GROUND_Y - 12, GROUND_Y - 5]:
		ci.draw_rect(Rect2(644, by, 11, 1), RUST[1])
	ci.draw_rect(Rect2(20, GROUND_Y - 5, 30, 2), STEEL_DARK)
	ci.draw_rect(Rect2(20, GROUND_Y - 2, 30, 2), STEEL_DARK)


## An I-beam column from the roof to the floor: lit left flange, dark right, rivets, rust,
## a worn hazard band and knee braces up to the roof.
func _column(ci: CanvasItem, cx: int, rng: RandomNumberGenerator) -> void:
	var w := 20
	ci.draw_rect(Rect2(cx, TOP_Y, w, GROUND_Y - TOP_Y), STEEL)
	ci.draw_rect(Rect2(cx, TOP_Y, 3, GROUND_Y - TOP_Y), STEEL_LIGHT)
	ci.draw_rect(Rect2(cx + 3, TOP_Y, 1, GROUND_Y - TOP_Y), STEEL_DARK)
	ci.draw_rect(Rect2(cx + w - 3, TOP_Y, 3, GROUND_Y - TOP_Y), STEEL_DARK)
	ci.draw_rect(Rect2(cx + 8, TOP_Y, 4, GROUND_Y - TOP_Y), STEEL.darkened(0.15))
	for y in range(TOP_Y + 4, GROUND_Y, 9):
		ci.draw_rect(Rect2(cx + 1, y, 1, 1), RIVET)
		ci.draw_rect(Rect2(cx + w - 2, y, 1, 1), RIVET.darkened(0.4))
	for y in range(166, 174):
		for x in range(cx + 4, cx + w - 3):
			if posmod(x + y, 6) < 3 and hash(Vector2i(x, y)) % 5 != 0:
				ci.draw_rect(Rect2(x, y, 1, 1), HAZARD)
	for k in 40:
		var rx := cx + rng.randi_range(1, w - 2)
		var ry := rng.randi_range(TOP_Y, GROUND_Y - 1)
		var c: Color = RUST[rng.randi_range(0, RUST.size() - 1)]
		c.a = rng.randf_range(0.4, 0.8)
		ci.draw_rect(Rect2(rx, ry, 1, rng.randi_range(1, 5)), c)
	# Knee braces.
	for p in Geometry2D.bresenham_line(Vector2i(cx - 28, 0), Vector2i(cx, 26)):
		ci.draw_rect(Rect2(p, Vector2(2, 1)), STEEL_DARK)
	for p in Geometry2D.bresenham_line(Vector2i(cx + w + 28, 0), Vector2i(cx + w, 26)):
		ci.draw_rect(Rect2(p, Vector2(2, 1)), STEEL_DARK)
	# Base plate.
	ci.draw_rect(Rect2(cx - 4, GROUND_Y - 5, w + 8, 5), STEEL_DARK)
	ci.draw_rect(Rect2(cx - 4, GROUND_Y - 5, w + 8, 1), STEEL)


func _paint_mid_lights(ci: CanvasItem, t: float) -> void:
	for i in LAMPS.size():
		var lamp: Dictionary = LAMPS[i]
		var lx: int = lamp.x
		var ly: int = lamp.y + 2
		var level := 0.0
		var tint := AMBER
		match str(lamp.kind):
			"dim":
				tint = COLD
				level = 0.35 + 0.04 * sin(t * 50.0)
			"flicker":
				# Mostly on, with stuttering drop-outs in bursts.
				var tick := int(t * 16.0)
				var bursty := hash(int(t * 0.7)) % 3 == 0
				level = 0.75
				if bursty and hash(tick) % 3 != 0:
					level = 0.08
				elif hash(tick * 7) % 23 == 0:
					level = 0.2
			"spark":
				level = _spark_lamp(ci, lx, ly, t)
			_:
				continue
		if level <= 0.01:
			continue
		# Glowing glass.
		var glass := tint
		glass.a = minf(level * 1.2, 1.0)
		ci.draw_rect(Rect2(lx - 5, ly, 11, 1), glass)
		var hot := tint.lightened(0.5)
		hot.a = level
		ci.draw_rect(Rect2(lx - 2, ly, 5, 1), hot)
		# Light cone down to the floor, and the pool it leaves.
		var spread := 46.0
		var cone := tint
		cone.a = 0.05 * level
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(lx - 5, ly + 1), Vector2(lx + 6, ly + 1),
			Vector2(lx + spread, GROUND_Y), Vector2(lx - spread, GROUND_Y),
		]), cone)
		cone.a = 0.045 * level
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(lx - 3, ly + 1), Vector2(lx + 4, ly + 1),
			Vector2(lx + spread * 0.5, GROUND_Y), Vector2(lx - spread * 0.5, GROUND_Y),
		]), cone)
		for k in 3:
			var pool := tint
			pool.a = 0.05 * level * (3 - k)
			var pw := int(spread) + 10 - k * 14
			ci.draw_rect(Rect2(lx - pw, GROUND_Y - 3 + k, pw * 2, 1), pool)
		var halo := tint
		halo.a = 0.1 * level
		ci.draw_rect(Rect2(lx - 9, ly - 3, 19, 6), halo)
		# Dust drifting through the light.
		for m in GameSettings.particle_slots(9, false):
			var h := hash(Vector2i(i, m))
			var depth := float(h % 1000) / 1000.0
			var fall := float(GROUND_Y - ly - 12)
			var my := ly + 8 + fmod(float(h % 97) + t * (3.0 + depth * 4.0), fall)
			var reach := (my - ly) / float(GROUND_Y - ly) * spread * 0.8
			var mx := lx + sin(t * 0.4 + m * 1.7) * reach
			var mote := tint
			mote.a = 0.25 * level * (0.4 + depth)
			ci.draw_rect(Rect2(floorf(mx), floorf(my), 1, 1), mote)


func _line(ci: CanvasItem, a: Vector2i, b: Vector2i, color: Color, thick: int = 1) -> void:
	for p in Geometry2D.bresenham_line(a, b):
		ci.draw_rect(Rect2(p, Vector2(thick, 1)), color)


## The shorted lamp: dark, until it arcs every few seconds with a flash and a shower of sparks.
## Returns how lit it is right now.
func _spark_lamp(ci: CanvasItem, lx: int, ly: int, t: float) -> float:
	var period := 3.2
	var cycle := floori(t / period)
	var since := t - cycle * period - float(hash(cycle) % 100) / 100.0
	if since < 0.0:
		return 0.0
	var level := 0.0
	if since < 0.25 and int(since * 40.0) % 2 == 0:
		level = 0.9
	# Sparks: each falls from the socket on its own arc.
	for k in GameSettings.particle_slots(10, false):
		var h := hash(Vector2i(cycle, k))
		var vx := float(h % 61 - 30)
		var vy := -float((h >> 8) % 30)
		var life := 0.5 + float((h >> 16) % 50) / 100.0
		if since > life:
			continue
		var x := lx + vx * since
		var y := ly + 1 + vy * since + 0.5 * 260.0 * since * since
		var c := SPARK if since < life * 0.5 else AMBER
		c.a = 1.0 - since / life
		ci.draw_rect(Rect2(floorf(x), floorf(y), 1, 1), c)
	return level
