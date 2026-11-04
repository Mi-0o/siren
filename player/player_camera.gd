class_name PlayerCamera
extends Camera2D
## The camera riding on the robot. Holding left or right eases it a little ahead that way, even
## when the robot can't move (against a wall); holding look up or look down (the up and down
## arrows by default) eases it up or down to see what's there while the robot looks that way.
## Letting go eases it back. Stepping up a low ledge lifts the robot at once, but the view
## follows it up smoothly.
##
## The look is added after the limits (limit_left/top/right/bottom): the view rests where the
## limits put it and looking reveals up to the look distance past them, so looking works even
## in a room exactly one screen tall. The camera applies the limits itself (Godot's own are
## switched off at start), and leaves the offset to the screen shake.

## The robot whose controls steer the camera. Defaults to the parent.
@export var player: Player
## How far the view leans ahead with left or right held, and up or down with look held, in px.
@export var look_ahead: float = 26.0
@export var look_up: float = 56.0
@export var look_down: float = 44.0
## Seconds the camera takes to get most of the way to where it's heading (smaller is snappier).
@export var smooth_time: float = 0.35

const NO_LIMIT: int = 10000000

var _base := Vector2.ZERO
var _limits := Rect2i()
var _look := Vector2.ZERO
## Height still to catch up after stepping up a low ledge, easing to 0.
var _step: float = 0.0


func _ready() -> void:
	_base = position
	if player == null:
		player = get_parent() as Player
	_limits = Rect2i(limit_left, limit_top, limit_right - limit_left, limit_bottom - limit_top)
	limit_left = -NO_LIMIT
	limit_top = -NO_LIMIT
	limit_right = NO_LIMIT
	limit_bottom = NO_LIMIT
	if player != null:
		player.stepped_up.connect(func(height: float) -> void: _step += height)
	_follow()


func _process(delta: float) -> void:
	var look := player.look_input() if player != null else Vector2.ZERO
	var target := Vector2(look.x * look_ahead, look.y * (look_down if look.y > 0.0 else look_up))
	# Exponential ease, so it starts gently and settles without overshoot at any frame rate.
	_look = target + (_look - target) * exp(-delta / maxf(smooth_time, 0.01))
	_step *= exp(-delta / 0.12)
	_follow()


## Centres on the robot, held inside the limits, then shifted by the look.
func _follow() -> void:
	var parent := get_parent() as Node2D
	if parent == null:
		return
	var half := get_viewport_rect().size / zoom * 0.5
	var at := parent.global_position + _base + Vector2(0.0, _step)
	at.x = _clamp_axis(at.x, _limits.position.x, _limits.end.x, half.x)
	at.y = _clamp_axis(at.y, _limits.position.y, _limits.end.y, half.y)
	global_position = at + _look


static func _clamp_axis(value: float, low: float, high: float, half: float) -> float:
	if high - low <= half * 2.0:
		return (low + high) * 0.5
	return clampf(value, low + half, high - half)
