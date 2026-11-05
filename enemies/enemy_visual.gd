class_name EnemyVisual
extends Node2D
## Base for drawing an enemy pixel by pixel, procedurally: each frame the subclass works out its
## joints (in "joint space": px from the feet, x pointing the way the enemy faces, y pointing
## up), plots lines and blobs between them, and this draws them with a 1 px dark silhouette
## outline like the robot's, snapped to whole pixels.
##
## Tools for procedural animation:
## - Foot: a foot that stays planted on the ground where it was put and only steps (in a small
##   arc) when the body has moved too far from it. Feet find the ground with ray casts.
## - solve_ik(): a two-bone limb reaching for a point, bending one way or the other.
## - Spring: a damped spring (for ears, heads, tails) that can be shoved by the body's
##   acceleration, so loose parts lag and bounce.

const OUTLINE := Color(0.04, 0.04, 0.05)

## The enemy this draws: its facing, velocity and state.
var body: Enemy
## Seconds since it appeared.
var time: float = 0.0
## The body's acceleration this frame (px/s²), for springs.
var accel := Vector2.ZERO

var _pixels: Dictionary = {}
var _last_velocity := Vector2.ZERO


func _ready() -> void:
	if body == null:
		body = get_parent() as Enemy


func _process(delta: float) -> void:
	if body == null or delta <= 0.0:
		return
	time += delta
	accel = (body.velocity - _last_velocity) / delta
	_last_velocity = body.velocity
	# Keep the drawing on whole pixels wherever the body is.
	position = body.global_position.round() - body.global_position
	_animate(delta)
	queue_redraw()


## Override: move the joints for this frame.
func _animate(_delta: float) -> void:
	pass


## Override: plot the body with plot(), line() and blob(), then call draw_pixels().
func _draw() -> void:
	pass


# --- Space -------------------------------------------------------------------------------------


## World point to joint space.
func to_joint(world: Vector2) -> Vector2:
	var d := world - body.global_position
	return Vector2(d.x * body.facing, -d.y)


## Joint-space point to world.
func to_world(joint: Vector2) -> Vector2:
	return body.global_position + Vector2(joint.x * body.facing, -joint.y)


## World y of the ground under world x, looking from up px above the feet to down px below.
## The feet's own height when there's nothing.
func ground_y(world_x: float, up: float = 6.0, down: float = 8.0) -> float:
	var depth := body.ground_depth_at(world_x, up, down)
	return body.global_position.y + (depth if depth != INF else 0.0)


# --- Limbs -------------------------------------------------------------------------------------


## The middle joint of a two-bone limb from root reaching for tip (both in joint space), with
## bone lengths a and b. bend 1 puts the joint on the left of root->tip, -1 on the right.
static func solve_ik(root: Vector2, tip: Vector2, a: float, b: float, bend: float) -> Vector2:
	var to_tip := tip - root
	var d := clampf(to_tip.length(), absf(a - b) + 0.01, a + b - 0.01)
	var dir := to_tip.normalized() if to_tip.length() > 0.001 else Vector2.DOWN
	var cos_angle := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	return root + dir.rotated(acos(cos_angle) * bend) * a


## A foot that stays where it was put on the ground until the body has moved on far enough,
## then steps to its new spot in a small arc.
class Foot:
	## Where it is, in world space.
	var pos := Vector2.ZERO
	var planted: bool = true
	## Step progress, 0 to 1, from step_from to step_to.
	var t: float = 1.0
	var step_from := Vector2.ZERO
	var step_to := Vector2.ZERO
	var step_time: float = 0.12
	var lift: float = 1.5

	## Moves towards spot (world): steps there when it's more than reach px away and allowed
	## (so pairs of feet can take turns). Returns true while stepping.
	func update(spot: Vector2, reach: float, allowed: bool, delta: float) -> bool:
		if t < 1.0:
			t = minf(t + delta / maxf(step_time, 0.01), 1.0)
			# Keep aiming at the latest spot while the foot is in the air.
			step_to = spot
			pos = step_from.lerp(step_to, t) + Vector2(0.0, -sin(t * PI) * lift)
			return t < 1.0
		if allowed and pos.distance_to(spot) > reach:
			step_from = pos
			step_to = spot
			t = 0.0
			return true
		return false

	func is_stepping() -> bool:
		return t < 1.0

	## Puts the foot straight down at spot.
	func place(spot: Vector2) -> void:
		pos = spot
		t = 1.0


## A damped 2D spring: offset springs back to zero, shoved around by kicks.
class Spring:
	var offset := Vector2.ZERO
	var velocity := Vector2.ZERO
	var stiffness: float = 260.0
	var damping: float = 12.0

	func _init(k: float = 260.0, c: float = 12.0) -> void:
		stiffness = k
		damping = c

	## Steps the spring, with force a push (px/s²), and returns the offset.
	func update(push: Vector2, delta: float, limit: float = 4.0) -> Vector2:
		velocity += (-offset * stiffness - velocity * damping + push) * delta
		offset += velocity * delta
		offset = offset.limit_length(limit)
		return offset


# --- Plotting ----------------------------------------------------------------------------------


## Pixel cell for a joint-space point; y = 0 is the row just above the floor.
func cell(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x * body.facing), -roundi(point.y) - 1)


func plot(point: Vector2, color: Color) -> void:
	_pixels[cell(point)] = color


## A 1 px line between two joint-space points.
func line(a: Vector2, b: Vector2, color: Color) -> void:
	var from := cell(a)
	var to := cell(b)
	var dx := absi(to.x - from.x)
	var dy := -absi(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var err := dx + dy
	var cur := from
	while true:
		_pixels[cur] = color
		if cur == to:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			cur.x += sx
		if e2 <= dx:
			err += dx
			cur.y += sy


func blob(center: Vector2, radius: float, color: Color) -> void:
	var r := ceili(radius)
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if Vector2(x, y).length() <= radius + 0.3:
				plot(center + Vector2(x, y), color)


## Draws everything plotted this frame, with the dark outline (never into the floor). While the
## body is sinking into the floor (Enemy.sink), it's drawn that much lower and what's under the
## floor is cut off.
func draw_pixels() -> void:
	var sunk := roundi(body.sink)
	if sunk > 0:
		var moved := {}
		for c: Vector2i in _pixels:
			var n := c + Vector2i(0, sunk)
			if n.y < 0:
				moved[n] = _pixels[c]
		_pixels = moved
	if body.dead and body.remains < 1.0:
		# A wreck being eaten: pixels go, scattered, until nothing's left.
		var kept := {}
		for c: Vector2i in _pixels:
			if _cell_noise(c) < body.remains:
				kept[c] = _pixels[c]
		_pixels = kept
	var edge := {}
	for c: Vector2i in _pixels:
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + offset
			if n.y < 0 and not _pixels.has(n):
				edge[n] = true
	for c: Vector2i in edge:
		_pixels[c] = OUTLINE
	for c: Vector2i in _pixels:
		draw_rect(Rect2(Vector2(c), Vector2.ONE), _pixels[c])
	_pixels.clear()


## A fixed pseudo-random 0 to 1 for a pixel cell.
static func _cell_noise(c: Vector2i) -> float:
	var h := (c.x * 73856093) ^ (c.y * 19349663)
	return float(absi(h) % 1000) / 1000.0


## A glow pixel cross around a joint-space point, drawn over everything (after draw_pixels).
func glow(point: Vector2, color: Color) -> void:
	var e := cell(point) + Vector2i(0, roundi(body.sink))
	if e.y >= 0:
		return
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		draw_rect(Rect2(Vector2(e + offset), Vector2.ONE), color)
