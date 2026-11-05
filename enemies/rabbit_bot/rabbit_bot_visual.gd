class_name RabbitBotVisual
extends EnemyVisual
## Draws the rabbit bot, pixel by pixel, animated procedurally:
## - The body (hips, back, head, ears) eases between key poses for what it's doing (sitting,
##   alert, crouched to hop, stretched or tucked in flight, cowering) on springs.
## - Its four feet are planted on the ground and only step when the body has moved on: the
##   front paws take turns, the hind feet move together, as a rabbit's do. The hind knee is
##   solved with IK from the hip to the planted foot. In the air the feet follow the pose.
## - The ears are springs: they whip back on a hop, flop on landing and wobble when it stops.
## - Landings squash the body by how hard they were; it leans into its movement, and the head
##   turns to the robot when it's alert. Cowering trembles.
## Like the robot it's dark, worn metal with a 1 px dark silhouette outline; its only light is
## one amber eye.

const METAL := Color(0.25, 0.26, 0.28)
const METAL_LIGHT := Color(0.38, 0.39, 0.41)
const METAL_DARK := Color(0.15, 0.155, 0.17)
const FAR_LIMB := Color(0.12, 0.125, 0.14)
const JOINT := Color(0.33, 0.33, 0.33)
const RUST := Color(0.36, 0.2, 0.12)
const WIRE := Color(0.45, 0.27, 0.13)
const EYE := Color(1.0, 0.64, 0.16)
const EYE_GLOW := Color(1.0, 0.55, 0.12, 0.28)
## Hind leg bones: hip to knee, knee to heel; the foot from heel to toe is rigid.
const THIGH: float = 2.8
const SHIN: float = 4.0
const FOOT := Vector2(-3.5, 0.5)
## The far legs sit this far behind the near ones (joint space).
const FAR := Vector2(-1.0, 0.0)
const BODY_JOINTS: Array[String] = ["hip", "back", "shoulder", "head", "snout", "ear_base",
		"ear_mid", "ear_tip", "far_ear_mid", "far_ear_tip", "tail"]

