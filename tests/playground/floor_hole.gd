extends Node2D
## A hole torn through the arena floor, for testing falls. Drawn in code: a dark shaft going
## down out of sight, bent and torn deck plating hanging from both lips, and cut cables dangling
## into the dark, one of them still live and spitting sparks now and then.
##
## Below the floor the shaft opens into a deep void the camera follows the robot down into
## when it falls out of the level (see ui/death_watch.gd): dim shaft walls with rivets, girders
## and pipes crossing behind, the odd failing lamp, all sinking into black. It's static art,
## drawn once, so the eye has something to see rushing past.
##
## The node's origin is the middle of the hole at floor level. The floors either side end at its
## edges (the hole itself has no collision).

## Hole width in pixels; must match the gap between the two floor pieces.
@export var width: int = 100

const SHAFT_DEPTH: int = 190
## How deep the void under the floor is drawn, and how wide.
const ABYSS_DEPTH: int = 4200
const ABYSS_HALF_W: int = 640
const VOID := Color(0.008, 0.008, 0.012)
const WALL := Color(0.045, 0.045, 0.052)
const WALL_LIGHT := Color(0.075, 0.073, 0.078)
const GIRDER := Color(0.03, 0.03, 0.036)
const LAMP := Color(1.0, 0.55, 0.16)
## The cable that is still live.
const LIVE: int = 1
const PLATE := Color(0.16, 0.16, 0.18)
const PLATE_DARK := Color(0.09, 0.09, 0.1)
const EDGE := Color(0.38, 0.37, 0.38)
const RUST: Array[Color] = [Color(0.3, 0.15, 0.06), Color(0.2, 0.1, 0.05), Color(0.38, 0.2, 0.07)]
const CABLES: Array[Color] = [Color(0.1, 0.03, 0.03), Color(0.04, 0.045, 0.05), Color(0.12, 0.1, 0.03)]
const SPARK := Color(1.0, 0.8, 0.45)
const ARC := Color(0.55, 0.85, 1.0)

var _time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _spark_wait: float = 1.5
var _arc_left: float = 0.0
var _sparks: Array[Vector4] = []
var _spark_age: Array[Vector2] = []
var _glow: Node2D
## Per cable: x offset from the hole's middle, length, colour index, sway phase.
var _cables: Array[Vector4] = []


func _ready() -> void:
	_rng.seed = 9091
	_cables = [
		Vector4(-width * 0.5 + 6, 34, 0, 0.0),
		Vector4(-width * 0.5 + 11, 58, 2, 1.7),
		Vector4(width * 0.5 - 8, 46, 1, 0.6),
		Vector4(width * 0.5 - 15, 22, 0, 2.9),
	]
	var abyss := Abyss.new()
	abyss.hole_width = width
	abyss.show_behind_parent = true
	add_child(abyss)
	_glow = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


## The void under the floor, drawn once.
class Abyss extends Node2D:
	var hole_width: int = 100

	func _draw() -> void:
		var hw := ABYSS_HALF_W
		# Fade in from the floor's under-structure, then solid black all the way down.
		for y in range(100, 160):
			var c := VOID
			c.a = float(y - 100) / 60.0
			draw_rect(Rect2(-hw, y, hw * 2, 1), c)
		draw_rect(Rect2(-hw, 160, hw * 2, ABYSS_DEPTH - 160), VOID)
		var rng := RandomNumberGenerator.new()
		rng.seed = 6161
		var half := hole_width >> 1
		# Girders and pipes crossing the void behind the shaft, at uneven spacing.
		var y := 230
		while y < ABYSS_DEPTH - 40:
			var fade := _fade(y)
			var w := rng.randi_range(4, 9)
			draw_rect(Rect2(-hw, y, hw * 2, w), GIRDER.lerp(VOID, 1.0 - fade))
			draw_rect(Rect2(-hw, y, hw * 2, 1), WALL.lerp(VOID, 1.0 - fade))
			if rng.randf() < 0.5:
				var py := y + w + rng.randi_range(6, 20)
				draw_rect(Rect2(-hw, py, hw * 2, 3), GIRDER.lightened(0.05).lerp(VOID, 1.0 - fade))
			y += rng.randi_range(120, 260)
		# The shaft's walls going on down, riveted, with a lamp now and then.
		for side in [-1, 1]:
			var x: int = -half - 7 if side < 0 else half + 1
			for wy in range(150, ABYSS_DEPTH, 32):
				var fade := _fade(wy)
				draw_rect(Rect2(x, wy, 6, 31), WALL.lerp(VOID, 1.0 - fade))
				var inner: int = x + 5 if side < 0 else x
				draw_rect(Rect2(inner, wy, 1, 31), WALL_LIGHT.lerp(VOID, 1.0 - fade))
				var rivet := WALL_LIGHT.lightened(0.2).lerp(VOID, 1.0 - fade)
				draw_rect(Rect2(x + 2, wy + 4, 1, 1), rivet)
				draw_rect(Rect2(x + 2, wy + 20, 1, 1), rivet)
		var ly := 330
		var lamp_side := 1
		while ly < ABYSS_DEPTH - 60:
			var fade := _fade(ly)
			var lx: int = half - 1 if lamp_side > 0 else -half
			var dead := rng.randf() < 0.3
			var c := LAMP if not dead else LAMP.darkened(0.8)
			c = c.lerp(VOID, (1.0 - fade) * 0.7)
			draw_rect(Rect2(lx - (1 if lamp_side > 0 else 0), ly, 2, 2), c)
			if not dead:
				for r in [3, 6, 10]:
					var g := LAMP
					g.a = 0.05 * fade
					draw_rect(Rect2(lx - r, ly - r, r * 2 + 2, r * 2 + 2), g)
			lamp_side = -lamp_side
			ly += rng.randi_range(260, 480)
		# A few cables hanging down through the shaft.
		for k in 6:
			var cx := rng.randi_range(-half + 6, half - 6)
			var top := rng.randi_range(200, ABYSS_DEPTH - 400)
			var length := rng.randi_range(60, 220)
			for cy in range(top, top + length, 23):
				draw_rect(Rect2(cx + (1 if (cy / 23) % 2 == 0 else 0), cy, 1, mini(23, top + length - cy)),
						Color(0.06, 0.03, 0.03).lerp(VOID, 1.0 - _fade(cy)))

	## How much of the detail shows at depth y: it sinks into the dark, but never quite all.
	func _fade(y: int) -> float:
		return clampf(1.0 - float(y - 150) / 3600.0, 0.35, 1.0)


