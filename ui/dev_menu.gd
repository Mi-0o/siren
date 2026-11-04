class_name DevMenu
extends Control
## Developer tools panel, opened with the key left of 1 (º on a Spanish keyboard, ` on a US one)
## while dev mode is on in the settings. Mouse only: the cursor shows while it's open and the
## keyboard keeps driving the robot. Keeps working while the game is paused from here.
##
## Rows: FLY, NOCLIP, PAUSE, ZOOM (a slider from 0.25x to 4x for the active camera, kept across
## scenes until the game restarts) and RESET ZOOM, SHOW HITBOXES toggles (the last draws every collision shape and
## live attack hitbox, see HitboxOverlay), REMOVE BURNS (clears every scorch mark and the
## burst's smoke), ADD CANNON CHARGE (one more burst), CHARGE, which unfolds into NO CHARGE USE
## (nothing drains charge), INFINITE REGEN (charge climbs 100/s), a charge slider with its value
## and SET CHARGE to apply it, then DAMAGE, which unfolds into CORE, LEGS and SYSTEMS,
## each with HEALTHY, MILD DAMAGE, HEAVY DAMAGE and FAULT, which set that part's state, plus
## RESTORE ALL to set every part healthy. OPEN PLAYGROUND and OPEN MAIN MENU at the top switch
## to those scenes; the robot rows do nothing where there's no robot (the main menu).
##
## The thin bar along the top drags the panel anywhere on screen. It keeps that spot when closed
## and reopened, and across scene changes, until the game restarts or goes back to the main
## menu, which put it back in its default spot. When the rows don't fit on screen, the list
## scrolls with the mouse wheel or by dragging the scrollbar on the right.

## Damage options, in Player.Damage order, and the short state names shown beside each part.
const DAMAGE_OPTIONS: Array[String] = ["HEALTHY", "MILD DAMAGE", "HEAVY DAMAGE", "FAULT"]
const STATE_NAMES: Array[String] = ["OK", "MILD", "HEAVY", "FAULT"]
const PANEL_X: int = 0
const PANEL_Y: int = 54
const PANEL_W: int = 112
const ROW_H: int = 10
const HEADER_H: int = 13
## The drag bar along the top.
const BAR_H: int = 5
## Fewest rows the panel shrinks to before it stops fitting the screen.
const MIN_ROWS: int = 4
const INDENT: int = 7
const BG := Color(0.03, 0.035, 0.045, 0.72)
const EDGE := Color(1.0, 0.16, 0.12, 0.6)
const TEXT := Color(0.85, 0.88, 0.9)
const TEXT_DIM := Color(0.5, 0.55, 0.58)
const ACCENT := Color(1.0, 0.3, 0.22)
const HOVER := Color(1.0, 1.0, 1.0, 0.07)
const SUBSYSTEMS: Array[String] = ["CORE", "LEGS", "SYSTEMS"]
const SPACE_W: int = 3
const PLAYGROUND_SCENE: String = "res://tests/movement_playground.tscn"
const MAIN_MENU_SCENE: String = "res://ui/main_menu.tscn"
## Zoom slider range, as powers of two: 0.25x to 4x.
const ZOOM_MIN_EXP: float = -2.0
const ZOOM_MAX_EXP: float = 2.0
## Camera zoom set here, applied again to each scene's camera.
static var zoom: float = 1.0

## The robot the tools act on.
var player: Player
## 3x5 glyphs to write with (the pause menu passes its SMALL_GLYPHS).
var font: Dictionary = {}

var _open: bool = false
var _damage_open: bool = false
var _charge_open: bool = false
## Charge level picked on the slider, applied by SET CHARGE.
var _charge_target: float = 0.0
var _dragging: bool = false
## Which slider is being dragged: "charge_slider" or "zoom".
var _drag_id: String = ""
## Which subsystem rows are unfolded, by index into SUBSYSTEMS.
var _sub_open: Array[bool] = [false, false, false]
var _rows: Array[Dictionary] = []
var _hover: int = -1
## Row that was just clicked, flashing for a moment.
var _flash_row: int = -1
var _flash_left: float = 0.0
var _mouse_mode_before: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
## Where the panel was dragged to, kept across scenes; NO_POSITION means the default spot.
const NO_POSITION := Vector2(-1.0, -1.0)
static var _saved_position := NO_POSITION
## First row shown, and how many fit.
var _scroll: int = 0
var _shown: int = 0
var _moving: bool = false
var _grab := Vector2.ZERO
var _scrolling: bool = false
var _bar_hover: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2(PANEL_X, PANEL_Y)
	visible = false
	_place.call_deferred()
	if not InputMap.has_action("dev_menu"):
		InputMap.add_action("dev_menu")
		var key := InputEventKey.new()
		# Physical position, so it's the key left of 1 on every layout.
		key.physical_keycode = KEY_QUOTELEFT
		InputMap.action_add_event("dev_menu", key)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dev_menu"):
		if _open:
			close()
		elif GameSettings.dev_mode:
			open()
		get_viewport().set_input_as_handled()