## Key poses: joint -> (forward, up) in px from the feet.
const SIT := {
	"hip": Vector2(-2.5, 3.5), "knee": Vector2(0.0, 2.5), "heel": Vector2(-3.5, 0.5),
	"toe": Vector2(0.5, 0.0), "shoulder": Vector2(2.0, 3.5), "paw": Vector2(2.5, 0.0),
	"back": Vector2(-0.5, 6.0), "head": Vector2(4.0, 6.0), "snout": Vector2(5.5, 5.5),
	"ear_base": Vector2(3.0, 7.5), "ear_mid": Vector2(2.0, 10.5), "ear_tip": Vector2(1.0, 13.0),
	"far_ear_mid": Vector2(3.0, 10.5), "far_ear_tip": Vector2(4.5, 11.5),
	"tail": Vector2(-4.5, 4.5),
}
const ALERT := {
	"hip": Vector2(-2.5, 3.5), "knee": Vector2(0.0, 2.5), "heel": Vector2(-3.5, 0.5),
	"toe": Vector2(0.5, 0.0), "shoulder": Vector2(2.0, 4.5), "paw": Vector2(3.0, 1.0),
	"back": Vector2(-0.5, 7.0), "head": Vector2(3.5, 7.5), "snout": Vector2(5.0, 7.5),
	"ear_base": Vector2(3.0, 9.0), "ear_mid": Vector2(3.0, 11.0), "ear_tip": Vector2(3.0, 13.0),
	"far_ear_mid": Vector2(4.0, 11.0), "far_ear_tip": Vector2(5.0, 12.0),
	"tail": Vector2(-4.5, 4.0),
}
const CROUCH := {
	"hip": Vector2(-2.5, 2.5), "knee": Vector2(0.0, 1.5), "heel": Vector2(-3.5, 0.3),
	"toe": Vector2(0.5, 0.0), "shoulder": Vector2(2.5, 2.5), "paw": Vector2(3.0, 0.0),
	"back": Vector2(-0.5, 4.5), "head": Vector2(4.0, 4.0), "snout": Vector2(5.5, 3.5),
	"ear_base": Vector2(2.5, 5.5), "ear_mid": Vector2(0.0, 7.5), "ear_tip": Vector2(-2.5, 9.0),
	"far_ear_mid": Vector2(1.0, 7.0), "far_ear_tip": Vector2(-0.5, 8.5),
	"tail": Vector2(-4.5, 3.5),
}
const STRETCH := {
	"hip": Vector2(-2.0, 4.5), "knee": Vector2(-4.5, 3.0), "heel": Vector2(-6.5, 2.0),
	"toe": Vector2(-8.5, 1.5), "shoulder": Vector2(2.5, 5.0), "paw": Vector2(5.5, 4.5),
	"back": Vector2(0.0, 6.5), "head": Vector2(5.0, 7.0), "snout": Vector2(6.5, 7.0),
	"ear_base": Vector2(3.5, 8.0), "ear_mid": Vector2(1.0, 10.0), "ear_tip": Vector2(-2.0, 11.5),
	"far_ear_mid": Vector2(2.0, 9.5), "far_ear_tip": Vector2(0.0, 10.5),
	"tail": Vector2(-4.0, 6.0),
}
const TUCK := {
	"hip": Vector2(-2.0, 4.0), "knee": Vector2(0.5, 3.0), "heel": Vector2(-2.0, 1.5),
	"toe": Vector2(0.5, 1.0), "shoulder": Vector2(2.5, 4.0), "paw": Vector2(4.5, 1.0),
	"back": Vector2(-0.5, 6.5), "head": Vector2(4.5, 6.0), "snout": Vector2(6.0, 5.5),
	"ear_base": Vector2(3.0, 7.5), "ear_mid": Vector2(1.5, 10.5), "ear_tip": Vector2(0.0, 12.5),
	"far_ear_mid": Vector2(2.5, 10.0), "far_ear_tip": Vector2(3.5, 11.0),
	"tail": Vector2(-4.5, 5.0),
}
const COWER := {
	"hip": Vector2(-2.5, 2.5), "knee": Vector2(0.0, 1.5), "heel": Vector2(-3.5, 0.3),
	"toe": Vector2(0.5, 0.0), "shoulder": Vector2(2.0, 2.5), "paw": Vector2(3.0, 0.0),
	"back": Vector2(-1.0, 4.5), "head": Vector2(3.5, 3.5), "snout": Vector2(5.0, 3.0),
	"ear_base": Vector2(2.0, 5.0), "ear_mid": Vector2(-1.0, 6.0), "ear_tip": Vector2(-4.0, 6.5),
	"far_ear_mid": Vector2(0.0, 5.5), "far_ear_tip": Vector2(-2.5, 6.0),
	"tail": Vector2(-4.5, 3.0),
}
## Nose to the floor, rump up, front paws raking at the ground (also its digging pose).
const RUMMAGE := {
	"hip": Vector2(-2.5, 3.8), "knee": Vector2(0.0, 2.5), "heel": Vector2(-3.5, 0.5),
	"toe": Vector2(0.5, 0.0), "shoulder": Vector2(2.5, 2.5), "paw": Vector2(4.0, 0.0),
	"back": Vector2(-0.5, 5.8), "head": Vector2(5.0, 2.5), "snout": Vector2(6.5, 1.0),
	"ear_base": Vector2(4.0, 4.0), "ear_mid": Vector2(2.0, 6.5), "ear_tip": Vector2(-0.5, 8.0),
	"far_ear_mid": Vector2(3.0, 6.0), "far_ear_tip": Vector2(1.5, 7.5),
	"tail": Vector2(-4.5, 5.5),
}
## Dead: on its back, flattened, legs stuck stiffly up, ears splayed along the floor. toe and
## paw are where the (near) feet end up.
const DEAD := {
	"hip": Vector2(-3.0, 2.0), "knee": Vector2(-1.5, 4.0), "heel": Vector2(-3.0, 5.0),
	"toe": Vector2(-1.0, 7.0), "shoulder": Vector2(2.5, 2.0), "paw": Vector2(3.5, 6.0),
	"back": Vector2(-0.5, 1.5), "head": Vector2(5.0, 1.5), "snout": Vector2(7.0, 1.0),
	"ear_base": Vector2(4.0, 1.0), "ear_mid": Vector2(6.5, 0.5), "ear_tip": Vector2(9.5, 0.5),
	"far_ear_mid": Vector2(5.5, 2.5), "far_ear_tip": Vector2(8.0, 3.5),
	"tail": Vector2(-5.5, 1.0),
}
const EYE_DEAD := Color(0.16, 0.1, 0.06)

