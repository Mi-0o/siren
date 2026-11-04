extends "res://charging_station/charging_station.gd"
## Repair station: a charging station with a scrapyard workshop behind the pad, a shelving unit
## and a workbench cluttered with spare robot parts and tools. Green lights say what it does
## without words: a lit wrench sign on top of the shelves, and three part lamps (core, legs,
## systems, the same icons as the HUD) on the right upright.
##
## It charges like any station. On top of that, once a body that can be repaired (it has
## get_damage() and set_damage()) has stood still for charge_delay, every damaged part steps one
## state towards healthy each repair_step_time: fault to heavy, heavy to mild, mild to healthy.
## Green weld sparks fly off the robot while it works.
##
## The part lamps are dim on standby. With a robot on the pad they show its parts: steady green
## when healthy, a slow blink while waiting to start, a fast blink while being repaired.
##
## Drawn in code like the charging station; the workshop sits behind the pad and the robot.

const GREEN := Color(0.25, 0.95, 0.45)
const GREEN_HOT := Color(0.75, 1.0, 0.8)
const GREEN_DIM := Color(0.05, 0.17, 0.09)
const SHELF_LIGHT := Color(0.24, 0.22, 0.21)
const SHELF_MID := Color(0.15, 0.14, 0.14)
const SHELF_DARK := Color(0.08, 0.08, 0.09)
const BENCH_TOP := Color(0.3, 0.27, 0.25)
const TOOLBOX_RED := Color(0.36, 0.1, 0.07)
const WIRE_RED := Color(0.55, 0.12, 0.08)
const WIRE_BLUE := Color(0.15, 0.27, 0.45)
const WIRE_YELLOW := Color(0.55, 0.45, 0.1)
## Part icons (core, legs, systems), the same as the HUD's.
const PART_ICONS: Array = [
	[".111.", "1...1", "1.1.1", "1...1", ".111."],
	[".111.", ".1.1.", ".1.1.", ".1.1.", "11.11"],
	[".1.1.", "11111", ".1.1.", "11111", ".1.1."],
]
## Wrench pictogram for the sign on top of the shelves.
const WRENCH: Array[String] = [
	"......11.",
	".....1..1",
	"......1.1",
	".....1.11",
	"....1.1..",
	"...1.1...",
	"..1.1....",
	".1.1.....",
	"..1......",
]
const PART_COUNT: int = 3
## Shelving unit: uprights' outer x positions and the board heights (top of each board).
const SHELF_LEFT: int = -30
const SHELF_RIGHT: int = 28
const SHELF_TOP_Y: int = -62
const SHELF_MID_Y: int = -44
## Workbench top surface height and its ends.
const BENCH_Y: int = -22
const BENCH_LEFT: int = -24
const BENCH_RIGHT: int = 23
## The part lamp panel on the right upright, and the wrench sign over the top board.
const LAMP_PANEL := Rect2i(31, -43, 7, 23)
const SIGN_RECT := Rect2i(-7, -74, 15, 12)

## Seconds per damage step, for each damaged part at once.
@export var repair_step_time: float = 1.2

## The repairable body on the pad this frame, or null.
var _patient: Node2D
var _repairing: bool = false
var _repair_clock: float = 0.0
var _green: Node2D
var _weld := PixelSparks.new()
## Seconds the sign flares after a repair step.
var _flare_left: float = 0.0


func _ready() -> void:
	super()
	_weld.colors = [Color.WHITE, GREEN_HOT, GREEN, Color(0.1, 0.4, 0.2)]
	_weld.gravity = 200.0
	_weld.damping = 0.3
	# Drawn over the amber light, so the green lamps stay green.
	_green = Node2D.new()
	add_child(_green)
	_green.draw.connect(_draw_green)


