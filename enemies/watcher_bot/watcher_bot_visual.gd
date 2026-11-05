class_name WatcherBotVisual
extends EnemyVisual
## Draws the watcher, pixel by pixel, animated procedurally. It's meant to look wrong: a long,
## skeletal rabbit shape with a spine of bare vertebrae and ribs, legs too long for it, front
## elbows bending the wrong way, two eyes stacked one above the other and a jaw that opens.
##
## - Body joints ease between key poses on all fours (sitting, walking, running low, crouched,
##   leaping, tucked) and the tall standing pose, by how far it has unfolded (stand). It unfolds
##   in jerky servo steps with hitches, and folds back down smoothly.
## - Four legs: the near pair, and the far pair behind the body (darker, set back and up a
##   little so they show between the near ones). Legs are two-bone IK; the hind legs end in a long
##   rigid hock, the front elbows bend forwards.
## - Walking and running are gait cycles driven by the distance covered, so planted feet never
##   slide: walking is a slow four-beat walk (near hind, near front, far hind, far front, one foot
##   up at a time, hips and shoulders rolling over the legs), running a gallop (the hind pair
##   lands just apart, then the front pair; the spine gathers and stretches, with a moment in the
##   air). Standing still, the feet are planted and shuffle one at a time to settle.
## - Standing, the front limbs hang off the shoulders on springs, claws twitching; warning, they
##   lift and spread; the swipe sweeps one over and down.
## - The head moves on its own: it snaps to odd tilts and holds them, and while scouting it
##   snaps all the way round to look behind. Watching the robot, it stares at it.
## - Eyes go from dim to hot amber when it warns or attacks; the jaw drops open, showing teeth.

const BONE := Color(0.33, 0.33, 0.31)
const BONE_LIGHT := Color(0.52, 0.5, 0.46)
const BONE_DARK := Color(0.17, 0.17, 0.17)
const FAR_LIMB := Color(0.12, 0.12, 0.13)
const RIB := Color(0.2, 0.2, 0.2)
const TEETH := Color(0.62, 0.6, 0.55)
const MOUTH := Color(0.02, 0.02, 0.02)
const CABLE := Color(0.28, 0.12, 0.1)
const EYE_DIM := Color(0.7, 0.42, 0.14)
const EYE_HOT := Color(1.0, 0.8, 0.38)
const GLOW_DIM := Color(1.0, 0.5, 0.12, 0.14)
const GLOW_HOT := Color(1.0, 0.6, 0.15, 0.32)
## Hind leg: thigh and shin (IK), then a rigid hock from the heel down to the toe.
const THIGH: float = 5.5
const SHIN: float = 6.5
const HOCK := Vector2(-2.5, 4.0)
## Front leg: upper and fore arm.
const UPPER_ARM: float = 5.5
const FORE_ARM: float = 6.5
## Far limbs: where they join the body, and where their feet rest, relative to the near ones.
## Set back and a pixel up, like legs on the far side seen slightly from above.
const FAR := Vector2(-2.5, 0.5)
const FAR_FOOT := Vector2(-2.5, 1.0)
## Gaits: stride (px of ground covered per cycle), duty (part of the cycle each foot is down),
## lift (px) and each leg's phase offset (hind, front, far hind, far front).
const WALK_GAIT := {"stride": 12.0, "duty": 0.72, "lift": 2.0,
		"offsets": [0.0, 0.25, 0.5, 0.75]}
const RUN_GAIT := {"stride": 30.0, "duty": 0.4, "lift": 3.5,
		"offsets": [0.0, 0.1, 0.5, 0.6]}
const LEGS: Array[String] = ["hind", "front", "far_hind", "far_front"]
const BODY_JOINTS: Array[String] = ["hip", "mid", "shoulder", "head", "snout", "ear_base",
		"ear_tip", "far_ear_tip", "tail", "hind", "front"]

