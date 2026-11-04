extends Area2D
## Charging station (checkpoint): a derelict ground pad that recharges any body inside its field
## with a recharge(amount) method, at recharge_rate per second. A body only charges once it has
## stood still in the field for charge_delay seconds; moving cuts the charge and restarts the
## wait. While waiting, the status lamp blinks faster as the emitter spools up.
##
## Drawn in code at native pixel scale. The origin is the ground surface at the pad's centre.
## Amber light rises from the pad in stepped bands over the charging area, sputtering when idle
## and flaring while it charges. Loose cables run from a busted junction box, and a frayed one
## beside the pad spits sparks now and then.

## Half the width of the lit charging column, in pixels. Matches the collision shape.
const FIELD_HALF_WIDTH: int = 16
## Light bands from the pad upwards: [height in pixels, opacity at full strength].
const GLOW_BANDS: Array = [[2, 0.6], [3, 0.4], [5, 0.26], [8, 0.16], [8, 0.08]]
## Height of the checkerboard-dithered fade above the last band, in pixels.
const GLOW_DITHER_HEIGHT: int = 10
const AMBER := Color(1.0, 0.55, 0.08)
const AMBER_HOT := Color(1.0, 0.85, 0.5)
const METAL_TOP := Color(0.27, 0.25, 0.24)
const METAL_SIDE := Color(0.14, 0.13, 0.13)
const METAL_DARK := Color(0.07, 0.07, 0.08)
const RUST := Color(0.3, 0.15, 0.07)
const HAZARD := Color(0.6, 0.42, 0.08)
const BOX_COLOR := Color(0.15, 0.16, 0.17)
const COPPER := Color(0.85, 0.5, 0.2)
## Loose cables as polylines in pixel coordinates, with their insulation colour. Rows at y = -1
## lie on the ground.
const CABLES: Array = [
	[[Vector2i(-25, -5), Vector2i(-24, -3), Vector2i(-23, -1), Vector2i(-21, -1)], Color(0.06, 0.06, 0.07)],
	[[Vector2i(-25, -8), Vector2i(-23, -7), Vector2i(-22, -5), Vector2i(-21, -4)], Color(0.38, 0.1, 0.07)],
	[
		[Vector2i(-33, -3), Vector2i(-35, -1), Vector2i(-41, -1), Vector2i(-43, -2), Vector2i(-47, -1)],
		Color(0.13, 0.17, 0.23)
	],
	[
		[
			Vector2i(20, -4), Vector2i(22, -2), Vector2i(24, -1), Vector2i(30, -1),
			Vector2i(32, -2), Vector2i(34, -1), Vector2i(36, -1)
		],
		Color(0.06, 0.06, 0.07)
	],
]
## Where the frayed cable's bare wires stick out.
const FRAYED_TIP := Vector2(37, -1)
## Emitter grille pixels that are burnt out, as offsets from its left end.
const DEAD_GRILLE: Array[int] = [4, 10, 11, 22]

## Charge restored per second. Faster or slower stations just change this.
@export var recharge_rate: float = 100.0
## Seconds a body must stand still in the field before charging starts.
@export var charge_delay: float = 1.5
## Speed (px/s) below which a body counts as standing still.
@export var still_speed: float = 1.0

var _charging: bool = false
## Seconds each body in the field has stood still, by instance id.
var _still_time: Dictionary[int, float] = {}
## How far the longest wait has got, 0 to 1, for the lamp.
var _arming: float = 0.0
## Eases from 0 (idle) to 1 (charging).
var _power: float = 0.0
var _time: float = 0.0
## Seconds left in an idle light dropout.
var _dropout_left: float = 0.0
## Seconds until the frayed cable next sparks.
var _spark_wait: float = 1.5
## Seconds the frayed tip stays lit after sparking.
var _tip_flash_left: float = 0.0
var _sparks := PixelSparks.new()
var _motes := PixelSparks.new()
## Each cable rasterised to pixels: [PackedVector2Array, Color].
var _cable_pixels: Array = []
var _rust_pixels: Array[Vector2] = []
## Child that draws all the light, on top of the pad.
var _light: Node2D