func _physics_process(delta: float) -> void:
	super(delta)
	_patient = null
	_repairing = false
	for body in get_overlapping_bodies():
		if not (body.has_method("get_damage") and body.has_method("set_damage")):
			continue
		_patient = body as Node2D
		var waited: float = _still_time.get(body.get_instance_id(), 0.0)
		if waited < charge_delay or not _needs_repair(body):
			continue
		_repairing = true
		_repair_clock += delta
		if _repair_clock >= repair_step_time:
			_repair_clock -= repair_step_time
			for part in PART_COUNT:
				var state: int = body.get_damage(part)
				if state > 0:
					body.set_damage(part, state - 1)
			_flare_left = 0.25
			_weld.emit(_weld_spot(), randi_range(6, 10), -PI / 2.0, 1.4, 30.0, 90.0, 0.15, 0.45)
		break
	if not _repairing:
		_repair_clock = 0.0


func _process(delta: float) -> void:
	super(delta)
	_flare_left -= delta
	if _repairing and randf() < delta * 18.0:
		_weld.emit(_weld_spot(), randi_range(1, 3), -PI / 2.0, 1.6, 15.0, 60.0, 0.1, 0.3)
	_weld.update(delta)
	_green.queue_redraw()


func _needs_repair(body: Node) -> bool:
	for part in PART_COUNT:
		if int(body.get_damage(part)) > 0:
			return true
	return false


## A random spot on the robot standing on the pad, in local coordinates.
func _weld_spot() -> Vector2:
	var x := 0.0
	if is_instance_valid(_patient):
		x = to_local(_patient.global_position).x
	return Vector2(roundf(x + randf_range(-5.0, 5.0)), roundf(randf_range(-34.0, -6.0)))


func _draw() -> void:
	_draw_workshop()
	super()


func _draw_workshop() -> void:
	_draw_shelves()
	_draw_bench()


