extends "res://ui/pause_menu.gd"
## The main menu: big neon plaques bolted to a frozen steel column in the middle of a gray
## screen. CONTINUE (only when there are saves; it resumes the most recent one), LOAD STATION,
## NEW GAME, SETTINGS and EXIT. Without saves NEW GAME takes the top spot.
##
## Built on the pause menu, so it shares the step-scripted mechanics, the neon, the settings
## pages and the save slots, but everything is bigger here: the plaques use double-size tubes
## and each one is a little different (a dead lamp, a welded patch, a crack, a failing letter, one
## hanging crooked off a broken bracket, cables dangling off them). The displays are larger too,
## lowered from the top on chains, and the slots show more of each save.
##
## Europa is cold: frost crusts the top edges, icicles hang under the plaques and the displays,
## the glass is frosted at its corners, ice chips shake loose when a plaque judders, and a few
## flakes drift across the background. All kept faint, so the buttons stay the focus.

const MENU_LABELS: Array[String] = ["CONTINUE", "LOAD STATION", "NEW GAME", "SETTINGS", "EXIT"]
const PLAYGROUND_SCENE: String = "res://tests/movement_playground.tscn"
const BG := Color(0.3, 0.31, 0.33)
const BG_SHADE := Color(0.2, 0.21, 0.23)
const LED_AMBER := Color(1.0, 0.55, 0.12)
const PART_COLORS: Array[Color] = [
	Color(0.25, 0.95, 0.45), Color(1.0, 0.84, 0.22), Color(1.0, 0.52, 0.1), Color(1.0, 0.12, 0.09)
]
const PART_ICONS: Array = [
	[".111.", "1...1", "1.1.1", "1...1", ".111."],
	[".111.", ".1.1.", ".1.1.", ".1.1.", "11.11"],
	[".1.1.", "11111", ".1.1.", "11111", ".1.1."],
]
## Plaques: height, distance between stacked plaques, and text scale.
const BIG_H: int = 18
const MENU_STEP: int = 25
const TEXT_SCALE: int = 1
const BIG_TEXT_X: int = 18
const BASE_W: int = 124
const MENU_PUSH: int = 4
## Where the middle of the button stack sits, as a fraction of the screen height. Low, to leave
## the top for the game's title.
const STACK_Y: float = 0.7
const COLUMN_W: int = 16
## What makes each plaque its own: width change, grime seed, lamp ("ok", "dead", "flicker"),
## letter whose tube is failing (-1 none), dangling cable ("plug", "loop", "frayed", "none"),
## welded patch, crack, pixels it hangs low on a broken bracket, and how frosted it is.
const STYLES: Dictionary = {
	"CONTINUE": {"w": 0, "seed": 5, "lamp": "ok", "faulty": -1, "cable": "plug", "patch": false,
			"crack": false, "sag": 0, "frost": 0.7},
	"LOAD STATION": {"w": -4, "seed": 17, "lamp": "ok", "faulty": 8, "cable": "none",
			"patch": true, "crack": false, "sag": 0, "frost": 0.9},
	"NEW GAME": {"w": 6, "seed": 29, "lamp": "dead", "faulty": -1, "cable": "loop",
			"patch": false, "crack": true, "sag": 0, "frost": 1.1},
	"SETTINGS": {"w": -2, "seed": 41, "lamp": "ok", "faulty": 3, "cable": "frayed",
			"patch": false, "crack": false, "sag": 0, "frost": 0.6},
	"EXIT": {"w": 4, "seed": 53, "lamp": "flicker", "faulty": -1, "cable": "plug", "patch": false,
			"crack": false, "sag": 2, "frost": 1.3},
}

## Pointer art: o outline, # metal, c neon edge, f frost.
const CURSOR: Array[String] = [
	"o.......",
	"oo......",
	"ofo.....",
	"oc#o....",
	"oc##o...",
	"oc###o..",
	"oc####o.",
	"oc##oooo",
	"oc#o....",
	"oco.....",
	"oo......",
]
const CLICK_TIME: float = 0.18

var _labels: Array[String] = []
## True once the mouse has moved, until a key is pressed.
var _mouse_on: bool = false
var _cursor_layer: CanvasLayer
var _cursor: Control
var _cursor_alpha: float = 0.0
var _hover_t: float = 0.0
var _click_left: float = 0.0
var _dev_menu: Control
var _snow: Array[Vector3] = []
var _column_grime: Array = []
var _panel_ice: Array = []
var _temp_text: Dictionary


func _ready() -> void:
	panel_size = Vector2i(300, 238)
	panel_screen = Rect2i(14, 22, 272, 200)
	back_rect = Rect2i(262, 4, 29, 13)
	slot_top = 6
	slot_h = 50
	slot_gap = 6
	page_row_y = 178
	settings_row_h = 24
	option_top = 26
	option_h = 18
	slider_w = 70
	settings_big = true
	super()
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for i in 46:
		_snow.append(Vector3(rng.randf_range(0, 480), rng.randf_range(0, 270), rng.randf()))
	for i in 60:
		_column_grime.append([Vector2(rng.randi_range(0, COLUMN_W - 1), rng.randi_range(0, 400)),
				RUST_COLORS[rng.randi_range(0, RUST_COLORS.size() - 1)]])
	for i in _panels.size():
		_panel_ice.append(_roll_icicles(panel_size.x - 10, 900 + i, 1.2))
	_temp_text = _build_text("-171 C", 1, 1, SMALL_GLYPHS)
	_rebuild_buttons()
	_setup_mouse()
	open.call_deferred()


func _process(delta: float) -> void:
	super(delta)
	_update_cursor(delta)
	for i in _snow.size():
		var f := _snow[i]
		f.y += delta * (6.0 + f.z * 8.0)
		f.x += delta * (sin(_time * 0.4 + f.z * 9.0) * 3.0 - 2.0)
		if f.y > 272.0:
			f.y = -2.0
			f.x = randf_range(0, _screen_size().x)
		if f.x < -2.0:
			f.x += _screen_size().x + 4.0
		_snow[i] = f
	for b in _buttons:
		if int(b.style.faulty) < 0:
			continue
		if b.fault_left > 0.0:
			b.fault_left -= delta
		else:
			b.fault_wait -= delta
			if b.fault_wait <= 0.0:
				b.fault_wait = _rng.randf_range(0.8, 3.5)
				b.fault_left = _rng.randf_range(0.06, 0.35)


# --- Buttons ---------------------------------------------------------------------------------