## How quickly joints ease to a new pose (per second), and faster for hops.
@export var ease_rate: float = 18.0
@export var hop_ease_rate: float = 40.0
## A planted foot steps once the body has moved this far (px) from it.
@export var step_reach: float = 2.0
## How much the ears are thrown around by the body's movement.
@export var ear_floppiness: float = 0.03

var bot: RabbitBot

var _pose: Dictionary = SIT.duplicate()
var _rng := RandomNumberGenerator.new()
## Feet: near and far hind toes, near and far front paws.
var _toe := Foot.new()
var _far_toe := Foot.new()
var _paw := Foot.new()
var _far_paw := Foot.new()
var _feet_planted: bool = false
var _facing_was: float = 0.0
var _ear := Spring.new(220.0, 9.0)
var _far_ear := Spring.new(180.0, 7.0)
## Joint-space positions of the feet this frame.
var _feet: Dictionary = {}
var _squash: float = 0.0
var _was_state: int = -1
var _air_speed: float = 0.0
## Ear twitch: seconds left, and which ear.
var _twitch_left: float = 0.0
var _twitch_far: bool = false
var _next_twitch: float = 1.0
## Sniff: seconds left of a head dip.
var _sniff_left: float = 0.0
var _next_sniff: float = 2.0
var _tremble := Vector2.ZERO
var _tremble_left: float = 0.0
## Fixed wear marks on the body, different for each bot.
var _rust_spots: Array[int] = []


func _ready() -> void:
	super()
	bot = body as RabbitBot
	_rng.randomize()
	for i in 2:
		_rust_spots.append(_rng.randi_range(0, 7))
	for foot in [_toe, _far_toe]:
		foot.step_time = 0.11
		foot.lift = 1.2
	for foot in [_paw, _far_paw]:
		foot.step_time = 0.09
		foot.lift = 1.0


func _animate(delta: float) -> void:
	if bot == null:
		return
	if bot.dead:
		_animate_dead(delta)
		return
	var state := bot.state
	if state == RabbitBot.State.AIR:
		_air_speed = maxf(bot.velocity.y, 0.0)
	if state != _was_state:
		if state == RabbitBot.State.LAND:
			# Squash by how hard it came down.
			_squash = clampf(_air_speed / 45.0, 0.3, 1.0) * 1.5
			_ear.velocity.y -= _air_speed * 1.2
			_far_ear.velocity.y -= _air_speed
		_was_state = state
	_squash = move_toward(_squash, 0.0, delta * 6.0)

	var target := _target_pose(delta)
	var airborne := state in [RabbitBot.State.WINDUP, RabbitBot.State.AIR, RabbitBot.State.LAND]
	var k := 1.0 - exp(-(hop_ease_rate if airborne else ease_rate) * delta)
	for joint in BODY_JOINTS:
		_pose[joint] = (_pose[joint] as Vector2).lerp(target[joint], k)
	for joint in ["toe", "paw"]:
		_pose[joint] = (_pose[joint] as Vector2).lerp(target[joint], k)

	# Ears: springs shoved by the body's acceleration (in joint space), against the motion.
	var push := Vector2(accel.x * bot.facing, -accel.y) * -ear_floppiness * 60.0
	_ear.update(push, delta, 3.5)
	_far_ear.update(push * 1.2, delta, 3.5)
	_update_feet(delta, state)


## Keels over onto its back with a last kick of the legs, then lies still.
func _animate_dead(delta: float) -> void:
	var k := 1.0 - exp(-ease_rate * 0.8 * delta)
	for joint in BODY_JOINTS:
		_pose[joint] = (_pose[joint] as Vector2).lerp(DEAD[joint], k)
	for joint in ["toe", "paw"]:
		_pose[joint] = (_pose[joint] as Vector2).lerp(DEAD[joint], k)
	# A few twitches of the legs in the first moments, then nothing.
	var kick := Vector2.ZERO
	if bot.dead_time < 1.5 and fmod(bot.dead_time, 0.5) < 0.12:
		kick = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 0.5))
	_feet = {"toe": _pose.toe + kick, "far_toe": _pose.toe + Vector2(1.5, -1.0),
			"paw": _pose.paw - kick, "far_paw": _pose.paw + Vector2(1.0, -1.0)}
	_ear.update(Vector2.ZERO, delta, 1.0)
	_far_ear.update(Vector2.ZERO, delta, 1.0)