## Key poses: joint -> (forward, up) px from the feet. hind/front are the feet's rest spots.
const QUAD := {
	"hip": Vector2(-5.0, 10.0), "mid": Vector2(0.0, 14.0), "shoulder": Vector2(5.0, 11.0),
	"head": Vector2(9.5, 12.0), "snout": Vector2(13.0, 10.5), "ear_base": Vector2(8.5, 14.0),
	"ear_tip": Vector2(4.0, 23.0), "far_ear_tip": Vector2(6.0, 22.5),
	"tail": Vector2(-8.0, 10.0), "hind": Vector2(-4.5, 0.0), "front": Vector2(7.0, 0.0),
}
const RUN := {
	"hip": Vector2(-5.0, 9.0), "mid": Vector2(0.0, 12.0), "shoulder": Vector2(5.5, 10.0),
	"head": Vector2(10.5, 10.0), "snout": Vector2(14.0, 9.0), "ear_base": Vector2(9.0, 12.0),
	"ear_tip": Vector2(1.0, 17.0), "far_ear_tip": Vector2(2.0, 16.5),
	"tail": Vector2(-9.0, 10.0), "hind": Vector2(-5.0, 0.0), "front": Vector2(8.0, 0.0),
}
const CROUCH := {
	"hip": Vector2(-5.0, 7.0), "mid": Vector2(0.0, 10.5), "shoulder": Vector2(5.0, 8.0),
	"head": Vector2(9.5, 8.0), "snout": Vector2(13.0, 6.5), "ear_base": Vector2(8.5, 10.0),
	"ear_tip": Vector2(1.0, 16.0), "far_ear_tip": Vector2(2.5, 15.5),
	"tail": Vector2(-8.0, 7.5), "hind": Vector2(-4.5, 0.0), "front": Vector2(7.5, 0.0),
}
const LEAP := {
	"hip": Vector2(-5.0, 10.0), "mid": Vector2(0.0, 13.0), "shoulder": Vector2(6.0, 12.5),
	"head": Vector2(11.0, 13.0), "snout": Vector2(14.5, 12.5), "ear_base": Vector2(9.5, 15.0),
	"ear_tip": Vector2(2.0, 19.0), "far_ear_tip": Vector2(3.0, 18.5),
	"tail": Vector2(-9.0, 12.0), "hind": Vector2(-12.0, 4.0), "front": Vector2(14.0, 7.0),
}
const TUCK := {
	"hip": Vector2(-5.0, 10.0), "mid": Vector2(0.0, 13.5), "shoulder": Vector2(5.0, 11.0),
	"head": Vector2(9.5, 11.5), "snout": Vector2(13.0, 10.0), "ear_base": Vector2(8.5, 14.0),
	"ear_tip": Vector2(4.0, 21.0), "far_ear_tip": Vector2(5.5, 20.5),
	"tail": Vector2(-8.0, 11.0), "hind": Vector2(-2.0, 3.0), "front": Vector2(9.5, 2.0),
}
## Rummaging: rump up, shoulders and head dropped to the floor, one claw raking.
const RUMMAGE := {
	"hip": Vector2(-5.0, 11.0), "mid": Vector2(0.0, 12.5), "shoulder": Vector2(5.0, 7.0),
	"head": Vector2(9.5, 4.0), "snout": Vector2(12.0, 1.5), "ear_base": Vector2(8.5, 6.5),
	"ear_tip": Vector2(3.0, 13.0), "far_ear_tip": Vector2(5.0, 12.5),
	"tail": Vector2(-8.5, 12.5), "hind": Vector2(-4.5, 0.0), "front": Vector2(8.0, 0.0),
}
## Dead: slumped on its side, flat along the floor, jaw hanging, legs stuck out stiff. The
## feet (hind, front) and the far feet are given in DEAD_FEET.
const DEAD := {
	"hip": Vector2(-5.0, 3.0), "mid": Vector2(0.0, 4.5), "shoulder": Vector2(5.0, 3.0),
	"head": Vector2(10.0, 2.0), "snout": Vector2(13.5, 1.0), "ear_base": Vector2(9.0, 3.0),
	"ear_tip": Vector2(3.0, 2.0), "far_ear_tip": Vector2(4.0, 4.0),
	"tail": Vector2(-10.0, 1.0), "hind": Vector2(-13.0, 3.0), "front": Vector2(12.0, 6.0),
}
const DEAD_FEET := {"hind": Vector2(-13.0, 3.0), "far_hind": Vector2(-11.5, 7.0),
		"front": Vector2(12.0, 6.0), "far_front": Vector2(13.0, 2.0)}
const EYE_DEAD := Color(0.14, 0.09, 0.05)

## Standing tall on the hind legs: front is where the hanging hands rest.
const STAND := {
	"hip": Vector2(-1.0, 13.0), "mid": Vector2(1.8, 20.0), "shoulder": Vector2(1.0, 26.0),
	"head": Vector2(3.0, 30.0), "snout": Vector2(6.5, 29.0), "ear_base": Vector2(2.5, 32.0),
	"ear_tip": Vector2(0.5, 39.0), "far_ear_tip": Vector2(2.0, 38.5),
	"tail": Vector2(-3.5, 10.5), "hind": Vector2(-1.5, 0.0), "front": Vector2(4.0, 14.5),
}

