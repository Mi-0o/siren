extends CharacterBody2D
## Test player: walks with the arrow keys, runs with left Shift, jumps with Z, dashes with X and
## fires a wire with C.
##
## World scale is taken from the collision rectangle: its height is 2 m.
## Tuning values are in metres and seconds, converted to pixels once in _ready().
##
## Jumping locks horizontal velocity for the air lock time: it is re-applied every airborne
## frame, so bumping a wall or ledge corner doesn't cancel it. The lock lasts a charged jump's
## flight time plus air_lock_extra_time, so it only runs out on long falls; attaching a wire
## clears it at once. Walking or dashing off a ledge isn't locked. Unlocked, air drag slowly
## bleeds off horizontal speed and the arrow keys give weak, capped air control.
##
## Jumps fire when Z is released. Holding Z on the ground for charge_time brings the player to a
## stop, and releasing then launches a charged jump instead of a normal one.
##
## C fires a wire (straight up when still, diagonally forward when moving) or releases it.
## While attached, Z reels in and X pays out instead of jumping and dashing.

## Height of the player in metres. The collision rectangle's pixel height maps to this.
const PLAYER_HEIGHT_M: float = 2.0
## A dash with less than this many pixels left is considered finished.
const DASH_END_EPSILON_PX: float = 0.01
## Angular resolution of the grapple point search, in degrees.
const WIRE_SEARCH_STEP_DEG: float = 1.0
## How long a missed wire shot stays on screen, in seconds.
const WIRE_MISS_SHOW_TIME: float = 0.1

@export_group("Ground")
## Top walking speed, in metres per second.
@export var walk_speed: float = 3.0
## Top running speed while holding run, in metres per second.
@export var run_speed: float = 6.0
## Time to go from standstill to walk_speed, in seconds. Running keeps the same acceleration.
@export var accel_time: float = 0.2
## Time to go from walk_speed to a stop, in seconds. The same braking is used for turning
## around, for slowing from a run to a walk and for stopping when a jump becomes charged.
@export var decel_time: float = 0.05

@export_group("Air")
## Downward acceleration, in metres per second squared. Real Europa is 1.315; raised for gameplay.
@export var gravity: float = 4.0
## Jump apex height above the takeoff point, in metres. Rounded up to a whole pixel.
@export var jump_height: float = 1.1
## Takeoff speeds at or below this (m/s) keep all their horizontal speed when jumping.
@export var jump_reduction_start_speed: float = 1.0
## Fraction of horizontal speed lost when jumping at walk_speed. Blends from 0 at
## jump_reduction_start_speed.
@export_range(0.0, 1.0, 0.05) var jump_walk_reduction: float = 0.3
## Fraction of horizontal speed lost when jumping at run_speed or faster. Blends from
## jump_walk_reduction at walk_speed.
@export_range(0.0, 1.0, 0.05) var jump_run_reduction: float = 0.5
## Time after takeoff to ease from the ground speed down to the reduced jump speed, in seconds.
@export var jump_slowdown_time: float = 0.25
## Extra time the air lock lasts beyond a charged jump's flight time, in seconds.
@export var air_lock_extra_time: float = 0.5
## Horizontal deceleration once the air lock ends, in metres per second squared.
@export var air_drag: float = 1.0
## Horizontal acceleration from the arrow keys once the air lock ends, in m/s squared.
@export var air_control_accel: float = 2.0
## Top horizontal speed the arrow keys can reach in the air, in metres per second. Faster
## momentum isn't cut, it only drags down towards this while the key is held.
@export var air_control_speed: float = 1.0

@export_group("Charged jump")
## How long Z must be held on the ground before the jump becomes charged, in seconds.
@export var charge_time: float = 1.0
## Horizontal speed of a charged jump, in the facing direction, in metres per second.
@export var charged_jump_speed: float = 6.0
## Apex height of a charged jump, in metres. Not rounded (2.03125 m = 32.5 px, clears 32 px).
@export var charged_jump_height: float = 2.03125

@export_group("Dash")
## Speed the dash starts at instantly, in metres per second.
@export var dash_speed: float = 12.0
## Total horizontal distance covered by a dash, in metres (4 m = 64 px).
@export var dash_distance: float = 4.0
## Duration of the braking at the end of the dash, in seconds. The rest is at full dash_speed.
@export var dash_stop_time: float = 0.15

