class_name PlayerFx
extends Node2D
## Dust and smoke from the robot's movements and weapons, all decoration (non-essential for the
## particles setting): grit kicked up behind it while running and skidding, a burst of dust as
## it jumps, dashes and lands (bigger for charged jumps and hard landings), a thin wisp from the
## arm after a plasma shot and thick smoke pouring off it for a while after the burst, grit
## knocked off a ledge as the hands slam onto it and scuffed up as the knee and feet come over.
##
## The Player adds one of these to itself. It draws in world space (top_level), so the dust
## stays where it was kicked up while the robot moves on.

const DUST: Array[Color] = [
	Color(0.72, 0.67, 0.6, 0.9), Color(0.6, 0.56, 0.5, 0.75), Color(0.45, 0.42, 0.38, 0.5),
]
## Dust specks per second while running, and while skidding to a stop.
const RUN_RATE: float = 30.0
const SKID_RATE: float = 55.0
## Seconds the arm smokes after a plasma shot, and after the burst.
const SHOT_SMOKE_TIME: float = 0.25
const BURST_SMOKE_TIME: float = 2.6

var player: Player

var _dust := PixelSparks.new()
var _smoke: Smoke
var _run_budget: float = 0.0
var _puff_budget: float = 0.0
var _was_dashing: bool = false
var _was_shot: bool = false
var _was_burst: bool = false
var _shot_smoke_left: float = 0.0
var _burst_smoke_left: float = 0.0
var _smoke_wait: float = 0.0
var _climb_grip: float = 1.0
var _climb_over: float = 1.0


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = 2
	_dust.colors = DUST
	_dust.gravity = 140.0
	_dust.damping = 0.05
	_smoke = Smoke.new()
	_smoke.free_when_empty = false
	_smoke.buoyancy = 12.0
	add_child(_smoke)
	if player != null:
		player.jumped.connect(_on_jumped)
		player.landed.connect(_on_landed)


func _feet() -> Vector2:
	return player.global_position + Vector2(0.0, 16.0)


func _process(delta: float) -> void:
	_dust.update(delta)
	if player == null:
		return
	var facing := player.get_facing()
	var on_floor := player.is_on_floor()
	var speed := absf(player.velocity.x)

	# Running: grit kicked up behind the feet, and now and then a little cloud.
	var rate := 0.0
	if on_floor and player.is_skidding():
		rate = SKID_RATE
	elif on_floor and player.get_posture() == Player.Posture.LOW and not player.is_dashing() \
			and speed > player.run_speed * Player.PIXELS_PER_METER * 0.5:
		rate = RUN_RATE
	if rate > 0.0:
		var back := -signf(player.velocity.x) if speed > 1.0 else -facing
		_run_budget += rate * delta
		var n := int(_run_budget)
		_run_budget -= n
		if n > 0:
			# Up and back: angle -PI/2 tipped 0.9 rad towards the back.
			var angle := -PI / 2.0 + back * 0.9
			_dust.emit(_feet() + Vector2(back * 2.0, -1.0), n, angle, 0.5, 20.0, 60.0, 0.3, 0.6)
		_puff_budget += rate * 0.3 * delta
		if _puff_budget >= 1.0:
			_puff_budget -= 1.0
			_smoke.puff(_feet() + Vector2(back * 3.0, -2.0),
					Vector2(back * randf_range(6.0, 14.0), -4.0), randf_range(0.4, 0.7), 1.0,
					randf_range(2.0, 3.5), 0.3)
	else:
		_run_budget = 0.0

	# Dash: a kick of dust as it launches.
	var dashing := player.is_dashing()
	if dashing and not _was_dashing:
		_kick(_feet(), 10, 2, -facing)
	_was_dashing = dashing

	# Plasma shot: a thin wisp off the arm.
	var shot := player.has_shot_fired()
	if shot and not _was_shot:
		_shot_smoke_left = SHOT_SMOKE_TIME
	_was_shot = shot
	# Burst: thick smoke pouring off the arm, thinning out.
	var burst := player.is_burst_fired() and not player.is_burst_jammed()
	if burst and not _was_burst:
		_burst_smoke_left = BURST_SMOKE_TIME
	_was_burst = burst
	_arm_smoke(delta, facing)
	_climb_dust(facing)
	queue_redraw()