## Seconds to unfold standing up (jerky) and to fold back down.
@export var rise_time: float = 0.9
@export var fold_time: float = 0.35
@export var ease_rate: float = 14.0
## Standing still, a planted foot shuffles back under the body once it's this far off (px).
@export var settle_reach: float = 3.0
## Below this speed (px/s) it stops cycling its legs and lets the feet settle.
@export var gait_min_speed: float = 4.0

var bot: WatcherBot

var _pose: Dictionary = QUAD.duplicate()
var _rng := RandomNumberGenerator.new()
## How far it has unfolded onto its hind legs, 0 to 1.
var _stand: float = 0.0
var _servo_wait: float = 0.0
## Feet: near hind, far hind, near front, far front.
var _hind := Foot.new()
var _far_hind := Foot.new()
var _front := Foot.new()
var _far_front := Foot.new()
var _feet_planted: bool = false
var _facing_was: float = 0.0
var _feet: Dictionary = {}
## Gait cycle: phase (0 to 1, by distance covered), how much the gait drives the legs (0 to 1)
## and how much of it is the gallop (0 walk, 1 run).
var _phase: float = 0.0
var _gait_weight: float = 0.0
var _run_weight: float = 0.0
var _last_x: float = 0.0
## Hanging hands (standing), as springs around their rest spot.
var _hand := Spring.new(90.0, 5.0)
var _far_hand := Spring.new(70.0, 4.0)
var _ears := Spring.new(160.0, 8.0)
var _tail := Spring.new(60.0, 4.0)
## Head: tilt (radians), which way it looks (1 forward, -1 behind) and the next snap.
var _head_tilt: float = 0.0
var _head_dir: float = 1.0
var _next_snap: float = 1.5
## Jaw opening, 0 to 1, and eye heat, 0 to 1.
var _jaw: float = 0.0
var _heat: float = 0.0
var _claw_twitch: float = 0.0


func _ready() -> void:
	super()
	bot = body as WatcherBot
	_rng.randomize()
	for foot in [_hind, _far_hind, _front, _far_front]:
		foot.step_time = 0.16
		foot.lift = 2.0


func _animate(delta: float) -> void:
	if bot == null:
		return
	if bot.dead:
		_animate_dead(delta)
		return
	_update_stand(delta)
	var target := _blend(_hurt(_quad_pose()), STAND, _stand)
	var k := 1.0 - exp(-ease_rate * delta)
	if bot.state in [WatcherBot.State.AIR, WatcherBot.State.LUNGE, WatcherBot.State.WINDUP,
			WatcherBot.State.LUNGE_WINDUP]:
		k = 1.0 - exp(-ease_rate * 2.5 * delta)
	for joint in BODY_JOINTS:
		_pose[joint] = (_pose[joint] as Vector2).lerp(target[joint], k)
	var push := Vector2(accel.x * bot.facing, -accel.y) * -0.04
	_ears.update(push, delta, 3.0)
	_tail.update(push * 1.5 + Vector2(0.0, -40.0), delta, 3.0)
	_hand.update(push * 2.0, delta, 4.0)
	_far_hand.update(push * 2.4, delta, 4.0)
	_update_head(delta)
	var hot := bot.state == WatcherBot.State.WARN or bot.mood == WatcherBot.Mood.HOSTILE
	var open := bot.state in [WatcherBot.State.WARN, WatcherBot.State.LUNGE_WINDUP,
			WatcherBot.State.LUNGE, WatcherBot.State.SWIPE]
	var jaw_rest := 0.35 if bot.is_hurt() else 0.0
	_jaw = move_toward(_jaw, 1.0 if open else jaw_rest, delta * (8.0 if open else 3.0))
	_heat = move_toward(_heat, 1.0 if hot else (0.45 if bot.watching else 0.0), delta * 3.0)
	_claw_twitch -= delta
	_update_feet(delta)


## Collapses: folds down, keels over onto its side, legs give a few jerks, then still.
func _animate_dead(delta: float) -> void:
	_stand = move_toward(_stand, 0.0, delta / maxf(fold_time, 0.01))
	var k := 1.0 - exp(-ease_rate * 0.6 * delta)
	for joint in BODY_JOINTS:
		_pose[joint] = (_pose[joint] as Vector2).lerp(DEAD[joint], k)
	_jaw = move_toward(_jaw, 0.7, delta * 2.0)
	_heat = 0.0
	_head_dir = 1.0
	_head_tilt = lerpf(_head_tilt, 0.15, k)
	var twitch := Vector2.ZERO
	if bot.dead_time < 2.0 and fmod(bot.dead_time, 0.6) < 0.1:
		twitch = Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0))
	if _feet.is_empty():
		_feet = DEAD_FEET.duplicate()
	for leg in LEGS:
		_feet[leg] = (_feet[leg] as Vector2).lerp(DEAD_FEET[leg], k) \
				+ (twitch if leg.begins_with("far") else -twitch) * 0.5
	_ears.update(Vector2.ZERO, delta, 1.0)
	_tail.update(Vector2.ZERO, delta, 1.0)