@export_group("Wire")
## Maximum reach of the wire, in metres (8 m = 128 px).
@export var wire_range: float = 8.0
## Elevation of a shot fired while moving, in degrees above horizontal in the direction of
## travel. Standing still always fires straight up.
@export var wire_moving_angle: float = 45.0
## How far off the aimed direction a surface may be and still be grabbed, in degrees.
## Smaller offsets always win; distance only breaks ties at the same offset.
@export var wire_search_angle: float = 12.0
## Speed the wire reels the player in while Z is held, in metres per second.
@export var reel_speed: float = 2.0
## Speed the wire pays out while X is held, in metres per second. Stops at wire_range.
@export var extend_speed: float = 2.0
## Push along the swing from the arrow keys while hanging from a taut wire, in m/s squared.
## Small on purpose: holding it barely tilts a still hang, but pushing in time with the swing
## (alternating left and right) builds it up.
@export var swing_push_accel: float = 0.6
## The arrow keys stop adding swing speed above this, in metres per second.
@export var swing_max_speed: float = 6.0

var _gravity_px: float
var _walk_speed_px: float
var _run_speed_px: float
var _accel_px: float
var _decel_px: float
var _jump_velocity_px: float
var _jump_reduction_start_px: float
var _charged_jump_velocity_px: float
var _charged_jump_speed_px: float
var _dash_speed_px: float
var _dash_distance_px: float
var _dash_brake_distance_px: float
var _dash_brake_px: float
var _wire_range_px: float
var _reel_speed_px: float
var _extend_speed_px: float
var _swing_push_px: float
var _swing_max_px: float
var _air_drag_px: float
var _air_control_accel_px: float
var _air_control_speed_px: float
## Air lock length in seconds: a charged jump's flight time plus air_lock_extra_time.
var _air_lock_duration: float
## Reused for every grapple search so shooting doesn't allocate a query per ray.
var _wire_query: PhysicsRayQueryParameters2D

## Last resolved input direction (-1, 0, 1); lets the newest key win when both are held.
var _input_dir: float = 0.0
## Last non-zero input direction; aims the charged jump.
var _facing: float = 1.0
## Horizontal velocity while airborne, re-applied every frame so wall contact doesn't cancel it.
var _air_velocity_x: float = 0.0
## Horizontal velocity _air_velocity_x eases towards after a jump's speed reduction.
var _air_target_x: float = 0.0
## Rate _air_velocity_x eases towards _air_target_x, in pixels per second squared.
var _air_slowdown_px: float = 0.0
## Seconds of air lock left. Set by jumping, cleared on the ground and by attaching a wire.
var _air_lock_left: float = 0.0
## True from pressing Z on the ground until it is released or the player leaves the ground.
var _jump_charging: bool = false
var _jump_hold_time: float = 0.0
## Distance left in the current dash, in pixels; 0 when not dashing.
var _dash_remaining_px: float = 0.0
var _dash_dir: float = 0.0
var _wire_attached: bool = false
## Grapple point in global coordinates.
var _wire_anchor: Vector2
## Current rope length in pixels. The player can move freely inside it; reeling shortens it.
var _wire_length: float = 0.0
## Seconds left showing a missed shot.
var _wire_miss_time: float = 0.0

@onready var _wire_line: Line2D = $Wire


func _ready() -> void:
	var shape := $CollisionShape2D.shape as RectangleShape2D
	var pixels_per_meter := shape.size.y / PLAYER_HEIGHT_M
	_gravity_px = gravity * pixels_per_meter
	_walk_speed_px = walk_speed * pixels_per_meter
	_run_speed_px = run_speed * pixels_per_meter
	_accel_px = _walk_speed_px / maxf(accel_time, 0.001)
	_decel_px = _walk_speed_px / maxf(decel_time, 0.001)
	_jump_reduction_start_px = jump_reduction_start_speed * pixels_per_meter
	_jump_velocity_px = _launch_velocity(ceilf(jump_height * pixels_per_meter))
	_charged_jump_velocity_px = _launch_velocity(charged_jump_height * pixels_per_meter)
	_charged_jump_speed_px = charged_jump_speed * pixels_per_meter
	_dash_speed_px = dash_speed * pixels_per_meter
	_dash_distance_px = dash_distance * pixels_per_meter
	# Constant braking over the last stretch: covers speed * time / 2, capped at the full dash.
	_dash_brake_distance_px = clampf(
		_dash_speed_px * dash_stop_time * 0.5, 0.001, _dash_distance_px
	)
	_dash_brake_px = _dash_speed_px * _dash_speed_px / (2.0 * _dash_brake_distance_px)
	_wire_range_px = wire_range * pixels_per_meter
	_reel_speed_px = reel_speed * pixels_per_meter
	_extend_speed_px = extend_speed * pixels_per_meter
	_swing_push_px = swing_push_accel * pixels_per_meter
	_swing_max_px = swing_max_speed * pixels_per_meter
	_air_drag_px = air_drag * pixels_per_meter
	_air_control_accel_px = air_control_accel * pixels_per_meter
	_air_control_speed_px = air_control_speed * pixels_per_meter
	# Up and back down to the same height: t = 2 * v / g.
	_air_lock_duration = 2.0 * _charged_jump_velocity_px / _gravity_px + air_lock_extra_time
	_wire_query = PhysicsRayQueryParameters2D.new()
	_wire_query.collision_mask = collision_mask
	_wire_query.exclude = [get_rid()]


