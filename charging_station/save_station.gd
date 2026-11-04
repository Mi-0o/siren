extends "res://charging_station/repair_station.gd"
## Save station: a charging and repair station that is also wired into the network. A tall
## lattice antenna with a blinking beacon stands behind it, and a heavy cable box on the right
## feeds a mess of cables down into the ground.
##
## While the robot stands on the pad, a flickering holographic A key hangs in the lower middle
## of the screen. Pressing A (the interact action) opens the save menu on the right, which saves
## into the active slot with the real date and time, area_name and station_name.
##
## Drawn in code like the other stations; the antenna is behind everything, the cable box in
## front of the workshop.

const HOLO := Color(0.42, 0.95, 1.0)
const HOLO_CORE := Color(0.85, 1.0, 1.0)
const BEACON := Color(1.0, 0.18, 0.1)
const KEY_GLYPH: Array[String] = [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"]
## Size of the holographic keycap, in screen pixels.
const KEYCAP := Vector2i(15, 15)
## Where the prompt sits, as a fraction of the screen height.
const PROMPT_HEIGHT: float = 0.74
## Antenna mast: centre x, top of the lattice, and the tip of the pole.
const MAST_X: int = -45
const LATTICE_TOP: int = -104
const MAST_TIP: int = -124
## The cable box, in local coordinates.
const CABLE_BOX := Rect2i(40, -28, 18, 28)
const GROUND_CABLE_COLORS: Array[Color] = [
	Color(0.06, 0.06, 0.07), Color(0.38, 0.1, 0.07), Color(0.13, 0.17, 0.23),
	Color(0.4, 0.33, 0.08), Color(0.08, 0.2, 0.1), Color(0.2, 0.2, 0.21),
]
## Cables from the box into the ground: polyline, colour index, thickness. Each one ends at the
## ground line, where it disappears through a hole.
const GROUND_CABLES: Array = [
	[[Vector2i(40, -6), Vector2i(38, -4), Vector2i(37, -1), Vector2i(37, 1)], 0, 2],
	[[Vector2i(40, -12), Vector2i(36, -9), Vector2i(33, -5), Vector2i(32, 1)], 2, 1],
	[[Vector2i(44, -1), Vector2i(44, 1)], 1, 2],
	[[Vector2i(50, -1), Vector2i(50, 1)], 3, 2],
	[[Vector2i(54, -1), Vector2i(55, 1)], 0, 1],
	[[Vector2i(58, -22), Vector2i(61, -20), Vector2i(63, -14), Vector2i(64, -6), Vector2i(64, 1)],
			0, 2],
	[[Vector2i(58, -17), Vector2i(60, -14), Vector2i(61, -8), Vector2i(60, -2), Vector2i(60, 1)],
			1, 1],
	[[Vector2i(58, -12), Vector2i(62, -9), Vector2i(67, -5), Vector2i(69, -1), Vector2i(69, 1)],
			4, 1],
	[[Vector2i(58, -8), Vector2i(64, -4), Vector2i(72, -2), Vector2i(75, -1), Vector2i(76, 1)],
			5, 2],
	[[Vector2i(58, -4), Vector2i(61, -2), Vector2i(66, -1), Vector2i(67, 1)], 2, 1],
	# The antenna's feed lines, down the mast and into the ground beside it.
	[[Vector2i(-41, -96), Vector2i(-40, -60), Vector2i(-39, -20), Vector2i(-38, -3),
			Vector2i(-36, 1)], 0, 1],
	[[Vector2i(-50, -70), Vector2i(-53, -40), Vector2i(-55, -12), Vector2i(-56, -2),
			Vector2i(-58, 1)], 1, 1],
]

## Shown in the save list.
@export var area_name: String = "PLAYGROUND"
@export var station_name: String = "MAIN STATION"
## The menu that shows the save screen. Found by group if left empty.
@export var menu: PauseMenu

var _ground_cable_pixels: Array = []
var _prompt_layer: CanvasLayer
var _prompt: Control
## Robot standing on the pad, able to save, or null.
var _saver: Player
## 0 to 1: how far the hologram has struck on.
var _holo: float = 0.0
var _holo_dropout: float = 0.0
## Seconds left of a torn line, and where it is.
var _tear_left: float = 0.0
var _tear_row: int = 0
var _tear_shift: int = 0


func _ready() -> void:
	super()
	for cable in GROUND_CABLES:
		var pixels := PackedVector2Array()
		var points: Array = cable[0]
		for i in points.size() - 1:
			for p in Geometry2D.bresenham_line(points[i], points[i + 1]):
				pixels.append(Vector2(p))
		_ground_cable_pixels.append([pixels, GROUND_CABLE_COLORS[cable[1]], cable[2]])
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_A
		InputMap.action_add_event("interact", key)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_Y
		InputMap.action_add_event("interact", pad)
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.layer = 2
	add_child(_prompt_layer)
	_prompt = Control.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prompt_layer.add_child(_prompt)
	_prompt.draw.connect(_draw_prompt)


func _physics_process(delta: float) -> void:
	super(delta)
	_saver = null
	for body in get_overlapping_bodies():
		if body is Player:
			var robot := body as Player
			if robot.is_on_floor() and not robot.is_dead():
				_saver = robot
			break


func _process(delta: float) -> void:
	super(delta)
	var showing := _saver != null and not _menu_open()
	# Strikes on in a stutter, fades out quicker.
	if showing:
		_holo = minf(_holo + delta * 4.0, 1.0)
	else:
		_holo = maxf(_holo - delta * 6.0, 0.0)
	_holo_dropout -= delta
	if showing and _holo_dropout <= 0.0 and randf() < delta * 1.5:
		_holo_dropout = randf_range(0.03, 0.09)
	_tear_left -= delta
	if _tear_left <= 0.0 and randf() < delta * 2.0:
		_tear_left = randf_range(0.05, 0.12)
		_tear_row = randi_range(0, KEYCAP.y - 3)
		_tear_shift = [-2, -1, 1, 2][randi_range(0, 3)]
	_prompt.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _saver == null or _saver.controls_locked or not event.is_action_pressed("interact"):
		return
	var m := _find_menu()
	if m == null or m.is_open:
		return
	m.open_save({"area": area_name, "station": station_name})
	get_viewport().set_input_as_handled()


func _menu_open() -> bool:
	var m := _find_menu()
	return m != null and m.is_open


func _find_menu() -> PauseMenu:
	if menu == null:
		menu = get_tree().get_first_node_in_group("pause_menu") as PauseMenu
	return menu


func _draw() -> void:
	_draw_antenna()
	super()
	_draw_cable_box()


func _draw_antenna() -> void:
	var base_half := 6
	var top_half := 2
	var height := -LATTICE_TOP
	# Guy wire to the left.
	var guy := METAL_SIDE
	guy.a = 0.8
	for p in Geometry2D.bresenham_line(Vector2i(MAST_X - 2, -88), Vector2i(MAST_X - 30, -1)):
		draw_rect(Rect2(Vector2(p), Vector2.ONE), guy)
	draw_rect(Rect2(MAST_X - 32, -2, 4, 2), METAL_SIDE)

	# Lattice: two legs closing towards the top, with zigzag bracing between them.
	var flip := false
	var y := -2
	while y > LATTICE_TOP:
		var t := float(-y) / height
		var half := roundi(lerpf(base_half, top_half, t))
		var next_y := maxi(y - 8, LATTICE_TOP)
		var next_half := roundi(lerpf(base_half, top_half, float(-next_y) / height))
		var a := Vector2i(MAST_X - half, y)
		var b := Vector2i(MAST_X + half, y)
		var c := Vector2i(MAST_X - next_half, next_y)
		var d := Vector2i(MAST_X + next_half, next_y)
		for p in Geometry2D.bresenham_line(a, b):
			draw_rect(Rect2(Vector2(p), Vector2.ONE), METAL_SIDE)
		var brace: Array = Geometry2D.bresenham_line(a, d) if flip else \
				Geometry2D.bresenham_line(b, c)
		for p in brace:
			draw_rect(Rect2(Vector2(p), Vector2.ONE), METAL_DARK.lightened(0.08))
		for p in Geometry2D.bresenham_line(a, c):
			draw_rect(Rect2(Vector2(p), Vector2.ONE), METAL_TOP)
		for p in Geometry2D.bresenham_line(b, d):
			draw_rect(Rect2(Vector2(p), Vector2.ONE), METAL_SIDE)
		flip = not flip
		y = next_y
	draw_rect(Rect2(MAST_X - top_half - 1, LATTICE_TOP - 1, top_half * 2 + 3, 2), METAL_SIDE)

	# Pole and dipole crossbars up top.
	draw_rect(Rect2(MAST_X, MAST_TIP, 1, LATTICE_TOP - MAST_TIP), METAL_TOP)
	draw_rect(Rect2(MAST_X + 1, MAST_TIP, 1, LATTICE_TOP - MAST_TIP), METAL_SIDE)
	for bar in [[-108, 8], [-113, 6], [-118, 4]]:
		draw_rect(Rect2(MAST_X - bar[1], bar[0], bar[1] * 2 + 2, 1), METAL_SIDE)
		draw_rect(Rect2(MAST_X - bar[1], bar[0] + 1, 1, 2), METAL_SIDE)
		draw_rect(Rect2(MAST_X + bar[1] + 1, bar[0] + 1, 1, 2), METAL_SIDE)
	# A small dish on an arm, aimed up and right.
	draw_rect(Rect2(MAST_X + 3, -80, 4, 1), METAL_SIDE)
	for p in [Vector2(7, -84), Vector2(8, -83), Vector2(9, -82), Vector2(9, -81), Vector2(10, -80),
			Vector2(10, -79), Vector2(9, -78), Vector2(8, -77)]:
		draw_rect(Rect2(p + Vector2(MAST_X, 0), Vector2.ONE), METAL_TOP)
	draw_rect(Rect2(MAST_X + 7, -81, 1, 1), METAL_DARK)
	# Base plate, bolted down, rust on the foot.
	draw_rect(Rect2(MAST_X - 8, -2, 17, 2), METAL_SIDE)
	draw_rect(Rect2(MAST_X - 8, -2, 17, 1), METAL_TOP)
	draw_rect(Rect2(MAST_X - 7, -1, 1, 1), RUST)
	draw_rect(Rect2(MAST_X + 6, -1, 1, 1), RUST)


func _draw_cable_box() -> void:
	# Cables first, so they come out from behind the box.
	for cable in _ground_cable_pixels:
		var color: Color = cable[1]
		var thick: int = cable[2]
		for p in cable[0]:
			var px: Vector2 = p
			# Below the ground line the cable has gone into the floor.
			if px.y >= 0.0:
				draw_rect(Rect2(px + Vector2(-1, 0), Vector2(thick + 2, 1)), Color(0, 0, 0, 0.55))
				draw_rect(Rect2(px, Vector2(thick, 1)), color.darkened(0.5))
				continue
			draw_rect(Rect2(px, Vector2(thick, 1)), color)
			if thick > 1:
				draw_rect(Rect2(px + Vector2(1, 0), Vector2.ONE), color.lightened(0.12))

	var r := CABLE_BOX
	draw_rect(Rect2(r.position.x - 1, -1, r.size.x + 2, 1), Color(0, 0, 0, 0.4))
	draw_rect(Rect2(r), BOX_COLOR)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), METAL_TOP)
	draw_rect(Rect2(r.end.x - 1, r.position.y + 1, 1, r.size.y - 1), METAL_DARK)
	draw_rect(Rect2(r.position.x, r.position.y + 1, 1, r.size.y - 1), METAL_SIDE)
	# Hazard band under the lid.
	for x in range(r.position.x + 1, r.end.x - 1):
		for yy in range(r.position.y + 2, r.position.y + 4):
			draw_rect(Rect2(x, yy, 1, 1), HAZARD if (x + yy) % 4 < 2 else METAL_DARK)
	# Door seam, hinges and a handle.
	draw_rect(Rect2(r.position.x + 2, r.position.y + 5, r.size.x - 4, r.size.y - 8), METAL_DARK, false, 1.0)
	draw_rect(Rect2(r.position.x + 1, r.position.y + 8, 1, 2), METAL_TOP)
	draw_rect(Rect2(r.position.x + 1, r.end.y - 8, 1, 2), METAL_TOP)
	draw_rect(Rect2(r.end.x - 5, r.position.y + 14, 1, 4), METAL_TOP)
	# Vent slits and a small status window (lit by the light layer).
	for k in 3:
		draw_rect(Rect2(r.position.x + 4, r.end.y - 7 + k * 2, 7, 1), METAL_DARK)
	draw_rect(Rect2(r.position.x + 4, r.position.y + 7, 8, 4), METAL_DARK)
	# Conduit stubs on top, one with a cable running up to the shelves.
	draw_rect(Rect2(r.position.x + 3, r.position.y - 2, 3, 2), METAL_SIDE)
	draw_rect(Rect2(r.position.x + 11, r.position.y - 3, 3, 3), METAL_SIDE)
	draw_rect(Rect2(r.position.x + 11, r.position.y - 3, 3, 1), METAL_TOP)
	for p in Geometry2D.bresenham_line(Vector2i(r.position.x + 4, r.position.y - 3),
			Vector2i(SHELF_RIGHT + 2, SHELF_MID_Y + 4)):
		draw_rect(Rect2(Vector2(p), Vector2.ONE), GROUND_CABLE_COLORS[0])
	for p in [Vector2(6, 9), Vector2(3, 14), Vector2(15, 2), Vector2(8, 25)]:
		draw_rect(Rect2(Vector2(r.position) + p, Vector2.ONE), RUST)