## Plants the feet on the ground and steps them as the body moves, or lets them follow the
## pose in the air.
func _update_feet(delta: float, state: int) -> void:
	var grounded := state != RabbitBot.State.AIR and bot.is_on_floor()
	if bot.facing != _facing_was:
		_facing_was = bot.facing
		_feet_planted = false
	var spots := {
		"toe": _ground_spot(_pose.toe), "far_toe": _ground_spot(_pose.toe + FAR),
		"paw": _ground_spot(_pose.paw), "far_paw": _ground_spot(_pose.paw + FAR),
	}
	if not grounded:
		_feet_planted = false
		_feet = {"toe": _pose.toe, "far_toe": _pose.toe + FAR, "paw": _pose.paw,
				"far_paw": _pose.paw + FAR}
		return
	if not _feet_planted:
		_feet_planted = true
		_toe.place(spots.toe)
		_far_toe.place(spots.far_toe)
		_paw.place(spots.paw)
		_far_paw.place(spots.far_paw)
	# Front paws take turns; the hind feet go together once the paws are down.
	var front_busy := _paw.is_stepping() or _far_paw.is_stepping()
	_paw.update(spots.paw, step_reach, not _far_paw.is_stepping(), delta)
	_far_paw.update(spots.far_paw, step_reach, not _paw.is_stepping(), delta)
	var hind_go := not front_busy and (_toe.pos.distance_to(spots.toe) > step_reach
			or _far_toe.pos.distance_to(spots.far_toe) > step_reach)
	_toe.update(spots.toe, 0.0 if hind_go else step_reach, hind_go or _toe.is_stepping(), delta)
	_far_toe.update(spots.far_toe, 0.0 if hind_go else step_reach,
			hind_go or _far_toe.is_stepping(), delta)
	_feet = {"toe": to_joint(_toe.pos), "far_toe": to_joint(_far_toe.pos),
			"paw": to_joint(_paw.pos), "far_paw": to_joint(_far_paw.pos)}
	if bot.state == RabbitBot.State.RUMMAGE or _digging():
		# Front paws rake the floor in turns: forward, down, dragged back under the body.
		var rate := 14.0 if _digging() else 7.0
		for i in 2:
			var key: String = "paw" if i == 0 else "far_paw"
			var phase := fmod(time * rate / TAU + i * 0.5, 1.0)
			var x := 1.5 - phase * 3.5 if phase < 0.6 else -2.0 + (phase - 0.6) / 0.4 * 3.5
			var y := 0.0 if phase < 0.6 else sin((phase - 0.6) / 0.4 * PI) * 1.5
			_feet[key] = _pose.paw + (FAR if i == 1 else Vector2.ZERO) + Vector2(x, y)


## Digging in or climbing out of the floor.
func _digging() -> bool:
	return bot.under in [Enemy.Under.DIGGING, Enemy.Under.EMERGING]


## Where a foot at joint-space point would stand: straight below it on the ground (world).
func _ground_spot(point: Vector2) -> Vector2:
	var world := to_world(point)
	return Vector2(world.x, ground_y(world.x))