func _menu_labels() -> Array[String]:
	var labels: Array[String] = []
	if SAVE_SLOTS.latest() >= 0:
		labels.append("CONTINUE")
		labels.append("LOAD STATION")
		labels.append("NEW GAME")
	else:
		labels.append("NEW GAME")
		labels.append("LOAD STATION")
	labels.append("SETTINGS")
	labels.append("EXIT")
	return labels


func _rebuild_buttons() -> void:
	var keep := _labels[selected] if selected < _labels.size() else ""
	_labels = _menu_labels()
	_buttons.clear()
	for label in _labels:
		var style: Dictionary = STYLES[label]
		var letters: Array = []
		var x := 0
		for ch in label:
			if ch == " ":
				x += SPACE_W * TEXT_SCALE
				continue
			var t := _build_text(ch, TEXT_SCALE, 2)
			letters.append({"text": t, "x": x})
			x += int(t.dims.x) + TEXT_SCALE
		var w := BASE_W + int(style.w)
		_buttons.append({
			"label": label,
			"style": style,
			"letters": letters,
			"w": w,
			"track": PauseMenu.MechTrack.new(),
			"select": PauseMenu.MechTrack.new(),
			"light": PauseMenu.NeonLight.new(),
			"jolt": PauseMenu.MechTrack.new(),
			"grime": _roll_big_grime(w, int(style.seed)),
			"frost": _roll_frost(w, BIG_H, int(style.seed) + 1, float(style.frost)),
			"icicles": _roll_icicles(w, int(style.seed) + 2, float(style.frost)),
			"fault_left": 0.0,
			"fault_wait": 1.0,
			"spark_wait": 1.0,
		})
	selected = maxi(_labels.find(keep), 0)


## The main menu never closes; it only steps between its screens.
func open() -> void:
	is_open = true
	_active = true
	_mode = Mode.BUTTONS
	for i in _buttons.size():
		var b := _buttons[i]
		(b.select as PauseMenu.MechTrack).snap(1.0 if i == selected else 0.0)
		(b.track as PauseMenu.MechTrack).play(_button_open_steps(i, 0.25))
		(b.light as PauseMenu.NeonLight).snap_off()
	opened.emit()


func close() -> void:
	pass


func _confirm() -> void:
	match _labels[selected]:
		"CONTINUE":
			_start_slot(SAVE_SLOTS.latest())
		"LOAD STATION":
			_show_panel(Mode.LOAD)
		"NEW GAME":
			_show_panel(Mode.NEW_GAME)
		"SETTINGS":
			_show_panel(Mode.SETTINGS)
		"EXIT":
			get_tree().quit()


func _select(index: int) -> void:
	super(index)
	# The judder shakes frost off the plaque's top edge.
	var r := _button_rect(index)
	for k in 3:
		_ice.emit(Vector2(r.position.x + _rng.randi_range(8, r.size.x - 8), r.position.y), 1,
				-PI / 2.0, 1.2, 8.0, 25.0, 0.4, 0.9)


## Back from a display: CONTINUE comes and goes with the saves.
func _back() -> void:
	if _menu_labels() != _labels:
		_rebuild_buttons()
	super()


## Loads a save into its scene; the scene's own menu puts the robot back once it's ready.
func _start_slot(index: int) -> void:
	if index < 0:
		return
	var data := SAVE_SLOTS.get_slot(index)
	if data.is_empty():
		return
	SAVE_SLOTS.set_active(index)
	SAVE_SLOTS.pending_load = data
	var scene := str(data.get("scene", ""))
	if scene == "" or not ResourceLoader.exists(scene):
		scene = PLAYGROUND_SCENE
	get_tree().change_scene_to_file.call_deferred(scene)


func _load_slot(index: int) -> void:
	_start_slot(index)


func _button_rect(index: int) -> Rect2i:
	var b := _buttons[index]
	var screen := _screen_size()
	var w: int = b.w
	var track: PauseMenu.MechTrack = b.track
	var select: PauseMenu.MechTrack = b.select
	var jolt: PauseMenu.MechTrack = b.jolt
	var rest_x := roundf(screen.x * 0.5 - w * 0.5)
	var x := lerpf(-w - 30.0, rest_x, track.value)
	x += select.value * MENU_PUSH - jolt.value * 3.0
	var stack_h := MENU_STEP * (_buttons.size() - 1) + BIG_H
	var y := roundi(screen.y * STACK_Y - stack_h * 0.5) + index * MENU_STEP + int(b.style.sag)
	var chatter := maxi(track.shake, maxi(select.shake, jolt.shake))
	return Rect2i(Vector2i(floori(x), y) + _shake_offset(index * 7 + 3, chatter),
			Vector2i(w, BIG_H))


func _rod_mouth(index: int) -> Vector2:
	var r := _button_rect(index)
	return Vector2(r.position.x + 4, r.position.y + BIG_H - 2)


func _on_button_tag(index: int, tag: String) -> void:
	var r := _button_rect(index)
	var light: PauseMenu.NeonLight = _buttons[index].light
	match tag:
		"locked":
			_vent(Vector2(r.position.x + 2, r.end.y - 2), PI * 0.8, 6, 24.0)
			_vent(Vector2(r.end.x - 2, r.position.y + 3), -PI / 4.0, 4, 20.0)
			light.strike()
			for k in 4:
				_ice.emit(Vector2(r.position.x + _rng.randi_range(6, r.size.x - 6), r.end.y), 1,
						PI / 2.0, 0.5, 4.0, 15.0, 0.4, 0.8)
		"release":
			_vent(Vector2(r.position.x + 2, r.end.y - 2), PI, 4, 26.0)
			light.turn_off()
		"vent_small":
			_vent(Vector2(r.position.x + 2, r.position.y + 4), PI, 2, 14.0)


func _draw() -> void:
	_draw_background()
	super()


func _draw_background() -> void:
	var screen := _screen_size()
	draw_rect(Rect2(Vector2.ZERO, screen), BG)
	# Darker towards the edges, in a few stepped bands.
	for k in 6:
		var c := BG_SHADE
		c.a = 0.09
		draw_rect(Rect2(0, 0, screen.x, 6 + k * 5), c)
		draw_rect(Rect2(0, screen.y - 6 - k * 5, screen.x, 6 + k * 5), c)
		draw_rect(Rect2(0, 0, 8 + k * 7, screen.y), c)
		draw_rect(Rect2(screen.x - 8 - k * 7, 0, 8 + k * 7, screen.y), c)
	# Frost creeping in from the screen corners.
	for corner in 4:
		var origin := Vector2(0 if corner % 2 == 0 else screen.x - 1, 0 if corner < 2 else screen.y - 1)
		var dir := Vector2(1 if corner % 2 == 0 else -1, 1 if corner < 2 else -1)
		for k in 140:
			var h := hash(Vector2i(corner, k))
			var d := Vector2(h % 38, (h >> 8) % 38)
			if d.length() > 36.0 or (h >> 16) % 3 != 0:
				continue
			var c := FROST
			c.a = 0.16 * (1.0 - d.length() / 36.0)
			draw_rect(Rect2(origin + d * dir, Vector2.ONE), c)
	for f in _snow:
		var c := FROST
		c.a = 0.18 + f.z * 0.25
		draw_rect(Rect2(Vector2(f.x, f.y).floor(), Vector2.ONE), c)
	_draw_column(screen)