func _process(delta: float) -> void:
	_time += delta
	_spark_wait -= delta
	_arc_left = maxf(0.0, _arc_left - delta)
	if _spark_wait <= 0.0:
		_spark_wait = _rng.randf_range(1.2, 4.0)
		_arc_left = 0.08
		var tip := _cable_tip(LIVE)
		for k in _rng.randi_range(4, 9):
			_sparks.append(Vector4(tip.x, tip.y, _rng.randf_range(-30.0, 30.0), _rng.randf_range(-40.0, 10.0)))
			_spark_age.append(Vector2(0.0, _rng.randf_range(0.3, 0.7)))
	var i := 0
	while i < _sparks.size():
		var s := _sparks[i]
		var age := _spark_age[i]
		age.x += delta
		if age.x >= age.y:
			_sparks.remove_at(i)
			_spark_age.remove_at(i)
			continue
		s.w += 170.0 * delta
		s.x += s.z * delta
		s.y += s.w * delta
		_sparks[i] = s
		_spark_age[i] = age
		i += 1
	queue_redraw()
	_glow.queue_redraw()


func _cable_tip(index: int) -> Vector2:
	var c := _cables[index]
	var sway := sin(_time * 1.3 + c.w) * 2.5 + sin(_time * 3.1 + c.w) * 0.6
	return Vector2(c.x + sway, c.y)


func _draw() -> void:
	var half := width >> 1
	# The shaft: darkness deepening downwards, faint ribs of the structure below.
	for y in SHAFT_DEPTH:
		var t := float(y) / float(SHAFT_DEPTH)
		draw_rect(Rect2(-half, y, width, 1), Color(0.01, 0.01, 0.015, clampf(0.55 + t * 0.9, 0.0, 1.0)))
	for ry in [26, 58, 94]:
		var c := Color(0.06, 0.06, 0.07, 0.6 * (1.0 - ry / 120.0))
		draw_rect(Rect2(-half, ry, width, 2), c)
		draw_rect(Rect2(-half, ry, width, 1), c.lightened(0.15))
	# Torn plating bent down from each lip, jagged and rusted.
	var rng := RandomNumberGenerator.new()
	rng.seed = 512
	for side in [-1, 1]:
		var lip: int = -half if side < 0 else half - 1
		# A flap hinged at the lip, hanging down and leaning into the hole, so it never looks
		# like floor you could stand on.
		for k in 7:
			var length := maxi(2, 14 - k * 2 + rng.randi_range(-2, 2))
			for y in range(k * 2, k * 2 + length):
				var px: int = lip - side * k
				var c := PLATE if (y + k) % 5 != 0 else PLATE_DARK
				if rng.randf() < 0.25:
					c = RUST[rng.randi_range(0, RUST.size() - 1)]
				draw_rect(Rect2(px, 3 + y, 1, 1), c)
	# Cut cables dangling into the dark.
	for i in _cables.size():
		var c := _cables[i]
		var tip := _cable_tip(i)
		var root := Vector2(c.x, 2)
		var prev := root
		for k in range(1, 13):
			var t := float(k) / 12.0
			var p := root.lerp(tip, t) + Vector2(0, sin(t * PI) * 1.5)
			p.x = lerpf(root.x, tip.x, t * t)
			draw_line(prev.round(), p.round(), CABLES[int(c.z)], 1.0)
			prev = p
		draw_rect(Rect2(tip.round() + Vector2(-1, 0), Vector2(3, 1)), Color(0.5, 0.35, 0.2))


func _draw_glow() -> void:
	var tip := _cable_tip(LIVE)
	if _arc_left > 0.0:
		_glow.draw_rect(Rect2(tip.round() + Vector2(-1, 0), Vector2(3, 2)), ARC)
		var halo := ARC
		halo.a = 0.25
		_glow.draw_rect(Rect2(tip.round() + Vector2(-4, -3), Vector2(9, 8)), halo)
		halo.a = 0.08
		_glow.draw_rect(Rect2(tip.round() + Vector2(-10, -9), Vector2(21, 20)), halo)
	for k in _sparks.size():
		var s := _sparks[k]
		var age := _spark_age[k]
		var c := SPARK.lerp(Color(1.0, 0.45, 0.1), age.x / age.y)
		c.a = 1.0 - age.x / age.y
		_glow.draw_rect(Rect2(floorf(s.x), floorf(s.y), 1, 1), c)