## Unfolds in uneven servo steps with the odd hitch; folds down in one smooth go.
func _update_stand(delta: float) -> void:
	var up := bot.standing
	if not up:
		_stand = move_toward(_stand, 0.0, delta / maxf(fold_time, 0.01))
		return
	_servo_wait -= delta
	if _servo_wait > 0.0 or _stand >= 1.0:
		return
	_servo_wait = 0.07
	var step := 0.07 / maxf(rise_time, 0.01) * _rng.randf_range(0.4, 1.9)
	if bot.state == WatcherBot.State.SWIPE:
		step *= 3.0
	_stand = minf(_stand + step, 1.0)
	if _rng.randf() < 0.12:
		# A hitch: the servos stall for a moment.
		_servo_wait = _rng.randf_range(0.12, 0.3)


## The all-fours pose for what it's doing.
func _quad_pose() -> Dictionary:
	if bot.is_underground():
		# Squeezing through a vent: flattened, head first.
		var v := CROUCH.duplicate()
		v.head += Vector2(1.0, -3.0)
		v.snout += Vector2(1.0, -4.0)
		return v
	match bot.state:
		WatcherBot.State.RUMMAGE:
			var r := RUMMAGE.duplicate()
			# The head jerks about as it picks through the scrap, and now and then comes up
			# to look round with something in its jaws.
			var pick := 0.6 * sin(time * 17.0) * sin(time * 5.3)
			r.head += Vector2(pick, 0.0)
			r.snout += Vector2(pick * 1.5, absf(pick))
			if fmod(bot.state_time, 3.1) > 2.6:
				r.head += Vector2(-1.0, 4.0)
				r.snout += Vector2(-1.5, 5.5)
				r.shoulder += Vector2(0.0, 1.5)
			return r
		WatcherBot.State.WINDUP, WatcherBot.State.LAND, WatcherBot.State.RECOVER:
			return CROUCH.duplicate()
		WatcherBot.State.LUNGE_WINDUP:
			var p := CROUCH.duplicate()
			p.head += Vector2(1.0, -1.5)
			p.snout += Vector2(1.5, -2.0)
			p.ear_tip += Vector2(-2.0, -3.0)
			p.far_ear_tip += Vector2(-2.0, -3.0)
			return p
		WatcherBot.State.AIR, WatcherBot.State.LUNGE:
			var t := clampf(inverse_lerp(-40.0, 40.0, bot.velocity.y), 0.0, 1.0)
			var p := _blend(LEAP, TUCK, t)
			if bot.state == WatcherBot.State.LUNGE:
				p.front = Vector2(15.0, 9.0)
			return p
		WatcherBot.State.RUN, WatcherBot.State.WALK:
			return _gait_pose()
	return QUAD.duplicate()


## Hurt (heavy core): the spine sags, the head hangs low and crooked, and it favours the near
## front leg (see _update_feet).
func _hurt(p: Dictionary) -> Dictionary:
	if not bot.is_hurt() or bot.state in [WatcherBot.State.AIR, WatcherBot.State.LUNGE]:
		return p
	p.mid += Vector2(0.0, -1.5)
	p.shoulder += Vector2(0.0, -1.0)
	for joint in ["head", "snout", "ear_base", "ear_tip", "far_ear_tip"]:
		p[joint] += Vector2(0.0, -2.0)
	p.ear_tip += Vector2(-2.0, -3.0)
	p.tail += Vector2(0.0, -2.0)
	return p


## The body on the move: a blend of the walking and galloping bodies by _run_weight, moved by
## the gait cycle.
func _gait_pose() -> Dictionary:
	var walk := QUAD.duplicate()
	var cycle := _phase * TAU
	var moving := _gait_weight
	# Walk: hips and shoulders roll up over whichever leg is under them, a small bob per step.
	var hip_roll := 0.5 * sin(cycle) * moving
	var shoulder_roll := 0.5 * sin(cycle - PI * 0.5) * moving
	walk.hip += Vector2(0.0, hip_roll)
	walk.shoulder += Vector2(0.0, shoulder_roll)
	for joint in ["head", "snout", "ear_base", "ear_tip", "far_ear_tip"]:
		walk[joint] += Vector2(0.0, shoulder_roll * 0.8 + 0.3 * cos(cycle * 4.0) * moving)
	# Gallop: gathered (hips forward, spine arched) as the hind feet land at phase 0, stretched
	# (shoulders reaching) as the front feet land at 0.5, airborne in between.
	var run := RUN.duplicate()
	var gather := cos(cycle) * moving
	var bounce := absf(sin(cycle)) * 1.2 * moving
	run.hip += Vector2(1.8 * gather, bounce)
	run.mid += Vector2(0.5 * gather, bounce + 1.8 * maxf(gather, 0.0))
	run.shoulder += Vector2(-1.2 * gather, bounce)
	for joint in ["head", "snout", "ear_base", "ear_tip", "far_ear_tip"]:
		run[joint] += Vector2(-1.2 * gather, bounce - 0.6 * gather)
	run.tail += Vector2(1.0 * gather, bounce + 1.0 * gather)
	return _blend(walk, run, _run_weight)