## The steel column the plaques are bolted to, with a frosted pipe and a cable bundle.
func _draw_column(screen: Vector2) -> void:
	var x0 := int(screen.x * 0.5) - (COLUMN_W >> 1)
	var h := int(screen.y)
	draw_rect(Rect2(x0 + 3, 0, COLUMN_W, h), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(x0, 0, COLUMN_W, h), TRUSS_DARK)
	draw_rect(Rect2(x0, 0, 3, h), TRUSS_MID)
	draw_rect(Rect2(x0 + COLUMN_W - 3, 0, 3, h), TRUSS_MID)
	draw_rect(Rect2(x0, 0, 1, h), TRUSS_LIGHT)
	draw_rect(Rect2(x0 + COLUMN_W - 3, 0, 1, h), TRUSS_LIGHT.darkened(0.2))
	for y in range(5, h, 11):
		draw_rect(Rect2(x0 + 1, y, 1, 1), HudDraw.RIVET_COLOR)
		draw_rect(Rect2(x0 + COLUMN_W - 2, y + 4, 1, 1), HudDraw.RIVET_COLOR)
	for g in _column_grime:
		var gp: Vector2 = g[0]
		if gp.y < h:
			draw_rect(Rect2(Vector2(x0, 0) + gp, Vector2.ONE), g[1])
	# Frost on the flanges' left edge, thicker high up.
	for y in range(0, h, 2):
		if hash(y * 13) % 5 < 2:
			var c := FROST
			c.a = 0.35
			draw_rect(Rect2(x0 - 1, y, 1, 1 + hash(y) % 2), c)
	# Pipe down the right side with frost rings, and a cable bundle with ties on the left.
	var px := x0 + COLUMN_W + 2
	draw_rect(Rect2(px, 0, 4, h), ROD_COLORS[1])
	draw_rect(Rect2(px, 0, 1, h), ROD_COLORS[0])
	draw_rect(Rect2(px + 3, 0, 1, h), ROD_COLORS[2])
	for y in range(9, h, 23):
		draw_rect(Rect2(px - 1, y, 6, 2), ICE_DEEP)
		draw_rect(Rect2(px - 1, y, 6, 1), FROST)
	var cx := x0 - 5
	for k in 3:
		var colors := [Color(0.06, 0.06, 0.07), CABLE_COLOR, Color(0.13, 0.17, 0.23)]
		draw_rect(Rect2(cx + k, 0, 1, h), colors[k])
	for y in range(14, h, 19):
		draw_rect(Rect2(cx - 1, y, 5, 1), TRUSS_MID)


