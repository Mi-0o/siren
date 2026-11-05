class_name WireVisual
extends Node2D
## Draws the robot's wire as pixel art: a one-pixel steel cable whose pixels cycle through
## light, mid and dark steel along its length, like the twisted strands of a wound cable catching
## the light. A small forged grappling hook sits at the tip: a shank with an eye for the cable at
## the back and two barbed prongs swept back from the point. It points the way it flew, stays
## that way once it has bitten, and trails behind the cable while being wound back in.
##
## The Player owns one (top_level, so it draws in world space) and hands it the rope's points
## and the hook's direction each frame.

## Strand colours along the cable, repeating every three pixels.
const STRANDS: Array[Color] = [
	Color(0.74, 0.76, 0.78), Color(0.52, 0.54, 0.57), Color(0.36, 0.37, 0.4),
]
const HOOK_DARK := Color(0.2, 0.21, 0.23)
const HOOK_MID := Color(0.46, 0.48, 0.51)
const HOOK_LIGHT := Color(0.8, 0.82, 0.84)

## The hook, drawn pixel by pixel for two headings, [x, y, shade] with shade 0 dark, 1 mid,
## 2 light. Other headings turn these by quarter turns, so it stays crisp in all eight
## directions. Pointing right (+x):
const HOOK_STRAIGHT: Array = [
	# Point and shank.
	[2, 0, 2], [1, 0, 2], [0, 0, 1], [-1, 0, 1], [-2, 0, 1], [-3, 0, 0],
	# Eye the cable is tied through.
	[-4, -1, 0], [-4, 1, 0], [-5, 0, 0],
	# Prongs swept back from the head; the lower one in shadow.
	[1, -1, 1], [0, -2, 1], [-1, -2, 2],
	[1, 1, 1], [0, 2, 0], [-1, 2, 0],
]
## Pointing up and right (+x, -y):
const HOOK_DIAGONAL: Array = [
	[2, -2, 2], [1, -1, 2], [0, 0, 1], [-1, 1, 1], [-2, 2, 1], [-3, 3, 0],
	[-4, 3, 0], [-3, 4, 0], [-4, 4, 1],
	[1, -2, 1], [0, -2, 1], [-1, -3, 2],
	[2, -1, 1], [2, 0, 0], [3, 1, 0],
]

## The cable, from the launcher to the hook, in global coordinates.
var rope: PackedVector2Array = []
## Which way the hook points (unit vector), and whether it's out at all.
var hook_dir: Vector2 = Vector2.RIGHT
var shown: bool = false


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if not shown or rope.size() < 2:
		return
	_draw_cable()
	_draw_hook(rope[rope.size() - 1])


func _draw_cable() -> void:
	var seen := {}
	var last := Vector2i(2147483647, 0)
	var n := 0
	# The last stretch runs into the hook's eye, which covers it.
	var tip := rope[rope.size() - 1]
	for i in rope.size() - 1:
		var a := rope[i]
		var b := rope[i + 1]
		var steps := maxi(ceili(a.distance_to(b) * 2.0), 1)
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps)
			var px := Vector2i(floori(p.x), floori(p.y))
			if px == last:
				continue
			last = px
			if seen.has(px) or Vector2(px).distance_to(tip) < 6.0:
				continue
			seen[px] = true
			draw_rect(Rect2(Vector2(px), Vector2.ONE), STRANDS[n % STRANDS.size()])
			n += 1


func _draw_hook(at: Vector2) -> void:
	var dir := hook_dir if hook_dir.length() > 0.01 else Vector2.RIGHT
	# Nearest of the eight headings: even ones use the straight hook, odd ones the diagonal,
	# each turned by quarter turns (exact on the pixel grid).
	var octant := posmod(roundi(dir.angle() / (PI / 4.0)), 8)
	var sprite: Array = HOOK_STRAIGHT
	var turns := octant / 2
	if octant % 2 == 1:
		sprite = HOOK_DIAGONAL
		# The diagonal is drawn pointing up-right (octant 7).
		turns = posmod((octant + 1) / 2, 4)
	var tip := Vector2(floorf(at.x), floorf(at.y))
	# Dark pixels first so the lighter ones win wherever they meet.
	for shade in 3:
		for p: Array in sprite:
			if p[2] != shade:
				continue
			var v := Vector2(p[0], p[1])
			for t in turns:
				v = Vector2(-v.y, v.x)
			# The point (2 px ahead of the head) sits on the tip.
			var lead := Vector2(2, 0) if sprite == HOOK_STRAIGHT else Vector2(2, -2)
			for t in turns:
				lead = Vector2(-lead.y, lead.x)
			var color := HOOK_DARK if shade == 0 else (HOOK_MID if shade == 1 else HOOK_LIGHT)
			draw_rect(Rect2(tip + v - lead, Vector2.ONE), color)
