extends Node
## Watches the robot for death and brings up the death screen (PauseMenu.open_death). The pause
## menu creates it for any level with a robot, so levels need nothing extra.
##
## Two ways to die so far:
## - Core fault. The robot drops to the ground (falling first if it's in the air) and lies there
##   dying; it takes CORE_DELAY seconds to actually die and bring the screen up.
## - Falling out of the level. Once the robot drops more than FALL_MARGIN px past the level's
##   bottom edge (the bottom limit of the robot's camera), the camera lets go of the limits and
##   follows it down for FALL_FOLLOW seconds, then eases to a stop. The robot falls on out of
##   view, and the screen comes up a moment later. Floors near the bottom edge of a level must
##   stay above that line.
##
## Nothing is paused at any point. Dev fly and noclip never count as falling, and the dev menu
## healing a core fault takes the death screen away again.

const FALL_MARGIN: float = 40.0
const FALL_FOLLOW: float = 5.0
## How quickly the camera catches up with the falling robot, and how long its stop takes.
const FOLLOW_SMOOTH: float = 0.2
const STOP_SMOOTH: float = 0.45
## Seconds after the robot has left the view (falling) or collapsed (core) before the screen.
const GONE_DELAY: float = 0.8
const CORE_DELAY: float = 4.0
## The death sign's text, the same however the robot died.
const MESSAGE: String = "SIGNAL LOST"
## Half the robot's height: its centre is this far above its feet and below its head.
const HALF_H: float = 20.0

enum State { ALIVE, CORE, FALLING, SHOWN }

var player: CharacterBody2D
var menu: Control

var _state: State = State.ALIVE
var _cause_core: bool = false
var _time: float = 0.0
var _gone_time: float = -1.0
var _cam: Camera2D
var _cam_pos: Vector2
var _cam_vel: Vector2


func _physics_process(delta: float) -> void:
	if player == null or menu == null:
		return
	match _state:
		State.ALIVE:
			if player.call("is_dead"):
				_state = State.CORE
				_cause_core = true
				_time = 0.0
			elif _fell_out():
				_start_fall()
		State.CORE:
			_time += delta
			if not player.call("is_dead"):
				_state = State.ALIVE
			elif _time >= CORE_DELAY:
				_show()
		State.FALLING:
			# No catching the wire or anything else on the way down.
			player.set("controls_locked", true)
		State.SHOWN:
			if _cause_core and not player.call("is_dead"):
				# Healed from the dev menu: back to life without a reload.
				menu.call("close_death")
				_state = State.ALIVE


func _process(delta: float) -> void:
	if _state != State.FALLING or _cam == null:
		return
	_time += delta
	var target: Vector2 = player.global_position
	if _time < FALL_FOLLOW:
		var next: Vector2 = target + (_cam_pos - target) * exp(-delta / FOLLOW_SMOOTH)
		_cam_vel = (next - _cam_pos) / maxf(delta, 0.0001)
		_cam_pos = next
	else:
		_cam_vel *= exp(-delta / STOP_SMOOTH)
		_cam_pos += _cam_vel * delta
	_cam.global_position = _cam_pos.round()
	var half_view := _cam.get_viewport_rect().size.y * 0.5
	var gone: bool = target.y - HALF_H > _cam_pos.y + half_view + 4.0
	if _time >= FALL_FOLLOW and gone:
		if _gone_time < 0.0:
			_gone_time = 0.0
		_gone_time += delta
		if _gone_time >= GONE_DELAY:
			_show()
			# Off the bottom of the world for good: stop simulating it.
			player.visible = false
			player.process_mode = Node.PROCESS_MODE_DISABLED


func _show() -> void:
	_state = State.SHOWN
	menu.call("open_death", MESSAGE)


func _fell_out() -> bool:
	if player.get("fly_mode") or player.get("noclip") or player.is_on_floor():
		return false
	var bottom := _level_bottom()
	if bottom >= 1000000.0:
		return false
	var y := player.global_position.y
	if y > bottom + HALF_H * 2.0:
		return true
	return y > bottom - FALL_MARGIN and not player.call("is_wire_attached")


## The bottom edge of the level: the robot camera's bottom limit. The robot's own camera applies
## its limits itself and keeps them in _limits.
func _level_bottom() -> float:
	for child in player.get_children():
		var cam := child as Camera2D
		if cam == null:
			continue
		var limits: Variant = cam.get("_limits")
		if limits is Rect2i and (limits as Rect2i).size.y > 0:
			return float((limits as Rect2i).end.y)
		return float(cam.limit_bottom)
	return 10000000.0


## Takes over from the robot's camera where it is, so the view can follow it down.
func _start_fall() -> void:
	_state = State.FALLING
	_cause_core = false
	_time = 0.0
	_gone_time = -1.0
	if menu.get("is_open"):
		menu.call("close")
	player.set("controls_locked", true)
	var old := player.get_viewport().get_camera_2d()
	_cam_pos = old.get_screen_center_position() if old != null else player.global_position
	_cam_vel = Vector2.ZERO
	_cam = Camera2D.new()
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if old != null:
		_cam.zoom = old.zoom
	_cam.global_position = _cam_pos
	player.get_parent().add_child(_cam)
	_cam.global_position = _cam_pos
	_cam.make_current()
