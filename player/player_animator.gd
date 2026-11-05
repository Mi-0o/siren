class_name PlayerAnimator
extends Node
## Procedural animation for the robot rig: idle, walk, running on all fours, dash, charged
## jump (set and lunge), air (rising and falling), wire and landing.
## The Player's physics drive everything; this only reads it and poses the bones.
##
## Layers, top to bottom:
## 1. Mode from the Player: idle, walk, quad (on all fours: the Player's LOW posture), dash,
##    set (charged jump ready), recover (hard landing) or air. Idle and walk share one posture
##    that blends slowly, so starting off it straightens over a moment and stopping hunches
##    back down. The hip slides back over the hitbox on all fours so the long body stays on it.
## 2. Key pose per mode: hip height, spine hunch, neck, head and arm angles. Springs carry every
##    value between poses, so mode changes need no authored transitions.
## 3. Legs: both pegs step between planted world points found by ground raycasts, so they
##    never slide. A gait clock advanced by distance walked times the steps, so the rhythm
##    stays regular: the near peg swings in the first part of each cycle, the far one half a
##    cycle later. Turns, landings and starts re-seed the clock with the trailing leg first.
##    The hip bobs with the cycle and the IK never locks the knee fully straight.
##    In the air the legs tuck while rising and reach for the ground while falling. Landings
##    are absorbed by a knee bend that grows with fall speed; a hard landing (the Player's
##    hard_landing_speed) drops into a crouch that holds until the Player's recovery ends.
##    On all fours the hands become pegs too: a half-bound gallop where the hind pegs push off
##    a beat apart, then the hands reach, with the spine flexing and stretching to it. Hands
##    are solved with IK every frame, elbows bent back, so they stay planted.
##    A dash is one long, low bound: the legs stay planted and straighten like hydraulic
##    rams, the body flies stretched just off the floor with the hands reaching, then the
##    hands catch the ground and fold, the legs swing under, and the robot stays crouched
##    on all fours before slowly rising (dash_recover_time). A charged jump settles into a
##    sprinter's set, hands down, launches into a full-stretch lunge, then eases into a flight
##    pose with the legs tucked forward, ready to land at any moment. After any jump, a long
##    fall eases slowly into the balancing fall pose (fall_blend_time).
##    While the wire is shown the near arm points straight along it, and the drawn wire starts
##    at that hand.
##    Attacks: melee strikes snap from a fighting guard through a chambered pose into the
##    strike and back (kicks drive one leg's peg along a path while the other stays planted);
##    a plasma shot throws the near arm straight out ahead and kicks it up as the bolt leaves;
##    the burst sinks into a wide braced stance, near arm out, trembling as it heats, and is
##    thrown back into a slide when it fires.
## 4. Idle life: tiny servo twitches on random joints, and every few seconds either an eye scan
##    or a jolty joint check of both arms.
## 5. Output: legs and hip are solved with 2-bone IK every frame; the upper body is only
##    updated servo_rate times a second, so it moves in small mechanical steps. The head is a
##    stabilised camera: it holds its angle while the body lurches underneath.
## 6. Low charge: below each of the Player's charge ratios (warning, critical, failing) the
##    servos update less often, snap to coarser angles and miss by random amounts, twitches
##    grow, steps land off target and stall mid-swing, the body slumps, and the head camera
##    loses its stabilisation. Every effect is set per tier in the Low charge group.
##
## All pose maths is in skeleton space: x forward (the facing direction), y down, origin on the
## ground under the hip. Angles are radians; positive tips a bone forward (clockwise when facing
## right). Arm and head angles are global (0 = hanging straight down / head level).

enum Mode {
	IDLE, WALK, AIR, RECOVER, QUAD, DASH, DASH_END, SET, STUMBLE, DOWN, CRAWL, CLIMB, MELEE, BRACE,
}

## Modes where the hands may be on the ground (see _hands_down()).
const HAND_MODES: Array[Mode] = [Mode.QUAD, Mode.DASH, Mode.DASH_END, Mode.SET, Mode.CRAWL]

## Body parts never sink below the floor: knees and elbows keep this many pixels above it.
const JOINT_CLEARANCE: float = 1.0
## How much better the other bend must be before a limb switches which way its middle joint
## bends near the floor, in pixels. Without it, a knee or elbow grazing the floor (a limb lying
## flat, as when dead) flicks between the two bends from one frame to the next.
const IK_HYSTERESIS: float = 2.0
## Lying down (dead or knocked down, not pushing up), how fast a limb joint may turn, in
## radians per second. The limbs there are slack and settle onto the floor, so a joint that would
## jump (an elbow folding against the floor, a knee finding its side) swings over instead.
const DOWN_LIMB_RATE: float = 7.0
## Body parts that lift the whole body when they would sink into the floor.
const BODY_BONES: Array[StringName] = [
	&"Hip", &"Waist1", &"Waist2", &"Waist3", &"Ribcage", &"Neck", &"Head",
]

## Fighting guard between melee strikes: hunched, fists up at the chest.
const GUARD: Dictionary = {
	&"lean": 0.5, &"neck": 0.15, &"head": 0.12, &"hip_h": 15.0, &"shift": 6.0,
	&"near_arm": 0.1, &"near_elbow": -2.2, &"far_arm": 0.3, &"far_elbow": -2.3,
}
## Melee strike poses, in the Player's MELEE_MOVES order: the leg that kicks (0 none, 1 near,
## 2 far), where its peg goes chambered and at the strike (skeleton space, from the ground under
## the hip), and the upper body chambered and striking (keys left out keep the guard).
const MELEE_POSES: Array[Dictionary] = [
	{  # Jab: the near fist snaps straight out.
		"leg": 0,
		"chamber": {&"near_arm": 0.35, &"near_elbow": -2.4, &"lean": 0.45},
		"strike": {&"near_arm": -1.52, &"near_elbow": -0.05, &"lean": 0.65, &"shift": 8.0},
	},
	{  # Cross: the far fist drives through with the shoulders turned into it.
		"leg": 0,
		"chamber": {&"far_arm": 0.55, &"far_elbow": -2.4, &"lean": 0.4},
		"strike": {&"far_arm": -1.55, &"far_elbow": -0.05, &"near_arm": 0.4, &"near_elbow": -2.3,
				&"lean": 0.75, &"shift": 9.0},
	},
	{  # Knee: grabs and pulls down while the near knee rams up.
		"leg": 1, "chamber_peg": Vector2(-3, 0), "kick_peg": Vector2(3, -7),
		"chamber": {&"near_arm": -0.9, &"near_elbow": -1.0, &"far_arm": -0.8, &"far_elbow": -1.2},
		"strike": {&"near_arm": -0.5, &"near_elbow": -1.5, &"far_arm": -0.4, &"far_elbow": -1.6,
				&"lean": 0.6, &"hip_h": 16.0},
	},
	{  # Front kick: knee up, then the leg punches straight out at hip height.
		"leg": 1, "chamber_peg": Vector2(5, -9), "kick_peg": Vector2(19, -13),
		"chamber": {&"lean": 0.35, &"hip_h": 16.0},
		"strike": {&"lean": 0.05, &"head": 0.25, &"hip_h": 16.5, &"near_arm": 0.5, &"far_arm": 0.6},
	},
	{  # Low sweep: drops low and scythes the far leg along the floor.
		"leg": 2, "chamber_peg": Vector2(-9, -2), "kick_peg": Vector2(16, -1),
		"chamber": {&"hip_h": 10.0, &"lean": 0.9},
		"strike": {&"hip_h": 9.0, &"lean": 1.05, &"near_arm": -0.6, &"near_elbow": -0.5,
				&"far_arm": 0.8, &"far_elbow": -0.4, &"head": 0.2},
	},
	{  # Roundhouse: winds the knee high, then whips the leg up at head height.
		"leg": 1, "chamber_peg": Vector2(4, -14), "kick_peg": Vector2(17, -27),
		"chamber": {&"lean": 0.2, &"hip_h": 16.0, &"near_arm": 0.4, &"far_arm": -0.6},
		"strike": {&"lean": -0.15, &"head": 0.05, &"neck": 0.3, &"hip_h": 16.5,
				&"near_arm": 0.9, &"near_elbow": -0.8, &"far_arm": -1.1, &"far_elbow": -0.6},
	},
]

## Length of the shin from knee to peg tip, in pixels.
const SHIN_LENGTH: float = 11.0
## Arm segment lengths, shoulder to elbow and elbow to hand tip, in pixels.
const UPPER_ARM_LENGTH: float = 8.0
const FOREARM_LENGTH: float = 10.0
## Below this horizontal speed (px/s) on the floor the robot counts as standing.
const WALK_THRESHOLD: float = 4.0
## Where the hip sits in the rig viewport horizontally, before the body shift.
const RIG_HIP_X: float = 40.0
## Idle actions: name, duration in seconds, and keyframes [time, {pose value: target}]. Values
## hold until the next key changes them; springs and servo stepping make the moves jolty.
const ACTIONS: Dictionary = {
	&"scan": [3.2, [
		[0.0, {&"eye": 1.0, &"neck": 0.55, &"head": -0.08}],
		[0.35, {&"scan": 1.0, &"head": -0.22}],
		[1.0, {&"head": 0.02}],
		[1.6, {&"head": 0.24}],
		[2.2, {&"head": 0.08, &"scan": 0.0}],
		[2.7, {&"eye": -1.0}],
	]],
	&"joint_check": [3.4, [
		[0.0, {&"head": 0.5, &"near_arm": -0.8, &"near_elbow": -0.3}],
		[0.45, {&"near_elbow": -1.7}],
		[0.8, {&"near_elbow": -0.5}],
		[1.05, {&"near_elbow": -1.7, &"near_arm": -1.3}],
		[1.5, {&"near_arm": -0.15, &"near_elbow": -0.35}],
		[1.8, {&"head": 0.35, &"far_arm": -0.75, &"far_elbow": -1.4}],
		[2.25, {&"far_elbow": -0.3}],
		[2.5, {&"far_elbow": -1.4}],
		[2.8, {&"far_arm": 0.05, &"far_elbow": -0.25}],
	]],
}
## Bones that idle twitches can nudge.
const TWITCH_BONES: Array[StringName] = [
	&"UpperArmNear", &"ForearmNear", &"UpperArmFar", &"ForearmFar", &"Head", &"Neck", &"Waist3",
]

@export_group("Stance")
## Hip height above the pegs when standing, in pixels. Lower = more bent knees.
@export var hip_height: float = 16.0
## Hip height while airborne.
@export var air_hip_height: float = 16.0
## Idle peg positions ahead of (positive) or behind the hip, in pixels.
@export var stance_near: float = 3.0
@export var stance_far: float = -5.0
## The hip sits this many pixels behind the hitbox centre, so the hunched body is centred on it.
@export var body_shift: float = 6.0

@export_group("Hunch")
## Total forward bend of the spine (hip + three waist bones + ribcage), per mode.
@export var idle_lean: float = 0.9
@export var walk_lean: float = 0.75
@export var air_lean: float = 0.55
## Neck bend forward, and head angle (0 level, positive nose down), per mode.
@export var idle_neck: float = 0.4
@export var idle_head: float = 0.22
## Head angle while looking up and while looking down (look up / look down held), radians.
## Like the other head angles, 0 is level and positive tips the nose down.
@export var look_up_head: float = -0.6
@export var look_down_head: float = 0.75
@export var walk_neck: float = 0.36
@export var walk_head: float = 0.16

@export_group("Jump")
## How far the body sinks in a normal jump's wind-up, in pixels, and how long the takeoff push
## pose lasts, in seconds.
@export var windup_crouch: float = 4.5
@export var jump_spring_time: float = 0.25

@export_group("Damage")
## Crawling on the arms (legs faulted): stride per arm pull in pixels, the share of it spent
## reaching, and how high the chest heaves with each pull.
@export var crawl_stride: float = 15.0
@export var crawl_swing: float = 0.45
@export var crawl_heave: float = 1.2
## Lying on the floor (knocked down, crawling, dead): hip height above the ground in pixels.
@export var prone_hip_height: float = 3.5

@export_group("Turn")
## A turn is a yaw rotation of the whole rig towards the camera and on round, drawn as a
## projection over whatever pose the modes produce. Seconds for a full about-turn; the body's
## own side flips halfway, while it faces the camera.
@export var turn_time: float = 0.24
## How far the head and chest lead the turn, and the hips trail it, in radians at the front
## view, so the turn twists through the spine instead of rotating as one block.
@export var turn_lead_head: float = 0.55
@export var turn_lead_chest: float = 0.25
@export var turn_lag_hips: float = 0.2
## Sideways distance of the legs and of the arms from the body's centre line, in pixels: the
## depth the side view hides, which spreads them apart when seen from the front.
@export var turn_leg_spread: float = 2.0
@export var turn_arm_spread: float = 4.0

@export_group("Posture blend")
## Seconds to straighten from the idle hunch into the walking posture after setting off, and
## to sink back into the hunch after stopping.
@export var walk_blend_in: float = 0.8
@export var walk_blend_out: float = 1.0