func _target_pose(delta: float) -> Dictionary:
	var pose: Dictionary
	if _digging():
		pose = RUMMAGE.duplicate()
		# Frantic: the whole body jerks with each scoop.
		var jerk := sin(time * 40.0) * 0.4
		for joint in BODY_JOINTS:
			pose[joint] += Vector2(jerk, 0.0)
		return pose
	match bot.state:
		RabbitBot.State.RUMMAGE:
			pose = RUMMAGE.duplicate()
			# Snuffling along the floor between scratches, the odd look up.
			var sniff := sin(time * 13.0) * 0.4
			pose.snout += Vector2(sniff, absf(sniff))
			pose.head += Vector2(sniff * 0.5, 0.0)
			if fmod(bot.state_time, 2.3) > 2.0:
				pose.head += Vector2(-0.5, 1.5)
				pose.snout += Vector2(-0.5, 3.0)
		RabbitBot.State.WINDUP:
			pose = CROUCH.duplicate()
		RabbitBot.State.AIR:
			# Stretched on the way up, tucked and reaching on the way down.
			var t := clampf(inverse_lerp(-30.0, 30.0, bot.velocity.y), 0.0, 1.0)
			pose = _blend(STRETCH, TUCK, t)
		RabbitBot.State.LAND:
			pose = _blend(CROUCH, SIT, clampf(bot.state_time / maxf(bot.land_time, 0.01), 0.0, 1.0))
		RabbitBot.State.COWER:
			pose = COWER.duplicate()
			_tremble_left -= delta
			if _tremble_left <= 0.0:
				_tremble_left = 0.05
				_tremble = Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.3, 0.3))
			for joint in ["back", "head", "snout", "shoulder", "ear_base", "ear_mid", "ear_tip",
					"far_ear_mid", "far_ear_tip"]:
				pose[joint] += _tremble
		RabbitBot.State.WALK:
			pose = SIT.duplicate()
			# Lean in, and let the feet's steps lift the body: up while the hind feet push.
			var lift := 0.0
			if _toe.is_stepping():
				lift = sin(_toe.t * PI) * 0.8
			for joint in BODY_JOINTS:
				pose[joint] += Vector2(0.3, lift)
			pose.head += Vector2(0.4, -0.3)
			pose.snout += Vector2(0.4, -0.3)
		_:
			pose = (ALERT if bot.alert else SIT).duplicate()
			if bot.alert:
				_look_at_robot(pose)
			else:
				_idle_actions(pose, delta)
	if bot.is_hurt() and bot.state not in [RabbitBot.State.AIR, RabbitBot.State.WINDUP]:
		# Hurt: hunched lower, head hanging a little, the far ear dead and flopped over, and a
		# limp (the body dips on every other step).
		for joint in BODY_JOINTS:
			var w := clampf((pose[joint] as Vector2).y / 8.0, 0.0, 1.0)
			pose[joint] += Vector2(0.0, -0.8 * w)
		pose.head += Vector2(0.0, -0.6)
		pose.snout += Vector2(0.0, -1.2)
		pose.far_ear_mid = pose.ear_base + Vector2(-2.5, 0.5)
		pose.far_ear_tip = pose.ear_base + Vector2(-4.5, -1.5)
		if bot.state == RabbitBot.State.WALK and _paw.is_stepping():
			for joint in BODY_JOINTS:
				pose[joint] += Vector2(0.0, -0.7 * sin(_paw.t * PI))
	if _squash > 0.0:
		for joint in BODY_JOINTS:
			var weight := clampf((pose[joint] as Vector2).y / 8.0, 0.0, 1.0)
			pose[joint] += Vector2(0.0, -_squash * weight)
	return pose


## Head (and ears) turn up or down towards the robot.
func _look_at_robot(pose: Dictionary) -> void:
	if not bot.target_alive():
		return
	var dy := bot.global_position.y - 8.0 - (bot.target.global_position.y)
	var tilt := clampf(dy / 24.0, -1.0, 1.0)
	pose.snout += Vector2(-0.3 * absf(tilt), tilt)
	pose.head += Vector2(0.0, tilt * 0.4)