func _draw_shelves() -> void:
	var height := -SHELF_TOP_Y
	# Faint cross bracing at the back of the unit.
	var brace := SHELF_DARK
	brace.a = 0.7
	for p in Geometry2D.bresenham_line(Vector2i(SHELF_LEFT + 2, SHELF_TOP_Y + 2),
			Vector2i(SHELF_RIGHT - 2, SHELF_MID_Y - 1)):
		draw_rect(Rect2(Vector2(p), Vector2.ONE), brace)
	for p in Geometry2D.bresenham_line(Vector2i(SHELF_LEFT + 2, SHELF_MID_Y + 2),
			Vector2i(SHELF_RIGHT - 2, -3)):
		draw_rect(Rect2(Vector2(p), Vector2.ONE), brace)

	# Perforated uprights, the left one bent a little near the bottom.
	for x in [SHELF_LEFT, SHELF_RIGHT - 1]:
		draw_rect(Rect2(x, SHELF_TOP_Y, 2, height), SHELF_MID)
		draw_rect(Rect2(x, SHELF_TOP_Y, 1, height), SHELF_LIGHT)
		for y in range(SHELF_TOP_Y + 3, -2, 4):
			draw_rect(Rect2(x + 1, y, 1, 1), SHELF_DARK)
		draw_rect(Rect2(x - 1, -1, 4, 1), SHELF_DARK)

	# Boards: lit edge on top, shadow under.
	for y in [SHELF_TOP_Y, SHELF_MID_Y]:
		var w := SHELF_RIGHT - SHELF_LEFT
		draw_rect(Rect2(SHELF_LEFT, y, w, 1), SHELF_LIGHT)
		draw_rect(Rect2(SHELF_LEFT, y + 1, w, 1), SHELF_MID)
		draw_rect(Rect2(SHELF_LEFT + 1, y + 2, w - 2, 1), Color(0, 0, 0, 0.35))
	# Mid board sags in the middle.
	draw_rect(Rect2(-6, SHELF_MID_Y + 2, 12, 1), SHELF_MID)

	# Top board: a rusty toolbox, battery cells, a spare thigh plate.
	var top := SHELF_TOP_Y
	draw_rect(Rect2(-26, top - 5, 13, 5), TOOLBOX_RED)
	draw_rect(Rect2(-26, top - 5, 13, 1), TOOLBOX_RED.lightened(0.2))
	draw_rect(Rect2(-26, top - 3, 13, 1), TOOLBOX_RED.darkened(0.4))
	draw_rect(Rect2(-22, top - 7, 5, 1), METAL_SIDE)
	draw_rect(Rect2(-22, top - 6, 1, 1), METAL_SIDE)
	draw_rect(Rect2(-18, top - 6, 1, 1), METAL_SIDE)
	draw_rect(Rect2(-24, top - 4, 1, 1), RUST)
	for k in 3:
		var cx := 12 + k * 3
		draw_rect(Rect2(cx, top - 4, 2, 4), METAL_SIDE if k != 1 else BOX_COLOR)
		draw_rect(Rect2(cx, top - 4, 2, 1), METAL_TOP)
	draw_rect(Rect2(20, top - 2, 6, 2), METAL_TOP.darkened(0.2))
	draw_rect(Rect2(25, top - 3, 1, 1), METAL_TOP.darkened(0.2))

	# Mid board: parts bins, a dented spare head with its eye dark, a coil of wire, an oil can.
	var mid := SHELF_MID_Y
	for k in 2:
		var bx := -27 + k * 7
		draw_rect(Rect2(bx, mid - 4, 6, 4), BOX_COLOR)
		draw_rect(Rect2(bx, mid - 4, 6, 1), METAL_TOP)
		draw_rect(Rect2(bx + 1, mid - 2, 4, 1), METAL_DARK)
	draw_rect(Rect2(-24, mid - 5, 1, 1), WIRE_RED)
	draw_rect(Rect2(-18, mid - 5, 1, 1), COPPER.darkened(0.3))
	# Spare head: a dome with a dead eye socket.
	draw_rect(Rect2(-9, mid - 5, 8, 5), METAL_SIDE)
	draw_rect(Rect2(-8, mid - 6, 6, 1), METAL_SIDE)
	draw_rect(Rect2(-8, mid - 6, 6, 1).grow_individual(0, 0, -2, 0), METAL_TOP)
	draw_rect(Rect2(-4, mid - 4, 2, 1), METAL_DARK)
	draw_rect(Rect2(-3, mid - 4, 1, 1), Color(0.25, 0.04, 0.03))
	draw_rect(Rect2(-9, mid - 1, 1, 1), RUST)
	# Coil of blue wire with a loose end hanging over the edge.
	for p in [Vector2(3, -3), Vector2(4, -4), Vector2(5, -4), Vector2(6, -3), Vector2(6, -2),
			Vector2(5, -1), Vector2(4, -1), Vector2(3, -2)]:
		draw_rect(Rect2(p + Vector2(0, mid), Vector2.ONE), WIRE_BLUE)
	for k in 5:
		draw_rect(Rect2(7, mid + 1 + k, 1, 1), WIRE_BLUE.darkened(0.2))
	# Oil can with a spout.
	draw_rect(Rect2(15, mid - 6, 4, 6), Color(0.28, 0.24, 0.1))
	draw_rect(Rect2(15, mid - 6, 4, 1), Color(0.4, 0.34, 0.14))
	draw_rect(Rect2(19, mid - 7, 1, 1), METAL_SIDE)
	draw_rect(Rect2(20, mid - 8, 1, 1), METAL_SIDE)
	draw_rect(Rect2(16, mid - 2, 2, 1), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(22, mid - 2, 4, 2), METAL_TOP.darkened(0.3))

	# Wrench sign on a bracket above the top board.
	var s := SIGN_RECT
	draw_rect(Rect2(s.position.x + 3, s.end.y, 1, top - s.end.y), SHELF_MID)
	draw_rect(Rect2(s.end.x - 4, s.end.y, 1, top - s.end.y), SHELF_MID)
	draw_rect(Rect2(s), METAL_DARK)
	draw_rect(Rect2(s.position.x, s.position.y, s.size.x, 1), SHELF_LIGHT)
	draw_rect(Rect2(s.position.x, s.end.y - 1, s.size.x, 1), SHELF_MID)
	draw_rect(Rect2(s.position.x + s.size.x - 1, s.position.y + 2, 1, 2), RUST)

	# Part lamp panel bolted to the right upright.
	var lp := LAMP_PANEL
	draw_rect(Rect2(SHELF_RIGHT + 1, lp.position.y + 3, lp.position.x - SHELF_RIGHT - 1, 2), SHELF_MID)
	draw_rect(Rect2(SHELF_RIGHT + 1, lp.end.y - 5, lp.position.x - SHELF_RIGHT - 1, 2), SHELF_MID)
	draw_rect(Rect2(lp), METAL_DARK)
	draw_rect(Rect2(lp.position.x, lp.position.y, lp.size.x, 1), SHELF_LIGHT)
	draw_rect(Rect2(lp.end.x - 1, lp.position.y + 1, 1, lp.size.y - 1), SHELF_MID)