@export_group("Walk")
## Ground covered by one full gait cycle (a step of each leg) at walk and at run speed, in
## pixels. In between it blends; slower than a walk it shortens towards stride_slow.
@export var stride_slow: float = 16.0
@export var stride_walk: float = 24.0
@export var stride_run: float = 30.0
## Part of the cycle each peg spends in the air. The rest it is planted.
@export_range(0.2, 0.5) var swing_fraction: float = 0.4
## Pegs land this much further forward than the middle of their stance, in pixels.
@export var stride_bias: float = 1.0
## Hip height while walking: higher than the hunched idle, so the planted leg is nearly
## straight mid-stance and the knee does its bending in the swing.
@export var walk_hip_height: float = 17.5
## How far the hip rises over each planted leg mid-stance, in pixels.
@export var walk_bob: float = 1.0
## How high each peg lifts mid-step, in pixels. The far one stays lower, scraping.
@export var near_lift: float = 2.5
@export var far_lift: float = 1.2
## Forward pitch kick per landing step (rad/s) and hip dip (px/s), for the lurch.
@export var lurch_kick: float = 0.8
@export var bob_kick: float = 6.0
## Legs never straighten past this share of their full length; the knee keeps a bend.
@export_range(0.8, 1.0) var knee_soft_start: float = 0.9

@export_group("Run on all fours")
## Spine bend on all fours (about a quarter turn: level), neck bend lifting the head, and
## head angle.
@export var quad_lean: float = 1.62
@export var quad_neck: float = -0.4
@export var quad_head: float = 0.15
## Hip height on all fours, and how far the hip sits behind the hitbox centre.
@export var quad_hip_height: float = 10.0
@export var quad_body_shift: float = 9.0
## Ground per gait cycle at run speed, and when barely moving.
@export var quad_stride: float = 46.0
@export var quad_stride_slow: float = 20.0
## Part of the cycle each limb is in the air at run speed (less when slow).
@export_range(0.2, 0.7) var quad_swing: float = 0.55
## Beat between the two pegs of a pair, as a part of the cycle. 0 is a pure bound.
@export var quad_pair_lag: float = 0.1
## Peg lift of the hind legs and the hands mid-swing, in pixels.
@export var quad_hind_lift: float = 2.5
@export var quad_fore_lift: float = 3.0
## Spine flex at run speed in radians (arched when gathered, flat when stretched), and hip bob.
@export var quad_flex: float = 0.25
@export var quad_bob: float = 1.5

@export_group("Dash")
## Spine bend, hip height and spine stretch while dashing.
@export var dash_lean: float = 1.6
@export var dash_hip_height: float = 10.0
@export var dash_stretch: float = 0.2
## Part of the dash spent pushing off planted legs before the body leaves them behind.
@export_range(0.0, 0.5) var dash_push: float = 0.15
## Seconds crouched on all fours after a dash before fully standing; the first part holds the
## crouch, the rest rises. Moving cuts it short.
@export var dash_recover_time: float = 0.9

@export_group("Charged jump")
## The set: spine bend, hip height, head angle, hip shift, and where the pegs and hands go
## (ahead of the hip, in pixels).
@export var set_lean: float = 1.25
@export var set_hip_height: float = 12.0
@export var set_head: float = 0.55
@export var set_body_shift: float = 8.0
@export var set_near_peg: float = 4.0
@export var set_far_peg: float = -10.0
@export var set_hands: float = 15.0
## Seconds the lunge pose lasts after a charged takeoff, easing into the flight pose.
@export var lunge_time: float = 0.45
## Seconds a normal jump from all fours keeps its pounce.
@export var pounce_time: float = 0.45

@export_group("Fall and landing")
## Spine bend and head angle while falling (head positive = looking down at the landing).
@export var fall_lean: float = 0.25
@export var fall_head: float = 0.35
## Fall speed (m/s) where the arms start throwing out for balance, and where they are fully
## out. Below it, stepping off a ledge is just a drop: arms lift a little, legs reach down.
@export var fall_pose_speed := Vector2(4.5, 6.5)
## Seconds to ease fully into the falling pose (and out of the jump's own pose) once falling
## that fast, so a jump that drops off a ledge turns into a fall gradually.
@export var fall_blend_time: float = 0.8
## How far the arms swing around their balancing pose while falling, in radians.
@export var balance_wobble: float = 0.3
## Knee bend from a soft landing, in pixels of hip drop per m/s of fall speed, and its cap.
@export var land_squat_per_speed: float = 1.4
@export var land_squat_max: float = 6.0
## How fast a soft landing's squat straightens back up, in pixels per second.
@export var land_squat_recovery: float = 12.0
## Hip height above the pegs while crouched after a hard landing.
@export var crouch_hip_height: float = 8.0
## Share of a hard landing's recovery spent slowly standing back up; the rest holds the
## crouch. Longer recoveries (harder impacts) rise more slowly.
@export_range(0.1, 1.0) var stand_up_share: float = 0.6

@export_group("Idle")
## Seconds between twitches, and their size range in radians.
@export var twitch_interval: Vector2 = Vector2(0.4, 1.5)
@export var twitch_size: Vector2 = Vector2(0.04, 0.1)
## Seconds standing still before an idle action, randomised between these.
@export var action_interval: Vector2 = Vector2(4.5, 9.0)
## Eye brightness while standing idle without scanning (1 = full).
@export_range(0.0, 1.0, 0.05) var standby_eye: float = 0.6
## Upper-body updates per second. Lower = choppier, more mechanical.
@export var servo_rate: float = 15.0

@export_group("Low charge")
## Each array has one value per charge tier: [normal, below warning, below critical,
## below failing]. Tiers follow the Player's warning_ratio, critical_ratio and failing_ratio.
## Upper-body servo updates per second (replaces servo_rate once charge is low).
@export var tier_servo_rate: PackedFloat32Array = [15.0, 10.0, 6.0, 3.5]
## Angle resolution of the servos, in radians: poses snap to multiples of this.
@export var tier_precision: PackedFloat32Array = [0.0, 0.035, 0.07, 0.13]
## Random error added to every joint on each servo update, in radians.
@export var tier_jitter: PackedFloat32Array = [0.0, 0.015, 0.04, 0.08]
## Twitch rate and size multipliers.
@export var tier_twitch_rate: PackedFloat32Array = [1.0, 1.5, 2.5, 4.0]
@export var tier_twitch_size: PackedFloat32Array = [1.0, 1.4, 2.0, 2.8]
## How much the head rides the body instead of holding steady: 0 = perfect camera, 1 = none.
@export var tier_head_drift: PackedFloat32Array = [0.0, 0.25, 0.55, 0.9]
## Random knocks to the head camera, in rad/s, applied a few times a second.
@export var tier_head_shake: PackedFloat32Array = [0.0, 0.4, 1.2, 2.5]
## Extra forward slump of the spine, in radians.
@export var tier_slump: PackedFloat32Array = [0.0, 0.05, 0.12, 0.25]
## How far a step may land from its target, in pixels.
@export var tier_step_error: PackedFloat32Array = [0.0, 1.0, 2.0, 3.5]
## Chance a step stalls halfway for a moment.
@export var tier_step_stall: PackedFloat32Array = [0.0, 0.0, 0.25, 0.5]

@export_group("Debug")
## Draws pegs, their homes and ground hits in the world.
@export var debug_draw: bool = false

## Eye brightness the visual should use, 0 to 1, before the charge dimming.
var eye_level: float = 1.0
## Strength of the eye's scan beam, 0 to 1.
var scan: float = 0.0

var player: Player
var skeleton: Skeleton2D
var bones: Dictionary[StringName, Bone2D]

var _display: Sprite2D
var _mode: Mode = Mode.IDLE
## Each limb bone's angle as last drawn (see _limit_down_limbs).
var _limb_angles: Dictionary = {}
var _facing: float = 1.0
var _time_in_mode: float = 0.0
var _near: Leg
var _far: Leg
var _near_hand: Leg
var _far_hand: Leg
## 0 = idle hunch, 1 = walking posture; eases between them.
var _walkness: float = 0.0
## Hip distance behind the hitbox centre.
var _shift := Spring.new()
## Spine flex: positive arches the back, negative stretches it.
var _flex := Spring.new()
var _flex_target: float = 0.0
var _lunge_left: float = 0.0
## Turn progress: 0 side view, 1 facing the camera, where the body's side flips.
var _turn_a: float = 0.0
## True while the hands push the body up off the floor, getting up.
var _pushing_up: bool = false
## Floor height in skeleton space per whole-pixel x, probed once per frame (INF: no floor).
var _floor_cache: Dictionary[int, float] = {}
## True while the hands grip the ledge in a climb.
var _climb_hands: bool = false
## The melee strike the legs last set up for (-1: none).
var _melee_seen: int = -1
## Which way the lead runs: +1 turning away from the current side, -1 coming round into it.
var _turn_sign: float = 1.0
## Yaw of each bone this frame, in radians (0 = side view), keyed by bone name.
var _yaw: Dictionary[StringName, float] = {}
## Per bone: [side (+1 near limb, -1 far limb, 0 body), lead factor name].
var _turn_bones: Dictionary[StringName, Array] = {}
## Every drawn part: [sprite, bone name, rest z, rest modulate, front width ratio,
## end-on ratio, anchor in sprite space].
var _parts: Array = []
var _pounce_left: float = 0.0
## Time left in a normal jump's takeoff push.
var _spring_left: float = 0.0
## Time left crouched after a dash.
var _dash_end_left: float = 0.0
## True from a charged takeoff until touching down.
var _charged_air: bool = false
## Eased weight of the falling pose, 0 to 1.
var _fall_w: float = 0.0
## Hip drop left from a soft landing, in pixels.
var _squat: float = 0.0
## Gait clock, 0 to 1 per cycle. The near peg swings from 0, the far one from 0.5.
var _gait_phase: float = 0.0
## Hip rise from the gait cycle, in pixels.
var _bob: float = 0.0
## Charge tier: 0 normal, 1 below warning, 2 below critical, 3 below failing.
var _tier: int = 0
var _dead: bool = false
## Body angle under the head, eased slowly: the head holds against fast changes from this.
var _body_under_head := Spring.new()
var _head_shake_wait: float = 0.0
var _head_jitter: float = 0.0

var _lean := Spring.new()
var _neck := Spring.new()
var _head := Spring.new()
var _hip_y := Spring.new()
var _hip_x := Spring.new()
var _near_arm := Spring.new()
var _near_elbow := Spring.new()
var _far_arm := Spring.new()
var _far_elbow := Spring.new()
var _eye := Spring.new(1.0)
var _scan := Spring.new()

var _twitch: Dictionary[StringName, float] = {}
var _twitch_until: Dictionary[StringName, float] = {}
var _twitch_wait: float = 1.0
var _clock: float = 0.0
var _servo_left: float = 0.0
## Upper-body rotations computed this frame, applied on servo ticks.
var _upper: Dictionary[StringName, float] = {}

var _action: StringName = &""
var _action_time: float = 0.0
var _action_wait: float = 6.0
var _last_action: StringName = &""
var _ray := PhysicsRayQueryParameters2D.new()
var _debug_node: Node2D
var _debug_points: Array = []


## One limb (a leg, or an arm used as a front leg): the peg tip in world space, plus the swing
## in progress. thigh and shin are the upper and lower bones.
class Leg:
	var thigh: Bone2D
	var shin: Bone2D
	var peg := Vector2.ZERO
	var swinging := false
	## Reaching for a first foothold after entering a mode, on its own timer.
	var fresh := false
	## Dash: still planted where the push started.
	var pinned := false
	## Landing error for the current walk step (low charge), in pixels.
	var miss := 0.0
	var stall_len := 0.0
	## Peg position in skeleton space while airborne, so it rides along with the body.
	var air_offset := Vector2.ZERO
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var t := 0.0
	var duration := 0.2
	var lift := 0.0
	## Where in the swing (0 to 1) a stall happens, and how long is left of it.
	var stall_at := 2.0
	var stall_left := 0.0
	## Bending its middle joint the non-preferred way to keep it out of the floor.
	var ik_flipped := false


## Damped spring on one value. zeta 1 settles without overshoot; lower wobbles.
class Spring:
	var value := 0.0
	var velocity := 0.0

	func _init(start := 0.0) -> void:
		value = start

	func step(target: float, freq: float, zeta: float, delta: float) -> float:
		var w := TAU * freq
		# Sub-stepped so stiff springs stay stable at large frame times.
		var n := maxi(1, ceili(w * delta / 0.4))
		var h := delta / n
		for i in n:
			velocity += (w * w * (target - value) - 2.0 * zeta * w * velocity) * h
			value += velocity * h
		return value


func setup(visual: PlayerVisual) -> void:
	player = visual.player
	skeleton = visual.skeleton
	bones = visual.bones
	_display = visual.get_node("Display")
	_near = Leg.new()
	_near.thigh = bones[&"ThighNear"]
	_near.shin = bones[&"ShinNear"]
	_far = Leg.new()
	_far.thigh = bones[&"ThighFar"]
	_far.shin = bones[&"ShinFar"]
	_near_hand = Leg.new()
	_near_hand.thigh = bones[&"UpperArmNear"]
	_near_hand.shin = bones[&"ForearmNear"]
	_far_hand = Leg.new()
	_far_hand.thigh = bones[&"UpperArmFar"]
	_far_hand.shin = bones[&"ForearmFar"]
	_shift.value = body_shift
	_ray.collision_mask = Player.SOLID_MASK
	_ray.exclude = [player.get_rid()]
	_facing = player.get_facing()
	_setup_turn_parts()
	_lean.value = idle_lean
	_body_under_head.value = idle_lean + idle_neck
	_neck.value = idle_neck
	_head.value = idle_head
	_hip_y.value = -hip_height
	_near_elbow.value = -0.35
	_far_elbow.value = -0.25
	_place_legs_under_body()
	player.landed.connect(_on_player_landed)
	player.jumped.connect(_on_player_jumped)
	player.stepped_up.connect(_on_player_stepped_up)
	_debug_node = Node2D.new()
	_debug_node.top_level = true
	_debug_node.z_index = 100
	visual.add_child(_debug_node)
	_debug_node.draw.connect(_draw_debug)