func _draw_button(index: int) -> void:
	var b := _buttons[index]
	var r := _button_rect(index)
	if r.end.x <= 0:
		return
	var style: Dictionary = b.style
	var p := r.position
	var w := r.size.x
	var h := r.size.y
	var c := PLAQUE_CHAMFER + 1

	# Drop shadow on the background.
	draw_colored_polygon(_big_polygon(p + Vector2i(3, 3), w, h), Color(0, 0, 0, 0.28))
	if int(style.sag) > 0:
		# The broken bracket it hangs crooked from.
		draw_rect(Rect2(p.x + w - 30, p.y - 4, 3, 5), TRUSS_DARK)
		draw_rect(Rect2(p.x + w - 31, p.y - 5, 5, 1), TRUSS_MID)
		draw_rect(Rect2(p.x + 26, p.y - 3, 2, 2), TRUSS_MID)

	draw_colored_polygon(_big_polygon(p, w, h), PLAQUE_COLOR)
	draw_rect(Rect2(p.x + c, p.y, w - c - 5, 1), PLAQUE_LIGHT)
	draw_rect(Rect2(p.x + c, p.y + 1, w - c - 5, 1), PLAQUE_LIGHT.darkened(0.35))
	for k in c:
		draw_rect(Rect2(p.x + c - 1 - k, p.y + 1 + k, 1, 1), PLAQUE_LIGHT)
		draw_rect(Rect2(p.x + k, p.y + h - c + k, 1, 1), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x, p.y + c, 1, h - c * 2), PLAQUE_LIGHT.darkened(0.25))
	draw_rect(Rect2(p.x + c, p.y + h - 1, w - c, 1), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + c, p.y + h - 2, w - c - 4, 1), PLAQUE_COLOR.darkened(0.3))
	draw_rect(Rect2(p.x + w - 5, p.y, 1, h), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + w - 4, p.y + 1, 4, h - 2), PLAQUE_COLOR.darkened(0.25))
	for g in b.grime:
		draw_rect(Rect2(Vector2(p) + g[0], Vector2.ONE), g[1])
	for rv in [Vector2i(c + 2, 3), Vector2i(c + 2, h - 4), Vector2i(w - 8, 3), Vector2i(w - 8, h - 4)]:
		draw_rect(Rect2(Vector2(p + rv), Vector2.ONE), HudDraw.RIVET_COLOR)
		draw_rect(Rect2(Vector2(p + rv) + Vector2(0, 1), Vector2.ONE), RUST_COLORS[1])

	var channel_end := w - 12
	if bool(style.patch):
		# A plate welded over a hole, with a bead of weld around it.
		var patch := Rect2i(p.x + w - 30, p.y + 4, 18, h - 8)
		draw_rect(Rect2(patch), PLAQUE_COLOR.lightened(0.05))
		for k in range(0, patch.size.x, 2):
			draw_rect(Rect2(patch.position.x + k, patch.position.y - 1, 1, 1), Color(0.35, 0.27, 0.2))
			draw_rect(Rect2(patch.position.x + k + 1, patch.end.y, 1, 1), Color(0.35, 0.27, 0.2))
		for k in range(0, patch.size.y, 2):
			draw_rect(Rect2(patch.position.x - 1, patch.position.y + k, 1, 1), Color(0.35, 0.27, 0.2))
		draw_rect(Rect2(patch.position.x + 3, patch.position.y + 3, 1, 1), HudDraw.RIVET_COLOR)
		draw_rect(Rect2(patch.end.x - 4, patch.end.y - 4, 1, 1), HudDraw.RIVET_COLOR)
		channel_end = w - 34
	if bool(style.crack):
		var crack := [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(2, 4),
				Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7)]
		for q in crack:
			draw_rect(Rect2(Vector2(p + Vector2i(w - 16, 0) + q), Vector2.ONE), PLAQUE_SHADOW)
			draw_rect(Rect2(Vector2(p + Vector2i(w - 15, 0) + q), Vector2.ONE), PLAQUE_LIGHT.darkened(0.3))

	var select: PauseMenu.MechTrack = b.select
	var sel := clampf(select.value, 0.0, 1.0)
	var light: PauseMenu.NeonLight = b.light
	var glow := light.level * lerpf(0.45, 1.0, sel)
	if index == selected and _mode == Mode.BUTTONS:
		glow *= 0.93 + 0.07 * sin(_time * 31.0)

	# Status lamp.
	var lamp_on := sel * light.level
	match str(style.lamp):
		"dead":
			lamp_on = 0.0
		"flicker":
			if lamp_on > 0.0 and hash(int(_time * 20.0)) % 7 == 0:
				lamp_on *= 0.2
	var lamp := Rect2(p.x + 8, p.y + (h >> 1) - 3, 5, 6)
	draw_rect(lamp, PLAQUE_SHADOW)
	draw_rect(lamp.grow(-1), LAMP_OFF.lerp(LAMP_ON, lamp_on))
	if str(style.lamp) == "dead":
		draw_rect(Rect2(lamp.position + Vector2(1, 1), Vector2(1, 2)), PLAQUE_SHADOW)
		draw_rect(Rect2(lamp.position + Vector2(2, 3), Vector2(1, 1)), PLAQUE_SHADOW)
	elif lamp_on > 0.5:
		var halo := LAMP_ON
		halo.a = 0.22 * lamp_on
		draw_rect(lamp.grow(1), halo)

	# Recessed channel for the tubes, its glass frosted at the ends.
	var channel := Rect2(p.x + BIG_TEXT_X - 4, p.y + 4, channel_end - BIG_TEXT_X + 4, h - 8)
	draw_rect(channel, CHANNEL_COLOR)
	draw_rect(Rect2(channel.position, Vector2(channel.size.x, 1)), PLAQUE_SHADOW)
	draw_rect(Rect2(channel.position.x, channel.end.y, channel.size.x, 1), PLAQUE_LIGHT.darkened(0.4))
	for k in 10:
		var fx := k % 4
		var fy := k / 4.0
		var f := FROST
		f.a = 0.12
		draw_rect(Rect2(channel.position + Vector2(fx, floorf(fy) + 1), Vector2.ONE), f)
		draw_rect(Rect2(channel.end - Vector2(fx + 1, floorf(fy) + 2), Vector2.ONE), f)

	var origin := Vector2i(p.x + BIG_TEXT_X, p.y + ((h - 7) >> 1))
	var faulty := int(style.faulty)
	for i in (b.letters as Array).size():
		var letter: Dictionary = b.letters[i]
		var level := glow
		if i == faulty and float(b.fault_left) > 0.0:
			level *= 0.1 if fmod(float(b.fault_left), 0.06) < 0.04 else 0.55
		_draw_neon(letter.text, origin + Vector2i(int(letter.x), 0), level, sel, BUTTON_TUBE,
				BUTTON_CORE, BUTTON_GHOST)

	# Frost crust and icicles.
	for f in b.frost:
		var fc := FROST
		fc.a = f[1]
		draw_rect(Rect2(Vector2(p) + f[0], Vector2.ONE), fc)
	_draw_icicles(b.icicles, Vector2i(p.x, p.y + h))
	_draw_cable(index, r)


func _big_polygon(p: Vector2i, w: int, h: int) -> PackedVector2Array:
	var c := PLAQUE_CHAMFER + 1
	var o := Vector2(p)
	return PackedVector2Array([
		o + Vector2(c, 0), o + Vector2(w, 0), o + Vector2(w, h), o + Vector2(c, h),
		o + Vector2(0, h - c), o + Vector2(0, c),
	])


## The cable that dangles off a plaque, swaying a little as the plaque settles.
func _draw_cable(index: int, r: Rect2i) -> void:
	var b := _buttons[index]
	var kind := str(b.style.cable)
	if kind == "none":
		return
	var sway := sin(_time * 1.3 + index * 2.1) * 1.5
	var select: PauseMenu.MechTrack = b.select
	sway += (1.0 - (b.track as PauseMenu.MechTrack).value) * 6.0 + select.shake * 1.0
	var color := CABLE_COLOR if kind != "plug" else Color(0.06, 0.06, 0.07)
	var points: Array[Vector2] = []
	match kind:
		"plug":
			var a := Vector2(r.end.x - 22, r.end.y)
			for k in 9:
				var t := k / 8.0
				points.append(a + Vector2(sway * t * t + t * 2.0, t * 15.0))
		"loop":
			var a := Vector2(r.position.x + 16, r.end.y)
			var e := Vector2(r.position.x + 50, r.end.y)
			for k in 13:
				var t := k / 12.0
				var sag := 4.0 * t * (1.0 - t) * 11.0
				points.append(a.lerp(e, t) + Vector2(sway * sin(t * PI) * 0.5, sag))
		"frayed":
			var a := Vector2(r.end.x - 1, r.position.y + 8)
			for k in 11:
				var t := k / 10.0
				points.append(a + Vector2(3.0 + t * 4.0 + sway * t, t * 20.0 - 4.0 * t * (1.0 - t)))
	for k in points.size() - 1:
		for q in Geometry2D.bresenham_line(Vector2i(points[k].round()), Vector2i(points[k + 1].round())):
			draw_rect(Rect2(Vector2(q), Vector2.ONE), color)
	var tip := points[points.size() - 1].round()
	match kind:
		"plug":
			draw_rect(Rect2(tip + Vector2(-1, 0), Vector2(3, 4)), TRUSS_MID)
			draw_rect(Rect2(tip + Vector2(-1, 4), Vector2(1, 2)), ROD_COLORS[0])
			draw_rect(Rect2(tip + Vector2(1, 4), Vector2(1, 2)), ROD_COLORS[0])
			var f := FROST
			f.a = 0.6
			draw_rect(Rect2(tip + Vector2(-1, 0), Vector2(3, 1)), f)
		"loop":
			# Beads of ice along the low point.
			for k in [5, 6, 8]:
				draw_rect(Rect2(points[k].round() + Vector2(0, 1), Vector2.ONE), ICE)
		"frayed":
			draw_rect(Rect2(tip + Vector2(0, 1), Vector2.ONE), Color(0.85, 0.5, 0.2))
			draw_rect(Rect2(tip + Vector2(1, 1), Vector2.ONE), Color(0.6, 0.35, 0.15))