func _draw_bench() -> void:
	var y := BENCH_Y
	var w := BENCH_RIGHT - BENCH_LEFT
	# Legs and a low stretcher with a crate under the bench.
	for x in [BENCH_LEFT + 1, BENCH_RIGHT - 3]:
		draw_rect(Rect2(x, y + 2, 2, -y - 3), SHELF_MID)
		draw_rect(Rect2(x, y + 2, 1, -y - 3), SHELF_LIGHT.darkened(0.2))
	draw_rect(Rect2(BENCH_LEFT + 1, -8, w - 2, 1), SHELF_MID)
	draw_rect(Rect2(BENCH_LEFT + 4, -7, 10, 5), BOX_COLOR.darkened(0.2))
	draw_rect(Rect2(BENCH_LEFT + 4, -7, 10, 1), METAL_SIDE)

	# Thick worn top with a front lip.
	draw_rect(Rect2(BENCH_LEFT, y, w, 1), BENCH_TOP)
	draw_rect(Rect2(BENCH_LEFT, y + 1, w, 1), SHELF_MID)
	draw_rect(Rect2(BENCH_LEFT, y + 2, w, 1), SHELF_DARK)
	for x in [-15, -2, 9, 18]:
		draw_rect(Rect2(x, y, 1, 1), RUST)

	# Vice on the left end.
	draw_rect(Rect2(-22, y - 2, 7, 2), METAL_SIDE)
	draw_rect(Rect2(-21, y - 6, 2, 4), METAL_TOP)
	draw_rect(Rect2(-17, y - 6, 2, 4), METAL_SIDE)
	draw_rect(Rect2(-25, y - 4, 4, 1), METAL_TOP.darkened(0.2))
	draw_rect(Rect2(-25, y - 5, 1, 3), METAL_SIDE)
	# A robot forearm opened up, its coloured wires spilling out.
	draw_rect(Rect2(-11, y - 3, 11, 3), METAL_SIDE)
	draw_rect(Rect2(-11, y - 3, 11, 1), METAL_TOP)
	draw_rect(Rect2(0, y - 4, 3, 4), METAL_SIDE.darkened(0.2))
	draw_rect(Rect2(1, y - 3, 1, 1), METAL_DARK)
	draw_rect(Rect2(-7, y - 2, 3, 1), METAL_DARK)
	draw_rect(Rect2(-7, y - 2, 1, 1), WIRE_RED)
	draw_rect(Rect2(-6, y - 1, 1, 1), WIRE_RED)
	draw_rect(Rect2(-5, y - 2, 1, 1), WIRE_YELLOW)
	draw_rect(Rect2(-4, y - 1, 2, 1), WIRE_BLUE)
	# Screwdriver, a tray of bolts.
	draw_rect(Rect2(6, y - 1, 6, 1), METAL_TOP)
	draw_rect(Rect2(12, y - 1, 3, 1), Color(0.45, 0.2, 0.06))
	draw_rect(Rect2(16, y - 2, 6, 2), METAL_DARK)
	draw_rect(Rect2(16, y - 2, 6, 1), METAL_SIDE)
	for x in [17, 19, 20]:
		draw_rect(Rect2(x, y - 2, 1, 1), METAL_TOP.lightened(0.15))