## Poses the rig for this frame. Call after the skeleton's facing is set.
func animate(delta: float) -> void:
	_clock += delta
	_lunge_left = maxf(_lunge_left - delta, 0.0)
	_pounce_left = maxf(_pounce_left - delta, 0.0)
	_spring_left = maxf(_spring_left - delta, 0.0)
	_dash_end_left = maxf(_dash_end_left - delta, 0.0)
	_update_turn(delta)

	var mode := Mode.AIR
	if player.is_climbing():
		mode = Mode.CLIMB
	elif player.is_meleeing() and player.is_on_floor():
		mode = Mode.MELEE
	elif player.is_bracing() and player.is_on_floor() and not player.is_crawling():
		mode = Mode.BRACE
	elif player.is_dashing():
		mode = Mode.DASH
	elif player.is_on_floor():
		if player.is_dead() or player.is_down():
			mode = Mode.DOWN
		elif player.is_crawling():
			mode = Mode.CRAWL
		elif player.is_stumbling():
			mode = Mode.STUMBLE
		elif player.is_recovering():
			mode = Mode.RECOVER
		elif player.is_jump_charged():
			mode = Mode.SET
		elif player.get_posture() == Player.Posture.LOW:
			mode = Mode.QUAD
		elif _dash_end_left > 0.0 and absf(player.velocity.x) <= WALK_THRESHOLD:
			mode = Mode.DASH_END
		elif absf(player.velocity.x) > WALK_THRESHOLD:
			mode = Mode.WALK
		else:
			mode = Mode.IDLE
	if mode != _mode:
		_enter(mode)
	_time_in_mode += delta
	_update_tier()

	_update_actions(delta)
	_update_twitches(delta)
	_update_legs(delta)
	_update_pose(delta)
	_solve(delta)
	_apply_turn_view()

	if debug_draw:
		_debug_node.queue_redraw()
	elif not _debug_points.is_empty():
		_debug_points.clear()
		_debug_node.queue_redraw()


func _enter(mode: Mode) -> void:
	var was := _mode
	_mode = mode
	_time_in_mode = 0.0
	if mode != Mode.IDLE:
		_end_action()
	else:
		_action_wait = randf_range(action_interval.x, action_interval.y)
	if was == Mode.AIR:
		# Landing: plant both pegs where they are, on the ground below, and dip.
		for leg in [_near, _far]:
			leg.swinging = false
			leg.peg.y = _ground_y(leg.peg.x)
	if mode != Mode.AIR:
		_charged_air = false
		_fall_w = 0.0
	if was == Mode.DASH:
		_dash_end_left = dash_recover_time
	elif mode != Mode.DASH_END:
		_dash_end_left = 0.0
	if was in [Mode.WALK, Mode.QUAD, Mode.DASH, Mode.SET] and mode != Mode.AIR:
		# Hand any peg still in the air to the idle stepper, to set down quickly.
		for leg: Leg in [_near, _far]:
			leg.fresh = false
			leg.pinned = false
			var ground := _ground_y(leg.peg.x)
			if leg.swinging or absf(leg.peg.y - ground) > 0.5:
				leg.swinging = true
				leg.from = leg.peg
				leg.to = Vector2(leg.peg.x, ground)
				leg.t = 0.0
				leg.duration = 0.1
				leg.lift = 0.0
				leg.stall_at = 2.0
	var had_hands := was in HAND_MODES
	var has_hands := mode in HAND_MODES
	if has_hands and (not had_hands or mode == Mode.DASH or (was == Mode.DASH and mode != Mode.DASH_END)):
		for hand: Leg in [_near_hand, _far_hand]:
			hand.peg = _hand_world(hand)
			hand.pinned = false
			_make_fresh(hand)
	if mode == Mode.WALK or mode == Mode.QUAD or mode == Mode.CRAWL:
		_start_gait()
	if mode in [Mode.DOWN, Mode.CRAWL, Mode.STUMBLE]:
		for leg: Leg in [_near, _far]:
			leg.swinging = false
			leg.fresh = false
			leg.pinned = false
	_pushing_up = false
	_melee_seen = -1
	if mode == Mode.CLIMB:
		# Hands shoot up to the ledge; the legs carry on from wherever they are.
		_climb_hands = true
		for hand: Leg in [_near_hand, _far_hand]:
			hand.peg = _hand_world(hand)
			hand.from = hand.peg
			hand.t = 0.0
			hand.fresh = true
			hand.pinned = false
		for leg: Leg in [_near, _far]:
			leg.swinging = false
			leg.fresh = false
			leg.air_offset = _to_rig(leg.peg)
	if mode == Mode.STUMBLE:
		# The trip: the body pitches forward and drops before it catches itself.
		_lean.velocity += 4.0
		_hip_y.velocity += 30.0
	if mode == Mode.DOWN and was != Mode.CRAWL:
		# Going down: the knees give and the body pitches over.
		_hip_y.velocity += 20.0
		_lean.velocity += 2.0
	if mode == Mode.DOWN and was == Mode.AIR:
		# Crashing down from the air: the legs kick out behind on impact, so the body doesn't
		# drop straight onto feet planted right under the hip (folding the legs flat there
		# leaves the knees nowhere stable to go, and they flip about).
		for leg: Leg in [_near, _far]:
			var rig := _to_rig(leg.peg)
			rig.x = minf(rig.x, -7.0 if leg == _near else -9.0)
			var world := _rig_to_world(rig)
			leg.peg = Vector2(world.x, _ground_y(world.x))
	if mode == Mode.AIR:
		for leg: Leg in [_near, _far]:
			leg.swinging = false
			leg.air_offset = _to_rig(leg.peg)
	if mode == Mode.DASH:
		# The push: legs stay planted and straighten as the body shoots away.
		for leg: Leg in [_near, _far]:
			leg.swinging = false
			leg.pinned = true
		for hand: Leg in [_near_hand, _far_hand]:
			hand.fresh = false
			hand.pinned = false
			hand.air_offset = _to_rig(hand.peg)
		# Dropping into the crouch the rams fire from.
		_hip_y.velocity += 25.0


## Starts a limb reaching for a first foothold from wherever it is now.
func _make_fresh(leg: Leg) -> void:
	leg.fresh = true
	leg.swinging = false
	leg.from = leg.peg
	leg.t = 0.0


func _on_player_stepped_up(height: float) -> void:
	# The body was lifted onto the step at once: keep it where it was and let it ease up as the
	# legs find the new floor.
	_hip_y.value += height


func _on_player_jumped(charged: bool) -> void:
	if charged:
		# The lunge: everything extends at once.
		_lunge_left = lunge_time
		_charged_air = true
		_hip_y.velocity -= 20.0
	elif _mode == Mode.QUAD:
		_pounce_left = pounce_time
	else:
		# The impulse: the crouched legs fire and the body springs off them.
		_spring_left = jump_spring_time
		_hip_y.velocity -= 35.0
		_lean.velocity -= 3.0


## Re-seeds the gait clock so the trailing leg (or one already lifting) steps first.
func _start_gait() -> void:
	var hip_x := _rig_to_world(Vector2.ZERO).x
	var lead := _near
	if _far.swinging and not _near.swinging:
		lead = _far
	elif not _near.swinging:
		var near_ahead := (_near.peg.x - hip_x) * _facing
		var far_ahead := (_far.peg.x - hip_x) * _facing
		lead = _near if near_ahead <= far_ahead else _far
	for leg: Leg in [_near, _far]:
		if leg.swinging and leg != lead:
			leg.peg = Vector2(leg.peg.x, _ground_y(leg.peg.x))
		leg.swinging = false
	_gait_phase = _phase_offset(lead)


## Where in the gait cycle a limb's swing starts, for the current mode.
func _phase_offset(leg: Leg) -> float:
	if _mode == Mode.CRAWL:
		return 0.5 if leg == _far_hand else 0.0
	if _mode == Mode.QUAD:
		if leg == _near:
			return 0.0
		if leg == _far:
			return quad_pair_lag
		return 0.5 + (quad_pair_lag if leg == _far_hand else 0.0)
	return 0.5 if leg == _far else 0.0


func _on_player_landed(speed: float, hard: bool) -> void:
	if hard:
		# Slammed into the crouch; RECOVER holds it until the Player lets go.
		_hip_y.velocity += 40.0 + speed * 6.0
		_lean.velocity += 2.0
		_head.velocity += 2.0
	else:
		_squat = clampf(speed * land_squat_per_speed, 0.0, land_squat_max)
		_hip_y.velocity += speed * 8.0


func _update_tier() -> void:
	var ratio := player.charge_ratio()
	_dead = ratio <= 0.0
	_tier = 0
	if ratio < player.failing_ratio:
		_tier = 3
	elif ratio < player.critical_ratio:
		_tier = 2
	elif ratio < player.warning_ratio:
		_tier = 1
	if _dead and _action != &"":
		_end_action()


## Advances the turn. The physics facing flips at once; the rig keeps its side and yaws round
## towards the camera, swaps sides while facing it (where the swap is invisible), then yaws on
## into the new side view. Reversing mid-turn simply yaws back.
func _update_turn(delta: float) -> void:
	var target := player.get_facing()
	var rate := 2.0 / maxf(turn_time, 0.01)
	var away := target != _facing
	if away:
		_turn_a = minf(_turn_a + rate * delta, 1.0)
		if _turn_a >= 1.0:
			_swap_sides(target)
			away = false
	else:
		_turn_a = maxf(_turn_a - rate * delta, 0.0)
	_turn_sign = move_toward(_turn_sign, 1.0 if away else -1.0, rate * 2.0 * delta)
	if _turn_a <= 0.0:
		_turn_sign = 1.0
	skeleton.scale.x = _facing
	skeleton.position.x = RIG_HIP_X - _facing * _shift.value

	# Ease in from the side view, fastest through the front view (and out again on the way
	# back, as the swap mirrors the curve).
	var yaw := PI / 2.0 * (1.0 - cos(_turn_a * PI / 2.0))
	var twist := _turn_sign * sin(yaw)
	var leads := {
		&"head": turn_lead_head, &"neck": (turn_lead_head + turn_lead_chest) * 0.5,
		&"chest": turn_lead_chest, &"waist3": turn_lead_chest * 0.4,
		&"waist2": (turn_lead_chest - turn_lag_hips) * 0.2, &"waist1": -turn_lag_hips * 0.5,
		&"hips": -turn_lag_hips,
	}
	for bone_name in _turn_bones:
		_yaw[bone_name] = yaw + twist * float(leads[_turn_bones[bone_name][1]])


## Halfway round, facing the camera: the rig takes the new side. The limb that was near is now
## the far one and vice versa, so their roles swap with them; seen from the front nothing
## moves, since only the depth axis mirrors.
func _swap_sides(facing: float) -> void:
	_facing = facing
	_turn_sign = -_turn_sign
	var legs := _swap_roles(_near, _far)
	_near = legs[0]
	_far = legs[1]
	var hands := _swap_roles(_near_hand, _far_hand)
	_near_hand = hands[0]
	_far_hand = hands[1]
	var spring := _near_arm
	_near_arm = _far_arm
	_far_arm = spring
	spring = _near_elbow
	_near_elbow = _far_elbow
	_far_elbow = spring
	for pair: Array in [[&"UpperArmNear", &"UpperArmFar"], [&"ForearmNear", &"ForearmFar"]]:
		var a: Bone2D = bones[pair[0]]
		var b: Bone2D = bones[pair[1]]
		var r := a.rotation
		a.rotation = b.rotation
		b.rotation = r
	_on_turn()


## Swaps two limbs' motion state while each keeps its bones. Returns [new near, new far].
func _swap_roles(near: Leg, far: Leg) -> Array:
	var thigh := near.thigh
	var shin := near.shin
	near.thigh = far.thigh
	near.shin = far.shin
	far.thigh = thigh
	far.shin = shin
	return [far, near]


func _on_turn() -> void:
	# The legs re-step on their own.
	_end_action()
	if _mode == Mode.WALK or _mode == Mode.QUAD or _mode == Mode.CRAWL:
		_start_gait()
	if _mode in HAND_MODES and _mode != Mode.DASH and _mode != Mode.DASH_END:
		# The shoulders swung to the other side of the hip: the hands find new footing.
		for hand: Leg in [_near_hand, _far_hand]:
			_make_fresh(hand)


#region Turn view

func _setup_turn_parts() -> void:
	var table := {
		&"Hip": [0, &"hips", 1.0, 1.0], &"Waist1": [0, &"waist1", 1.0, 1.0],
		&"Waist2": [0, &"waist2", 1.0, 1.0], &"Waist3": [0, &"waist3", 1.0, 1.0],
		&"Ribcage": [0, &"chest", 1.0, 0.9], &"Neck": [0, &"neck", 1.0, 0.5],
		&"Head": [0, &"head", 0.67, 1.0],
		&"ThighNear": [1, &"hips", 1.0, 0.25], &"ShinNear": [1, &"hips", 1.0, 0.25],
		&"ThighFar": [-1, &"hips", 1.0, 0.25], &"ShinFar": [-1, &"hips", 1.0, 0.25],
		&"UpperArmNear": [1, &"chest", 1.0, 0.3], &"ForearmNear": [1, &"chest", 1.0, 0.3],
		&"UpperArmFar": [-1, &"chest", 1.0, 0.3], &"ForearmFar": [-1, &"chest", 1.0, 0.3],
	}
	for bone_name: StringName in table:
		var row: Array = table[bone_name]
		_turn_bones[bone_name] = [row[0], row[1]]
		_yaw[bone_name] = 0.0
		var bone: Bone2D = bones[bone_name]
		for child in bone.get_children():
			if child is Sprite2D:
				var sprite := child as Sprite2D
				# Limbs pivot on their joint so chains stay joined; body blocks and the head
				# on their own middle.
				var anchor := sprite.get_rect().get_center() if row[0] == 0 else Vector2.ZERO
				if sprite.name == &"Glow":
					anchor = PlayerVisual.EYE_POINT + PlayerVisual.PIXEL_CENTER
				_parts.append([sprite, bone_name, sprite.z_index, sprite.modulate,
						row[2], row[3], anchor])


