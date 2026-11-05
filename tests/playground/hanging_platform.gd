extends StaticBody2D
## A steel catwalk slung high above the arena on cables, drawn in code to match the floor and
## the steps: a worn tread-plate deck, a hazard-striped fascia, a girder with lightening holes
## and a shallow truss underneath. Four cables run up out of sight into the roof, each with a
## turnbuckle; one has snapped and its loose end hangs down, swaying. A caged work lamp hangs
## under the middle, flickering and throwing an amber cone down, and a red lamp blinks on the
## right end.
##
## The node's origin is the middle of the walking surface. Only the deck collides.

## Walking surface length in pixels.
@export var width: int = 176
## How far the cables run up, in pixels above the deck (past the top of the view).
@export var cable_rise: int = 140

const DEPTH: int = 12
const EDGE := Color(0.38, 0.37, 0.38)
const DECK := Color(0.16, 0.16, 0.18)
const DECK_DARK := Color(0.11, 0.11, 0.125)
const TREAD := Color(0.24, 0.24, 0.26)
const SEAM := Color(0.05, 0.05, 0.06)
const RIVET := Color(0.32, 0.3, 0.29)
const FASCIA := Color(0.09, 0.09, 0.1)
const HAZARD := Color(0.5, 0.35, 0.07)
const GIRDER := Color(0.075, 0.075, 0.085)
const GIRDER_LIGHT := Color(0.13, 0.125, 0.13)
const HOLE := Color(0.015, 0.015, 0.02)
const TRUSS := Color(0.07, 0.07, 0.08)
const CABLE := Color(0.2, 0.2, 0.21)
const CABLE_DARK := Color(0.1, 0.1, 0.11)
const RUST: Array[Color] = [Color(0.3, 0.15, 0.06), Color(0.2, 0.1, 0.05), Color(0.38, 0.2, 0.07)]
const LAMP := Color(1.0, 0.62, 0.22)
const LAMP_HOT := Color(1.0, 0.85, 0.6)
const WARN_RED := Color(1.0, 0.15, 0.08)

var _lights: Lights