## The lit parts: wrench sign, part lamps, the bench's scanner strip and the weld sparks.
func _draw_green() -> void:
	var flare := _flare_left > 0.0
	var hum := 0.92 + 0.08 * sin(_time * 21.0)

	# Wrench sign, glowing steady; it flares when a repair step lands.
	var sign_level := hum * (1.0 if _repairing or flare else 0.8)
	if flare and fmod(_flare_left, 0.08) < 0.04:
		sign_level = 1.25
	var inner := Vector2(SIGN_RECT.position + Vector2i(3, 2))
	var halo := GREEN
	halo.a = 0.13 * sign_level
	_green.draw_rect(Rect2(inner - Vector2(2, 1), Vector2(13, 11)), halo)
	var lit := GREEN_DIM.lerp(GREEN, clampf(sign_level, 0.0, 1.0))
	if sign_level > 1.0:
		lit = GREEN.lerp(GREEN_HOT, sign_level - 1.0)
	_draw_glyph(_green, WRENCH, inner, lit, "1")
	halo.a = 0.05 * sign_level
	_green.draw_rect(Rect2(SIGN_RECT.position.x - 2, SIGN_RECT.end.y, SIGN_RECT.size.x + 4, 3), halo)

	# Part lamps: one icon per part, top to bottom core, legs, systems.
	for part in PART_COUNT:
		var pos := Vector2(LAMP_PANEL.position.x + 1, LAMP_PANEL.position.y + 2 + part * 7)
		var level := _lamp_level(part)
		var color := GREEN_DIM.lerp(GREEN, clampf(level, 0.0, 1.0))
		if level > 1.0:
			color = GREEN.lerp(GREEN_HOT, level - 1.0)
		if level > 0.6:
			var glow := GREEN
			glow.a = 0.12 * level
			_green.draw_rect(Rect2(pos - Vector2.ONE, Vector2(7, 7)), glow)
		_draw_glyph(_green, PART_ICONS[part], pos, color, "1")

	# A scanner strip on the bench's front edge: a slow chaser on standby, a fast one at work.
	var strip_x := BENCH_LEFT + 4
	var strip_w := BENCH_RIGHT - BENCH_LEFT - 8
	var speed := 40.0 if _repairing else 9.0
	var head := int(fmod(_time * speed, strip_w + 8.0)) - 4
	for k in strip_w:
		var d := absi(k - head)
		var a := 0.12
		if d < 4:
			a = lerpf(0.9, 0.2, d / 4.0)
		var c := GREEN
		c.a = a * (1.0 if _repairing else 0.6)
		_green.draw_rect(Rect2(strip_x + k, BENCH_Y + 1, 1, 1), c)

	_weld.draw(_green)


## How lit a part lamp is: 0 dark, 1 full green, above 1 hot.
func _lamp_level(part: int) -> float:
	if not is_instance_valid(_patient):
		# Standby: dim and steady, with the odd flicker.
		return 0.4 if randf() > 0.01 else 0.15
	var state := int(_patient.call("get_damage", part))
	if state == 0:
		return 1.0
	if _repairing:
		return 1.3 if fmod(_time, 0.16) < 0.08 else 0.2
	return 0.9 if fmod(_time, 0.9) < 0.45 else 0.2


## Draws a pixel glyph (one string per row) with its top left at pos.
func _draw_glyph(canvas: CanvasItem, rows: Array, pos: Vector2, color: Color, on: String) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == on:
				canvas.draw_rect(Rect2(pos + Vector2(x, y), Vector2.ONE), color)