## Puts the panel where it was last dragged, or back in its default spot in the main menu.
func _place() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == MAIN_MENU_SCENE:
		_saved_position = NO_POSITION
	position = Vector2(PANEL_X, PANEL_Y) if _saved_position == NO_POSITION else _saved_position
	_clamp_position()
	_apply_zoom()


## Keeps the drag bar and a few rows on screen.
func _clamp_position() -> void:
	var view := get_viewport_rect().size
	position = Vector2(
		clampf(roundf(position.x), 0.0, maxf(view.x - PANEL_W, 0.0)),
		clampf(roundf(position.y), 0.0, maxf(view.y - _top() - MIN_ROWS * ROW_H - 3, 0.0))
	)


## Height of the bar and the title above the first row.
func _top() -> int:
	return BAR_H + HEADER_H


func open() -> void:
	_open = true
	visible = true
	_mouse_mode_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild()


func close() -> void:
	_open = false
	visible = false
	_hover = -1
	_moving = false
	_scrolling = false
	Input.mouse_mode = _mouse_mode_before


func _process(delta: float) -> void:
	if not _open:
		return
	if not GameSettings.dev_mode:
		close()
		return
	_flash_left = maxf(_flash_left - delta, 0.0)
	_rebuild()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_hover = _row_at(motion.position.y)
		_bar_hover = motion.position.y < BAR_H
		if _moving:
			position = get_viewport().get_mouse_position() - _grab
			_clamp_position()
			_saved_position = position
			_rebuild()
		elif _scrolling:
			_scroll_to(motion.position.y)
		elif _dragging:
			_slide_to(motion.position.x)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_scroll += -1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			_rebuild()
			_hover = _row_at(button.position.y)
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			_dragging = false
			_moving = false
			_scrolling = false
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			var row := _row_at(button.position.y)
			if button.position.y < BAR_H:
				_moving = true
				_grab = get_viewport().get_mouse_position() - position
			elif _overflows() and button.position.x >= PANEL_W - 5 and button.position.y >= _top():
				_scrolling = true
				_scroll_to(button.position.y)
			elif row >= 0 and _rows[row].kind in ["slider", "zoom"]:
				_dragging = true
				_drag_id = _rows[row].id
				_slide_to(button.position.x)
			elif row >= 0:
				_click(_rows[row])
				_flash_row = row
				_flash_left = 0.12
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		_bar_hover = false


func _row_at(y: float) -> int:
	if y < _top():
		return -1
	var index := floori((y - _top()) / ROW_H)
	if index >= _shown:
		return -1
	index += _scroll
	return index if index < _rows.size() else -1


func _overflows() -> bool:
	return _rows.size() > _shown


## Scrolls so the scrollbar's thumb sits under panel y.
func _scroll_to(y: float) -> void:
	var track := float(_shown * ROW_H)
	var t := clampf((y - _top()) / maxf(track, 1.0), 0.0, 1.0)
	_scroll = int(round(t * float(_rows.size() - _shown)))
	_rebuild()