## Draws the rig at this frame's yaw: every part moved to where the rotation puts it, kept as
## thick as the solid part it stands for (never flat), re-stacked by depth, and the limbs
## shaded by how far they face away from the camera.
func _apply_turn_view() -> void:
	var turning := _turn_a > 0.0
	var depths: Array = []
	var to_rig := skeleton.transform.affine_inverse()
	for part: Array in _parts:
		var sprite: Sprite2D = part[0]
		var bone_name: StringName = part[1]
		if not turning:
			sprite.transform = Transform2D.IDENTITY
			sprite.z_index = part[2]
			if _turn_bones[bone_name][0] != 0:
				sprite.modulate = part[3]
			continue
		var bone := bones[bone_name]
		var bone_global := bone.get_global_transform()
		var g := to_rig * bone_global
		var yaw: float = _yaw[bone_name]
		var c := cos(yaw)
		var s := sin(yaw)
		var side: float = _turn_bones[bone_name][0]
		# The bone's length axis, foreshortened, but never shorter than the part is thick.
		var length := g.y.length()
		var y_honest := Vector2(g.y.x * c, g.y.y)
		var h := y_honest.length() / maxf(length, 0.001)
		var dir := y_honest.normalized() if h > 0.0001 else Vector2(0, 1)
		var y_axis := dir * length * (h + float(part[5]) * (1.0 - h))
		# Across it, the part's width: its side depth turning into its front width.
		var width := g.x.length()
		if sprite.name != &"Glow":
			width *= absf(c) + absf(s) * float(part[4])
		var x_axis := Vector2(dir.y, -dir.x) * width * (1.0 if c >= 0.0 else -1.0)
		var anchor: Vector2 = part[6]
		var anchor_rig := g * anchor
		var anchor_view := _project(anchor_rig, side * _spread(bone_name), yaw)
		var origin := anchor_view - x_axis * anchor.x - y_axis * anchor.y
		var view := Transform2D(x_axis, y_axis, origin)
		sprite.transform = bone_global.affine_inverse() * (skeleton.transform * view)
		if side != 0.0:
			# Near limbs face the camera, far ones away; both half lit side-on to it.
			var away := 0.5 * (1.0 - side * c)
			sprite.modulate = Color.WHITE.lerp(PlayerVisual.FAR_TINT, away)
		var depth := (anchor_rig.x - _shift.value) * s + side * _spread(bone_name) * c
		depths.append([depth + float(part[2]) * 0.001, sprite])
	if turning:
		depths.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for i in depths.size():
			(depths[i][1] as Sprite2D).z_index = i


## Sideways offset of a bone from the centre line, in pixels (positive towards the camera).
func _spread(bone_name: StringName) -> float:
	return turn_arm_spread if String(bone_name).contains("Arm") else turn_leg_spread


## Rotates a skeleton-space point about the vertical axis through the hitbox centre. offset is
## the point's sideways distance from the centre line, positive towards the camera.
func _project(p: Vector2, offset: float, yaw: float) -> Vector2:
	if yaw == 0.0:
		return p
	var pivot := _shift.value
	return Vector2(pivot + (p.x - pivot) * cos(yaw) - offset * sin(yaw), p.y)


## Where a point in a bone's local space is drawn this frame, in the rig viewport's pixels.
func view_point(bone_name: StringName, local: Vector2) -> Vector2:
	var bone := bones[bone_name]
	var point := bone.get_global_transform() * local
	var info: Array = _turn_bones.get(bone_name, [0, &"hips"])
	var yaw: float = _yaw.get(bone_name, 0.0)
	if yaw == 0.0:
		return point
	var side: float = info[0]
	var rig := skeleton.transform.affine_inverse() * point
	return skeleton.transform * _project(rig, side * _spread(bone_name), yaw)


## Where a world point carried by a bone (a hand tip, say) is drawn this frame, in world space.
func view_world(bone_name: StringName, world: Vector2) -> Vector2:
	var to_view := _display.get_global_transform()
	var bone := bones[bone_name]
	var local := bone.get_global_transform().affine_inverse() * (to_view.affine_inverse() * world)
	return to_view * view_point(bone_name, local)


## How far a bone faces away from the camera: 0 lit like a near limb, 1 shaded like a far one.
func shade(bone_name: StringName) -> float:
	var info: Array = _turn_bones.get(bone_name, [0, &"hips"])
	var side: float = info[0]
	if side == 0.0:
		return 0.0
	return 0.5 * (1.0 - side * cos(_yaw.get(bone_name, 0.0)))

#endregion


#region Legs

func _update_legs(delta: float) -> void:
	var hip_world := _rig_to_world(Vector2.ZERO)
	var vx := player.velocity.x
	match _mode:
		Mode.AIR:
			for leg: Leg in [_near, _far]:
				leg.swinging = false
			var hip := Vector2(_hip_x.value, _hip_y.value)
			# Tucked while rising; reaching down for the ground while falling. After a charged
			# takeoff they stay tucked forward under the body, ready to take a landing.
			var falling := player.velocity.y > 0.0
			var near_off := Vector2(2, air_hip_height + 2.5) if falling else Vector2(3, 13)
			var far_off := Vector2(-3, air_hip_height + 2.0) if falling else Vector2(-3, 12)
			if _charged_air:
				near_off = Vector2(5, 13.5).lerp(Vector2(2, air_hip_height + 2.5), _fall_w)
				far_off = Vector2(1, 14.5).lerp(Vector2(-3, air_hip_height + 2.0), _fall_w)
			if _pounce_left > 0.0:
				var p := _pounce_left / pounce_time
				near_off = near_off.lerp(Vector2(6, 10), p)
				far_off = far_off.lerp(Vector2(-6, 11), p)
			if _lunge_left > 0.0:
				# Legs driven out straight behind by the push.
				var l := smoothstep(0.0, 1.0, _lunge_left / lunge_time)
				near_off = near_off.lerp(Vector2(-8, 18), l)
				far_off = far_off.lerp(Vector2(-12, 15.5), l)
			var k := 1.0 - exp(-10.0 * delta)
			_near.air_offset = _near.air_offset.lerp(hip + near_off, k)
			_far.air_offset = _far.air_offset.lerp(hip + far_off, k)
			_near.peg = _rig_to_world(_near.air_offset)
			_far.peg = _rig_to_world(_far.air_offset)
		Mode.WALK:
			# The legs keep near their walking beat while starting off. Turning round, the
			# Player stops briefly: the gait waits and the lead leg steps off as it resumes.
			var speed := maxf(absf(vx), 0.7 * player.walk_speed * Player.PIXELS_PER_METER)
			var stride := _stride(speed)
			_gait_phase = fposmod(_gait_phase + speed * delta / stride, 1.0)
			for leg: Leg in [_near, _far]:
				var u := fposmod(_gait_phase - _phase_offset(leg), 1.0)
				var lift := near_lift if leg == _near else far_lift
				_gait_limb(leg, u / swing_fraction, stride, swing_fraction, hip_world.x, lift, delta)
		Mode.QUAD when player.is_skidding():
			# Skidding out of a run: hands planted out front and hind pegs braced ahead of
			# the hip, all scraping along the floor with the body.
			var k := 1.0 - exp(-14.0 * delta)
			for leg: Leg in [_near, _far, _near_hand, _far_hand]:
				leg.swinging = false
				leg.fresh = false
				var target := Vector2(5, 0) if leg == _near else Vector2(1, 0)
				if leg == _near_hand or leg == _far_hand:
					var shoulder := _to_rig(_shoulder_world(leg))
					target = Vector2(shoulder.x + (8.0 if leg == _near_hand else 5.0), 0.0)
				var rig := _to_rig(leg.peg).lerp(target, k)
				var world := _rig_to_world(rig)
				leg.peg = Vector2(world.x, _ground_y(world.x))
			_flex_target = quad_flex
		Mode.QUAD:
			var speed := absf(vx)
			var run := player.run_speed * Player.PIXELS_PER_METER
			var f := clampf(speed / run, 0.0, 1.0)
			var stride := lerpf(quad_stride_slow, quad_stride, f)
			var swing := lerpf(0.35, quad_swing, f)
			_gait_phase = fposmod(_gait_phase + speed * delta / stride, 1.0)
			for leg: Leg in [_near, _far, _near_hand, _far_hand]:
				var u := fposmod(_gait_phase - _phase_offset(leg), 1.0)
				var hand := leg == _near_hand or leg == _far_hand
				var root := _shoulder_world(leg).x if hand else hip_world.x
				var lift := quad_fore_lift if hand else quad_hind_lift
				_gait_limb(leg, u / swing, stride, swing, root, lift, delta)
			# The back arches as the hind legs land gathered (cycle 0.5) and flattens as the
			# hands stretch out.
			_flex_target = quad_flex * f * cos(TAU * (_gait_phase - 0.55))
		Mode.DASH:
			var k := 1.0 - exp(-16.0 * delta)
			var braking := player.is_dash_braking()
			var pushing := player.dash_progress() < dash_push
			var hip_rig := Vector2(_hip_x.value, _hip_y.value)
			for leg: Leg in [_near, _far]:
				if leg.pinned:
					# The push: planted until the rams are fully extended or the push ends.
					if not pushing or _to_rig(leg.peg).distance_to(hip_rig) > 19.0:
						leg.pinned = false
						leg.air_offset = _to_rig(leg.peg)
					continue
				var target := Vector2(-15, -2) if leg == _near else Vector2(-12, -3)
				if braking:
					# Swinging under the body to land behind the hands.
					target = Vector2(2, 0) if leg == _near else Vector2(-3, 0)
				leg.air_offset = leg.air_offset.lerp(target, k)
				leg.peg = _rig_to_world(leg.air_offset)
			for hand: Leg in [_near_hand, _far_hand]:
				if hand.pinned:
					continue
				var shoulder := _to_rig(_shoulder_world(hand))
				var ahead := 10.0 if hand == _near_hand else 7.0
				var target := Vector2(shoulder.x + ahead, -3.0)
				if braking:
					# Reaching down to catch the ground; once there, the hand stays put and
					# the elbow folds as the body slides over it.
					target.y = 0.0
					if hand.air_offset.y > -0.6:
						hand.pinned = true
						hand.peg = Vector2(hand.peg.x, _ground_y(hand.peg.x))
						continue
				hand.air_offset = hand.air_offset.lerp(target, k)
				hand.peg = _rig_to_world(hand.air_offset)
		Mode.DASH_END:
			if not _far.swinging:
				_update_stepper(_near, delta, 2.0, hip_world.x + _facing * 2.0, 1.5, 0.2)
			if not _near.swinging:
				_update_stepper(_far, delta, 2.0, hip_world.x - _facing * 5.0, 1.0, 0.25)
			for hand: Leg in [_near_hand, _far_hand]:
				if hand.fresh:
					_reach(hand, delta, _shoulder_world(hand).x + _facing * 4.0)
					if not hand.fresh:
						hand.pinned = true
				elif not hand.pinned:
					_make_fresh(hand)
		Mode.SET:
			var near_home := hip_world.x + _facing * set_near_peg
			var far_home := hip_world.x + _facing * set_far_peg
			if not _far.swinging:
				_update_stepper(_near, delta, 1.5, near_home, 2.0, 0.15)
			if not _near.swinging:
				_update_stepper(_far, delta, 1.5, far_home, 1.5, 0.2)
			for hand: Leg in [_near_hand, _far_hand]:
				var x := hip_world.x + _facing * (set_hands + (1.0 if hand == _near_hand else -2.0))
				if hand.fresh:
					_reach(hand, delta, x)
				elif absf(hand.peg.x - x) > 4.0:
					_make_fresh(hand)
		Mode.STUMBLE:
			# A catch step: the near peg shoots out ahead to stop the fall, the far one follows
			# back under once the body has caught itself.
			var p := player.stumble_progress()
			var near_home := hip_world.x + _facing * (9.0 if p < 0.6 else stance_near)
			var far_home := hip_world.x + _facing * stance_far
			if not _far.swinging:
				_update_stepper(_near, delta, 2.0, near_home, 2.0, 0.12)
			if not _near.swinging:
				_update_stepper(_far, delta, 2.0, far_home, 1.0, 0.18)
		Mode.DOWN:
			_update_down_limbs(delta, hip_world)
		Mode.CLIMB:
			_update_climb_limbs(delta)
		Mode.MELEE:
			_update_melee_legs(delta, hip_world)
		Mode.BRACE:
			# Feet spread wide, then dragged along with the body as it slides back.
			var b := player.burst_brace()
			var k := 1.0 - exp(-12.0 * delta)
			var homes := [stance_near + 7.0 * b, stance_far - 8.0 * b]
			for i in 2:
				var leg: Leg = [_near, _far][i]
				leg.swinging = false
				leg.fresh = false
				var x: float = hip_world.x + _facing * float(homes[i])
				leg.peg.x = lerpf(leg.peg.x, x, k)
				leg.peg.y = _ground_y(leg.peg.x)
		Mode.CRAWL:
			# Dragging itself along on the arms; the dead legs trail flat behind.
			var speed := absf(vx)
			_gait_phase = fposmod(_gait_phase + speed * delta / crawl_stride, 1.0)
			for hand: Leg in [_near_hand, _far_hand]:
				var u := fposmod(_gait_phase - _phase_offset(hand), 1.0)
				_gait_limb(
					hand, u / crawl_swing, crawl_stride, crawl_swing, _shoulder_world(hand).x,
					2.5, delta
				)
			_drag_legs(delta, 1.0)
		Mode.IDLE, Mode.RECOVER:
			var wide := _mode == Mode.RECOVER and _recover_crouch() > 0.5
			var near_home := hip_world.x + _facing * (stance_near + (2.0 if wide else 0.0))
			var far_home := hip_world.x + _facing * (stance_far - (1.0 if wide else 0.0))
			var settle := 2.5
			if not _far.swinging:
				_update_stepper(_near, delta, settle, near_home, 1.0, 0.22)
			if not _near.swinging:
				_update_stepper(_far, delta, settle, far_home, 0.5, 0.3)

	# The hip rides highest over each planted leg mid-stance (cycle 0.2 and 0.7) and dips
	# while both pegs are down.
	var bob := 0.0
	if _mode == Mode.CRAWL:
		# The chest heaves up with each pull.
		var f := clampf(absf(vx) / 6.0, 0.0, 1.0)
		bob = crawl_heave * f * 0.5 * (1.0 - cos(TAU * 2.0 * _gait_phase))
	elif _mode == Mode.WALK:
		bob = walk_bob * 0.5 * (1.0 + cos(TAU * 2.0 * (_gait_phase - 0.2)))
	elif _mode == Mode.QUAD:
		var f := clampf(absf(vx) / (player.run_speed * Player.PIXELS_PER_METER), 0.0, 1.0)
		# Highest in the gathered moment between hind push-off and the hands landing.
		bob = quad_bob * f * 0.5 * (1.0 + cos(TAU * (_gait_phase - 0.3)))
	if _mode != Mode.QUAD:
		_flex_target = 0.0
	_bob = move_toward(_bob, bob, 20.0 * delta)

	if debug_draw:
		_debug_points = [
			[_near.peg, Color.CYAN], [_far.peg, Color.MAGENTA], [hip_world, Color.YELLOW],
			[_near_hand.peg, Color.ORANGE], [_far_hand.peg, Color.RED],
		]