func _ready() -> void:
	_sparks.colors = [Color.WHITE, AMBER_HOT, AMBER, Color(0.5, 0.2, 0.05)]
	_sparks.gravity = 240.0
	_sparks.damping = 0.3
	_motes.colors = [AMBER_HOT, AMBER, Color(0.6, 0.3, 0.06)]
	_motes.gravity = -6.0

	for cable in CABLES:
		var pixels := PackedVector2Array()
		var points: Array = cable[0]
		for i in points.size() - 1:
			for p in Geometry2D.bresenham_line(points[i], points[i + 1]):
				pixels.append(Vector2(p))
		_cable_pixels.append([pixels, cable[1]])

	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 9:
		_rust_pixels.append(Vector2(rng.randi_range(-19, 18), rng.randi_range(-2, -1)))

	_light = Node2D.new()
	add_child(_light)
	_light.draw.connect(_draw_light)


func _physics_process(delta: float) -> void:
	_charging = false
	_arming = 0.0
	var present: Dictionary[int, float] = {}
	for body in get_overlapping_bodies():
		if not body.has_method("recharge"):
			continue
		var id := body.get_instance_id()
		var still := true
		if body is CharacterBody2D:
			var character := body as CharacterBody2D
			still = character.is_on_floor() and character.velocity.length() < still_speed
		var waited: float = _still_time.get(id, 0.0) + delta if still else 0.0
		present[id] = waited
		if waited >= charge_delay:
			body.recharge(recharge_rate * delta)
			_charging = true
		elif still:
			_arming = maxf(_arming, waited / maxf(charge_delay, 0.001))
	# Bodies that left the field start from zero next time.
	_still_time = present


func _process(delta: float) -> void:
	_time += delta
	_power = move_toward(_power, 1.0 if _charging else 0.0, delta * 4.0)

	# Idle, the old emitter sputters out for a moment every so often.
	_dropout_left -= delta
	if not _charging and _dropout_left <= 0.0 and randf() < delta * 0.8:
		_dropout_left = randf_range(0.05, 0.2)

	_spark_wait -= delta
	_tip_flash_left -= delta
	if _spark_wait <= 0.0:
		_sparks.emit(FRAYED_TIP, randi_range(3, 8), -PI / 2.0, 1.1, 25.0, 80.0, 0.15, 0.4)
		_tip_flash_left = 0.08
		_spark_wait = randf_range(0.6, 2.0) if _charging else randf_range(1.5, 4.5)

	if randf() < delta * lerpf(0.6, 14.0, _power):
		var x := randf_range(-FIELD_HALF_WIDTH + 2, FIELD_HALF_WIDTH - 2)
		_motes.emit(Vector2(x, -2), 1, -PI / 2.0, 0.15, 10.0, 26.0, 0.8, 1.5)

	_sparks.update(delta)
	_motes.update(delta)
	queue_redraw()
	_light.queue_redraw()


func _draw() -> void:
	# Oil stain soaked into the ground around the pad.
	draw_rect(Rect2(-23, 0, 46, 2), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(-20, 2, 40, 1), Color(0, 0, 0, 0.15))

	_draw_junction_box()
	for cable in _cable_pixels:
		for p in cable[0]:
			draw_rect(Rect2(p, Vector2.ONE), cable[1])
	draw_rect(Rect2(FRAYED_TIP, Vector2.ONE), COPPER)
	draw_rect(Rect2(FRAYED_TIP + Vector2(1, -1), Vector2.ONE), COPPER.darkened(0.3))

	# Pad: a thin plate with a lit emitter grille on top, bevelled at the ends where the Step
	# collision ramps up so the player walks onto it.
	draw_rect(Rect2(-20, -2, 40, 1), METAL_TOP)
	draw_rect(Rect2(-20, -1, 40, 1), METAL_SIDE)
	for p in [
		Vector2(-22, -1), Vector2(-21, -1), Vector2(-21, -2),
		Vector2(20, -1), Vector2(21, -1), Vector2(20, -2),
	]:
		draw_rect(Rect2(p, Vector2.ONE), METAL_SIDE)
	for p in _rust_pixels:
		draw_rect(Rect2(p, Vector2.ONE), RUST)
	for x in range(-14, 14, 2):
		draw_rect(Rect2(x, -2, 1, 1), METAL_DARK)

	# Corner posts with worn hazard stripes.
	for left in [-20, 17]:
		draw_rect(Rect2(left, -7, 3, 5), METAL_SIDE)
		draw_rect(Rect2(left, -7, 3, 1), METAL_TOP)
		for y in range(-6, -2):
			for x in range(left, left + 3):
				if (x + y) % 4 == 0:
					draw_rect(Rect2(x, y, 1, 1), HAZARD)