func _physics_process(delta: float) -> void:
	# Read every frame, even airborne, so key order is tracked correctly on landing.
	var direction := _read_direction()
	if direction != 0.0:
		_facing = direction

	# The wire works in every state, including mid-dash.
	if Input.is_action_just_pressed("wire"):
		_on_wire_pressed()

	if _dash_remaining_px <= 0.0 and Input.is_action_just_pressed("dash") and _can_dash():
		_dash_dir = signf(velocity.x)
		_dash_remaining_px = _dash_distance_px
		_jump_charging = false

	if _dash_remaining_px > 0.0:
		_update_dash(delta)
	else:
		if is_on_floor():
			_update_ground(direction, delta)
		else:
			_update_air(direction, delta)
		_move()

	_update_wire_line(delta)


## move_and_slide() with the wire's rope constraint around it.
func _move() -> void:
	if _wire_attached:
		_constrain_velocity_to_wire()
	move_and_slide()
	if _wire_attached:
		_settle_wire_length()


func _update_ground(direction: float, delta: float) -> void:
	if _wire_attached:
		# Z reels instead of jumping while attached; reeling is applied in the rope constraint.
		_jump_charging = false
		velocity.x = _ground_velocity_x(direction, delta)
		return

	# Only jumps lock the air; walking or dashing off a ledge falls unlocked.
	_air_lock_left = 0.0
	if Input.is_action_just_pressed("jump"):
		_jump_charging = true
		_jump_hold_time = 0.0
	if _jump_charging:
		_jump_hold_time += delta

	var charged := _jump_charging and _jump_hold_time >= charge_time
	if charged:
		# Charged: brake to a stop and ignore movement input until Z is released.
		velocity.x = move_toward(velocity.x, 0.0, _decel_px * delta)
	else:
		velocity.x = _ground_velocity_x(direction, delta)

	if _jump_charging and Input.is_action_just_released("jump"):
		_jump_charging = false
		if charged:
			var charged_x := _facing * _charged_jump_speed_px
			_launch(charged_x, charged_x, _charged_jump_velocity_px)
		else:
			_launch(velocity.x, _jump_velocity_x(velocity.x), _jump_velocity_px)
		return

	# Walking off a ledge keeps the current speed with no reduction.
	_air_velocity_x = velocity.x
	_air_target_x = velocity.x


func _update_air(direction: float, delta: float) -> void:
	# A charge only builds on the ground; leaving it cancels the jump.
	_jump_charging = false
	velocity.y += _gravity_px * delta

	if _wire_attached:
		# Swinging: momentum is free so the rope can turn it into a pendulum.
		if direction != 0.0:
			_push_swing(direction, delta)
		return

	if _air_lock_left > 0.0:
		_air_lock_left -= delta
		_air_velocity_x = move_toward(_air_velocity_x, _air_target_x, _air_slowdown_px * delta)
		velocity.x = _air_velocity_x
		return

	velocity.x = _air_velocity_x_unlocked(velocity.x, direction, delta)


## Free-fall horizontal velocity: drag pulls towards zero, or towards air_control_speed in the
## held direction. Pressing against the momentum brakes it, then slowly moves the other way.
func _air_velocity_x_unlocked(vx: float, direction: float, delta: float) -> float:
	if direction == 0.0:
		return move_toward(vx, 0.0, _air_drag_px * delta)
	var target := direction * _air_control_speed_px
	if vx * direction > _air_control_speed_px:
		# Already faster than control allows in that direction: only drag, never a boost.
		return move_toward(vx, target, _air_drag_px * delta)
	return move_toward(vx, target, _air_control_accel_px * delta)