## Chamber and strike weights of the melee strike playing: x rises through the wind-up, then
## y snaps in for the hit, holds while the hitbox is live and eases back to the guard.
func _melee_weights() -> Vector2:
	var i := player.melee_move()
	if i < 0:
		return Vector2.ZERO
	var hit: Vector2 = Player.MELEE_MOVES[i].hit
	var p := player.melee_progress()
	var chamber := smoothstep(0.0, hit.x * 0.75, p)
	var strike := smoothstep(hit.x * 0.75, hit.x, p)
	var back := smoothstep(hit.y, 1.0, p)
	return Vector2(chamber * (1.0 - strike), strike * (1.0 - back))


## One value of the melee pose: the guard, pulled towards the chamber and the strike.
func _melee_value(key: StringName, pose: Dictionary, w: Vector2) -> float:
	var guard: float = GUARD[key]
	var chamber: float = pose.chamber.get(key, guard)
	var strike: float = pose.strike.get(key, guard)
	return guard + (chamber - guard) * w.x + (strike - guard) * w.y


## Melee footwork: a kicking leg's peg follows its chamber and strike path; the other legs keep
## a fighting stance, stepping to follow the small lunges.
func _update_melee_legs(delta: float, hip_world: Vector2) -> void:
	var i := player.melee_move()
	var pose: Dictionary = MELEE_POSES[i]
	var kicker: Leg = null
	if pose.leg == 1:
		kicker = _near
	elif pose.leg == 2:
		kicker = _far
	if i != _melee_seen:
		_melee_seen = i
		if kicker != null:
			kicker.swinging = false
	var w := _melee_weights()
	var near_rest := stance_near + 2.0
	var far_rest := stance_far - 2.0
	if kicker != null:
		var rest := Vector2(near_rest if kicker == _near else far_rest, 0.0)
		var chamber: Vector2 = pose.chamber_peg
		var kick: Vector2 = pose.kick_peg
		var rig := rest + (chamber - rest) * w.x + (kick - rest) * w.y
		kicker.peg = _rig_to_world(rig)
		kicker.peg.y = minf(kicker.peg.y, _ground_y(kicker.peg.x))
	for leg: Leg in [_near, _far]:
		if leg == kicker:
			continue
		var home := hip_world.x + _facing * (near_rest if leg == _near else far_rest)
		var other := _far if leg == _near else _near
		if kicker != null or not other.swinging:
			_update_stepper(leg, delta, 3.0, home, 1.5, 0.1)


## Lying, the legs lie out flat behind; getting up, they gather under the body, kneeling, then
## stand. Hands brace on the floor while pushing up.
func _update_down_limbs(delta: float, hip_world: Vector2) -> void:
	var r := 0.0 if player.is_dead() else player.get_up_progress()
	var gather := smoothstep(0.0, 0.45, r)
	_drag_legs(delta, 1.0 - gather)
	var push := r > 0.02 and r < 0.75
	if push and not _pushing_up:
		for hand: Leg in [_near_hand, _far_hand]:
			hand.peg = _hand_world(hand)
			_make_fresh(hand)
	_pushing_up = push
	if push:
		for hand: Leg in [_near_hand, _far_hand]:
			var x := _shoulder_world(hand).x + _facing * (3.0 if hand == _near_hand else 1.0)
			if hand.fresh:
				_reach(hand, delta, x)


## Ledge climb, slow and heavy in the low gravity. From a jump: the hands slam onto the edge
## and the body hangs a moment taking its weight, legs swinging lazily; then the arms haul it up
## with a strained servo tremble while the near peg scrabbles for purchase on the wall; the
## near knee comes up onto the lip, the body pitches over low, pressing down on the hands, the
## far leg swings up after it and it rises from the crouch. A mantle (from the ground) skips the
## hang: the hands reach up onto the edge, the near leg steps up onto it while the far one
## pushes off the ground, and it presses itself up and over.
func _update_climb_limbs(delta: float) -> void:
	var mantle := player.is_mantling()
	var progress := player.climb_progress()
	var rise := player.climb_rise()
	var over := player.climb_over()
	var edge := player.climb_edge()
	# The hands stay planted, pressing, until the body is well over them.
	if over > (0.6 if mantle else 0.7):
		_climb_hands = false
	for hand: Leg in [_near_hand, _far_hand]:
		var target := edge + Vector2(_facing * (3.0 if hand == _near_hand else 1.0), 0.0)
		if hand.fresh:
			# Accelerating into the edge, so it lands with a slam, not a soft ease.
			hand.t = minf(hand.t + delta / (0.15 if mantle else 0.09), 1.0)
			var arc := 3.0 * sin(PI * hand.t) if mantle else 0.0
			hand.peg = hand.from.lerp(target, hand.t * hand.t) + Vector2(0.0, -arc)
			if hand.t >= 1.0:
				hand.fresh = false
				hand.peg = target
				if hand == _near_hand:
					# The catch jolts through the body.
					_lean.velocity += 0.8 if mantle else 2.0
					_hip_y.velocity += 6.0 if mantle else 22.0
		else:
			hand.peg = target
	var k := 1.0 - exp(-9.0 * delta)
	var near_spot := Vector2(edge.x + _facing * 4.0, edge.y)
	var far_spot := Vector2(edge.x + _facing * 9.0, edge.y)
	if mantle:
		if progress <= 0.0:
			return  # Reaching up: the feet stay planted.
		# The near leg steps up onto the ledge first; the far one keeps pushing off the ground
		# until the body is going over, then follows.
		_climb_leg(_near, near_spot, k)
		if over > 0.35:
			_climb_leg(_far, far_spot, k * 0.8)
		return
	if progress <= 0.0:
		# Hanging: legs swinging slowly, like a pendulum in the weak gravity, settling.
		var sway := sin(_clock * 3.4) * lerpf(1.6, 0.6, player.climb_grip())
		_near.air_offset = _near.air_offset.lerp(Vector2(1.5 + sway, 3.0), k)
		_far.air_offset = _far.air_offset.lerp(Vector2(-1.0 + sway * 0.7, 4.0), k)
		_near.peg = _rig_to_world(_near.air_offset)
		_far.peg = _rig_to_world(_far.air_offset)
	elif rise < 0.6:
		# Hauling: the near peg scrabbles up the wall for purchase, slipping now and then; the far
		# leg hangs, then braces against the wall too.
		var climb := smoothstep(0.0, 0.6, rise)
		var scrabble := absf(sin(_clock * 13.0)) * 2.5 * (1.0 - climb)
		_near.air_offset = _near.air_offset.lerp(Vector2(6.0, 2.0 - 9.0 * climb + scrabble), k)
		_far.air_offset = _far.air_offset.lerp(Vector2(lerpf(0.0, 4.0, climb), 3.0), k)
		_near.peg = _against_wall(_rig_to_world(_near.air_offset), edge)
		_far.peg = _against_wall(_rig_to_world(_far.air_offset), edge)
	else:
		# Over the top: the near knee comes up onto the lip, then the far leg swings up after it.
		_climb_leg(_near, near_spot, k)
		if over > 0.45:
			_climb_leg(_far, far_spot, k * 0.8)
		else:
			_far.air_offset = _far.air_offset.lerp(Vector2(3.0, 2.0), k)
			_far.peg = _against_wall(_rig_to_world(_far.air_offset), edge)


## Moves a leg peg towards spot on top of the ledge, going up and over the corner instead of
## through it.
func _climb_leg(leg: Leg, spot: Vector2, k: float) -> void:
	leg.swinging = false
	var edge := player.climb_edge()
	var target := spot
	if leg.peg.y > edge.y - 2.5 and _facing * (leg.peg.x - edge.x) < 1.0:
		# Still below the lip: lift it clear first.
		target = Vector2(edge.x - _facing * 1.0, edge.y - 4.0)
		leg.peg = _against_wall(leg.peg.lerp(target, minf(k * 1.6, 1.0)), edge)
		return
	leg.peg = leg.peg.lerp(target, k)
	leg.peg.y = minf(leg.peg.y, edge.y)


## p kept on the open side of the climbed wall's face.
func _against_wall(p: Vector2, edge: Vector2) -> Vector2:
	if p.y > edge.y and _facing * (p.x - edge.x) > -0.5:
		p.x = edge.x - _facing * 0.5
	return p


## Moves the leg pegs along the floor towards lying flat behind the hip (lying 1) or a kneeling
## stance under it (lying 0).
func _drag_legs(delta: float, lying: float) -> void:
	var k := 1.0 - exp(-(6.0 if lying > 0.5 else 10.0) * delta)
	for leg: Leg in [_near, _far]:
		leg.swinging = false
		var flat := Vector2(-19.5, 0.0) if leg == _near else Vector2(-18.5, 0.0)
		var kneel := Vector2(3.0, 0.0) if leg == _near else Vector2(-4.0, 0.0)
		var target := kneel.lerp(flat, lying)
		var rig := _to_rig(leg.peg)
		rig = rig.lerp(target, k)
		var world := _rig_to_world(rig)
		leg.peg = Vector2(world.x, _ground_y(world.x))


## Ground covered per gait cycle at this speed.
func _stride(speed: float) -> float:
	var walk := player.walk_speed * Player.PIXELS_PER_METER
	var run := player.run_speed * Player.PIXELS_PER_METER
	if speed < walk:
		return lerpf(stride_slow, stride_walk, speed / walk)
	return lerpf(stride_walk, stride_run, clampf(inverse_lerp(walk, run, speed), 0.0, 1.0))


## One limb of a gait. s runs 0 to 1 through the swing and past 1 while planted. root_x is
## the world x of the limb's joint (hip or shoulder).
func _gait_limb(
	leg: Leg, s: float, stride: float, swing_frac: float, root_x: float, lift: float,
	delta: float
) -> void:
	if leg.fresh:
		_reach(leg, delta, root_x + _facing * 2.0)
		return
	if absf(leg.peg.x - root_x) > 30.0:
		leg.peg = Vector2(root_x, _ground_y(root_x))
	if s >= 1.0:
		if leg.swinging:
			leg.swinging = false
			leg.peg = leg.to
			_on_land(leg)
		return
	if not leg.swinging:
		leg.swinging = true
		leg.from = leg.peg
		var miss := tier_step_error[_tier]
		leg.miss = randf_range(-miss, miss)
		leg.stall_at = 2.0
		if randf() < tier_step_stall[_tier]:
			# Low-charge stall: the peg hangs mid-step, then jerks to catch up on the beat.
			leg.stall_at = randf_range(0.3, 0.55)
			leg.stall_len = randf_range(0.15, 0.3)
	# Land where the root will be at touchdown, half a stance ahead of it.
	var stance := (1.0 - swing_frac) * stride
	var ahead := (1.0 - s) * swing_frac * stride + stance * 0.5 + stride_bias
	var land_x := root_x + _facing * ahead + leg.miss
	leg.to = Vector2(land_x, _ground_y(land_x))
	var t := s
	if s > leg.stall_at:
		var a := leg.stall_at
		t = a if s < a + leg.stall_len else a + (s - a - leg.stall_len) * (1.0 - a) / (1.0 - a - leg.stall_len)
	var e := t * t * (3.0 - 2.0 * t)
	# The lift peaks early, folding the lower limb back as the joint comes through.
	leg.peg = leg.from.lerp(leg.to, e) + Vector2(0, -lift * sin(PI * pow(t, 0.75)))