## Ear twitches and sniffing while it sits calmly.
func _idle_actions(pose: Dictionary, delta: float) -> void:
	_next_twitch -= delta
	if _next_twitch <= 0.0:
		_next_twitch = _rng.randf_range(0.8, 3.0)
		_twitch_far = _rng.randf() < 0.5
		# A flick: kick the ear's spring backwards.
		(_far_ear if _twitch_far else _ear).velocity += Vector2(-60.0, -25.0)
	_next_sniff -= delta
	if _next_sniff <= 0.0:
		_next_sniff = _rng.randf_range(1.5, 4.0)
		_sniff_left = 0.6
	if _sniff_left > 0.0:
		_sniff_left -= delta
		# Two quick dips of the snout.
		var dip := 1.0 if fmod(_sniff_left, 0.3) > 0.15 else 0.0
		pose.head += Vector2(0.3, -dip)
		pose.snout += Vector2(0.0, -dip * 1.5)


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
	var ear_off := _ear.offset
	var far_ear_off := _far_ear.offset
	# Far side first: hind leg and front leg, a pixel behind and darker.
	_hind_leg(p.hip + FAR, _feet.far_toe, FAR_LIMB, FAR_LIMB, FAR_LIMB)
	line(p.shoulder + FAR, _feet.far_paw, FAR_LIMB)
	line(p.ear_base + Vector2(0.5, 0.0), p.far_ear_mid + far_ear_off * 0.5, FAR_LIMB)
	line(p.far_ear_mid + far_ear_off * 0.5, p.far_ear_tip + far_ear_off, FAR_LIMB)
	# Body: a thin hunched curve, hip over the back to the shoulder.
	_body(p.hip, p.back, p.shoulder)
	# The haunch: a rounded plate over the hind leg's hip joint.
	blob(p.hip + Vector2(0.3, -0.3), 1.4, METAL_DARK)
	plot(p.hip + Vector2(0.0, 1.0), METAL)
	# A dangling scrap of wire for a tail.
	line(p.hip + Vector2(-1.0, 0.5), p.tail, METAL_DARK)
	plot(p.tail + Vector2(-0.5, -1.0), WIRE)
	plot(p.tail + Vector2(-1.0, -2.0), WIRE)
	# Neck and head: a big head for the scrawny body, a skull plate tapering to the snout.
	line(p.shoulder + Vector2(0.0, 1.0), p.head, METAL)
	blob(p.head, 1.5, METAL)
	line(p.head, p.snout, METAL)
	line(p.head + Vector2(0.0, -1.0), p.snout + Vector2(-0.5, -0.5), METAL_DARK)
	plot(p.head + Vector2(0.0, 1.5), METAL_LIGHT)
	plot(p.head + Vector2(-1.0, 1.5), METAL_LIGHT)
	plot(p.head + Vector2(1.0, 1.0), METAL_LIGHT)
	# Near limbs: a long hind leg with a joint, a stick of a front leg.
	_hind_leg(p.hip, _feet.toe, METAL, METAL_DARK, METAL)
	line(p.shoulder, _feet.paw, METAL)
	# Near ear: thin, with a light edge.
	line(p.ear_base, p.ear_mid + ear_off * 0.5, METAL)
	line(p.ear_mid + ear_off * 0.5, p.ear_tip + ear_off, METAL_LIGHT)
	# The eye, the only light.
	var eye_color := EYE
	var cowering := bot.state == RabbitBot.State.COWER
	if cowering:
		eye_color.a = 0.55 + 0.45 * _flicker()
	var lit := not bot.dead
	if bot.dead:
		# The eye gutters out in the first moments, then it's dark.
		eye_color = EYE_DEAD
		if bot.dead_time < 1.2 and _flicker() > 0.6:
			eye_color = EYE.darkened(0.5)
	elif bot.is_hurt() and _flicker() > 0.8:
		# Hurt, the eye drops out now and then.
		eye_color = EYE.darkened(0.6)
		lit = false
	var eye: Vector2 = p.head + Vector2(1.0, 0.5)
	plot(eye, eye_color)
	draw_pixels()
	# A faint glow around the eye, over the outline.
	if lit and (not cowering or _flicker() > 0.5):
		glow(eye, EYE_GLOW)


## Thigh and shin solved with IK from the hip to the heel; the foot is rigid behind the toe.
func _hind_leg(hip: Vector2, toe: Vector2, thigh_color: Color, shin_color: Color,
		foot_color: Color) -> void:
	var heel := toe + FOOT
	var knee := solve_ik(hip, heel, THIGH, SHIN, 1.0)
	line(hip, knee, thigh_color)
	line(hip + Vector2(0.0, 1.0), knee + Vector2(0.0, 0.5), thigh_color)
	if thigh_color == METAL:
		plot(knee, JOINT)
	line(knee, heel, shin_color)
	line(heel, toe, foot_color)


func _flicker() -> float:
	return 0.5 + 0.5 * sin(time * 37.0) * sin(time * 11.0)


## The torso: a quadratic curve from a to c through control b, two pixels thick, with a lighter
## spine on top and a couple of rust spots.
func _body(a: Vector2, b: Vector2, c: Vector2) -> void:
	var control := b * 2.0 - (a + c) * 0.5
	var steps := 10
	for i in steps + 1:
		var t := float(i) / steps
		var q := a.lerp(control, t).lerp(control.lerp(c, t), t)
		plot(q, METAL)
		plot(q + Vector2(0.0, -1.0), METAL_DARK)
		plot(q + Vector2(0.0, 1.0), METAL_LIGHT if i > 1 and i < steps - 1 else METAL)
		if i in _rust_spots:
			plot(q, RUST)