## Pushes along the swing's arc in the held direction. Only works on a taut rope, so it can't be
## used as air control while the wire is slack.
func _push_swing(direction: float, delta: float) -> void:
	var offset := global_position - _wire_anchor
	var distance := offset.length()
	if distance < _wire_length - 0.5 or distance < 0.001:
		return
	var normal := offset / distance
	var tangent := Vector2(-normal.y, normal.x)
	if tangent.x * direction < 0.0:
		tangent = -tangent
	if velocity.dot(tangent) < _swing_max_px:
		velocity += tangent * _swing_push_px * delta


func _update_dash(delta: float) -> void:
	if not is_on_floor():
		velocity.y += _gravity_px * delta

	var speed := _dash_speed_px
	if _dash_remaining_px < _dash_brake_distance_px:
		# Speed that brakes to exactly zero over the remaining distance.
		speed = sqrt(2.0 * _dash_brake_px * _dash_remaining_px)
	velocity.x = _dash_dir * minf(speed, _dash_remaining_px / delta)

	var start_x := position.x
	_move()
	var moved_x := absf(position.x - start_x)
	_dash_remaining_px -= moved_x

	# A wall, or a taut wire holding the player back, ends the dash early.
	if _dash_remaining_px < DASH_END_EPSILON_PX or is_on_wall() or moved_x < DASH_END_EPSILON_PX:
		# Forced stop: the dash always ends at rest, whatever is held.
		_dash_remaining_px = 0.0
		velocity.x = 0.0
		_air_velocity_x = 0.0
		_air_target_x = 0.0


## X pays out the wire instead of dashing while attached, as Z reels instead of jumping.
func _can_dash() -> bool:
	return is_on_floor() and not _wire_attached and not _jump_charging and velocity.x != 0.0


## C fires a wire, or releases the attached one without firing another.
func _on_wire_pressed() -> void:
	if _wire_attached:
		_detach_wire()
		return
	var aim := _wire_aim()
	if _find_grapple_point(aim):
		_wire_attached = true
		_wire_length = global_position.distance_to(_wire_anchor)
		_wire_miss_time = 0.0
		_jump_charging = false
		_air_lock_left = 0.0
	else:
		_wire_miss_time = WIRE_MISS_SHOW_TIME
		_wire_line.set_point_position(1, aim * _wire_range_px)


## Letting go mid-air keeps the swing's momentum with no air lock, so drag and air control apply.
func _detach_wire() -> void:
	_wire_attached = false


## Returns the unit aim direction: straight up when still with no arrow held, otherwise
## wire_moving_angle above horizontal. A held arrow picks the side, so you can fire backwards
## mid-jump; with no arrow held it fires in the direction of travel.
func _wire_aim() -> Vector2:
	var side := _input_dir if _input_dir != 0.0 else signf(velocity.x)
	if is_zero_approx(side):
		return Vector2.UP
	var angle := deg_to_rad(wire_moving_angle)
	return Vector2(side * cos(angle), -sin(angle))