## Snaps the head to odd tilts, looks round behind it while scouting, stares at the robot.
func _update_head(delta: float) -> void:
	_next_snap -= delta
	var scouting := bot.state == WatcherBot.State.STAND and not bot.watching
	if bot.watching:
		_head_dir = 1.0
		if bot.target_alive():
			var dy: float = bot.target.global_position.y - (bot.global_position.y - _pose.head.y)
			_head_tilt = lerpf(_head_tilt, clampf(-dy / 40.0, -0.6, 0.6), 1.0 - exp(-10.0 * delta))
		if bot.state == WatcherBot.State.WARN and _next_snap <= 0.0:
			# Small violent twitches.
			_next_snap = _rng.randf_range(0.15, 0.4)
			_head_tilt += _rng.randf_range(-0.35, 0.35)
		return
	if _next_snap > 0.0:
		return
	if scouting:
		_next_snap = _rng.randf_range(0.6, 1.4)
		if _rng.randf() < 0.6:
			_head_dir = -_head_dir
		_head_tilt = _rng.randf_range(-0.5, 0.5)
	else:
		_head_dir = 1.0
		_next_snap = _rng.randf_range(1.5, 4.5)
		# Snap to a crooked tilt (or back straight) and hold it.
		_head_tilt = 0.0 if absf(_head_tilt) > 0.1 else _rng.randf_range(-0.55, 0.55)