## A limb reaching for a first foothold at x on its own quick timer.
func _reach(leg: Leg, delta: float, x: float) -> void:
	leg.t = minf(leg.t + delta / 0.16, 1.0)
	leg.to = Vector2(x, _ground_y(x))
	var e := leg.t * leg.t * (3.0 - 2.0 * leg.t)
	leg.peg = leg.from.lerp(leg.to, e) + Vector2(0, -2.0 * sin(PI * leg.t))
	if leg.t >= 1.0:
		leg.fresh = false
		leg.peg = leg.to


## Advances a swing, or starts one when the peg is out of place. In walk mode trigger is the
## (negative) distance behind the hip that lifts it; in idle it's how far from home it may be.
func _update_stepper(
	leg: Leg, delta: float, trigger: float, home_x: float, lift: float, duration: float
) -> void:
	if leg.swinging:
		if leg.t >= leg.stall_at and leg.stall_left > 0.0:
			# Low-charge stall: the peg hangs mid-step while the motor catches up.
			leg.stall_left -= delta
			return
		leg.t = minf(leg.t + delta / leg.duration, 1.0)
		var e := leg.t * leg.t * (3.0 - 2.0 * leg.t)
		leg.peg = leg.from.lerp(leg.to, e) + Vector2(0, -leg.lift * sin(PI * leg.t))
		if leg.t >= 1.0:
			leg.swinging = false
			leg.peg = leg.to
			_on_land(leg)
		return

	var hip_x := _rig_to_world(Vector2.ZERO).x
	var start := false
	if _mode == Mode.WALK:
		start = (leg.peg.x - hip_x) * _facing < trigger
	else:
		start = absf(leg.peg.x - home_x) > trigger
	# Anything far out of reach (a teleport, a respawn) just re-plants.
	if absf(leg.peg.x - hip_x) > 24.0 or absf(leg.peg.y - _ground_y(leg.peg.x)) > 24.0:
		leg.peg = Vector2(home_x, _ground_y(home_x))
		return
	if start:
		leg.swinging = true
		leg.t = 0.0
		leg.from = leg.peg
		var miss := tier_step_error[_tier]
		var land_x := home_x + randf_range(-miss, miss)
		leg.to = Vector2(land_x, _ground_y(land_x))
		leg.duration = duration
		leg.lift = lift
		leg.stall_at = 2.0
		if randf() < tier_step_stall[_tier]:
			leg.stall_at = randf_range(0.3, 0.6)
			leg.stall_left = randf_range(0.08, 0.2)


func _on_land(leg: Leg) -> void:
	if _mode != Mode.WALK:
		return
	# A tired lurch on every step, heavier on the near leg, with the arms swinging loose.
	var weight := 1.0 if leg == _near else 0.6
	_lean.velocity += lurch_kick * weight
	_hip_y.velocity += bob_kick * weight
	var swing := 1.2 if leg == _near else -1.2
	_near_arm.velocity -= swing
	_far_arm.velocity += swing * 0.7


func _place_legs_under_body() -> void:
	var hip := _rig_to_world(Vector2.ZERO)
	_near.peg = Vector2(hip.x + _facing * stance_near, _ground_y(hip.x + _facing * stance_near))
	_far.peg = Vector2(hip.x + _facing * stance_far, _ground_y(hip.x + _facing * stance_far))


## World y of the floor under x, or the hitbox bottom when there is none in reach.
func _ground_y(x: float) -> float:
	var feet := _rig_to_world(Vector2.ZERO)
	_ray.from = Vector2(x, feet.y - 12.0)
	_ray.to = Vector2(x, feet.y + 12.0)
	var hit := player.get_world_2d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return feet.y
	if debug_draw:
		_debug_points.append([hit.position, Color.GREEN])
	return hit.position.y

#endregion

#region Pose

func _update_pose(delta: float) -> void:
	# Idle and walk share one posture that blends slowly: setting off, the robot straightens a
	# little (it stays hunched) over walk_blend_in; stopping, it sinks back over walk_blend_out.
	var walk_target := 1.0 if _mode == Mode.WALK else 0.0
	var blend_time := walk_blend_in if walk_target > _walkness else walk_blend_out
	_walkness = move_toward(_walkness, walk_target, delta / maxf(blend_time, 0.01))
	var w := smoothstep(0.0, 1.0, _walkness)
	# Arms hang limp just as in idle, walking or not.
	var lean := lerpf(idle_lean, walk_lean, w)
	var neck := lerpf(idle_neck, walk_neck, w)
	var head := lerpf(idle_head, walk_head, w)
	var hip_h := lerpf(hip_height, walk_hip_height, w)
	var near_arm := -0.12
	var near_elbow := -0.35
	var far_arm := 0.08
	var far_elbow := -0.25
	var eye := standby_eye if _time_in_mode > 2.0 else 1.0
	var shift := body_shift
	var lean_freq := 1.6
	var arm_freq := 2.5
	var hip_freq := 4.0
	match _mode:
		Mode.WALK:
			eye = 1.0
		Mode.QUAD:
			lean = quad_lean
			neck = quad_neck
			head = quad_head
			hip_h = quad_hip_height
			shift = quad_body_shift
			lean_freq = 2.4
			hip_freq = 5.0
			eye = 1.0
			if player.is_skidding():
				# Sitting back on the haunches against the skid, head up.
				lean -= 0.3
				head -= 0.15
				hip_h -= 1.5
				lean_freq = 4.0
		Mode.DASH:
			lean = dash_lean
			neck = quad_neck
			head = quad_head
			hip_h = dash_hip_height
			shift = quad_body_shift
			_flex_target = quad_flex if player.is_dash_braking() else -dash_stretch
			if not player.is_dash_braking() and player.dash_progress() >= dash_push:
				# In flight: the body skims a little off the floor.
				hip_h += 2.0
			lean_freq = 5.0
			hip_freq = 8.0
			eye = 1.0
		Mode.DASH_END:
			# Crouched on all fours, then rising slowly back into the idle hunch.
			var c := _dash_crouch()
			lean = lerpf(lean, 1.35, c)
			neck = lerpf(neck, -0.35, c)
			head = lerpf(head, 0.25, c)
			hip_h = lerpf(hip_h, 11.0, c)
			shift = lerpf(shift, quad_body_shift, c)
			_flex_target = 0.12 * c
			lean_freq = 2.5
			eye = 1.0
		Mode.SET:
			# Sprinter's set: hips up behind, shoulders over the hands, eye on the ground ahead.
			lean = set_lean
			neck = 0.1
			head = set_head
			hip_h = set_hip_height
			shift = set_body_shift
			_flex_target = 0.08
			lean_freq = 3.0
			eye = 1.0
		Mode.AIR:
			hip_h = air_hip_height
			eye = 1.0
			if player.is_wire_anchored():
				# Hanging: the body straightens under the arm, the head tilts up to the anchor.
				lean = 0.1
				neck = 0.15
				head = -0.15
				far_arm = 0.25
				far_elbow = -0.3
			else:
				var fall := player.velocity.y / Player.PIXELS_PER_METER
				var fall_target := smoothstep(fall_pose_speed.x, fall_pose_speed.y, fall)
				_fall_w = move_toward(_fall_w, fall_target, delta / maxf(fall_blend_time, 0.01))
				var f := smoothstep(0.0, 1.0, _fall_w)
				if _charged_air:
					# Flight: leaning into the leap, arms out ahead, eye on where it'll land.
					lean = 0.8
					neck = -0.15
					head = 0.2
					near_arm = -1.3
					far_arm = -0.9
					near_elbow = -0.45
					far_elbow = -0.3
				elif player.velocity.y < 0.0:
					lean = air_lean
					near_arm = -0.6
					far_arm = 0.5
					near_elbow = -0.6
					far_elbow = -0.25
				else:
					# Dropping: arms lift a little and the head dips to watch the ground.
					lean = air_lean
					head = 0.25
					near_arm = -0.45
					far_arm = 0.3
					near_elbow = -0.5
					far_elbow = -0.35
				# A real fall throws the arms out front and back, wheeling for balance.
				var wobble := balance_wobble * f * sin(_clock * 7.0)
				lean = lerpf(lean, fall_lean, f)
				neck = lerpf(neck, idle_neck, f)
				head = lerpf(head, fall_head, f)
				near_arm = lerpf(near_arm, -1.7, f) + wobble
				far_arm = lerpf(far_arm, 1.5, f) + balance_wobble * f * sin(_clock * 7.0 + 1.9)
				near_elbow = lerpf(near_elbow, -0.35, f) - 0.2 * wobble
				far_elbow = lerpf(far_elbow, 0.3, f)
			if player.climb_slip_time() < 0.6:
				# Lost the ledge: arms still up, grabbing at it as it drops away.
				var slip := 1.0 - player.climb_slip_time() / 0.6
				near_arm = lerpf(near_arm, -2.7, slip)
				far_arm = lerpf(far_arm, -2.4, slip)
				near_elbow = lerpf(near_elbow, -0.4, slip)
				far_elbow = lerpf(far_elbow, -0.6, slip)
				head = lerpf(head, -0.4, slip)
			if _pounce_left > 0.0:
				# A jump from all fours: the body stays long and low, arms reaching ahead.
				var p := smoothstep(0.0, 1.0, _pounce_left / pounce_time)
				lean = lerpf(lean, 1.25, p)
				neck = lerpf(neck, -0.6, p)
				near_arm = lerpf(near_arm, -1.5, p)
				far_arm = lerpf(far_arm, -1.2, p)
				near_elbow = lerpf(near_elbow, -0.3, p)
				far_elbow = lerpf(far_elbow, -0.3, p)
				shift = lerpf(shift, quad_body_shift, p)
			if _lunge_left > 0.0:
				# Charged takeoff: fully stretched, arms driving forward and up, legs trailing.
				var l := smoothstep(0.0, 1.0, _lunge_left / lunge_time)
				lean = lerpf(lean, 1.0, l)
				neck = lerpf(neck, -0.35, l)
				head = lerpf(head, -0.1, l)
				near_arm = lerpf(near_arm, -2.15, l)
				far_arm = lerpf(far_arm, -1.9, l)
				near_elbow = lerpf(near_elbow, 0.0, l)
				far_elbow = lerpf(far_elbow, 0.0, l)
				shift = lerpf(shift, set_body_shift, l)
				arm_freq = 6.0
				lean_freq = 3.0
		Mode.RECOVER:
			# Crouched over the impact, bracing a hand towards the floor, then pushing back up
			# slowly over the last part of the recovery.
			eye = 1.0
			var c := _recover_crouch()
			lean = lerpf(lean, 1.15, c)
			neck = lerpf(neck, 0.15, c)
			head = lerpf(head, 0.45, c)
			hip_h = lerpf(hip_h, crouch_hip_height, c)
			near_arm = lerpf(near_arm, -0.3, c)
			near_elbow = lerpf(near_elbow, -0.9, c)
			far_arm = lerpf(far_arm, 0.35, c)
			far_elbow = lerpf(far_elbow, -0.6, c)
	match _mode:
		Mode.STUMBLE:
			# Pitching forward and catching itself: arms flung out ahead, head snapping up.
			eye = 1.0
			var p := player.stumble_progress()
			var e := smoothstep(0.0, 0.15, p) * (1.0 - smoothstep(0.45, 1.0, p))
			lean += 0.6 * e
			head -= 0.35 * e
			hip_h -= 3.0 * e
			near_arm = lerpf(near_arm, -1.15, e)
			far_arm = lerpf(far_arm, -0.8, e)
			near_elbow = lerpf(near_elbow, -0.2, e)
			far_elbow = lerpf(far_elbow, -0.5, e)
			lean_freq = 3.0
			arm_freq = 7.0
		Mode.DOWN:
			eye = 1.0
			var dead := player.is_dead()
			var r := 0.0 if dead else player.get_up_progress()
			# Lying face down; on all fours pushing up; then back to the standing hunch.
			var lying := 1.0 - smoothstep(0.0, 0.45, r)
			var kneel := 1.0 - smoothstep(0.45, 1.0, r)
			var k_lean := lerpf(lean, 1.3, kneel)
			var k_hip := lerpf(hip_h, 8.0, kneel)
			var k_head := lerpf(head, 0.15, kneel)
			var k_shift := lerpf(shift, quad_body_shift, kneel)
			lean = lerpf(k_lean, 1.6 if dead else 1.64, lying)
			hip_h = lerpf(k_hip, prone_hip_height, lying)
			neck = lerpf(neck, 0.0, maxf(lying, kneel))
			head = lerpf(k_head, 0.9 if dead else 0.45, lying)
			shift = lerpf(k_shift, 2.0, lying)
			if dead:
				# Limp: arms flopped back along the body.
				near_arm = 1.25
				far_arm = 1.05
				near_elbow = 0.15
				far_elbow = 0.25
				lean_freq = 1.4
			else:
				near_arm = lerpf(near_arm, -1.25, lying)
				far_arm = lerpf(far_arm, -1.0, lying)
				near_elbow = lerpf(near_elbow, -0.9, lying)
				far_elbow = lerpf(far_elbow, -0.7, lying)
				lean_freq = 2.0 if r <= 0.0 else 2.6
			hip_freq = 5.0
		Mode.CLIMB:
			# Slow, heavy and deliberate: the springs are soft so it all floats a little in the
			# weak gravity. Hanging close to the wall, eye on the edge; hauling with a strained
			# servo tremble; then pitching over low as the arms press it up, knee on the lip, and
			# finally rising out of the crouch on top.
			eye = 1.0
			var rise := player.climb_rise()
			var over := player.climb_over()
			var press := smoothstep(0.5, 1.0, rise)
			var stand := smoothstep(0.65, 1.0, over)
			var hauling := player.climb_progress() > 0.0 and rise < 0.62
			if player.is_mantling():
				# Reaching up and leaning in, then pressing up over the hands.
				var reach := player.climb_grip()
				lean = lerpf(idle_lean, 0.45, reach) + 0.55 * press
				hip_h = hip_height - 2.0 * reach - 4.0 * press
				hauling = player.climb_progress() > 0.0 and rise < 0.45
			else:
				lean = lerpf(0.3 + 0.3 * rise, 1.25, press)
				hip_h = lerpf(hip_height, 9.0, press)
			neck = lerpf(0.15, 0.25, press)
			head = lerpf(0.2, 0.3, press)
			shift = lerpf(body_shift, quad_body_shift, press)
			# Out of the crouch, back towards standing, as it gets its legs under it.
			lean = lerpf(lean, idle_lean + 0.2, stand)
			hip_h = lerpf(hip_h, hip_height - 2.0, stand)
			shift = lerpf(shift, body_shift, stand)
			if hauling:
				var strain := 0.05 if _tier > 0 else 0.035
				lean += strain * sin(_clock * 45.0)
				head += 0.03 * sin(_clock * 37.0)
			lean_freq = 2.4
			hip_freq = 4.5
			arm_freq = 4.0
		Mode.MELEE:
			eye = 1.0
			var pose: Dictionary = MELEE_POSES[maxi(player.melee_move(), 0)]
			var mw := _melee_weights()
			lean = _melee_value(&"lean", pose, mw)
			neck = _melee_value(&"neck", pose, mw)
			head = _melee_value(&"head", pose, mw)
			hip_h = _melee_value(&"hip_h", pose, mw)
			shift = _melee_value(&"shift", pose, mw)
			near_arm = _melee_value(&"near_arm", pose, mw)
			near_elbow = _melee_value(&"near_elbow", pose, mw)
			far_arm = _melee_value(&"far_arm", pose, mw)
			far_elbow = _melee_value(&"far_elbow", pose, mw)
			lean_freq = 7.0
			hip_freq = 9.0
			arm_freq = 14.0
		Mode.BRACE:
			# Sinking into a wide stance, near arm thrust out ahead, far arm braced back; it
			# trembles as the arm heats and is thrown back when the burst goes.
			eye = 1.0
			var b := player.burst_brace()
			var r := player.burst_recoil()
			var heat := 0.0 if player.is_burst_fired() else player.burst_heat()
			var tremble := 0.035 * heat * sin(_clock * 55.0)
			lean = lerpf(lean, 0.85, b) - 0.75 * r + tremble
			neck = lerpf(neck, -0.05, b)
			head = lerpf(head, 0.0, b) - 0.2 * r
			hip_h = lerpf(hip_h, 10.5, b) - 1.5 * r
			shift = lerpf(shift, 8.0, b)
			near_arm = lerpf(near_arm, -PI / 2.0, smoothstep(0.0, 0.6, b)) - 0.6 * r + tremble
			near_elbow = lerpf(near_elbow, 0.0, b)
			far_arm = lerpf(far_arm, 0.95, b) + 0.5 * r
			far_elbow = lerpf(far_elbow, -0.8, b)
			lean_freq = 5.0
			hip_freq = 7.0
			arm_freq = 9.0
		Mode.CRAWL:
			eye = 1.0
			# Aiming lying down, it props its chest up a little on the far arm.
			lean = 1.42 - (0.12 if player.is_arm_forward() else 0.0)
			neck = -0.35
			head = -0.05
			hip_h = prone_hip_height
			shift = 3.0
			lean_freq = 2.0
			hip_freq = 6.0
	if (_mode == Mode.IDLE or _mode == Mode.WALK) and player.is_jump_charging():
		# Wind-up: a quick crouch onto the legs with the arms cocked back, then sinking
		# further as a held jump charges.
		var wind := smoothstep(0.0, player.jump_windup_time, player.jump_hold_time())
		var c := smoothstep(0.4, 1.0, player.jump_charge_fraction())
		hip_h -= windup_crouch * wind + 2.0 * c
		lean += 0.25 * wind + 0.15 * c
		head += 0.1 * wind + 0.1 * c
		near_arm = lerpf(near_arm, 0.7, wind)
		far_arm = lerpf(far_arm, 0.55, wind)
		near_elbow = lerpf(near_elbow, -0.5, wind)
		far_elbow = lerpf(far_elbow, -0.4, wind)
		hip_freq = 9.0
		lean_freq = 5.0
		arm_freq = 7.0
	if _spring_left > 0.0:
		# Takeoff: legs driving straight, arms swinging forward and up.
		var l := smoothstep(0.0, 1.0, _spring_left / jump_spring_time)
		near_arm = lerpf(near_arm, -1.9, l)
		far_arm = lerpf(far_arm, -1.6, l)
		near_elbow = lerpf(near_elbow, -0.2, l)
		far_elbow = lerpf(far_elbow, -0.2, l)
		lean = lerpf(lean, 0.3, l)
		arm_freq = 8.0

	var targets := {
		&"neck": neck, &"head": head, &"near_arm": near_arm, &"near_elbow": near_elbow,
		&"far_arm": far_arm, &"far_elbow": far_elbow, &"eye": 0.0, &"scan": 0.0,
	}
	_apply_action_keys(targets)
	# Looking up or down (look up / look down held): the head tips that way, the neck helps.
	var look_y := player.look_input().y
	if look_y != 0.0 and _mode not in [Mode.DOWN, Mode.CLIMB]:
		targets[&"head"] = look_down_head if look_y > 0.0 else look_up_head
		targets[&"neck"] = float(targets[&"neck"]) + look_y * (0.3 if look_y > 0.0 else 0.4)
		if look_y < 0.0 and _mode != Mode.CRAWL:
			# Looking up it straightens its back a little too.
			lean -= 0.25
	var action_freq := 5.0 if _action != &"" else arm_freq
	lean += tier_slump[_tier]
	if _dead:
		# Out of charge: the frame sags and the arms drop.
		lean += 0.35
		targets[&"head"] = 0.6
		targets[&"neck"] = 0.6
		targets[&"near_arm"] = 0.0
		targets[&"far_arm"] = 0.05
		targets[&"near_elbow"] = 0.0
		targets[&"far_elbow"] = 0.0

	_head_shake_wait -= delta
	if _head_shake_wait <= 0.0:
		_head_shake_wait = randf_range(0.15, 0.5)
		var shake := tier_head_shake[_tier]
		_head.velocity += randf_range(-shake, shake)

	_lean.step(lean, lean_freq, 0.55, delta)
	_shift.step(shift, 3.0, 0.8, delta)
	_flex.step(_flex_target, 4.0, 0.6, delta)
	_neck.step(targets[&"neck"], action_freq, 0.6, delta)
	_head.step(targets[&"head"], action_freq, 0.55, delta)
	_near_arm.step(targets[&"near_arm"], action_freq, 0.45, delta)
	_near_elbow.step(targets[&"near_elbow"], action_freq, 0.5, delta)
	_far_arm.step(targets[&"far_arm"], action_freq, 0.45, delta)
	_far_elbow.step(targets[&"far_elbow"], action_freq, 0.5, delta)
	_hip_x.step(0.0, 2.0, 0.7, delta)
	# The action's eye key adds to (or, at -1, cancels) the standby dimming.
	_eye.step(clampf(eye + targets[&"eye"], standby_eye, 1.0), 3.0, 1.0, delta)
	_scan.step(targets[&"scan"], 2.0, 1.0, delta)
	eye_level = clampf(_eye.value, 0.0, 1.0)
	scan = clampf(_scan.value, 0.0, 1.0)

	var ground := Vector2(_to_rig(_near.peg).y, _to_rig(_far.peg).y)
	var on_pegs := _mode not in [Mode.AIR, Mode.CLIMB, Mode.MELEE, Mode.BRACE]
	var ground_y := (ground.x + ground.y) * 0.5 if on_pegs else 0.0
	_squat = move_toward(_squat, 0.0, land_squat_recovery * delta)
	_hip_y.step(ground_y - hip_h + _squat, hip_freq, 0.6, delta)