func _roll_big_grime(w: int, rng_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var grime: Array = []
	var keep := Rect2(BIG_TEXT_X - 5, 3, w - BIG_TEXT_X - 6, BIG_H - 6)
	var poly := _big_polygon(Vector2i.ZERO, w, BIG_H)
	var tries := 0
	while grime.size() < 60 and tries < 3000:
		tries += 1
		var g := Vector2(rng.randi_range(1, w - 6), rng.randi_range(2, BIG_H - 3))
		if keep.has_point(g) or not Geometry2D.is_point_in_polygon(g, poly):
			continue
		if g.x > 6 and g.x < 15 and absf(g.y - BIG_H * 0.5) < 5.0:
			continue
		grime.append([g, RUST_COLORS[rng.randi_range(0, RUST_COLORS.size() - 1)]])
		if rng.randf() < 0.3:
			for k in rng.randi_range(1, 3):
				if g.y + k < BIG_H - 2:
					grime.append([g + Vector2(0, k), RUST_COLORS[1]])
	return grime


func _emit_ambient_sparks(delta: float) -> void:
	_panel_spark_wait -= delta
	if _panel_spark_wait <= 0.0:
		_panel_spark_wait = _rng.randf_range(spark_interval.x * 2.0, spark_interval.y * 2.5)
		var index := _panel_index()
		if index >= 0 and (_panels[index].light as PauseMenu.NeonLight).level > 0.5:
			var r := _panel_rect(index)
			var spot := Vector2(r.position) + Vector2(1, _rng.randi_range(PANEL_CHAMFER, 60))
			_sparks.emit(spot, _rng.randi_range(1, 2), PI + _rng.randf_range(-0.6, 0.6), 0.8,
					15.0, 40.0, 0.12, 0.28)
	for i in _buttons.size():
		var b := _buttons[i]
		b.spark_wait = float(b.spark_wait) - delta
		if float(b.spark_wait) > 0.0:
			continue
		var r := _button_rect(i)
		if str(b.style.cable) == "frayed":
			b.spark_wait = _rng.randf_range(0.5, 2.2)
			var tip := Vector2(r.end.x + 6, r.position.y + 28)
			_sparks.emit(tip, _rng.randi_range(2, 5), PI / 2.0, 1.3, 15.0, 50.0, 0.1, 0.3)
		elif i == selected and _mode == Mode.BUTTONS:
			b.spark_wait = _rng.randf_range(spark_interval.x, spark_interval.y)
			if (b.light as PauseMenu.NeonLight).level > 0.5:
				var spot := Vector2(r.position) + Vector2(BIG_TEXT_X + _rng.randi_range(0, 60), 4)
				_sparks.emit(spot, _rng.randi_range(1, 3), -PI / 2.0 + _rng.randf_range(-1, 1),
						0.9, 20.0, 55.0, 0.12, 0.3)
		else:
			b.spark_wait = 1.0


# --- Displays --------------------------------------------------------------------------------


## Displays hang from the top edge on two chains and are lowered into the middle.
func _panel_rect(index: int) -> Rect2i:
	var track: PauseMenu.MechTrack = _panels[index].track
	var screen := _screen_size()
	var x := roundi((screen.x - panel_size.x) * 0.5)
	var rest_y := roundi((screen.y - panel_size.y) * 0.5) + 6
	var y := floori(lerpf(-panel_size.y - 14.0, rest_y, track.value))
	var offset := _shake_offset(211 + index, track.shake)
	offset.y = mini(offset.y, 0)
	return Rect2i(Vector2i(x, y) + offset, panel_size)


func _chain_xs(r: Rect2i) -> Array[int]:
	return [r.position.x + 46, r.end.x - 48]


func _on_panel_tag(index: int, tag: String) -> void:
	var r := _panel_rect(index)
	match tag:
		"locked":
			for x in _chain_xs(r):
				_vent(Vector2(x - 2, r.position.y - 1), PI, 6, 30.0)
				_vent(Vector2(x + 3, r.position.y - 1), 0.0, 6, 30.0)
			_vent(Vector2(r.position.x + 3, r.end.y - 3), PI * 0.8, 5, 18.0)
			_vent(Vector2(r.end.x - 3, r.end.y - 3), PI * 0.2, 5, 18.0)
			(_panels[index].light as PauseMenu.NeonLight).strike()
			for k in 8:
				_ice.emit(Vector2(r.position.x + _rng.randi_range(8, r.size.x - 8), r.end.y), 1,
						PI / 2.0, 0.6, 5.0, 20.0, 0.4, 0.9)
		"catch":
			for x in _chain_xs(r):
				_vent(Vector2(x + 1, r.position.y - 2), -PI / 2.0, 2, 12.0)
		"release":
			for x in _chain_xs(r):
				_vent(Vector2(x, r.position.y - 1), -PI / 2.0, 5, 30.0)


func _draw_panel(index: int) -> void:
	var panel := _panels[index]
	var r := _panel_rect(index)
	if r.end.y <= 0:
		return
	var p := r.position
	var w := panel_size.x
	var h := panel_size.y
	var c := PANEL_CHAMFER

	# Chains up through the top edge.
	for x in _chain_xs(r):
		var y := p.y - 1
		var link := 0
		while y > -4:
			if link % 2 == 0:
				draw_rect(Rect2(x, y - 4, 3, 5), TRUSS_MID, false, 1.0)
				draw_rect(Rect2(x, y - 4, 1, 1), TRUSS_LIGHT)
			else:
				draw_rect(Rect2(x + 1, y - 4, 1, 5), TRUSS_LIGHT.darkened(0.2))
			if link % 5 == 2:
				var f := FROST
				f.a = 0.5
				draw_rect(Rect2(x - 1, y - 4, 1, 2), f)
			y -= 4
			link += 1
		draw_rect(Rect2(x - 3, p.y - 3, 9, 4), TRUSS_DARK)
		draw_rect(Rect2(x - 2, p.y - 3, 7, 1), TRUSS_LIGHT)

	draw_colored_polygon(_panel_polygon(p + Vector2i(4, 4)), Color(0, 0, 0, 0.3))
	draw_colored_polygon(_panel_polygon(p), PLAQUE_COLOR)
	draw_rect(Rect2(p.x + c, p.y, w - c - 4, 1), PLAQUE_LIGHT)
	draw_rect(Rect2(p.x + c, p.y + 1, w - c - 4, 1), PLAQUE_LIGHT.darkened(0.35))
	for k in c:
		draw_rect(Rect2(p.x + c - 1 - k, p.y + 1 + k, 1, 1), PLAQUE_LIGHT)
		draw_rect(Rect2(p.x + k, p.y + h - c + k, 1, 1), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x, p.y + c, 1, h - c * 2), PLAQUE_LIGHT.darkened(0.25))
	draw_rect(Rect2(p.x + c, p.y + h - 1, w - c, 1), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + w - 4, p.y, 1, h), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + w - 3, p.y + 1, 3, h - 2), PLAQUE_COLOR.darkened(0.25))
	for g in panel.grime:
		draw_rect(Rect2(Vector2(p) + g[0], Vector2.ONE), g[1])
	for x in range(10, w - 6, 24):
		draw_rect(Rect2(p.x + x, p.y + 2, 1, 1), HudDraw.RIVET_COLOR)
		draw_rect(Rect2(p.x + x + 6, p.y + h - 3, 1, 1), HudDraw.RIVET_COLOR)
	for y in range(30, h - 10, 30):
		draw_rect(Rect2(p.x + 4, p.y + y, 1, 1), HudDraw.RIVET_COLOR)
		draw_rect(Rect2(p.x + w - 7, p.y + y + 8, 1, 1), HudDraw.RIVET_COLOR)
	# Side vents and worn hazard paint.
	for k in 6:
		draw_rect(Rect2(p.x + 3, p.y + h - 60 + k * 3, 7, 1), PLAQUE_SHADOW)
		draw_rect(Rect2(p.x + w - 11, p.y + 40 + k * 3, 6, 1), PLAQUE_SHADOW)
	for k in 4:
		draw_rect(Rect2(p.x + 1, p.y + 70 + k * 5, 2, 3), Color(0.42, 0.3, 0.08))

	var light: PauseMenu.NeonLight = panel.light
	var level := light.level * (0.95 + 0.05 * sin(_time * 23.0))

	# Title strip and BACK.
	draw_rect(Rect2(p.x + 4, p.y + 7, 4, 5), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + 5, p.y + 8, 2, 3), LAMP_OFF.lerp(LAMP_ON, clampf(level, 0.0, 1.0)))
	var title_channel := Rect2(p.x + 10, p.y + 4, back_rect.position.x - 13, 13)
	draw_rect(title_channel, CHANNEL_COLOR)
	draw_rect(Rect2(title_channel.position, Vector2(title_channel.size.x, 1)), PLAQUE_SHADOW)
	_draw_neon(panel.title, p + Vector2i(14, 7), level, 1.0, BUTTON_TUBE, BUTTON_CORE,
			BUTTON_GHOST)
	var active := index == _panel_index()
	_draw_back_button(p, level, active and _focus < 0)

	# Screen.
	var s := Rect2i(p + panel_screen.position, panel_screen.size)
	draw_rect(Rect2(s.grow(2)), PLAQUE_SHADOW)
	draw_rect(Rect2(s.position.x - 2, s.end.y + 1, s.size.x + 4, 1), PLAQUE_LIGHT.darkened(0.3))
	draw_rect(Rect2(s.end.x + 1, s.position.y - 2, 1, s.size.y + 4), PLAQUE_LIGHT.darkened(0.3))
	draw_rect(Rect2(s), SCREEN_BG)
	if level > 0.02:
		var scrambled := active and _glitch_left > GLITCH_TIME * 0.5
		if not scrambled:
			_draw_screen(index, s, level, active)
		if active and _glitch_left > 0.0:
			_draw_glitch(s, level)
		var scan := Color(0, 0, 0, 0.28)
		for y in range(s.position.y + 1, s.end.y, 2):
			draw_rect(Rect2(s.position.x, y, s.size.x, 1), scan)
		var band_y := s.position.y + int(fmod(_time * 26.0, s.size.y + 12.0)) - 6
		var band := PHOSPHOR
		band.a = 0.05 * level
		for k in 8:
			var y := band_y + k
			if y >= s.position.y and y < s.end.y:
				draw_rect(Rect2(s.position.x, y, s.size.x, 1), band)
	_draw_glass_frost(s, 500 + index)
	draw_rect(Rect2(s.position.x + 1, s.position.y + 1, 8, 1), Color(1, 1, 1, 0.06))
	draw_rect(Rect2(s.position.x + 1, s.position.y + 2, 1, 5), Color(1, 1, 1, 0.06))

	# Temperature readout under the screen, in amber LEDs.
	var temp_level := 0.35 + 0.65 * clampf(level, 0.0, 1.0)
	draw_rect(Rect2(p.x + w - 48, s.end.y + 4, 30, 9), PLAQUE_SHADOW)
	_draw_neon(_temp_text, Vector2i(p.x + w - 45, s.end.y + 6), temp_level, 0.0, LED_AMBER,
			LED_AMBER.lightened(0.5), Color(0.2, 0.08, 0.03))
	# A thermometer with almost nothing in it.
	draw_rect(Rect2(p.x + w - 54, s.end.y + 4, 3, 7), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + w - 53, s.end.y + 9, 1, 2), ICE)

	# Frost along the top, icicles under the housing.
	for x in range(c, w - 4):
		if hash(Vector2i(x, index)) % 3 != 0:
			var f := FROST
			f.a = 0.55 + float(hash(x) % 30) / 100.0
			draw_rect(Rect2(p.x + x, p.y - (hash(x * 3) % 2), 1, 1), f)
	_draw_icicles(_panel_ice[index], Vector2i(p.x + 5, p.y + h))


