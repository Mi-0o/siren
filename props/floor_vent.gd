@tool
class_name FloorVent
extends Node2D
## A grate set into the floor over an old duct. Every vent in a level joins the same duct
## network: enemies can squeeze in through one, travel under the floor (out of sight, taking
## time for the distance) and come out of another. Place it with its origin on the floor's
## walking surface, centred on the grate. It's only drawn: the grate is flush with the floor and
## nothing falls in.
##
## While an enemy goes in or comes out, open (0 to 1) slides the grate aside; rattle() gives it
## a shake. Below the slats a faint amber light flickers somewhere down the duct.

const GROUP: StringName = &"floor_vents"
const FRAME := Color(0.2, 0.2, 0.21)
const FRAME_LIGHT := Color(0.36, 0.36, 0.37)
const SLAT := Color(0.29, 0.29, 0.3)
const DARK := Color(0.02, 0.02, 0.025)
const RUST := Color(0.34, 0.19, 0.11)
const GLOW := Color(1.0, 0.55, 0.15)

## Width of the opening, in px.
@export var width: int = 18:
	set(value):
		width = maxi(value, 8)
		queue_redraw()

## How far the grate is slid aside, 0 (shut) to 1 (open).
var open: float = 0.0:
	set(value):
		open = clampf(value, 0.0, 1.0)
		queue_redraw()

var _time: float = 0.0
var _rattle: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 1


func _process(delta: float) -> void:
	_time += delta
	_rattle = maxf(_rattle - delta, 0.0)
	queue_redraw()


## Shakes the grate for a moment (something's moving in the duct).
func rattle(seconds: float = 0.3) -> void:
	_rattle = maxf(_rattle, seconds)


## The other vents of this level.
func others() -> Array[FloorVent]:
	var out: Array[FloorVent] = []
	if not is_inside_tree():
		return out
	for node in get_tree().get_nodes_in_group(GROUP):
		if node != self and node is FloorVent:
			out.append(node)
	return out


func _draw() -> void:
	var half := width / 2
	var left := -half
	# The hole: a dark recess with the duct's far glow flickering in it.
	draw_rect(Rect2(left, 0, width, 5), DARK)
	var flicker := 0.12 + 0.08 * sin(_time * 3.1) * sin(_time * 7.7)
	if fmod(_time, 4.3) < 0.08:
		flicker *= 0.3
	draw_rect(Rect2(left + 2, 3, width - 4, 2), Color(GLOW, flicker))
	draw_rect(Rect2(left + 4, 4, width - 8, 1), Color(GLOW, flicker * 1.6))
	# The frame around the opening, sunk in the deck.
	draw_rect(Rect2(left - 2, -1, 2, 6), FRAME)
	draw_rect(Rect2(left + width, -1, 2, 6), FRAME)
	draw_rect(Rect2(left - 2, -1, width + 4, 1), FRAME_LIGHT)
	draw_rect(Rect2(left - 2, 5, width + 4, 1), FRAME)
	draw_rect(Rect2(left - 1, 1, 1, 1), FRAME_LIGHT)
	draw_rect(Rect2(left + width, 1, 1, 1), FRAME_LIGHT)
	# The grate: a plate of slats, slid aside while open, jittering while rattled.
	var shift := roundi(open * (width - 3))
	var jitter := Vector2.ZERO
	if _rattle > 0.0:
		jitter = Vector2(randi_range(-1, 1), randi_range(-1, 0))
	var gx := left + shift + int(jitter.x)
	var gy := int(jitter.y)
	var visible_w := width - shift
	if visible_w > 0:
		draw_rect(Rect2(gx, gy, visible_w, 1), FRAME_LIGHT)
		draw_rect(Rect2(gx, gy + 1, visible_w, 1), FRAME)
		var x := 1
		while x < visible_w - 1:
			draw_rect(Rect2(gx + x, gy, 1, 2), SLAT)
			x += 3
		draw_rect(Rect2(gx, gy, 1, 2), FRAME)
		if visible_w > 2:
			draw_rect(Rect2(gx + visible_w - 1, gy, 1, 2), FRAME)
		# A rust streak and two bolts.
		if visible_w > 6:
			draw_rect(Rect2(gx + 5, gy + 1, 2, 1), RUST)
			draw_rect(Rect2(gx + 1, gy, 1, 1), FRAME_LIGHT)
			draw_rect(Rect2(gx + visible_w - 2, gy, 1, 1), FRAME_LIGHT)
	# Slid aside, the grate sits on the deck beside the hole.
	if shift > 0:
		draw_rect(Rect2(left + width, -2, mini(shift, 10), 1), FRAME_LIGHT)
		draw_rect(Rect2(left + width, -1, mini(shift, 10), 1), FRAME)