func _update_actions(delta: float) -> void:
	if _mode != Mode.IDLE:
		return
	if _action != &"":
		_action_time += delta
		if _action_time >= ACTIONS[_action][0]:
			_end_action()
		return
	_action_wait -= delta
	if _action_wait <= 0.0:
		# Alternate mostly, with the odd repeat so it doesn't feel scripted.
		var options: Array = ACTIONS.keys()
		var pick: StringName = options.pick_random()
		if pick == _last_action and randf() < 0.7:
			pick = options[1 - options.find(pick)]
		_action = pick
		_last_action = pick
		_action_time = 0.0


func _end_action() -> void:
	_action = &""
	_action_wait = randf_range(action_interval.x, action_interval.y)


## Overwrites targets with every key of the running action reached so far.
func _apply_action_keys(targets: Dictionary) -> void:
	if _action == &"":
		return
	for key: Array in ACTIONS[_action][1]:
		if key[0] > _action_time:
			break
		targets.merge(key[1], true)


func _update_twitches(delta: float) -> void:
	for bone_name in _twitch_until.keys():
		if _clock >= _twitch_until[bone_name]:
			_twitch.erase(bone_name)
			_twitch_until.erase(bone_name)
	_twitch_wait -= delta
	if _twitch_wait > 0.0:
		return
	# Walking twitches less: the motors are busy.
	var slow := 2.5 if _mode == Mode.WALK else 1.0
	slow /= tier_twitch_rate[_tier]
	_twitch_wait = randf_range(twitch_interval.x, twitch_interval.y) * slow
	if _mode == Mode.AIR or _mode == Mode.DASH or _dead or player.is_dead():
		return
	var bone_name: StringName = TWITCH_BONES.pick_random()
	# The head is a stabilised camera: it only twitches once charge is low.
	if bone_name == &"Head" and _tier == 0:
		bone_name = &"Neck"
	var size := randf_range(twitch_size.x, twitch_size.y) * tier_twitch_size[_tier]
	size *= 1.0 if randf() < 0.5 else -1.0
	_twitch[bone_name] = size
	_twitch_until[bone_name] = _clock + randf_range(0.12, 0.35)

#endregion

#region Solve

func _solve(delta: float) -> void:
	_floor_cache.clear()
	var hip: Bone2D = bones[&"Hip"]
	var spine := _lean.value
	hip.position = Vector2(_hip_x.value, _hip_y.value - _bob).round()
	var flex := _flex.value
	hip.rotation = spine * 0.15 - flex * 0.5
	_solve_leg(_near, hip)
	_solve_leg(_far, hip)

	# Upper body: the rest of the bend goes through the waist and ribcage. Flex moves bend
	# from the ends into the waist (arching) or out of it (stretching), same total.
	var rib_global := hip.rotation
	for bone_name: StringName in [&"Waist1", &"Waist2", &"Waist3", &"Ribcage"]:
		if bone_name == &"Ribcage":
			_upper[bone_name] = spine * 0.25 - flex * 0.25
		else:
			_upper[bone_name] = spine * 0.2 + flex * 0.25
		rib_global += _upper[bone_name]
	_upper[&"Neck"] = _neck.value
	_upper[&"UpperArmNear"] = _near_arm.value - rib_global
	_upper[&"ForearmNear"] = _near_elbow.value
	_upper[&"UpperArmFar"] = _far_arm.value - rib_global
	_upper[&"ForearmFar"] = _far_elbow.value

	var rate := servo_rate if _tier == 0 else tier_servo_rate[_tier]
	var tick := false
	_servo_left -= delta
	if _servo_left <= 0.0:
		tick = true
		_servo_left += 1.0 / rate
		if _servo_left < 0.0:
			_servo_left = 1.0 / rate
		var step := tier_precision[_tier]
		var jitter := tier_jitter[_tier]
		for bone_name in _upper:
			var angle: float = _upper[bone_name] + _twitch.get(bone_name, 0.0)
			angle += randf_range(-jitter, jitter)
			bones[bone_name].rotation = snappedf(angle, step) if step > 0.0 else angle
	_solve_head(delta, tick)
	# Planted hands and the wire arm are solved every frame against the body as it stands,
	# so they hold still while the servos step the spine.
	if _hands_down():
		_solve_hand(_near_hand, _near_arm, _near_elbow)
		_solve_hand(_far_hand, _far_arm, _far_elbow)
	_keep_above_floor()
	if player.is_wire_shown():
		_aim_wire_arm()
	elif player.is_shooting():
		_aim_shot_arm()
	elif player.is_bracing() and _mode == Mode.CRAWL:
		_aim_crawl_burst_arm()
	_limit_down_limbs(delta)
	player.set_arm_tip(view_world(&"ForearmNear", _hand_world(_near_hand)))


## Lying down, limb joints turn at most DOWN_LIMB_RATE, so nothing pops from one pose to another.
## Remembers every frame's angles, so lying down starts from the pose it was in.
func _limit_down_limbs(delta: float) -> void:
	var limit := _mode == Mode.DOWN and not _pushing_up
	var step := DOWN_LIMB_RATE * delta
	for limb: Leg in [_near, _far, _near_hand, _far_hand]:
		for bone: Bone2D in [limb.thigh, limb.shin]:
			if limit and _limb_angles.has(bone):
				var last: float = _limb_angles[bone]
				var turn := clampf(angle_difference(last, bone.rotation), -step, step)
				bone.rotation = wrapf(last + turn, -PI, PI)
			_limb_angles[bone] = bone.rotation


