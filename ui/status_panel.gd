extends Control
## HUD status panel above the charge gauge: the Europa clock and the robot's three damage
## indicators (core, legs, systems), on the same grimy plate as the gauge.
##
## A Europa day is 85 hours, so the clock runs from 00:00 to 84:59 and wraps. One full day takes
## day_length_seconds of real time (40 minutes by default).
##
## The indicators are status lights shaped as short bars, one per part, showing its damage
## state: steady green when healthy, yellow with a slight pulse on mild damage, orange pulsing
## hard into red-orange on heavy damage, and a bright, steady red glow on a fault. They sputter a
## little like the rest of the worn hardware (except a fault, which burns steady).

## Hours in a Europa day; the clock shows 00:00 to 84:59.
const DAY_HOURS: int = 85
const PLATE_SIZE := Vector2(116, 13)
const RIVETS: Array = [Vector2(2, 2), Vector2(113, 10)]
const CLOCK_POS := Vector2(4, 4)
const CLOCK_COLOR := Color(0.5, 0.88, 0.92)
## Unlit segments behind the digits, like an old display.
const CLOCK_GHOST_COLOR := Color(0.13, 0.19, 0.21)
## A recessed groove between the clock and the indicators.
const DIVIDER_X: int = 24
const BARS_X: int = 28
const ICON_SIZE: int = 5
## Inner size of each indicator bar.
const BAR_SIZE := Vector2(16, 3)
## Gap between the icon and its bar's well, and between indicators.
const ICON_GAP: int = 2
const GROUP_GAP: int = 4
const WELL_COLOR := Color(0.02, 0.02, 0.03)
const EMPTY_COLOR := Color(0.07, 0.1, 0.08)
const GREEN := Color(0.25, 0.95, 0.45)
const GREEN_TOP := Color(0.7, 1.0, 0.75)
const GREEN_BOTTOM := Color(0.12, 0.55, 0.25)
const ICON_COLOR := Color(0.3, 0.62, 0.38)
const YELLOW := Color(1.0, 0.84, 0.22)
const ORANGE := Color(1.0, 0.52, 0.1)
const RED_ORANGE := Color(1.0, 0.27, 0.07)
const FAULT_RED := Color(1.0, 0.12, 0.09)
## Core (reactor), legs, systems (circuit grid), left to right.
const ICONS: Array = [
	[".111.", "1...1", "1.1.1", "1...1", ".111."],
	[".111.", ".1.1.", ".1.1.", ".1.1.", "11.11"],
	[".1.1.", "11111", ".1.1.", "11111", ".1.1."],
]
## Burnt-out pixel columns in each bar's fill, as offsets from its left end.
const DEAD_COLUMNS: Array = [[11], [], [4, 5]]

## Player whose damage states are shown.
@export var player: Player
## Real seconds for one full Europa day.
@export var day_length_seconds: float = 2400.0
## Europa time the clock starts at, in minutes past 00:00.
@export var start_minutes: float = 0.0
## Chance per frame that an indicator flickers dim for a frame.
@export_range(0.0, 1.0, 0.005) var flicker_chance: float = 0.01

## Current Europa time, in minutes past 00:00.
var europa_minutes: float = 0.0

var _time: float = 0.0
var _grime: Array = []
var _states: Array[int] = [0, 0, 0]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	europa_minutes = start_minutes
	var clock_rect := Rect2(CLOCK_POS, Vector2(HudDraw.text_width("00:00"), HudDraw.GLYPH_HEIGHT))
	var bars_rect := Rect2(BARS_X - 1, 3, PLATE_SIZE.x - BARS_X - 4, 7)
	_grime = HudDraw.roll_grime(PLATE_SIZE, 13, 30, [clock_rect, bars_rect])
	if player == null:
		return
	player.damage_changed.connect(_on_damage_changed)
	_on_damage_changed()


func _process(delta: float) -> void:
	_time += delta
	var day_minutes := DAY_HOURS * 60.0
	europa_minutes = fmod(europa_minutes + delta * day_minutes / day_length_seconds, day_minutes)
	queue_redraw()