## Lays out the visible rows from what's unfolded, and sizes the panel to fit them, so clicks
## outside it fall through.
func _rebuild() -> void:
	_rows.clear()
	_rows.append({"label": "OPEN PLAYGROUND", "kind": "button", "id": "playground", "indent": 0})
	_rows.append({"label": "OPEN MAIN MENU", "kind": "button", "id": "main_menu", "indent": 0})
	_rows.append({"label": "FLY", "kind": "toggle", "id": "fly", "indent": 0})
	_rows.append({"label": "NOCLIP", "kind": "toggle", "id": "noclip", "indent": 0})
	_rows.append({"label": "PAUSE", "kind": "toggle", "id": "pause", "indent": 0})
	_rows.append({"label": "ZOOM", "kind": "zoom", "id": "zoom", "indent": 0})
	_rows.append({"label": "RESET ZOOM", "kind": "button", "id": "reset_zoom", "indent": 0})
	_rows.append({"label": "SHOW HITBOXES", "kind": "toggle", "id": "hitboxes", "indent": 0})
	_rows.append({"label": "REMOVE BURNS", "kind": "button", "id": "burns", "indent": 0})
	_rows.append({"label": "ADD CANNON CHARGE", "kind": "button", "id": "cannon", "indent": 0})
	_rows.append({"label": "CHARGE", "kind": "fold", "id": "charge", "indent": 0})
	if _charge_open:
		_rows.append({"label": "NO CHARGE USE", "kind": "toggle", "id": "no_charge_use",
				"indent": 1})
		_rows.append({"label": "INFINITE REGEN", "kind": "toggle", "id": "regen", "indent": 1})
		_rows.append({"label": "", "kind": "slider", "id": "charge_slider", "indent": 1})
		_rows.append({"label": "SET CHARGE", "kind": "button", "id": "set_charge", "indent": 1})
	_rows.append({"label": "DAMAGE", "kind": "fold", "id": "damage", "indent": 0})
	if _damage_open:
		for i in SUBSYSTEMS.size():
			_rows.append({"label": SUBSYSTEMS[i], "kind": "fold", "id": "sub", "sub": i,
					"indent": 1})
			if _sub_open[i]:
				for option in DAMAGE_OPTIONS:
					_rows.append({"label": option, "kind": "button", "id": option, "sub": i,
							"indent": 2})
		_rows.append({"label": "RESTORE ALL", "kind": "button", "id": "restore", "indent": 1})
	# As many rows as fit between the panel's top and the bottom of the screen.
	var room := get_viewport_rect().size.y - position.y - _top() - 3
	_shown = mini(_rows.size(), maxi(floori(room / ROW_H), MIN_ROWS))
	_scroll = clampi(_scroll, 0, maxi(_rows.size() - _shown, 0))
	size = Vector2(PANEL_W, _top() + _shown * ROW_H + 3)


func _click(row: Dictionary) -> void:
	match row.id:
		"playground", "main_menu":
			get_tree().paused = false
			close()
			get_tree().change_scene_to_file(
				PLAYGROUND_SCENE if row.id == "playground" else MAIN_MENU_SCENE
			)
			return
		"fly":
			if player != null:
				player.fly_mode = not player.fly_mode
		"noclip":
			if player != null:
				player.noclip = not player.noclip
		"pause":
			get_tree().paused = not get_tree().paused
		"reset_zoom":
			zoom = 1.0
			_apply_zoom()
		"hitboxes":
			HitboxOverlay.set_enabled(not HitboxOverlay.enabled, self)
		"burns":
			get_tree().call_group(Scorch.GROUP, &"queue_free")
		"cannon":
			if player != null:
				player.add_cannon_charge(1)
		"charge":
			_charge_open = not _charge_open
			if _charge_open and player != null:
				_charge_target = roundf(player.charge)
		"no_charge_use":
			if player != null:
				player.dev_no_charge_use = not player.dev_no_charge_use
		"regen":
			if player != null:
				player.dev_infinite_regen = not player.dev_infinite_regen
		"set_charge":
			if player != null:
				player._set_charge(_charge_target)
		"damage":
			_damage_open = not _damage_open
		"sub":
			_sub_open[row.sub] = not _sub_open[row.sub]
		"restore":
			if player != null:
				for part in 3:
					player.set_damage(part as Player.Part, Player.Damage.HEALTHY)
		_:
			_damage(row.sub, row.id)
	_rebuild()


## Sets one subsystem to the state a damage option names.
func _damage(sub: int, option: String) -> void:
	if player == null:
		return
	player.set_damage(sub as Player.Part, DAMAGE_OPTIONS.find(option) as Player.Damage)


func _state(sub: int) -> int:
	return player.get_damage(sub as Player.Part) if player != null else 0


func _is_on(id: String) -> bool:
	match id:
		"fly":
			return player != null and player.fly_mode
		"noclip":
			return player != null and player.noclip
		"pause":
			return get_tree().paused
		"hitboxes":
			return HitboxOverlay.enabled
		"no_charge_use":
			return player != null and player.dev_no_charge_use
		"regen":
			return player != null and player.dev_infinite_regen
	return false