## Moves the feet: through the gait cycle while it walks or runs, planted and settling one
## at a time while it stands, following the pose in the air. Standing up, the front feet become
## hands.
func _update_feet(delta: float) -> void:
	var grounded := bot.is_on_floor() and bot.state not in [WatcherBot.State.AIR, WatcherBot.State.LUNGE]
	if bot.facing != _facing_was:
		_facing_was = bot.facing
		_feet_planted = false
	var p := _pose
	# The gait cycle runs on the ground covered, so planted feet stay put.
	var moved := absf(bot.global_position.x - _last_x)
	_last_x = bot.global_position.x
	var cycling := grounded and bot.state in [WatcherBot.State.WALK, WatcherBot.State.RUN] \
			and absf(bot.velocity.x) > gait_min_speed and _stand < 0.2
	_gait_weight = move_toward(_gait_weight, 1.0 if cycling else 0.0, delta * 6.0)
	var run_target := 1.0 if absf(bot.velocity.x) > bot.walk_speed * Enemy.PX * 1.6 else 0.0
	_run_weight = move_toward(_run_weight, run_target, delta * 4.0)
	var stride: float = lerpf(WALK_GAIT.stride, RUN_GAIT.stride, _run_weight)
	if cycling:
		_phase = fposmod(_phase + moved / stride, 1.0)
	# Hanging (or lifted) hands.
	var hand: Vector2 = p.front + _hand.offset
	var far_hand: Vector2 = p.front + FAR + Vector2(-1.0, 0.5) + _far_hand.offset
	if bot.state == WatcherBot.State.WARN:
		hand = p.shoulder + Vector2(6.0, -3.0) + _hand.offset
		far_hand = p.shoulder + FAR + Vector2(4.5, -1.0) + _far_hand.offset
	elif bot.state == WatcherBot.State.SWIPE:
		var t := clampf(bot.state_time / maxf(bot.swipe_time, 0.01), 0.0, 1.0)
		var angle := lerpf(-2.3, 0.7, smoothstep(0.25, 0.7, t))
		hand = p.shoulder + Vector2.RIGHT.rotated(angle) * Vector2(1.0, -1.0) * 11.5
		far_hand = p.shoulder + FAR + Vector2(4.0, -6.0)
	if not grounded:
		_feet_planted = false
		_feet = {"hind": p.hind, "far_hind": p.hind + FAR_FOOT + Vector2(0.0, 1.0),
				"front": p.front, "far_front": p.front + FAR_FOOT + Vector2(0.0, 1.0)}
		return
	var rest := _rest_spots(p)
	var spots := {}
	for leg in LEGS:
		spots[leg] = _ground_spot(rest[leg])
	var feet_list: Array[Foot] = [_hind, _front, _far_hind, _far_front]
	if not _feet_planted:
		_feet_planted = true
		for n in LEGS.size():
			feet_list[n].place(spots[LEGS[n]])
	var gait := _gait_feet(rest)
	if _gait_weight > 0.5:
		# Keep the planted feet where the cycle has them, ready to settle from there on a stop.
		for n in LEGS.size():
			var world := to_world(gait[LEGS[n]])
			feet_list[n].place(Vector2(world.x, ground_y(world.x, 10.0, 12.0)))
	else:
		# Standing still: one foot at a time shuffles back under the body.
		var busy := false
		for foot in feet_list:
			busy = busy or foot.is_stepping()
		for n in LEGS.size():
			var foot := feet_list[n]
			foot.step_time = 0.14
			foot.lift = 1.5
			var go := not busy and foot.pos.distance_to(spots[LEGS[n]]) > settle_reach
			if foot.update(spots[LEGS[n]], 0.0 if go else INF, go or foot.is_stepping(), delta):
				busy = true
	_feet = {}
	for n in LEGS.size():
		var planted := to_joint(feet_list[n].pos)
		if LEGS[n].begins_with("far"):
			planted += Vector2(0.0, FAR_FOOT.y)
		_feet[LEGS[n]] = planted.lerp(gait[LEGS[n]], _gait_weight)
	if bot.state == WatcherBot.State.RUMMAGE and grounded:
		# The near claw rakes the floor: reaching out, dragged back in under the chest.
		var phase := fmod(bot.state_time * 1.6, 1.0)
		var rake: Vector2
		if phase < 0.55:
			rake = Vector2(lerpf(4.0, -3.0, phase / 0.55), 0.0)
		else:
			var u := (phase - 0.55) / 0.45
			rake = Vector2(lerpf(-3.0, 4.0, u), sin(u * PI) * 3.0)
		_feet.front = rest.front + rake
	if bot.is_hurt() and grounded and _stand < 0.3 and bot.state != WatcherBot.State.RUMMAGE:
		# Limping: the near front leg is held up off the floor, tucked, and only dabs down now
		# and then.
		var dab := 1.0 if fmod(time, 1.7) < 0.25 else 0.0
		_feet.front = (rest.front as Vector2) + Vector2(-2.0, 4.0 * (1.0 - dab))
	if _stand > 0.35:
		var w := clampf((_stand - 0.35) / 0.4, 0.0, 1.0)
		_feet.front = (_feet.front as Vector2).lerp(hand, w)
		_feet.far_front = (_feet.far_front as Vector2).lerp(far_hand, w)
		# Keep the front feet ready to plant where the hands come down.
		_front.place(spots.front)
		_far_front.place(spots.far_front)


## Where each foot rests under the body (joint space, on the feet's level).
func _rest_spots(p: Dictionary) -> Dictionary:
	var front_x: float = lerpf(QUAD.front.x, RUN.front.x, _run_weight)
	return {
		"hind": Vector2(p.hind.x, 0.0), "front": Vector2(front_x, 0.0),
		"far_hind": Vector2(p.hind.x, 0.0) + Vector2(FAR_FOOT.x, 0.0),
		"far_front": Vector2(front_x, 0.0) + Vector2(FAR_FOOT.x, 0.0),
	}


## Each foot in the gait cycle (joint space): planted and sliding back under the body for the
## duty part of its cycle (which matches the ground going by), then swinging forward in an arc.
## The far feet sit FAR_FOOT up, as they're further away.
func _gait_feet(rest: Dictionary) -> Dictionary:
	var out := {}
	var stride: float = lerpf(WALK_GAIT.stride, RUN_GAIT.stride, _run_weight)
	var duty: float = lerpf(WALK_GAIT.duty, RUN_GAIT.duty, _run_weight)
	var lift: float = lerpf(WALK_GAIT.lift, RUN_GAIT.lift, _run_weight)
	for n in LEGS.size():
		var leg := LEGS[n]
		var offset: float = lerpf(WALK_GAIT.offsets[n], RUN_GAIT.offsets[n], _run_weight)
		var t := fposmod(_phase + offset, 1.0)
		var x: float
		var y: float = 0.0
		# On the ground the foot covers duty * stride, as far as the body moves meanwhile.
		var reach := stride * duty
		if t < duty:
			x = reach * (0.5 - t / duty)
		else:
			var swing := (t - duty) / (1.0 - duty)
			x = reach * (-0.5 + smoothstep(0.0, 1.0, swing))
			y = sin(swing * PI) * lift
		var spot: Vector2 = rest[leg] + Vector2(x, 0.0)
		var ground := to_joint(Vector2(to_world(spot).x, ground_y(to_world(spot).x, 10.0, 12.0))).y
		out[leg] = Vector2(spot.x, ground + y)
		if leg.begins_with("far"):
			out[leg] += Vector2(0.0, FAR_FOOT.y)
	return out


