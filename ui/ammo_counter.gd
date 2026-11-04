class_name AmmoCounter
extends Control
## HUD cannon-charge counter, under the charge bar: a tiny CRT screen set in a grimy metal plate,
## showing a shell icon and how many charges the burst (F) has left, in white phosphor.
##
## CRT look: scanlines, a faint bloom round the glyphs, a slow rolling bright band, a slight
## brightness flicker, and a jolt (flash, sideways jitter) when the count changes. At zero the
## digits sit dim and blink.

const PLATE_SIZE := Vector2(25, 13)
const RIVETS: Array = [Vector2(2, 2), Vector2(22, 10)]
const SCREEN := Rect2(4, 3, 15, 7)
const SCREEN_COLOR := Color(0.025, 0.035, 0.04)
const PHOSPHOR := Color(0.92, 0.97, 1.0)
const BLOOM := Color(0.6, 0.8, 1.0)
const SHELL: Array = ["010", "111", "111", "101", "111"]
## Seconds for the rolling band to cross the screen, and pause before the next.
const ROLL_TIME: float = 0.6
const ROLL_GAP: float = 2.4

## Player whose cannon charges are shown.
@export var player: Player

var _count: int = 0
var _time: float = 0.0
var _jolt: float = 0.0
var _flicker: float = 1.0
var _grime: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = PLATE_SIZE
	size = PLATE_SIZE
	_grime = HudDraw.roll_grime(PLATE_SIZE, 11, 10, [SCREEN.grow(1)])
	if player == null:
		return
	player.cannon_charges_changed.connect(_on_changed)
	_count = player.cannon_charges


func _on_changed(count: int) -> void:
	if count != _count:
		_jolt = 1.0
	_count = count


func _process(delta: float) -> void:
	_time += delta
	_jolt = maxf(_jolt - delta / 0.25, 0.0)
	_flicker = randf_range(0.88, 1.0)
	queue_redraw()


func _draw() -> void:
	HudDraw.draw_plate(self, PLATE_SIZE, _grime, RIVETS)
	draw_rect(SCREEN.grow(1), Color(0.0, 0.0, 0.0, 0.8), false, 1.0)
	draw_rect(SCREEN, SCREEN_COLOR.lerp(Color(0.3, 0.35, 0.4), 0.5 * _jolt))

	var level := _flicker
	if _count == 0:
		# Empty: dim, blinking.
		level *= 0.3 if fmod(_time, 1.0) < 0.5 else 0.15
	level = minf(level + 0.6 * _jolt, 1.6)
	var jitter := Vector2(roundf(randf_range(-1.0, 1.0) * _jolt), 0.0)
	var text := "%02d" % mini(_count, 99)
	var x := SCREEN.position.x + 2.0
	var y := SCREEN.position.y + 1.0
	var glyphs: Array = [[SHELL, Vector2(x, y)]]
	x += 5.0
	for c in text:
		glyphs.append([HudDraw.GLYPHS[c], Vector2(x, y)])
		x += 4.0
	var bloom := Color(BLOOM, 0.18 * minf(level, 1.0))
	for g: Array in glyphs:
		for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			HudDraw.draw_glyph(self, g[0], g[1] + o + jitter, bloom)
	var color := PHOSPHOR * Color(level, level, level, 1.0)
	color.a = clampf(level, 0.0, 1.0)
	for g: Array in glyphs:
		HudDraw.draw_glyph(self, g[0], g[1] + jitter, color)

	# Scanlines over everything on the screen, and the slow rolling band.
	for row in range(0, int(SCREEN.size.y), 2):
		draw_rect(Rect2(SCREEN.position + Vector2(0, row + 1), Vector2(SCREEN.size.x, 1)),
				Color(0.0, 0.0, 0.0, 0.35))
	var cycle := fmod(_time, ROLL_TIME + ROLL_GAP)
	if cycle < ROLL_TIME:
		var band := int(cycle / ROLL_TIME * SCREEN.size.y)
		draw_rect(Rect2(SCREEN.position + Vector2(0, band), Vector2(SCREEN.size.x, 1)),
				Color(PHOSPHOR, 0.12))