func _draw() -> void:
	HudDraw.draw_plate(self, PLATE_SIZE, _grime, RIVETS)
	_draw_clock()

	draw_rect(Rect2(DIVIDER_X, 2, 1, 9), HudDraw.PLATE_SHADOW)
	draw_rect(Rect2(DIVIDER_X + 1, 2, 1, 9), HudDraw.PLATE_LIGHT.darkened(0.3))

	var x := BARS_X
	for i in ICONS.size():
		HudDraw.draw_glyph(self, ICONS[i], Vector2(x, 4), ICON_COLOR)
		x += ICON_SIZE + ICON_GAP
		_draw_indicator(Vector2(x + 1, 5), _states[i], DEAD_COLUMNS[i])
		x += int(BAR_SIZE.x) + 2 + GROUP_GAP


## HH:MM in Europa time. The colon blinks once a real second.
func _draw_clock() -> void:
	HudDraw.draw_text(self, "88:88", CLOCK_POS, CLOCK_GHOST_COLOR)
	var total := int(europa_minutes)
	# Hours and minutes are drawn at fixed spots so the blinking colon never shifts the minutes.
	HudDraw.draw_text(self, "%02d" % floori(total / 60.0), CLOCK_POS, CLOCK_COLOR)
	var minutes_x := HudDraw.text_width("00:") + 1
	HudDraw.draw_text(self, "%02d" % (total % 60), CLOCK_POS + Vector2(minutes_x, 0), CLOCK_COLOR)
	if fmod(_time, 1.0) < 0.5:
		var colon_x := HudDraw.text_width("00") + 1
		HudDraw.draw_text(self, ":", CLOCK_POS + Vector2(colon_x, 0), CLOCK_COLOR)


## One status bar with its inner area at pos, lit for a damage state (Player.Damage).
func _draw_indicator(pos: Vector2, state: int, dead_columns: Array) -> void:
	var cell := Rect2(pos, BAR_SIZE)
	var flicker := randf() < flicker_chance
	var strength := 0.55 if flicker else 0.9 + 0.1 * sin(_time * 2.0 + pos.x)
	var color := GREEN
	var glow := 0.22
	match state:
		Player.Damage.MILD:
			color = YELLOW
			strength = 0.55 if flicker else 0.92 + 0.08 * sin(_time * 4.0)
			glow = 0.26
		Player.Damage.HEAVY:
			# A strong throb, deepening into red-orange at each peak.
			var beat := 0.5 + 0.5 * sin(_time * TAU * 1.3)
			color = ORANGE.lerp(RED_ORANGE, beat)
			strength = 0.5 + 0.5 * beat
			glow = 0.15 + 0.4 * beat
		Player.Damage.FAULT:
			color = FAULT_RED
			strength = 1.0
			glow = 0.55

	var halo := color
	halo.a = glow * strength
	draw_rect(cell.grow(2), halo, false, 1.0)
	if state == Player.Damage.FAULT:
		halo.a = 0.2
		draw_rect(cell.grow(3), halo, false, 1.0)
	draw_rect(cell.grow(1), WELL_COLOR)
	draw_rect(cell, EMPTY_COLOR)

	var top := color.lerp(Color.WHITE, 0.55)
	var bottom := color.darkened(0.5)
	var dim := Color(strength, strength, strength)
	var w := BAR_SIZE.x
	draw_rect(Rect2(pos, Vector2(w, BAR_SIZE.y)), color * dim)
	draw_rect(Rect2(pos, Vector2(w, 1)), top * dim)
	draw_rect(Rect2(pos + Vector2(0, BAR_SIZE.y - 1), Vector2(w, 1)), bottom * dim)
	for column in dead_columns:
		draw_rect(Rect2(pos + Vector2(column, 0), Vector2(1, BAR_SIZE.y)), bottom * 0.6)


func _on_damage_changed() -> void:
	_states = [
		player.get_damage(Player.Part.CORE), player.get_damage(Player.Part.LEGS),
		player.get_damage(Player.Part.SYSTEMS),
	]