## The parts that move or change every frame: the snapped cable, the work lamp and the red lamp.
class Lights extends Node2D:
	var deck_width: int = 176
	var rise: int = 140
	var time: float = 0.0
	var lamp_level: float = 1.0
	var _flicker_left: float = 0.0
	var _flicker_wait: float = 3.0
	var _rng := RandomNumberGenerator.new()
	var _glow: Node2D

	func _ready() -> void:
		_rng.seed = 7071
		_glow = Node2D.new()
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow.material = add
		_glow.draw.connect(_draw_glow)
		add_child(_glow)

	func _process(delta: float) -> void:
		time += delta
		_flicker_wait -= delta
		if _flicker_left > 0.0:
			_flicker_left -= delta
		elif _flicker_wait <= 0.0:
			_flicker_left = _rng.randf_range(0.1, 0.6)
			_flicker_wait = _rng.randf_range(2.0, 7.0)
		var hum := 0.92 + 0.08 * sin(time * 23.0) * sin(time * 1.9)
		if _flicker_left > 0.0:
			hum *= 0.0 if fmod(_flicker_left, 0.09) < 0.05 else 0.5
		lamp_level = hum
		queue_redraw()
		_glow.queue_redraw()

	func _draw() -> void:
		var half := deck_width >> 1
		# The snapped cable: hangs from the roof on the left, its frayed end swinging.
		var top := Vector2(-half + 30, -rise)
		var length := float(rise) - 26.0
		var swing := sin(time * 0.9) * 0.06 + sin(time * 2.3) * 0.015
		var prev := top
		for k in range(1, 41):
			var t := float(k) / 40.0
			var p := top + Vector2(sin(swing * t * 1.6) * length * t, length * t)
			draw_line(prev.round(), p.round(), CABLE_DARK, 1.0)
			prev = p
		for k in 3:
			var d := Vector2(k - 1, 2 + (k % 2)).rotated(swing * 2.0)
			draw_rect(Rect2((prev + d).round(), Vector2.ONE), CABLE)
		# Work lamp: a short chain from the girder, a cage, a bulb.
		var lx := 6
		draw_rect(Rect2(lx, 30, 1, 4), CABLE_DARK)
		draw_rect(Rect2(lx - 3, 34, 7, 1), GIRDER_LIGHT)
		var bulb := LAMP.lerp(LAMP_HOT, 0.5)
		bulb.a = 0.25 + 0.75 * lamp_level
		draw_rect(Rect2(lx - 1, 35, 3, 2), bulb)
		for cx in [lx - 3, lx, lx + 3]:
			draw_rect(Rect2(cx, 35, 1, 3), CABLE_DARK)
		draw_rect(Rect2(lx - 3, 38, 7, 1), CABLE_DARK)
		# Red lamp on the right end, blinking.
		var on := fmod(time, 1.4) < 0.45
		draw_rect(Rect2(half - 4, -3, 2, 2), WARN_RED if on else Color(0.25, 0.04, 0.03))

	## Additive light: the lamp's cone down and its spill on the girder, and the red lamp's halo.
	func _draw_glow() -> void:
		var lx := 6
		var level := lamp_level
		if level > 0.02:
			for y in range(36, 110):
				var spread := 2 + int((y - 36) * 0.42)
				var c := LAMP
				c.a = 0.11 * level * (1.0 - float(y - 36) / 74.0)
				_glow.draw_rect(Rect2(lx - spread, y, spread * 2 + 1, 1), c)
			var halo := LAMP
			halo.a = 0.22 * level
			_glow.draw_rect(Rect2(lx - 4, 33, 9, 7), halo)
			halo.a = 0.08 * level
			_glow.draw_rect(Rect2(lx - 14, 22, 29, 18), halo)
		if fmod(time, 1.4) < 0.45:
			var red := WARN_RED
			red.a = 0.2
			_glow.draw_rect(Rect2((deck_width >> 1) - 6, -5, 6, 6), red)
			red.a = 0.07
			_glow.draw_rect(Rect2((deck_width >> 1) - 9, -8, 12, 12), red)


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, DEPTH)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, DEPTH * 0.5)
	add_child(col)
	_lights = Lights.new()
	_lights.deck_width = width
	_lights.rise = cable_rise
	add_child(_lights)