## Load and new game slots get more detail on the big screen: Europa time, charge and the
## state each part was saved in.
func _draw_slot(s: Rect2i, k: int, level: float, active: bool) -> void:
	super(s, k, level, active)
	var index := _slot_page * SAVE_SLOTS.PAGE_SIZE + k
	var data := SAVE_SLOTS.get_slot(index)
	if data.is_empty() or (not _slot_box.is_empty() and int(_slot_box.slot) == index):
		return
	var r := _slot_box_rect(s, k)
	var on := active and _focus == k
	var bright := level * (1.0 if on else 0.6)
	var col := r.position.x + 128
	var dotted := PHOSPHOR_DIM
	dotted.a = level * 0.6
	for y in range(r.position.y + 12, r.end.y - 4, 2):
		draw_rect(Rect2(col - 6, y, 1, 1), dotted)
	var minutes := int(float(data.get("europa_minutes", 0.0)))
	_draw_neon(_txt("EUROPA"), Vector2i(col, r.position.y + 13), bright * 0.6, 0.0, PHOSPHOR,
			PHOSPHOR_CORE, SCREEN_BG)
	_draw_neon(_txt("%02d:%02d" % [floori(minutes / 60.0), minutes % 60]), Vector2i(col + 34,
			r.position.y + 13), bright, 0.0, PHOSPHOR, PHOSPHOR_CORE, SCREEN_BG)
	var ratio := clampf(float(data.get("charge", 0.0)) / maxf(float(data.get("max_charge",
			1000.0)), 1.0), 0.0, 1.0)
	_draw_neon(_txt("CHARGE"), Vector2i(col, r.position.y + 21), bright * 0.6, 0.0, PHOSPHOR,
			PHOSPHOR_CORE, SCREEN_BG)
	var groove := PHOSPHOR_DIM
	groove.a = level
	draw_rect(Rect2(col + 34, r.position.y + 22, 40, 3), groove)
	var fill := LED_AMBER
	fill.a = bright
	draw_rect(Rect2(col + 34, r.position.y + 22, roundi(40 * ratio), 3), fill)
	_draw_neon(_txt("%d%%" % roundi(ratio * 100.0)), Vector2i(col + 78, r.position.y + 21),
			bright, 0.0, PHOSPHOR, PHOSPHOR_CORE, SCREEN_BG)
	var keys := ["core", "legs", "systems"]
	for part in 3:
		var state := clampi(int(data.get(keys[part], 0)), 0, 3)
		var color := PART_COLORS[state]
		color.a = bright
		var ip := Vector2(col + part * 9, r.position.y + 30)
		for gy in 5:
			var row: String = PART_ICONS[part][gy]
			for gx in 5:
				if row[gx] == "1":
					draw_rect(Rect2(ip + Vector2(gx, gy), Vector2.ONE), color)