## The slider's track, from its left to its right end, in panel x.
func _slider_track() -> Vector2i:
	return Vector2i(5 + INDENT, PANEL_W - 24)


## The zoom slider's track, right of its label.
func _zoom_track() -> Vector2i:
	return Vector2i(5 + 22, PANEL_W - 27)


## Zooms the camera that's showing the scene. Wildly game-breaking, on purpose: it's for looking
## around while testing.
func _apply_zoom() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.zoom = Vector2(zoom, zoom)


func _slider_max() -> float:
	return player.max_charge if player != null else 1000.0


## Moves the slider being dragged to panel x: charge in steps of 5, zoom in steps of 0.05.
func _slide_to(x: float) -> void:
	if _drag_id == "zoom":
		var zt := _zoom_track()
		var f := clampf((x - zt.x) / float(zt.y - zt.x), 0.0, 1.0)
		zoom = snappedf(pow(2.0, lerpf(ZOOM_MIN_EXP, ZOOM_MAX_EXP, f)), 0.05)
		_apply_zoom()
		return
	var track := _slider_track()
	var t := clampf((x - track.x) / float(track.y - track.x), 0.0, 1.0)
	_charge_target = clampf(roundf(t * _slider_max() / 5.0) * 5.0, 0.0, _slider_max())


func _draw() -> void:
	var w := PANEL_W
	var h := int(size.y)
	draw_rect(Rect2(0, 0, w, h), BG)
	draw_rect(Rect2(w - 1, 0, 1, h), EDGE)
	draw_rect(Rect2(0, 0, w, 1), EDGE)
	draw_rect(Rect2(0, h - 1, w, 1), EDGE)
	# The drag bar: a darker strip with a grip of dots in the middle.
	draw_rect(Rect2(1, 1, w - 2, BAR_H - 1), Color(ACCENT, 0.3 if _bar_hover or _moving else 0.14))
	for gx in range(w / 2 - 8, w / 2 + 9, 2):
		draw_rect(Rect2(gx, 2, 1, 1), Color(ACCENT, 0.8 if _bar_hover or _moving else 0.5))
		draw_rect(Rect2(gx + 1, 3, 1, 1), Color(ACCENT, 0.8 if _bar_hover or _moving else 0.5))
	draw_rect(Rect2(0, BAR_H, w, 1), EDGE)
	_text("DEV TOOLS", Vector2i(5, BAR_H + 4), ACCENT)
	draw_rect(Rect2(4, _top() - 3, w - 9, 1), Color(ACCENT, 0.4))

	if _overflows():
		# Scrollbar: a dim track down the right edge, the thumb showing the part in view.
		var track := _shown * ROW_H
		var thumb := maxi(int(round(float(track) * _shown / _rows.size())), 3)
		var ty := _top() + int(round(float(track - thumb) * _scroll / (_rows.size() - _shown)))
		draw_rect(Rect2(w - 3, _top(), 1, track), Color(TEXT_DIM, 0.3))
		draw_rect(Rect2(w - 4, ty, 2, thumb), ACCENT if _scrolling else Color(ACCENT, 0.7))

	for i in range(_scroll, _scroll + _shown):
		var row := _rows[i]
		var y := _top() + (i - _scroll) * ROW_H
		if i == _hover:
			draw_rect(Rect2(1, y, w - 2, ROW_H), HOVER)
		if i == _flash_row and _flash_left > 0.0:
			draw_rect(Rect2(1, y, w - 2, ROW_H), Color(ACCENT, 0.25))
		var x := 5 + int(row.indent) * INDENT
		var ty := y + 3
		match row.kind:
			"toggle":
				var on := _is_on(row.id)
				_checkbox(Vector2i(x, ty), on)
				_text(row.label, Vector2i(x + 8, ty), TEXT if on or i == _hover else TEXT_DIM)
			"fold":
				var unfolded: bool
				match row.id:
					"damage":
						unfolded = _damage_open
					"charge":
						unfolded = _charge_open
					_:
						unfolded = _sub_open[row.sub]
				_text("-" if unfolded else "+", Vector2i(x, ty), ACCENT)
				_text(row.label, Vector2i(x + 6, ty), TEXT)
				if row.id == "sub":
					var state := STATE_NAMES[_state(row.sub)]
					_text(state, Vector2i(w - 6 - _text_width(state), ty), _state_color(row.sub))
			"button":
				draw_rect(Rect2(x, ty + 2, 2, 1), ACCENT)
				_text(row.label, Vector2i(x + 4, ty), TEXT if i == _hover else TEXT_DIM)
			"slider":
				_slider(ty, i == _hover or (_dragging and _drag_id == "charge_slider"))
			"zoom":
				_zoom_slider(x, ty, i == _hover or (_dragging and _drag_id == "zoom"))