func _draw() -> void:
	var half := width >> 1
	var x0 := -half
	var rng := RandomNumberGenerator.new()
	rng.seed = 3313

	# Cables up into the roof, each with a turnbuckle, anchored on lugs at the deck's edge.
	for cx in [x0 + 10, x0 + 52, half - 52, half - 11]:
		var x: int = cx
		draw_rect(Rect2(x, -cable_rise, 1, cable_rise - 4), CABLE)
		draw_rect(Rect2(x + 1, -cable_rise, 1, cable_rise - 4), CABLE_DARK)
		draw_rect(Rect2(x - 1, -18, 4, 5), GIRDER_LIGHT)
		draw_rect(Rect2(x, -17, 2, 3), HOLE)
		draw_rect(Rect2(x - 1, -4, 4, 4), GIRDER_LIGHT)
		draw_rect(Rect2(x, -3, 2, 2), HOLE)
	# Stub of the snapped cable's anchor, torn open.
	draw_rect(Rect2(x0 + 29, -3, 4, 3), GIRDER_LIGHT.darkened(0.3))
	draw_rect(Rect2(x0 + 30, -4, 1, 1), CABLE)

	# Shallow truss under the girder, tapering to the middle.
	for x in range(x0 + 4, half - 4):
		var t := absf(float(x) / float(half))
		var bottom := 22 + int(8.0 * (1.0 - t))
		draw_rect(Rect2(x, bottom, 1, 1), TRUSS.lightened(0.15))
	for x in range(x0 + 4, half - 4, 16):
		var t := absf(float(x) / float(half))
		var bottom := 22 + int(8.0 * (1.0 - t))
		draw_rect(Rect2(x, 22, 1, bottom - 21), TRUSS)
		for p in Geometry2D.bresenham_line(Vector2i(x, 22), Vector2i(x + 8, 22 + int(8.0 * (1.0 - absf(float(x + 8) / float(half))))) ):
			draw_rect(Rect2(p, Vector2.ONE), TRUSS)

	# Girder with lightening holes, rust running down.
	draw_rect(Rect2(x0 + 2, 14, width - 4, 8), GIRDER)
	draw_rect(Rect2(x0 + 2, 14, width - 4, 1), GIRDER_LIGHT)
	draw_rect(Rect2(x0 + 2, 21, width - 4, 1), SEAM)
	for hx in range(x0 + 12, half - 8, 22):
		for dy in range(-2, 3):
			var w := 2 if absi(dy) < 2 else 1
			draw_rect(Rect2(hx - w, 18 + dy, w * 2 + 1, 1), HOLE)
		draw_rect(Rect2(hx + 10, 16, 1, 1), RIVET)
		draw_rect(Rect2(hx + 10, 20, 1, 1), RIVET)
	for k in width / 5:
		var rx := x0 + rng.randi_range(2, width - 3)
		var c := RUST[rng.randi_range(0, RUST.size() - 1)]
		c.a = rng.randf_range(0.3, 0.7)
		var run := rng.randi_range(1, 9)
		draw_rect(Rect2(rx, 15 + rng.randi_range(0, 5), 1, run), c)

	# Fascia with hazard stripes, worn through in patches.
	draw_rect(Rect2(x0, 8, width, 6), FASCIA)
	var worn_until := x0
	for x in range(x0, half):
		if x >= worn_until and rng.randf() < 0.02:
			worn_until = x + rng.randi_range(5, 22)
		for y in range(9, 13):
			if posmod(x + y, 8) < 4:
				var c := HAZARD.darkened(0.75) if x < worn_until else HAZARD
				draw_rect(Rect2(x, y, 1, 1), c)
	draw_rect(Rect2(x0, 13, width, 1), SEAM)

	# Deck: tread plate with seams every 44 px.
	draw_rect(Rect2(x0, 1, width, 7), DECK)
	for x in range(x0 + 1, half - 1, 4):
		var row := 2 if posmod(x - x0, 8) < 4 else 5
		draw_rect(Rect2(x, row, 2, 1), TREAD)
		draw_rect(Rect2(x, row + 1, 2, 1), DECK_DARK)
	for sx in range(x0 + 44, half, 44):
		draw_rect(Rect2(sx, 1, 1, 7), SEAM)
		draw_rect(Rect2(sx + 1, 1, 1, 7), DECK.lightened(0.08))
	for k in width / 4:
		var c := RUST[rng.randi_range(0, RUST.size() - 1)]
		c.a = rng.randf_range(0.25, 0.6)
		draw_rect(Rect2(x0 + rng.randi_range(0, width - 1), rng.randi_range(1, 7), 1, 1), c)
	draw_rect(Rect2(x0, 7, width, 1), SEAM)

	# Worn top edge.
	draw_rect(Rect2(x0, 0, width, 1), EDGE)
	for k in width / 5:
		draw_rect(Rect2(x0 + rng.randi_range(0, width - 1), 0, rng.randi_range(1, 4), 1),
				EDGE.darkened(rng.randf_range(0.2, 0.5)))

	# Hazard end plates.
	for side in [-1, 1]:
		var ex: int = x0 if side < 0 else half - 4
		draw_rect(Rect2(ex, -1, 4, 15), FASCIA)
		for y in range(0, 14):
			for k in 2:
				if posmod(y + k * side, 6) < 3:
					draw_rect(Rect2(ex + 1 + k, y, 1, 1), HAZARD)
		draw_rect(Rect2(ex, -1, 4, 1), EDGE)