## Ledge climb: grit knocked off the lip as the hands land on it, drifting down slowly, and a
## scuff of dust as the body comes over onto it.
func _climb_dust(facing: float) -> void:
	if not player.is_climbing():
		_climb_grip = 1.0
		_climb_over = 1.0
		return
	var edge := player.climb_edge()
	var grip := player.climb_grip()
	if grip >= 0.3 and _climb_grip < 0.3:
		var n := 5 if player.is_mantling() else 9
		_dust.emit(edge + Vector2(facing * 2.0, -1.0), n, PI / 2.0 - facing * 0.4, 0.5, 6.0, 22.0,
				0.6, 1.1)
		_smoke.puff(edge + Vector2(facing * 2.0, -1.0), Vector2(-facing * 6.0, -3.0),
				randf_range(0.5, 0.8), 1.0, randf_range(2.0, 3.0), 0.3)
	var over := player.climb_over()
	if over >= 0.2 and _climb_over < 0.2:
		_kick(edge + Vector2(facing * 4.0, 0.0), 6, 1, facing)
	_climb_grip = grip
	_climb_over = over


func _arm_smoke(delta: float, facing: float) -> void:
	if _shot_smoke_left <= 0.0 and _burst_smoke_left <= 0.0:
		return
	_smoke_wait -= delta
	_shot_smoke_left -= delta
	_burst_smoke_left -= delta
	if _smoke_wait > 0.0:
		return
	var at := player.muzzle()
	if _burst_smoke_left > 0.0:
		var f := _burst_smoke_left / BURST_SMOKE_TIME
		_smoke_wait = lerpf(0.25, 0.04, f)
		_smoke.puff(at + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)),
				Vector2(facing * randf_range(2.0, 10.0), randf_range(-14.0, -6.0)),
				randf_range(1.0, 1.9), 1.5, randf_range(4.0, 7.0), 0.3 + 0.25 * f, 0.7 * f * f)
	elif _shot_smoke_left > 0.0:
		_smoke_wait = 0.06
		_smoke.puff(at, Vector2(facing * 3.0, -8.0), randf_range(0.35, 0.55), 0.5, 1.5, 0.3)


func _on_jumped(charged: bool) -> void:
	_kick(_feet(), 14 if charged else 7, 3 if charged else 1, 0.0)


func _on_landed(speed: float, hard: bool) -> void:
	var n := int(clampf(speed * 3.0, 3.0, 26.0))
	_kick(_feet(), n, 4 if hard else (2 if speed > 2.5 else 0), 0.0)


## Dust thrown out low along the floor from at: to one side (side -1 or 1) or both (0), with a
## few soft clouds.
func _kick(at: Vector2, count: int, puffs: int, side: float) -> void:
	var sides: Array[float] = [-1.0, 1.0]
	if side != 0.0:
		sides = [side]
	for s in sides:
		var a := PI if s < 0.0 else 0.0
		_dust.emit(at + Vector2(0, -1), int(ceil(float(count) / sides.size())),
				a - s * 0.35, 0.3, 25.0, 80.0, 0.25, 0.55)
		for i in int(ceil(float(puffs) / sides.size())):
			_smoke.puff(at + Vector2(s * randf_range(2.0, 6.0), -2.0),
					Vector2(s * randf_range(10.0, 24.0), randf_range(-6.0, -2.0)),
					randf_range(0.5, 0.9), 1.0, randf_range(2.5, 4.5), 0.35)


func _draw() -> void:
	_dust.draw(self)
