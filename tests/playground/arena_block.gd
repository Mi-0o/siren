extends StaticBody2D
## A solid block standing on the arena floor, drawn in code to match it: a tread-plate top with
## a worn edge, then a body that gets more detail the taller it is. A low one is just a slab
## with hazard ends; taller ones get a framed steel body, a hazard band, a vent grille with an
## amber glow behind it and, on the tallest, corrugated ribs like a cargo container. A small
## status lamp blinks on each.
##
## The node's origin is the middle of the block's bottom edge, so it sits on the floor at y 0.

@export var size: Vector2i = Vector2i(80, 20)
## Changes the rust, wear and lamp timing between blocks.
@export var variant: int = 0

const EDGE := Color(0.38, 0.37, 0.38)
const DECK := Color(0.16, 0.16, 0.18)
const TREAD := Color(0.24, 0.24, 0.26)
const DECK_DARK := Color(0.11, 0.11, 0.125)
const SEAM := Color(0.05, 0.05, 0.06)
const BODY := Color(0.1, 0.1, 0.115)
const BODY_LIGHT := Color(0.15, 0.148, 0.155)
const BODY_DARK := Color(0.06, 0.06, 0.07)
const RIVET := Color(0.32, 0.3, 0.29)
const HAZARD := Color(0.5, 0.35, 0.07)
const GRILLE := Color(0.025, 0.025, 0.03)
const GLOW := Color(1.0, 0.55, 0.15)
const RUST: Array[Color] = [Color(0.3, 0.15, 0.06), Color(0.2, 0.1, 0.05), Color(0.38, 0.2, 0.07)]
const LAMP_COLORS: Array[Color] = [
	Color(0.35, 0.95, 1.0), Color(1.0, 0.6, 0.18), Color(0.35, 0.95, 0.45), Color(1.0, 0.2, 0.1),
]


## The lamp and the glow behind the vents, redrawn every frame.
class Lights extends Node2D:
	var block_size: Vector2i
	var variant: int = 0
	var time: float = 0.0
	var vent: Rect2i = Rect2i()

	func _process(delta: float) -> void:
		time += delta
		queue_redraw()

	func _draw() -> void:
		var w := block_size.x
		var h := block_size.y
		var x0 := -(w >> 1)
		# Status lamp near the top right corner.
		var period := 1.1 + variant * 0.37
		var on := fmod(time + variant * 0.5, period) < period * 0.35
		var c: Color = LAMP_COLORS[variant % LAMP_COLORS.size()]
		var ly := -h + (5 if h > 10 else 3)
		var lx := x0 + w - 7
		if h <= 10:
			ly = -h + 4
		c.a = 1.0 if on else 0.18
		draw_rect(Rect2(lx, ly, 2, 1), c)
		if on:
			var halo := c
			halo.a = 0.15
			draw_rect(Rect2(lx - 2, ly - 2, 6, 5), halo)
		# Amber glow breathing behind the vent slots.
		if vent.size.x > 0:
			var level := 0.35 + 0.25 * sin(time * 2.3 + variant)
			if hash(int(time * 9.0) + variant * 31) % 13 == 0:
				level *= 0.3
			for y in range(vent.position.y + 1, vent.end.y, 2):
				var g := GLOW
				g.a = level
				draw_rect(Rect2(vent.position.x + 1, y, vent.size.x - 2, 1), g)
			var bloom := GLOW
			bloom.a = 0.06 * level
			draw_rect(Rect2(vent.grow(3)), bloom)


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(size)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, -size.y * 0.5)
	add_child(col)
	var lights := Lights.new()
	lights.block_size = size
	lights.variant = variant
	lights.vent = _vent_rect()
	add_child(lights)


## Where the vent grille goes, or an empty rect when the block is too low for one.
func _vent_rect() -> Rect2i:
	if size.y < 28:
		return Rect2i()
	var vw := 18
	return Rect2i(-(size.x >> 1) + 8, -size.y + 9, vw, mini(11, size.y - 20))