func _draw_green() -> void:
	super()
	# Beacon on the antenna tip: a slow red blink with a halo.
	var on := fmod(_time, 1.4) < 0.18
	var tip := Vector2(MAST_X, MAST_TIP - 1)
	_green.draw_rect(Rect2(tip, Vector2(2, 1)), BEACON if on else BEACON.darkened(0.7))
	if on:
		var halo := BEACON
		halo.a = 0.22
		_green.draw_rect(Rect2(tip - Vector2(1, 1), Vector2(4, 3)), halo)
		halo.a = 0.08
		_green.draw_rect(Rect2(tip - Vector2(3, 3), Vector2(8, 7)), halo)
	# Status window on the cable box: data blips that run faster while someone stands on the pad.
	var w := Vector2(CABLE_BOX.position + Vector2i(5, 8))
	var rate := 14.0 if _saver != null else 4.0
	for k in 6:
		var blip := fmod(_time * rate + k * 1.7, 6.0) < 1.0
		var c := GREEN if k % 3 != 2 else AMBER
		c.a = 0.85 if blip else 0.18
		_green.draw_rect(Rect2(w + Vector2(k, (k * 7) % 2), Vector2.ONE), c)


## The holographic A key, centred low on the screen.
func _draw_prompt() -> void:
	if _holo <= 0.0:
		return
	var screen := _prompt.get_viewport_rect().size
	var bob := 1 if fmod(_time, 1.6) < 0.8 else 0
	var origin := Vector2i(
		roundi((screen.x - KEYCAP.x) * 0.5), roundi(screen.y * PROMPT_HEIGHT) - bob
	)
	var level := _holo * (0.85 + 0.15 * sin(_time * 37.0))
	if _holo < 1.0 and fmod(_time, 0.06) < 0.03:
		level *= 0.4
	if _holo_dropout > 0.0:
		level *= 0.3

	# Projector beam rising from a thin emitter strip below the key.
	var emitter_y := origin.y + KEYCAP.y + 6
	var beam := HOLO
	for y in range(origin.y + KEYCAP.y, emitter_y):
		beam.a = 0.06 * level
		_prompt.draw_rect(Rect2(origin.x - 2, y, KEYCAP.x + 4, 1), beam)
	var strip := HOLO
	strip.a = 0.5 * level
	_prompt.draw_rect(Rect2(origin.x - 4, emitter_y, KEYCAP.x + 8, 1), strip)
	strip.a = 0.15 * level
	_prompt.draw_rect(Rect2(origin.x - 6, emitter_y + 1, KEYCAP.x + 12, 1), strip)

	# Keycap: outline with clipped corners, a thicker bottom edge for depth, the A inside.
	var pixels: Array[Vector2i] = []
	for x in range(1, KEYCAP.x - 1):
		pixels.append(Vector2i(x, 0))
		pixels.append(Vector2i(x, KEYCAP.y - 1))
		pixels.append(Vector2i(x, KEYCAP.y - 2))
	for y in range(1, KEYCAP.y - 1):
		pixels.append(Vector2i(0, y))
		pixels.append(Vector2i(KEYCAP.x - 1, y))
	var glyph_pos := Vector2i((KEYCAP.x - 5) >> 1, 3)
	var glyph: Array[Vector2i] = []
	for gy in KEY_GLYPH.size():
		for gx in KEY_GLYPH[gy].length():
			if KEY_GLYPH[gy][gx] == "#":
				glyph.append(glyph_pos + Vector2i(gx, gy))

	var halo := HOLO
	halo.a = 0.08 * level
	_prompt.draw_rect(Rect2(Vector2(origin - Vector2i(2, 2)), Vector2(KEYCAP + Vector2i(4, 4))), halo)
	var fill := HOLO
	fill.a = 0.06 * level
	_prompt.draw_rect(Rect2(Vector2(origin + Vector2i.ONE), Vector2(KEYCAP - Vector2i(2, 3))), fill)
	for p in pixels:
		_holo_pixel(origin, p, HOLO, 0.75 * level)
	for p in glyph:
		_holo_pixel(origin, p, HOLO_CORE, level)


## One hologram pixel: every other row is fainter (scanlines), and a torn row slips sideways.
func _holo_pixel(origin: Vector2i, p: Vector2i, color: Color, alpha: float) -> void:
	var q := p
	if _tear_left > 0.0 and (p.y == _tear_row or p.y == _tear_row + 1):
		q.x += _tear_shift
	var c := color
	c.a = alpha * (1.0 if p.y % 2 == 0 else 0.55)
	_prompt.draw_rect(Rect2(Vector2(origin + q), Vector2.ONE), c)