func _ground_spot(point: Vector2) -> Vector2:
	var world := to_world(point)
	return Vector2(world.x, ground_y(world.x, 10.0, 12.0))


func _blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for joint in a:
		out[joint] = (a[joint] as Vector2).lerp(b[joint], t)
	return out


# --- Drawing -----------------------------------------------------------------------------------


func _draw() -> void:
	if bot == null or _feet.is_empty():
		return
	var p := _pose
	# Far limbs first, darker and a pixel and a half behind.
	_hind_leg(p.hip + FAR, _feet.far_hind, FAR_LIMB, FAR_LIMB)
	_front_leg(p.shoulder + FAR, _feet.far_front, FAR_LIMB, FAR_LIMB)
	# Far ear.
	var head_geo := _head_points(p)
	line(head_geo.ear_base, head_geo.far_ear_mid, FAR_LIMB)
	line(head_geo.far_ear_mid, head_geo.far_ear_tip, FAR_LIMB)
	# Tail: a limp cable.
	var tail: Vector2 = p.tail + _tail.offset
	line(p.hip + Vector2(-1.0, 0.0), (p.hip + tail) * 0.5 + Vector2(0.0, -1.0), CABLE)
	line((p.hip + tail) * 0.5 + Vector2(0.0, -1.0), tail, CABLE)
	_spine(p.hip, p.mid, p.shoulder)
	# Pelvis and shoulder plates.
	blob(p.hip, 1.6, BONE_DARK)
	plot(p.hip + Vector2(0.0, 1.0), BONE)
	blob(p.shoulder, 1.2, BONE_DARK)
	# Neck: two thin rods.
	line(p.shoulder + Vector2(0.0, 1.0), p.head, BONE)
	line(p.shoulder, p.head + Vector2(0.0, -1.0), BONE_DARK)
	_head(head_geo)
	# Near limbs.
	_hind_leg(p.hip, _feet.hind, BONE, BONE_DARK)
	_front_leg(p.shoulder, _feet.front, BONE, BONE_LIGHT)
	# Near ear: a long thin blade.
	line(head_geo.ear_base, head_geo.ear_mid, BONE)
	line(head_geo.ear_mid, head_geo.ear_tip, BONE_LIGHT)
	# Eyes, stacked one above the other.
	var eye_color := EYE_DIM.lerp(EYE_HOT, _heat)
	if _heat > 0.9:
		eye_color = eye_color.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(time * 40.0)))
	var lit := true
	var low_lit := true
	if bot.dead:
		# Out, after a last stutter.
		lit = bot.dead_time < 1.0 and fmod(time * 9.0, 1.0) < 0.4
		low_lit = false
	elif bot.is_hurt():
		# The lower eye is dead; the upper one stutters.
		low_lit = false
		lit = fmod(time * 3.7, 1.0) > 0.12
	plot(head_geo.eye_top, eye_color if lit else EYE_DEAD)
	plot(head_geo.eye_low, eye_color if low_lit else EYE_DEAD)
	draw_pixels()
	var glow_color := GLOW_DIM.lerp(GLOW_HOT, _heat)
	if lit:
		glow(head_geo.eye_top, glow_color)
	if low_lit:
		glow(head_geo.eye_low, glow_color)