func _draw() -> void:
	var w := size.x
	var h := size.y
	var x0 := -(w >> 1)
	var top := -h
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150 + variant * 77

	# Contact shadow on the floor.
	draw_rect(Rect2(x0 - 2, 0, w + 4, 1), Color(0, 0, 0, 0.45))

	# Body.
	draw_rect(Rect2(x0, top, w, h), BODY)
	if h > 10:
		# Frame: lit left edge, dark right edge and bottom.
		draw_rect(Rect2(x0, top + 5, 1, h - 5), BODY_LIGHT)
		draw_rect(Rect2(x0 + w - 1, top + 5, 1, h - 5), BODY_DARK)
		draw_rect(Rect2(x0, -1, w, 1), BODY_DARK)
		draw_rect(Rect2(x0 + 2, top + 6, 1, h - 8), BODY_DARK)
		draw_rect(Rect2(x0 + w - 3, top + 6, 1, h - 8), BODY_LIGHT.darkened(0.3))
		for y in range(top + 8, -2, 6):
			draw_rect(Rect2(x0 + 1, y, 1, 1), RIVET)
			draw_rect(Rect2(x0 + w - 2, y, 1, 1), RIVET.darkened(0.3))
	if h >= 40:
		# Corrugated ribs, like a cargo container.
		for x in range(x0 + 5, x0 + w - 4, 4):
			draw_rect(Rect2(x, top + 6, 1, h - 9), BODY_LIGHT.darkened(0.1))
			draw_rect(Rect2(x + 2, top + 6, 1, h - 9), BODY_DARK)
	if h >= 18:
		# Hazard band low on the front, scuffed.
		var band_y := -6
		for x in range(x0 + 3, x0 + w - 3):
			for y in range(band_y, band_y + 3):
				if posmod(x + y + variant, 8) < 4 and hash(Vector2i(x, y + variant)) % 7 != 0:
					draw_rect(Rect2(x, y, 1, 1), HAZARD)
		draw_rect(Rect2(x0 + 3, band_y - 1, w - 6, 1), SEAM)
	var vent := _vent_rect()
	if vent.size.x > 0:
		draw_rect(Rect2(vent.grow(1)), BODY_DARK)
		draw_rect(Rect2(vent), GRILLE)
		for y in range(vent.position.y, vent.end.y, 2):
			draw_rect(Rect2(vent.position.x, y, vent.size.x, 1), BODY_LIGHT.darkened(0.2))
		# A label plate beside the vent.
		var plate := Rect2(vent.end.x + 5, vent.position.y + 1, 14, 6)
		draw_rect(plate, BODY_DARK)
		draw_rect(Rect2(plate.position.x + 2, plate.position.y + 2, 6, 1), TREAD)
		draw_rect(Rect2(plate.position.x + 2, plate.position.y + 4, 9, 1), TREAD.darkened(0.3))
	if h <= 10:
		# A low slab: hazard chevrons on both ends instead.
		for side in [0, 1]:
			var ex: int = x0 if side == 0 else x0 + w - 5
			for y in range(top + 4, 0):
				for k in 5:
					if posmod(y + k, 4) < 2:
						draw_rect(Rect2(ex + k, y, 1, 1), HAZARD)
	# Rust specks and runs.
	for k in maxi(floori(w * h / 60.0), 4):
		var rx := x0 + rng.randi_range(1, w - 2)
		var ry := rng.randi_range(top + 4, -2)
		var c: Color = RUST[rng.randi_range(0, RUST.size() - 1)]
		c.a = rng.randf_range(0.3, 0.7)
		draw_rect(Rect2(rx, ry, 1, mini(rng.randi_range(1, 4), -1 - ry)), c)

	# Tread-plate top, the same as the floor's.
	draw_rect(Rect2(x0, top, w, 4), DECK)
	for x in range(x0 + 1, x0 + w - 1, 4):
		var row := top + (1 if posmod(x - x0, 8) < 4 else 2)
		draw_rect(Rect2(x, row, 2, 1), TREAD)
	draw_rect(Rect2(x0, top + 3, w, 1), DECK_DARK)
	draw_rect(Rect2(x0, top + 4, w, 1), SEAM)
	draw_rect(Rect2(x0, top, w, 1), EDGE)
	for k in floori(w / 6.0):
		var ex := x0 + rng.randi_range(0, w - 1)
		var worn := EDGE.darkened(rng.randf_range(0.2, 0.5))
		draw_rect(Rect2(ex, top, rng.randi_range(1, 3), 1), worn)
	# Corner bolts on the top plate.
	draw_rect(Rect2(x0 + 2, top + 2, 1, 1), RIVET)
	draw_rect(Rect2(x0 + w - 3, top + 2, 1, 1), RIVET)