## No clipping: whatever the pose asks for, nothing is drawn inside the floor. A body part that
## would sink into it lifts the whole body (the limbs re-solve to their pegs), and any free arm
## that would reach into it folds against it instead.
func _keep_above_floor() -> void:
	var hip: Bone2D = bones[&"Hip"]
	var sink := 0.0
	var to_rig := skeleton.transform.affine_inverse()
	for bone_name in BODY_BONES:
		var bone := bones[bone_name]
		var sprite := bone.get_node_or_null("Sprite") as Sprite2D
		if sprite == null:
			continue
		var rect := sprite.get_rect().grow(-0.5)
		var t := to_rig * bone.get_global_transform()
		for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x, 0.0),
				rect.end, rect.position + Vector2(0.0, rect.size.y)]:
			var p := t * corner
			sink = maxf(sink, p.y - _floor_rig(p.x))
	if sink > 0.0:
		hip.position.y -= ceilf(sink)
		_solve_leg(_near, hip)
		_solve_leg(_far, hip)
		if _hands_down():
			_solve_hand(_near_hand, _near_arm, _near_elbow)
			_solve_hand(_far_hand, _far_arm, _far_elbow)
	if not _hands_down():
		_fold_free_arm(_far_hand)
		if not player.is_wire_shown():
			_fold_free_arm(_near_hand)


## A swinging arm whose elbow or hand would go into the floor bends against it instead.
func _fold_free_arm(hand: Leg) -> void:
	var base := _bone_rig(hand.thigh).origin
	var elbow := _bone_rig(hand.shin).origin
	var tip := _bone_rig(hand.shin) * Vector2(0, FOREARM_LENGTH)
	var tip_floor := _floor_rig(tip.x) - 0.5
	if tip.y <= tip_floor and elbow.y <= _floor_rig(elbow.x) - JOINT_CLEARANCE:
		return
	var target := Vector2(tip.x, minf(tip.y, tip_floor))
	# Keep the elbow on the side it was already bent to, unless that side is underground.
	var side := signf((elbow - base).cross(tip - base))
	var bend := 1.0 if side >= 0.0 else -1.0
	var angles := _ik_above_floor(base, target, UPPER_ARM_LENGTH, FOREARM_LENGTH, bend, hand)
	hand.thigh.rotation = wrapf(angles.x - PI / 2.0 - _rib_global(), -PI, PI)
	hand.shin.rotation = wrapf(angles.y - angles.x, -PI, PI)


## Two-bone IK that bends the middle joint the preferred way unless that would put it in the
## floor, in which case it bends the other way (whichever stays higher). Given the limb, it
## remembers which way it bent and holds it unless the other way is clearly better.
func _ik_above_floor(
	base: Vector2, target: Vector2, l1: float, l2: float, bend: float, limb: Leg = null
) -> Vector2:
	var angles := two_bone_ik(base, target, l1, l2, bend)
	var joint := base + Vector2.from_angle(angles.x) * l1
	# A limb already bent the other way only comes back once the preferred bend is clearly clear.
	var flipped := limb != null and limb.ik_flipped
	var clearance := JOINT_CLEARANCE + (IK_HYSTERESIS if flipped else 0.0)
	if joint.y <= _floor_rig(joint.x) - clearance:
		if limb != null:
			limb.ik_flipped = false
		return angles
	var other := two_bone_ik(base, target, l1, l2, -bend)
	var other_joint := base + Vector2.from_angle(other.x) * l1
	if limb == null:
		return other if other_joint.y < joint.y else angles
	# Switch only when the other bend is better by a margin, either way.
	if flipped:
		limb.ik_flipped = other_joint.y < joint.y + IK_HYSTERESIS
	else:
		limb.ik_flipped = other_joint.y < joint.y - IK_HYSTERESIS
	return other if limb.ik_flipped else angles


## Floor height under a skeleton-space x, in skeleton space; INF where there is no floor
## close below the body (over a drop, or mid-air).
func _floor_rig(x: float) -> float:
	var key := roundi(x)
	if _floor_cache.has(key):
		return _floor_cache[key]
	var world := _rig_to_world(Vector2(key, 0.0))
	_ray.from = Vector2(world.x, world.y - 14.0)
	_ray.to = Vector2(world.x, world.y + 24.0)
	var hit := player.get_world_2d().direct_space_state.intersect_ray(_ray)
	var y := INF if hit.is_empty() else _to_rig(hit.position).y
	_floor_cache[key] = y
	return y


## True while the hands are posed as feet.
func _hands_down() -> bool:
	if _mode == Mode.CLIMB:
		return _climb_hands
	if _mode == Mode.DOWN:
		return _pushing_up
	if _mode == Mode.DASH_END:
		return _dash_crouch() > 0.5
	return _mode in HAND_MODES


## How crouched the robot still is after a dash: 1 holding the crouch, easing to 0 standing.
func _dash_crouch() -> float:
	var t := 1.0 - _dash_end_left / maxf(dash_recover_time, 0.01)
	return 1.0 - smoothstep(0.35, 1.0, t)


## How crouched the robot still is after a hard landing: 1 holding the crouch, easing to 0 as
## it stands over the last stand_up_share of the recovery.
func _recover_crouch() -> float:
	var stand := player.recovery_total() * stand_up_share
	return smoothstep(0.0, maxf(stand, 0.01), player.recovery_left())


## Arm IK to a hand peg, elbow bent back like a front leg. The arm springs follow the result,
## so letting go later continues from here.
func _solve_hand(hand: Leg, arm: Spring, elbow: Spring) -> void:
	var base := _bone_rig(hand.thigh).origin
	var target := _to_rig(hand.peg)
	var reach := UPPER_ARM_LENGTH + FOREARM_LENGTH
	var to_target := target - base
	var d := to_target.length()
	var soft := reach * knee_soft_start
	if d > soft:
		var k := reach - soft
		target = base + to_target / d * (soft + k * (1.0 - exp(-(d - soft) / k)))
	target.y = minf(target.y, _floor_rig(target.x))
	var angles := _ik_above_floor(base, target, UPPER_ARM_LENGTH, FOREARM_LENGTH, -1.0, hand)
	var arm_global := angles.x - PI / 2.0
	hand.thigh.rotation = wrapf(arm_global - _rib_global(), -PI, PI)
	hand.shin.rotation = wrapf(angles.y - angles.x, -PI, PI)
	arm.value = arm_global
	arm.velocity = 0.0
	elbow.value = hand.shin.rotation
	elbow.velocity = 0.0


## Points the near arm straight at the wire's end and starts the drawn wire at its hand.
func _aim_wire_arm() -> void:
	var upper: Bone2D = bones[&"UpperArmNear"]
	var base := _bone_rig(upper).origin
	var aim := (_to_rig(player.wire_lead()) - base).angle()
	upper.rotation = wrapf(aim - PI / 2.0 - _rib_global(), -PI, PI)
	bones[&"ForearmNear"].rotation = 0.0
	_near_arm.value = aim - PI / 2.0
	_near_arm.velocity = 0.0
	_near_elbow.value = 0.0
	_near_elbow.velocity = 0.0
	player.set_wire_origin(view_world(&"ForearmNear", _hand_world(_near_hand)))


## Throws the near arm out for a plasma shot, at the shot's aim (straight ahead, up, or onto the
## enemy it locked on to), kicking up as the bolt leaves.
func _aim_shot_arm() -> void:
	var w := player.shot_raise()
	# Rig space: x ahead, y down; the arm hangs at 0 and points ahead at -PI/2.
	var aim := -PI / 2.0 - player.shot_elevation()
	var arm := lerp_angle(_near_arm.value, aim - 0.18 * player.shot_recoil(), w)
	var elbow := lerpf(_near_elbow.value, 0.0, w)
	bones[&"UpperArmNear"].rotation = wrapf(arm - _rib_global(), -PI, PI)
	bones[&"ForearmNear"].rotation = elbow
	_near_arm.value = arm
	_near_arm.velocity = 0.0
	_near_elbow.value = elbow
	_near_elbow.velocity = 0.0


## Crawling with dead legs, the burst is fired lying down: propped on the far arm, the near arm
## thrust out ahead, trembling as it heats and thrown up by the kick.
func _aim_crawl_burst_arm() -> void:
	var w := smoothstep(0.0, 0.6, player.burst_brace())
	var heat := 0.0 if player.is_burst_fired() else player.burst_heat()
	var tremble := 0.035 * heat * sin(_clock * 55.0)
	var arm := lerp_angle(_near_arm.value, -PI / 2.0 - 0.6 * player.burst_recoil() + tremble, w)
	var elbow := lerpf(_near_elbow.value, 0.0, w)
	bones[&"UpperArmNear"].rotation = wrapf(arm - _rib_global(), -PI, PI)
	bones[&"ForearmNear"].rotation = elbow
	_near_arm.value = arm
	_near_arm.velocity = 0.0
	_near_elbow.value = elbow
	_near_elbow.velocity = 0.0


## Global angle of the ribcage as currently posed.
func _rib_global() -> float:
	var angle := 0.0
	for bone_name: StringName in [&"Hip", &"Waist1", &"Waist2", &"Waist3", &"Ribcage"]:
		angle += bones[bone_name].rotation
	return angle


## A bone's transform in skeleton space.
func _bone_rig(bone: Bone2D) -> Transform2D:
	return bone.get_relative_transform_to_parent(skeleton)


func _shoulder_world(hand: Leg) -> Vector2:
	return _rig_to_world(_bone_rig(hand.thigh).origin)


## World position of a hand's tip as currently posed.
func _hand_world(hand: Leg) -> Vector2:
	return _rig_to_world(_bone_rig(hand.shin) * Vector2(0, FOREARM_LENGTH))


## The head is a camera on a gimbal: every frame it cancels whatever the body under it does,
## holding the pose's head angle. Low charge blends in drift (it rides the body's motion) and
## moves it to the servo ticks.
func _solve_head(delta: float, tick: bool) -> void:
	var under := 0.0
	for bone_name: StringName in [&"Hip", &"Waist1", &"Waist2", &"Waist3", &"Ribcage", &"Neck"]:
		under += bones[bone_name].rotation
	_body_under_head.step(under, 0.6, 1.0, delta)
	if _tier >= 2 and not tick:
		return
	var drift := tier_head_drift[_tier]
	var head_global := _head.value + drift * (under - _body_under_head.value)
	var angle: float = head_global - under + _twitch.get(&"Head", 0.0)
	if tick:
		_head_jitter = randf_range(-tier_jitter[_tier], tier_jitter[_tier])
	angle += _head_jitter
	var step := tier_precision[_tier]
	if step > 0.0:
		angle = snappedf(angle, step)
	bones[&"Head"].rotation = angle


## 2-bone IK from the thigh joint to the peg, knee bent forward.
func _solve_leg(leg: Leg, hip: Bone2D) -> void:
	var base := hip.position + leg.thigh.position.rotated(hip.rotation)
	var target := _to_rig(leg.peg)
	var l1 := leg.shin.position.length()
	# Soft reach: past knee_soft_start of full length the reach eases in, so the knee
	# never snaps straight and the peg just trails a hair short instead.
	var reach := l1 + SHIN_LENGTH
	var soft := reach * knee_soft_start
	var to_target := target - base
	var d := to_target.length()
	if d > soft:
		var k := reach - soft
		target = base + to_target / d * (soft + k * (1.0 - exp(-(d - soft) / k)))
	# A peg resting on the floor sits on it; a leg lying along it keeps its thickness above it.
	var flat := absf((target - base).normalized().x)
	target.y = minf(target.y, _floor_rig(target.x) - 1.5 * flat * flat)
	var angles := _ik_above_floor(base, target, l1, SHIN_LENGTH, 1.0, leg)
	# Bones point down (+y) at rotation 0, so subtract a quarter turn from the limb angles.
	leg.thigh.rotation = wrapf(angles.x - PI / 2.0 - hip.rotation, -PI, PI)
	leg.shin.rotation = wrapf(angles.y - angles.x, -PI, PI)


## Angles (radians, from +x) of the upper and lower segment of a two-bone limb reaching from
## base towards target. bend = 1 puts the middle joint on the side the angle decreases (forward
## for a limb hanging down), -1 the other side. Out of reach, the limb points straight at it.
static func two_bone_ik(
	base: Vector2, target: Vector2, l1: float, l2: float, bend: float
) -> Vector2:
	var to_target := target - base
	var d := clampf(to_target.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var aim := to_target.angle()
	var cos_inner := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var a1 := aim - bend * acos(cos_inner)
	var joint := base + Vector2.from_angle(a1) * l1
	var end := base + Vector2.from_angle(aim) * d
	return Vector2(a1, (end - joint).angle())

#endregion

#region Spaces

## Skeleton space (x forward, y down, origin on the ground under the hip) to world.
func _rig_to_world(p: Vector2) -> Vector2:
	return _display.get_global_transform() * (skeleton.transform * p)


func _to_rig(world: Vector2) -> Vector2:
	var viewport_point := _display.get_global_transform().affine_inverse() * world
	return skeleton.transform.affine_inverse() * viewport_point


func _draw_debug() -> void:
	for point in _debug_points:
		_debug_node.draw_rect(Rect2(point[0] - Vector2(0.5, 0.5), Vector2.ONE), point[1])

#endregion
