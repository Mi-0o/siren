extends StaticBody2D
## The test arena's floor: one long industrial steel platform, drawn in code at native pixel
## scale. The node's origin is the middle of the walking surface; the collision box is built
## from width and depth at startup.
##
## From the top down: a worn edge, a tread-plate deck with seams and rivets, a fascia with
## flaking hazard stripes, a channel of cyan LEDs (most of them dead, a couple failing), a
## rusted girder with lightening holes, and support trusses fading into the dark below. Each end
## has a hazard-striped end plate and a red warning lamp, so the edge is easy to spot.

## Walking surface length in pixels.
@export var width: int = 2000
## Collision depth below the surface.
@export var depth: int = 40

const DRAW_DEPTH: int = 140
const EDGE := Color(0.38, 0.37, 0.38)
const DECK := Color(0.16, 0.16, 0.18)
const DECK_DARK := Color(0.11, 0.11, 0.125)
const TREAD := Color(0.24, 0.24, 0.26)
const SEAM := Color(0.05, 0.05, 0.06)
const RIVET := Color(0.32, 0.3, 0.29)
const FASCIA := Color(0.09, 0.09, 0.1)
const HAZARD := Color(0.5, 0.35, 0.07)
const CHANNEL := Color(0.02, 0.025, 0.03)
const GIRDER := Color(0.075, 0.075, 0.085)
const GIRDER_LIGHT := Color(0.13, 0.125, 0.13)
const HOLE := Color(0.015, 0.015, 0.02)
const TRUSS := Color(0.06, 0.06, 0.07)
const RUST: Array[Color] = [Color(0.3, 0.15, 0.06), Color(0.2, 0.1, 0.05), Color(0.38, 0.2, 0.07)]
const LED_ON := Color(0.35, 0.95, 1.0)
const LED_DEAD := Color(0.06, 0.12, 0.13)
const LED_STEP: int = 6
const LED_Y: int = 16
const WARN_RED := Color(1.0, 0.15, 0.08)

var _lights: Lights


## The parts that change every frame: the LED strip and the end lamps.
class Lights extends Node2D:
	var floor_width: int = 2000
	var time: float = 0.0
	## Per LED: 0 dead, 1 lit, 2 failing (flickers).
	var states: PackedByteArray

	func _process(delta: float) -> void:
		time += delta
		queue_redraw()

	func _draw() -> void:
		var half := floor_width >> 1
		var count := states.size()
		for i in count:
			var state := states[i]
			if state == 0:
				continue
			var x := -half + 4 + i * LED_STEP
			var level := 0.75
			if state == 2:
				var tick := int(time * 18.0 + i * 7)
				level = 0.0 if hash(Vector2i(tick, i)) % 5 < 2 else 0.9
			if level <= 0.0:
				continue
			var c := LED_ON
			c.a = level
			draw_rect(Rect2(x, LED_Y, 3, 1), c)
			var glow := LED_ON
			glow.a = 0.12 * level
			draw_rect(Rect2(x - 1, LED_Y - 1, 5, 3), glow)
		# Red lamps on the end plates, blinking.
		var on := fmod(time, 1.2) < 0.5
		for side in [-1, 1]:
			var lx: int = side * half - (3 if side > 0 else -1)
			var c := WARN_RED if on else Color(0.25, 0.04, 0.03)
			draw_rect(Rect2(lx, -4, 2, 3), c)
			if on:
				var halo := WARN_RED
				halo.a = 0.18
				draw_rect(Rect2(lx - 2, -6, 6, 7), halo)
				halo.a = 0.07
				draw_rect(Rect2(lx - 5, -9, 12, 13), halo)


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, depth)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, depth * 0.5)
	add_child(col)
	_lights = Lights.new()
	_lights.floor_width = width
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var count := floori(float(width - 8) / LED_STEP)
	_lights.states.resize(count)
	# Runs of working LEDs between long dead stretches, with the odd failing one.
	var i := 0
	while i < count:
		var run := rng.randi_range(3, 18)
		var lit := rng.randf() < 0.45
		for k in run:
			if i >= count:
				break
			var state := 1 if lit else 0
			if lit and rng.randf() < 0.08:
				state = 2
			elif not lit and rng.randf() < 0.03:
				state = 2
			_lights.states[i] = state
			i += 1
	add_child(_lights)