## The charge slider: a track filled up to the picked level, a handle, and the number.
func _slider(ty: int, hot: bool) -> void:
	var track := _slider_track()
	var t := _charge_target / maxf(_slider_max(), 1.0)
	var hx := track.x + int(round(t * float(track.y - track.x)))
	draw_rect(Rect2(track.x, ty + 2, track.y - track.x + 1, 1), Color(TEXT_DIM, 0.6))
	draw_rect(Rect2(track.x, ty + 2, hx - track.x, 1), ACCENT)
	draw_rect(Rect2(hx, ty, 1, 5), TEXT if hot else TEXT_DIM)
	var value := str(int(_charge_target))
	_text(value, Vector2i(PANEL_W - 6 - _text_width(value), ty), TEXT if hot else TEXT_DIM)


## ZOOM, a track on a doubling scale with a tick at 1x, the handle and the zoom (e.g. 1.50X).
func _zoom_slider(x: int, ty: int, hot: bool) -> void:
	_text("ZOOM", Vector2i(x, ty), TEXT if hot else TEXT_DIM)
	var track := _zoom_track()
	var f := inverse_lerp(ZOOM_MIN_EXP, ZOOM_MAX_EXP, log(zoom) / log(2.0))
	var hx := track.x + int(round(clampf(f, 0.0, 1.0) * float(track.y - track.x)))
	var one_x := track.x + ((track.y - track.x) >> 1)
	draw_rect(Rect2(track.x, ty + 2, track.y - track.x + 1, 1), Color(TEXT_DIM, 0.6))
	draw_rect(Rect2(one_x, ty + 1, 1, 3), Color(TEXT_DIM, 0.8))
	draw_rect(Rect2(mini(hx, one_x), ty + 2, absi(hx - one_x), 1), ACCENT)
	draw_rect(Rect2(hx, ty, 1, 5), TEXT if hot else TEXT_DIM)
	var value := "%.2fX" % zoom
	_text(value, Vector2i(PANEL_W - 6 - _text_width(value), ty), TEXT if hot else TEXT_DIM)


func _state_color(sub: int) -> Color:
	match _state(sub):
		Player.Damage.MILD:
			return Color(1.0, 0.84, 0.22)
		Player.Damage.HEAVY:
			return Color(1.0, 0.52, 0.1)
		Player.Damage.FAULT:
			return ACCENT
	return Color(0.35, 0.95, 0.5)


func _checkbox(pos: Vector2i, on: bool) -> void:
	var c := TEXT_DIM
	draw_rect(Rect2(pos.x, pos.y, 5, 1), c)
	draw_rect(Rect2(pos.x, pos.y + 4, 5, 1), c)
	draw_rect(Rect2(pos.x, pos.y + 1, 1, 3), c)
	draw_rect(Rect2(pos.x + 4, pos.y + 1, 1, 3), c)
	if on:
		draw_rect(Rect2(pos.x + 1, pos.y + 1, 3, 3), ACCENT)


## Plain 3x5 text in font, top left at pos.
func _text(text: String, pos: Vector2i, color: Color) -> void:
	var x := pos.x
	for ch in text:
		if ch == " ":
			x += SPACE_W
			continue
		var rows: Array = font.get(ch, ["...", "...", "...", "...", "..."])
		for gy in rows.size():
			var line: String = rows[gy]
			for gx in line.length():
				if line[gx] == "#":
					draw_rect(Rect2(x + gx, pos.y + gy, 1, 1), color)
		x += (rows[0] as String).length() + 1


func _text_width(text: String) -> int:
	var width := 0
	for ch in text:
		if ch == " ":
			width += SPACE_W
			continue
		var rows: Array = font.get(ch, ["..."])
		width += (rows[0] as String).length() + 1
	return maxi(width - 1, 0)