func _draw_junction_box() -> void:
	draw_rect(Rect2(-32, -12, 8, 12), BOX_COLOR)
	draw_rect(Rect2(-32, -12, 8, 1), METAL_TOP)
	draw_rect(Rect2(-25, -11, 1, 11), METAL_DARK)
	# Missing cover: gutted insides with a few wire stubs.
	draw_rect(Rect2(-31, -10, 5, 6), METAL_DARK)
	draw_rect(Rect2(-30, -8, 1, 2), Color(0.38, 0.1, 0.07))
	draw_rect(Rect2(-28, -9, 1, 3), Color(0.13, 0.17, 0.23))
	# The cover, hanging off one hinge.
	draw_rect(Rect2(-34, -9, 1, 7), METAL_TOP.darkened(0.2))
	draw_rect(Rect2(-35, -3, 1, 2), METAL_TOP.darkened(0.4))
	for p in [Vector2(-31, -2), Vector2(-27, -11), Vector2(-26, -3)]:
		draw_rect(Rect2(p, Vector2.ONE), RUST)


func _draw_light() -> void:
	var strength := lerpf(0.45, 1.0, _power)
	if _charging:
		strength *= 0.9 + 0.1 * sin(_time * 9.0)
	elif _dropout_left > 0.0:
		strength *= 0.3

	# Stepped column rising from the pad over the charging area.
	var y := -2
	for band in GLOW_BANDS:
		var height: int = band[0]
		y -= height
		var color := AMBER
		color.a = band[1] * strength
		_light.draw_rect(Rect2(-FIELD_HALF_WIDTH, y, FIELD_HALF_WIDTH * 2, height), color)
	var dither := AMBER
	dither.a = 0.08 * strength
	for dy in GLOW_DITHER_HEIGHT:
		for x in range(-FIELD_HALF_WIDTH, FIELD_HALF_WIDTH):
			if (x + dy) % 2 == 0:
				_light.draw_rect(Rect2(x, y - 1 - dy, 1, 1), dither)
	# Brighter edges mark the sides of the field near the ground.
	var edge := AMBER
	edge.a = 0.25 * strength
	_light.draw_rect(Rect2(-FIELD_HALF_WIDTH - 1, -12, 1, 10), edge)
	_light.draw_rect(Rect2(FIELD_HALF_WIDTH, -12, 1, 10), edge)

	# Light spilling onto the ground beside and under the pad.
	var spill := AMBER
	spill.a = 0.18 * strength
	_light.draw_rect(Rect2(-26, -1, 52, 1), spill)
	spill.a = 0.1 * strength
	_light.draw_rect(Rect2(-24, 0, 48, 2), spill)

	# Emitter grille, with a few burnt-out cells.
	var grille := AMBER_HOT
	grille.a = 0.5 + 0.5 * strength
	for i in 14:
		if not DEAD_GRILLE.has(i * 2 + 1):
			_light.draw_rect(Rect2(-13 + i * 2, -2, 1, 1), grille)

	# Status lamp on the right post; the left one is long dead.
	# Idle the lamp blinks slowly; spooling up for a still body it blinks faster and faster.
	var blink := lerpf(1.6, 0.2, _arming) if _arming > 0.0 else 1.6
	var lamp := AMBER if _charging or fmod(_time, blink) < blink * 0.5 else AMBER * 0.25
	_light.draw_rect(Rect2(18, -8, 1, 1), lamp)

	if _tip_flash_left > 0.0:
		_light.draw_rect(Rect2(FRAYED_TIP - Vector2.ONE, Vector2(3, 3)), Color(1, 0.8, 0.5, 0.35))
	_motes.draw(_light)
	_sparks.draw(_light)