func _draw() -> void:
	var half := width >> 1
	var x0 := -half
	var rng := RandomNumberGenerator.new()
	rng.seed = 4410

	# Under-structure first: trusses down into the dark.
	_draw_trusses(x0, rng)

	# Girder under the deck, with lightening holes and rust.
	draw_rect(Rect2(x0, 21, width, 22), GIRDER)
	draw_rect(Rect2(x0, 21, width, 1), GIRDER_LIGHT)
	draw_rect(Rect2(x0, 42, width, 1), SEAM)
	for hx in range(x0 + 20, half - 10, 40):
		_hole(hx, 31)
		draw_rect(Rect2(hx + 18, 23, 1, 18), SEAM)
		draw_rect(Rect2(hx + 19, 23, 1, 18), GIRDER_LIGHT.darkened(0.3))
		draw_rect(Rect2(hx + 17, 24, 1, 1), RIVET)
		draw_rect(Rect2(hx + 17, 39, 1, 1), RIVET)
	for k in floori(width / 14.0):
		var rx := x0 + rng.randi_range(0, width - 1)
		var ry := rng.randi_range(22, 40)
		var c := RUST[rng.randi_range(0, RUST.size() - 1)]
		c.a = rng.randf_range(0.3, 0.7)
		var run := rng.randi_range(1, 6)
		draw_rect(Rect2(rx, ry, 1, mini(run, 43 - ry)), c)

	# LED channel.
	draw_rect(Rect2(x0, 14, width, 7), FASCIA)
	draw_rect(Rect2(x0, LED_Y - 1, width, 3), CHANNEL)
	for i in _lights.states.size():
		if _lights.states[i] == 0:
			draw_rect(Rect2(x0 + 4 + i * LED_STEP, LED_Y, 3, 1), LED_DEAD)
	draw_rect(Rect2(x0, 20, width, 1), SEAM)

	# Fascia with hazard stripes, worn through in patches.
	draw_rect(Rect2(x0, 8, width, 6), FASCIA)
	var wear := RandomNumberGenerator.new()
	wear.seed = 99
	var worn_until := x0
	for x in range(x0, half):
		if x >= worn_until and wear.randf() < 0.004:
			worn_until = x + wear.randi_range(8, 60)
		for y in range(9, 13):
			if posmod(x + y, 8) < 4:
				var c := HAZARD
				if x < worn_until:
					c = HAZARD.darkened(0.75)
				elif hash(Vector2i(x, y)) % 9 == 0:
					c = HAZARD.darkened(0.5)
				draw_rect(Rect2(x, y, 1, 1), c)
	draw_rect(Rect2(x0, 13, width, 1), SEAM)

	# Deck: tread plate with seams every 64 px.
	draw_rect(Rect2(x0, 1, width, 7), DECK)
	for x in range(x0 + 1, half - 1, 4):
		var row := 2 if posmod(x - x0, 8) < 4 else 5
		draw_rect(Rect2(x, row, 2, 1), TREAD)
		draw_rect(Rect2(x, row + 1, 2, 1), DECK_DARK)
	for sx in range(x0 + 64, half, 64):
		draw_rect(Rect2(sx, 1, 1, 7), SEAM)
		draw_rect(Rect2(sx + 1, 1, 1, 7), DECK.lightened(0.08))
		for ry in [2, 6]:
			draw_rect(Rect2(sx - 2, ry, 1, 1), RIVET)
			draw_rect(Rect2(sx + 3, ry, 1, 1), RIVET)
	# Grime and rust spots on the deck.
	for k in floori(width / 6.0):
		var gx := x0 + rng.randi_range(0, width - 1)
		var gy := rng.randi_range(1, 7)
		var c := RUST[rng.randi_range(0, RUST.size() - 1)]
		c.a = rng.randf_range(0.25, 0.6)
		draw_rect(Rect2(gx, gy, 1, 1), c)
	draw_rect(Rect2(x0, 7, width, 1), SEAM)

	# Worn top edge: bright where boots scuffed it, dull elsewhere.
	draw_rect(Rect2(x0, 0, width, 1), EDGE)
	for k in floori(width / 5.0):
		var ex := x0 + rng.randi_range(0, width - 1)
		draw_rect(Rect2(ex, 0, rng.randi_range(1, 4), 1), EDGE.darkened(rng.randf_range(0.2, 0.5)))

	_draw_end(x0, 1)
	_draw_end(half - 6, -1)


## Vertical posts every 160 px with X bracing, darkening with depth.
func _draw_trusses(x0: int, rng: RandomNumberGenerator) -> void:
	var post_xs: Array[int] = []
	for px in range(x0 + 40, (width >> 1) - 20, 160):
		post_xs.append(px)
	for px in post_xs:
		for y in range(43, DRAW_DEPTH):
			var fade := 1.0 - float(y - 43) / float(DRAW_DEPTH - 43)
			draw_rect(Rect2(px, y, 5, 1), TRUSS.lerp(Color.BLACK, 1.0 - fade))
			draw_rect(Rect2(px, y, 1, 1), GIRDER_LIGHT.lerp(Color.BLACK, 1.0 - fade * 0.7))
	for i in post_xs.size() - 1:
		var a := post_xs[i] + 5
		var b := post_xs[i + 1]
		for y0 in [44, 90]:
			_fading_line(Vector2i(a, y0), Vector2i(b, y0 + 44))
			_fading_line(Vector2i(a, y0 + 44), Vector2i(b, y0))
		# A cable sagging between the posts.
		if rng.randf() < 0.6:
			var sag := rng.randi_range(8, 20)
			var cable := Color(0.1, 0.03, 0.03) if rng.randf() < 0.3 else Color(0.04, 0.045, 0.05)
			for x in range(a, b):
				var t := float(x - a) / float(b - a)
				var y := 45 + int(sag * 4.0 * t * (1.0 - t))
				draw_rect(Rect2(x, y, 1, 1), cable)


func _fading_line(a: Vector2i, b: Vector2i) -> void:
	for p in Geometry2D.bresenham_line(a, b):
		var fade := 1.0 - float(p.y - 43) / float(DRAW_DEPTH - 43)
		draw_rect(Rect2(p, Vector2.ONE), TRUSS.lerp(Color.BLACK, clampf(1.0 - fade, 0.0, 1.0)))


## A round lightening hole in the girder, 9 px across, with a lit lower rim.
func _hole(cx: int, cy: int) -> void:
	for dy in range(-4, 5):
		var w := 4 if absi(dy) < 3 else (3 if absi(dy) == 3 else 1)
		draw_rect(Rect2(cx - w, cy + dy, w * 2 + 1, 1), HOLE)
	draw_rect(Rect2(cx - 2, cy + 5, 5, 1), GIRDER_LIGHT)


## Hazard-striped end plate, 6 px wide, at x (facing outwards on side).
func _draw_end(x: int, side: int) -> void:
	draw_rect(Rect2(x, -2, 6, 45), FASCIA)
	for y in range(-1, 42):
		for k in 4:
			if posmod(y + k * side, 6) < 3:
				draw_rect(Rect2(x + 1 + k, y, 1, 1), HAZARD)
	draw_rect(Rect2(x, -2, 6, 1), EDGE)