# --- Mouse -----------------------------------------------------------------------------------
# The mouse works everywhere in the main menu: hovering highlights, left click picks, right click
# steps back, the wheel moves up and down. The cursor stays hidden until the mouse moves, and any
# key or pad button hides it again and hands control back to the keyboard.


func _setup_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	for child in get_children():
		if child.get_script() == DEV_MENU_SCRIPT:
			_dev_menu = child as Control
	_cursor_layer = CanvasLayer.new()
	# Over the menu and the dev tools, under the brightness overlay.
	_cursor_layer.layer = 110
	add_child(_cursor_layer)
	_cursor = Control.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cursor_layer.add_child(_cursor)
	_cursor.draw.connect(_draw_cursor)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.relative.length_squared() > 0.0:
			_mouse_on = true
			var pos := (make_input_local(motion) as InputEventMouseMotion).position
			_hover(pos)
			# Dragging a slider.
			if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
				var hit := _hit(pos)
				if str(hit.get("kind", "")) == "option" and _is_slider(int(hit.index)):
					_set_slider(int(hit.index), pos)
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		_mouse_on = true
		if button.pressed:
			match button.button_index:
				MOUSE_BUTTON_LEFT:
					_click((make_input_local(button) as InputEventMouseButton).position)
				MOUSE_BUTTON_RIGHT:
					_right_click()
				MOUSE_BUTTON_WHEEL_UP:
					_step(-1)
				MOUSE_BUTTON_WHEEL_DOWN:
					_step(1)
		get_viewport().set_input_as_handled()
		return
	if (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_mouse_on = false
		_cursor_alpha = 0.0
		_hover_t = 0.0
	super(event)


## What's under the mouse: {"kind", "index"}, or empty. Kinds: "button" (a main plaque),
## "focus" (a row, slot or BACK on a display), "page" (0 left, 1 right), "option" (a settings
## row), "key_reset" (a controls row's reset symbol), "box" (a slot's choice plate),
## "conflict" (REVERT or SWAP).
func _hit(pos: Vector2) -> Dictionary:
	var at := Vector2i(pos.floor())
	if _mode == Mode.BUTTONS:
		for i in _buttons.size():
			if _button_rect(i).has_point(at):
				return {"kind": "button", "index": i}
		return {}
	var index := _panel_index()
	if index < 0:
		return {}
	var p := _panel_rect(index).position
	var s := Rect2i(p + panel_screen.position, panel_screen.size)
	if not _conflict.is_empty():
		var box := Rect2i(s.position.x + 5, s.position.y + 44, s.size.x - 10, 52)
		var gap := box.size.x - 44 * 2 - 12
		for i in 2:
			if Rect2i(box.position.x + 6 + i * (44 + gap), box.position.y + 30, 44, 15).has_point(at):
				return {"kind": "conflict", "index": i}
		return {}
	if not _slot_box.is_empty():
		var r := _slot_box_rect(s, int(_slot_box.slot) % SAVE_SLOTS.PAGE_SIZE)
		for i in 2:
			var px := r.position.x + 8 if i == 0 else r.end.x - 8 - 46
			if Rect2i(px, r.position.y + 17, 46, 14).has_point(at):
				return {"kind": "box", "index": i}
		return {}
	if Rect2i(p + back_rect.position, back_rect.size).has_point(at):
		return {"kind": "focus", "index": -1}
	if not s.has_point(at):
		return {}
	match _mode:
		Mode.LOAD, Mode.SAVE, Mode.NEW_GAME:
			for k in SAVE_SLOTS.PAGE_SIZE:
				if _slot_box_rect(s, k).has_point(at):
					return {"kind": "focus", "index": k}
			var y := s.position.y + page_row_y
			var cx := s.position.x + (s.size.x >> 1)
			for i in 2:
				var bx := cx - 34 if i == 0 else cx + 34 - PAGE_BUTTON.x
				if Rect2i(bx, y, PAGE_BUTTON.x, PAGE_BUTTON.y).has_point(at):
					return {"kind": "page", "index": i}
			if Rect2i(s.position.x, y - 2, s.size.x, PAGE_BUTTON.y + 4).has_point(at):
				return {"kind": "focus", "index": SAVE_SLOTS.PAGE_SIZE}
		Mode.SETTINGS:
			if _settings_page >= 0:
				var options: Array = _pages[_settings_page]
				var row := floori(float(at.y - s.position.y - option_top) / option_h)
				if at.y >= s.position.y + option_top and row >= 0 and row < _visible_options():
					row += _option_scroll
					if row < options.size():
						var item: Dictionary = options[row]
						var icon := _key_reset_rect(s, row).grow(3)
						var on_icon: bool = item.kind == "key" and icon.has_point(at)
						return {"kind": "key_reset" if on_icon else "option", "index": row}
			else:
				var n := _category_rows.size()
				var row := floori(float(at.y - s.position.y - SETTINGS_TOP) / settings_row_h)
				if at.y >= s.position.y + SETTINGS_TOP and row >= 0 and row < n:
					return {"kind": "focus", "index": row}
				var dev_y := s.position.y + SETTINGS_TOP + n * settings_row_h + 2
				if at.y >= dev_y and at.y < dev_y + _text_h() + 4:
					return {"kind": "focus", "index": n}
	return {}


func _hover(pos: Vector2) -> void:
	var hit := _hit(pos)
	if hit.is_empty():
		return
	var index := int(hit.index)
	match str(hit.kind):
		"button":
			if index != selected:
				_select(index)
		"focus", "option", "key_reset":
			if _capturing < 0:
				_focus = index
				_option_col = 1 if str(hit.kind) == "key_reset" else 0
		"page":
			_focus = SAVE_SLOTS.PAGE_SIZE
		"box":
			if int(_slot_box.choice) != index:
				_slot_box.choice = index
				_slot_box.armed = false
		"conflict":
			_conflict.choice = index


func _click(pos: Vector2) -> void:
	_click_left = CLICK_TIME
	if _capturing >= 0:
		# Clicking while a controls row waits for a key gives up on it.
		_capturing = -1
		return
	var hit := _hit(pos)
	var kind := str(hit.get("kind", ""))
	if not _conflict.is_empty():
		if kind == "conflict":
			_conflict.choice = int(hit.index)
			_conflict_input(_action_event("menu_confirm"))
		return
	if not _slot_box.is_empty():
		if kind == "box":
			_hover(pos)
			_slot_box_input(_action_event("menu_confirm"))
		else:
			_slot_box = {}
		return
	if hit.is_empty():
		return
	_hover(pos)
	match kind:
		"button":
			_confirm()
		"focus":
			_panel_confirm()
		"page":
			_turn_page(-1 if int(hit.index) == 0 else 1)
		"option", "key_reset":
			if _is_slider(int(hit.index)):
				_set_slider(int(hit.index), pos)
			else:
				_activate_option()


## Right click steps back: closes a choice box or warning, or goes back a screen.
func _right_click() -> void:
	_click_left = CLICK_TIME
	if _capturing >= 0:
		_capturing = -1
	elif not _conflict.is_empty():
		_conflict = {}
	elif not _slot_box.is_empty():
		_slot_box = {}
	elif _mode != Mode.BUTTONS:
		_go_back()


func _is_slider(row: int) -> bool:
	if _mode != Mode.SETTINGS or _settings_page < 0:
		return false
	var item: Dictionary = _pages[_settings_page][row]
	return item.kind == "slider"


## Sets a slider from where on its track the mouse is.
func _set_slider(row: int, pos: Vector2) -> void:
	var p := _panel_rect(_panel_index()).position
	var s := Rect2i(p + panel_screen.position, panel_screen.size)
	var track_x := s.end.x - 8 + 3 - slider_w
	if pos.x < track_x - 3:
		return
	var v := snappedf(clampf((pos.x - track_x) / slider_w, 0.0, 1.0), SLIDER_STEP)
	_apply_slider(_pages[_settings_page][row], v)


func _action_event(action: StringName) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func _update_cursor(delta: float) -> void:
	var shown := _mouse_on and not (_dev_menu != null and _dev_menu.visible)
	_cursor_alpha = move_toward(_cursor_alpha, 1.0 if shown else 0.0, delta * 10.0)
	var hovering := shown and not _hit(get_local_mouse_position()).is_empty()
	_hover_t = move_toward(_hover_t, 1.0 if hovering else 0.0, delta * 8.0)
	_click_left = maxf(_click_left - delta, 0.0)
	_cursor.queue_redraw()


## A small frosted metal pointer with a neon edge. The tip blinks, brackets close in around it
## over anything clickable, and a click presses it in and flashes a ring.
func _draw_cursor() -> void:
	if _cursor_alpha <= 0.0:
		return
	var a := _cursor_alpha
	var press := 1 if _click_left > CLICK_TIME * 0.4 else 0
	var o := Vector2(_cursor.get_local_mouse_position().floor()) + Vector2(press, press)
	var hum := 0.85 + 0.15 * sin(_time * 9.0)
	if hash(int(_time * 15.0)) % 23 == 0:
		hum *= 0.4
	var neon := BUTTON_TUBE.lerp(BUTTON_CORE, 0.3 * _hover_t)
	neon.a = a * hum
	var halo := BUTTON_TUBE
	halo.a = a * 0.12 * hum
	var shadow := Color(0, 0, 0, 0.4 * a)
	for y in CURSOR.size():
		var row: String = CURSOR[y]
		for x in row.length():
			if row[x] != ".":
				_cursor.draw_rect(Rect2(o + Vector2(x + 1, y + 1), Vector2.ONE), shadow)
	for y in CURSOR.size():
		var row: String = CURSOR[y]
		for x in row.length():
			var color: Color
			match row[x]:
				"o":
					color = Color(0.05, 0.055, 0.06, a)
				"#":
					color = (PLAQUE_LIGHT if y < 5 else PLAQUE_COLOR.lightened(0.12))
					color.a = a
				"c":
					color = neon
					_cursor.draw_rect(Rect2(o + Vector2(x - 1, y), Vector2(3, 1)), halo)
				"f":
					color = FROST
					color.a = a * 0.9
				_:
					continue
			_cursor.draw_rect(Rect2(o + Vector2(x, y), Vector2.ONE), color)
	# The tip blinks.
	if fmod(_time, 0.9) < 0.45:
		var tip := BUTTON_CORE
		tip.a = a
		_cursor.draw_rect(Rect2(o, Vector2.ONE), tip)

	if _hover_t > 0.0:
		var d := roundf(lerpf(8.0, 3.0, ease(_hover_t, 0.4)))
		var mark := BUTTON_TUBE
		mark.a = a * _hover_t * hum
		for corner in 4:
			var sx := -1.0 if corner % 2 == 0 else 1.0
			var sy := -1.0 if corner < 2 else 1.0
			var cpos := o + Vector2(sx * d, sy * d)
			_cursor.draw_rect(Rect2(cpos, Vector2.ONE), mark)
			_cursor.draw_rect(Rect2(cpos - Vector2(sx, 0), Vector2.ONE), mark)
			_cursor.draw_rect(Rect2(cpos - Vector2(0, sy), Vector2.ONE), mark)

	if _click_left > 0.0:
		var t := 1.0 - _click_left / CLICK_TIME
		var ring := BUTTON_CORE
		ring.a = a * (1.0 - t) * 0.8
		var radius := 2.0 + t * 6.0
		for k in 8:
			var q := o + Vector2.from_angle(k * PI / 4.0) * radius
			_cursor.draw_rect(Rect2(q.round(), Vector2.ONE), ring)