## Head geometry for this frame, with its tilt and the way it's looking.
func _head_points(p: Dictionary) -> Dictionary:
	var head: Vector2 = p.head
	var flip := Vector2(_head_dir, 1.0)
	var rot := _head_tilt * _head_dir
	var snout_off: Vector2 = ((p.snout as Vector2) - head) * flip
	var ear_base_off: Vector2 = ((p.ear_base as Vector2) - head) * flip
	var ear_tip_off: Vector2 = ((p.ear_tip as Vector2) - head) * flip + _ears.offset
	var far_tip_off: Vector2 = ((p.far_ear_tip as Vector2) - head) * flip + _ears.offset * 1.2
	var g := {}
	g.head = head
	g.snout = head + snout_off.rotated(rot)
	g.ear_base = head + ear_base_off.rotated(rot)
	g.ear_tip = head + ear_tip_off.rotated(rot)
	g.far_ear_tip = head + far_tip_off.rotated(rot)
	g.ear_mid = (g.ear_base as Vector2).lerp(g.ear_tip, 0.45) + Vector2(-0.6 * _head_dir, 0.3)
	g.far_ear_mid = (g.ear_base as Vector2).lerp(g.far_ear_tip, 0.5) + Vector2(0.4 * _head_dir, -0.4)
	var dir: Vector2 = ((g.snout as Vector2) - head).normalized()
	var down := Vector2(dir.y, -dir.x) if _head_dir > 0.0 else Vector2(-dir.y, dir.x)
	g.down = down
	g.dir = dir
	g.jaw_tip = (g.snout as Vector2) + down * (0.8 + 2.6 * _jaw) - dir * (1.0 + 0.6 * _jaw)
	g.eye_top = head + dir * 2.0 - down * 0.8
	g.eye_low = head + dir * 2.0 + down * 0.8
	return g


## A long narrow skull, and the jaw under it.
func _head(g: Dictionary) -> void:
	var head: Vector2 = g.head
	var snout: Vector2 = g.snout
	var down: Vector2 = g.down
	blob(head, 1.6, BONE)
	line(head - down * 1.2, snout, BONE_LIGHT)
	line(head, snout, BONE)
	line(head + down * 1.0, snout + down * 0.5, BONE_DARK)
	# Jaw, hinged at the back of the head; open, the mouth shows dark with teeth along it.
	var hinge := head + down * 1.5
	line(hinge, g.jaw_tip, BONE_DARK)
	if _jaw > 0.3:
		for i in range(1, 4):
			var t := float(i) / 4.0
			var upper := (head + down * 1.0).lerp(snout + down * 0.5, t)
			var lower := hinge.lerp(g.jaw_tip, t)
			var gap := upper.lerp(lower, 0.5)
			plot(gap, MOUTH)
			plot(upper + down * 0.7, TEETH if i % 2 == 1 else MOUTH)
			plot(lower - down * 0.7, TEETH if i % 2 == 0 else MOUTH)


## Bare spine from hip over mid to the shoulder, with vertebrae bumps and ribs hanging under it.
func _spine(a: Vector2, b: Vector2, c: Vector2) -> void:
	var control := b * 2.0 - (a + c) * 0.5
	var steps := 14
	for i in steps + 1:
		var t := float(i) / steps
		var q := a.lerp(control, t).lerp(control.lerp(c, t), t)
		plot(q, BONE)
		plot(q + Vector2(0.0, -1.0), BONE_DARK)
		if i % 2 == 0 and i > 0 and i < steps:
			plot(q + Vector2(0.0, 1.0), BONE_LIGHT)
		# Ribs: thin bars down from the front half of the spine.
		if i in [8, 10, 12]:
			var tangent := (control.lerp(c, t) - a.lerp(control, t)).normalized()
			var rib_dir := Vector2(tangent.y, -tangent.x)
			if rib_dir.y > 0.0:
				rib_dir = -rib_dir
			line(q + rib_dir * 1.0, q + rib_dir * 3.5 + tangent * -0.8, RIB)


## Thigh and shin by IK from the hip to the heel; the long hock is rigid down to the toe.
func _hind_leg(hip: Vector2, toe: Vector2, color: Color, shade: Color) -> void:
	var heel := toe + HOCK
	var knee := solve_ik(hip, heel, THIGH, SHIN, 1.0)
	line(hip, knee, color)
	line(knee, heel, shade)
	line(heel, toe, color)
	plot(toe + Vector2(1.0, 0.0), shade)


## Upper and fore arm by IK, the elbow bending forwards; a hand of two hooked claws.
func _front_leg(shoulder: Vector2, paw: Vector2, color: Color, claw: Color) -> void:
	var elbow := solve_ik(shoulder, paw, UPPER_ARM, FORE_ARM, 1.0)
	line(shoulder, elbow, color)
	line(elbow, paw, color)
	var dir := (paw - elbow).normalized()
	var spread := 0.6 if bot.state in [WatcherBot.State.WARN, WatcherBot.State.SWIPE] else 0.25
	if _claw_twitch <= 0.0 and _stand > 0.5 and _rng.randf() < 0.02:
		_claw_twitch = 0.12
	if _claw_twitch > 0.0:
		spread += 0.5
	if _stand > 0.4 or bot.state in [WatcherBot.State.LUNGE, WatcherBot.State.AIR]:
		line(paw, paw + dir.rotated(spread) * 2.5, claw)
		line(paw, paw + dir.rotated(-spread) * 2.5, claw)
	else:
		line(paw, paw + Vector2(1.5, 0.0), claw)