## Casts rays fanning out from the aim in WIRE_SEARCH_STEP_DEG steps. The first offset that hits
## anything wins, so angle always beats distance; at the same offset the closer hit wins.
## Stores the result in _wire_anchor and returns whether a surface was found.
func _find_grapple_point(aim: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var origin := global_position
	_wire_query.from = origin
	var steps := int(wire_search_angle / WIRE_SEARCH_STEP_DEG)

	for i in steps + 1:
		var offset := deg_to_rad(i * WIRE_SEARCH_STEP_DEG)
		var best_distance := INF
		for side in 2:
			# side 0 rotates one way, side 1 the other; offset 0 only needs one ray.
			_wire_query.to = origin + aim.rotated(offset * (1 - 2 * side)) * _wire_range_px
			var hit := space.intersect_ray(_wire_query)
			if not hit.is_empty():
				var distance := origin.distance_to(hit.position)
				if distance < best_distance:
					best_distance = distance
					_wire_anchor = hit.position
			if i == 0:
				break
		if best_distance < INF:
			return true
	return false


## Returns -1 while reeling in (Z), 1 while paying out (X), 0 when neither or both are held.
func _winch_input() -> float:
	return Input.get_axis("jump", "dash")


## Keeps the player inside the rope: removes any velocity stretching it. Reeling guarantees at
## least reel_speed towards the anchor; paying out lets the player move away at up to
## extend_speed until the rope reaches wire_range. Gravity plus this makes the pendulum.
func _constrain_velocity_to_wire() -> void:
	var offset := global_position - _wire_anchor
	var distance := offset.length()
	var winch := _winch_input()
	if distance < 0.001 or (winch >= 0.0 and distance < _wire_length):
		return

	var normal := offset / distance
	var max_outward := 0.0
	if winch < 0.0:
		max_outward = -_reel_speed_px
	elif winch > 0.0 and _wire_length < _wire_range_px:
		max_outward = _extend_speed_px
	var outward := velocity.dot(normal)
	if outward > max_outward:
		velocity -= normal * (outward - max_outward)


## After moving: the rope length follows the player while reeling or paying out, and any drift
## past the rope length (from the fixed time step) is pulled back.
func _settle_wire_length() -> void:
	var offset := global_position - _wire_anchor
	var distance := offset.length()
	var winch := _winch_input()
	if winch < 0.0:
		_wire_length = minf(_wire_length, distance)
	elif winch > 0.0:
		_wire_length = clampf(distance, _wire_length, _wire_range_px)
	if distance > _wire_length:
		move_and_collide(-offset / distance * (distance - _wire_length))


func _update_wire_line(delta: float) -> void:
	if _wire_attached:
		_wire_line.set_point_position(1, to_local(_wire_anchor))
		_wire_line.visible = true
	elif _wire_miss_time > 0.0:
		_wire_miss_time -= delta
		_wire_line.visible = true
	else:
		_wire_line.visible = false


## Leaves the ground at takeoff_x, then eases horizontally to target_x over jump_slowdown_time.
func _launch(takeoff_x: float, target_x: float, launch_velocity: float) -> void:
	velocity.x = takeoff_x
	velocity.y = -launch_velocity
	_air_velocity_x = takeoff_x
	_air_target_x = target_x
	_air_slowdown_px = absf(takeoff_x - target_x) / maxf(jump_slowdown_time, 0.001)
	_air_lock_left = _air_lock_duration


## Vertical takeoff speed that peaks at height_px. The continuous v = sqrt(2 * g * h) overshoots
## by about v * dt / 2 at a fixed physics step, so this solves v^2 / 2g + v * dt / 2 = h instead.
func _launch_velocity(height_px: float) -> float:
	var g_dt := _gravity_px / Engine.physics_ticks_per_second
	return (sqrt(g_dt * g_dt + 8.0 * _gravity_px * height_px) - g_dt) * 0.5


func _ground_velocity_x(direction: float, delta: float) -> float:
	var vx := velocity.x
	if direction == 0.0:
		return move_toward(vx, 0.0, _decel_px * delta)
	if vx * direction < 0.0:
		# Turning around: brake hard to zero first, then accelerate the other way next frame.
		return move_toward(vx, 0.0, _decel_px * delta)

	var top_speed := _run_speed_px if Input.is_action_pressed("run") else _walk_speed_px
	# Speeding up uses acceleration; dropping from a run to a walk uses braking.
	var rate := _accel_px if absf(vx) < top_speed else _decel_px
	return move_toward(vx, direction * top_speed, rate * delta)


## Returns the horizontal jump speed after the jump speed reduction. The reduction blends
## linearly between the tuning points so a slightly faster run-up never jumps shorter.
func _jump_velocity_x(vx: float) -> float:
	var speed := absf(vx)
	var reduction := 0.0
	if speed >= _run_speed_px:
		reduction = jump_run_reduction
	elif speed > _walk_speed_px:
		reduction = remap(
			speed, _walk_speed_px, _run_speed_px, jump_walk_reduction, jump_run_reduction
		)
	elif speed > _jump_reduction_start_px:
		reduction = remap(speed, _jump_reduction_start_px, _walk_speed_px, 0.0, jump_walk_reduction)
	return vx * (1.0 - reduction)


## Returns -1, 0 or 1. When both keys are held, the most recently pressed one wins.
func _read_direction() -> float:
	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")

	if left and right:
		if Input.is_action_just_pressed("move_left"):
			_input_dir = -1.0
		elif Input.is_action_just_pressed("move_right"):
			_input_dir = 1.0
	elif left:
		_input_dir = -1.0
	elif right:
		_input_dir = 1.0
	else:
		_input_dir = 0.0

	return _input_dir
