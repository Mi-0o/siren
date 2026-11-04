class_name Player
extends CharacterBody2D
## Test player: walks with the arrow keys, runs with left Shift, jumps with Z, dashes with X and
## fires a wire with C.
##
## World scale is fixed at PIXELS_PER_METER. Tuning values are in metres and seconds, converted
## to pixels once in _ready(). The body is drawn by the PlayerVisual child (a bone rig); this
## script only does physics.
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
## Reversing direction on the ground first brakes to a full stop; only then does the facing
## flip, and the robot holds still for turn_pause before setting off the other way. Stopping or
## reversing from a run brakes more gently (run_stop_time), so the robot skids a little.
##
## C fires a wire (straight up when still, diagonally forward when moving) or releases it.
## While attached, Z reels in and X pays out instead of jumping and dashing.
##
## Everything runs on charge, which only charging stations restore (see recharge()). Walking and
## running drain it while an arrow key is held on the ground, hanging from the wire drains it
## (reeling in drains more), and jumps, dashes, wire shots and ledge climbs cost a lump sum. An action needs its full cost to
## start: with too little charge a jump doesn't fire, a held jump never becomes charged, and dash
## and wire do nothing.
##
## Low charge cuts abilities in tiers, set as fractions of max_charge so they follow it when it
## changes. Below critical_ratio there's no dash or charged jump. Below failing_ratio there's
## also no jump, wire shot or running, and walking slows to failing_walk_factor. At zero every
## input is ignored and the robot lets go of the wire.
##
## Core, legs and systems each have a damage state: healthy, mild, heavy or fault (see the
## Damage group). Mild and heavy damage weaken and destabilise that part; a legs fault leaves
## the robot crawling on its arms, a core fault kills it and a systems fault disables the wire.
## Stumbles (a quick stagger, input muted) and knockdowns (thrown to the floor, then getting up)
## come from heavy leg or core damage.
##
## Walking or running into a ledge no higher than step_max_height just steps up onto it (the
## animator eases the body up, the legs find the new floor). A ledge up to climb_auto_height is
## mantled without a jump: hands on top, a leg up, pushed up onto it. Anything higher needs a
## jump: jumping into a wall whose top is no more than climb_max_height above the feet grabs the
## ledge and climbs it (a muscle-up): the jump's momentum is dropped and the body is hoisted up
## and over onto the ledge, with input ignored meanwhile. With heavy core damage the climb may
## fail halfway and drop the robot back down.
##
## Landing at hard_landing_speed or faster is a hard landing: the robot crouches to take the
## impact and ignores all input until it has stood back up (hard_landing_recovery).
##
## Three attacks. S is melee: a six-strike combo (jab, cross, knee, front kick, low sweep,
## roundhouse), each strike costing melee_cost; pressing S during a strike chains the next, and
## the combo starts over after melee_chain_time without one. D fires a plasma bolt straight
## ahead from the raised arm (shot_cost, shot_cooldown between shots). F is the charged burst:
## the robot braces, the arm's heat line glows red to white over burst_heat_time, then a
## massive explosion fills a cone (burst_angle wide) out to the screen's edge, shaking and
## glaring the screen, scorching what it hits and flinging the robot back into a slide. It
## costs burst_cost charge and one cannon charge (ammo, cannon_charges). Melee and the burst need the ground;
## a systems fault disables D and F like the wire. Every strike has its own AttackHitbox.
##
## The hitbox follows the body's posture: standing, LOW on all fours (running and dashing) and
## CROUCH (a charged jump ready to fire, or recovering from a hard landing). Its bottom edge
## never moves. A posture only grows the box where there is room, so the robot stays low under
## a ceiling (it keeps moving on all fours at whatever speed it has).

## Emitted whenever charge changes.
signal charge_changed(charge: float, max_charge: float)
## Emitted whenever the core, legs or systems damage state changes.
signal damage_changed
## Emitted on touching down from the air. speed is the fall speed in m/s; hard landings lock
## all input until the robot has stood back up (see hard_landing_speed).
signal landed(speed: float, hard: bool)
## Emitted on takeoff. charged is true for a charged jump.
signal jumped(charged: bool)
## Emitted whenever the number of cannon charges (the burst's ammo) changes.
signal cannon_charges_changed(count: int)
## Emitted when a damaged wire launcher fails to fire.
signal wire_misfired
## Stepped straight up onto a low ledge, by height pixels (the animator eases the body up).
signal stepped_up(height: float)

enum Posture { STAND, LOW, CROUCH, PRONE }
## Damage state of one part. FAULT is the part out of action.
enum Damage { HEALTHY, MILD, HEAVY, FAULT }
enum Part { CORE, LEGS, SYSTEMS }

## World scale. 16 px per metre was the old 32 px test rectangle at 2 m; it stays fixed so the
## taller robot body doesn't change any movement tuning.
const PIXELS_PER_METER: float = 16.0
## A dash with less than this many pixels left is considered finished.
const DASH_END_EPSILON_PX: float = 0.01
## Angular resolution of the grapple point search, in degrees.
const WIRE_SEARCH_STEP_DEG: float = 1.0
## The drawn steel wire: pixels per rope segment, most segments, gravity on it (px/s²),
## velocity kept per frame, and constraint passes per frame.
const ROPE_SEGMENT: float = 4.0
const ROPE_MAX_POINTS: int = 64
const ROPE_GRAVITY: float = 220.0
const ROPE_DAMPING: float = 0.985
const ROPE_ITERATIONS: int = 14
## How straight steel wire stays at each joint: two segments apart, the rope spans at least
## this share of their length (1 would be a rigid rod).
const ROPE_STIFFNESS: float = 0.95
const STEEL := Color(0.6, 0.62, 0.64)

## Where the wire's hook is: in the launcher, flying out, anchored, or reeling back in.
enum Hook { STOWED, FLYING, ATTACHED, RETURNING }

@export_group("Charge")
## Charge capacity. The player starts full.
@export var max_charge: float = 1000.0
## Drain while walking on the ground, per second.
@export var walk_drain: float = 2.0
## Drain while running on the ground, per second.
@export var run_drain: float = 7.0
## Drain while hanging from the wire (attached and off the ground), per second. Standing on the
## ground with the wire attached costs nothing.
@export var hang_drain: float = 1.0
## Drain while reeling the wire in (Z held while attached), per second, in place of hang_drain.
@export var reel_drain: float = 6.0
## Cost of a normal jump.
@export var jump_cost: float = 20.0
## Cost of a charged jump. A held jump only becomes charged with at least this much charge.
@export var charged_jump_cost: float = 60.0
## Cost of a dash.
@export var dash_cost: float = 40.0
## Cost of firing the wire, hit or miss.
@export var wire_cost: float = 15.0
## Fraction of max_charge below which the HUD starts warning. Visual only.
@export_range(0.0, 1.0, 0.01) var warning_ratio: float = 0.3
## Fraction of max_charge below which dashing and charged jumps are disabled.
@export_range(0.0, 1.0, 0.01) var critical_ratio: float = 0.1
## Fraction of max_charge below which jumping, the wire and running are disabled too.
@export_range(0.0, 1.0, 0.01) var failing_ratio: float = 0.02
## Walk speed multiplier below failing_ratio.
@export_range(0.0, 1.0, 0.05) var failing_walk_factor: float = 0.7

@export_group("Damage")
## Damage state of each part. Set them through set_damage() in code; changing them here works too.
@export var core_damage: Damage = Damage.HEALTHY:
	set(value):
		core_damage = value
		_apply_damage(Part.CORE, value)
@export var legs_damage: Damage = Damage.HEALTHY:
	set(value):
		legs_damage = value
		_apply_damage(Part.LEGS, value)
@export var systems_damage: Damage = Damage.HEALTHY:
	set(value):
		systems_damage = value
		_apply_damage(Part.SYSTEMS, value)
@export_subgroup("Legs")
## Walking and running speed multiplier with mild and with heavy leg damage.
@export_range(0.0, 1.0, 0.05) var legs_mild_speed: float = 0.8
@export_range(0.0, 1.0, 0.05) var legs_heavy_speed: float = 0.45
## Mild: chance that a jump or dash comes out weak, and its strength range when it does.
@export_range(0.0, 1.0, 0.05) var legs_mild_weak_chance: float = 0.3
@export var legs_mild_weak_strength: Vector2 = Vector2(0.55, 0.85)
## Heavy: stumbles per second while walking, on average.
@export var legs_heavy_stumble_rate: float = 0.22
## Heavy: chance that landing from a jump throws the robot to the floor.
@export_range(0.0, 1.0, 0.05) var legs_heavy_fall_chance: float = 0.35
## Fault: crawling speed on the arms, in metres per second.
@export var crawl_speed: float = 0.6
@export_subgroup("Core")
## Charging speed and charge drain multipliers with mild core damage.
@export_range(0.0, 1.0, 0.05) var core_mild_charge_factor: float = 0.7
@export var core_mild_drain_factor: float = 1.2
## Heavy: average charging speed multiplier. The rate also stutters, cuts out and surges.
@export_range(0.0, 1.0, 0.05) var core_heavy_charge_factor: float = 0.45
@export var core_heavy_drain_factor: float = 1.2
## Heavy: stumbles per second while moving, on average, and the share that end on the floor.
@export var core_heavy_stumble_rate: float = 0.15
@export_range(0.0, 1.0, 0.05) var core_heavy_fall_share: float = 0.3
## Heavy: drain surges per second on average, their drain multiplier and length in seconds.
@export var core_heavy_surge_rate: float = 0.1
@export var core_heavy_surge_factor: float = 4.0
@export var core_heavy_surge_time: Vector2 = Vector2(0.6, 1.8)
@export_subgroup("Systems")
## Random error added to the wire's aim, in degrees, with mild and with heavy damage.
@export var systems_mild_aim_error: float = 14.0
@export var systems_heavy_aim_error: float = 22.0
## Chance a shot reaches less far, and the fraction of wire_range it then reaches at most.
@export_range(0.0, 1.0, 0.05) var systems_mild_short_chance: float = 0.3
@export_range(0.0, 1.0, 0.05) var systems_mild_short_reach: float = 0.6
@export_range(0.0, 1.0, 0.05) var systems_heavy_short_chance: float = 0.5
@export_range(0.0, 1.0, 0.05) var systems_heavy_short_reach: float = 0.3
## Heavy: chance that pressing the wire does nothing but spark (no charge spent).
@export_range(0.0, 1.0, 0.05) var systems_heavy_misfire_chance: float = 0.3
## Plasma shot (D): random spread either side of straight ahead, in degrees, with mild and with
## heavy damage.
@export var systems_mild_shot_spread: float = 5.0
@export var systems_heavy_shot_spread: float = 10.0
## Plasma shot: chance the bolt hangs in the arm before leaving, and how long, in seconds.
@export_range(0.0, 1.0, 0.05) var systems_mild_shot_delay_chance: float = 0.25
@export var systems_mild_shot_delay: Vector2 = Vector2(0.06, 0.16)
@export_range(0.0, 1.0, 0.05) var systems_heavy_shot_delay_chance: float = 0.5
@export var systems_heavy_shot_delay: Vector2 = Vector2(0.15, 0.4)
## Heavy: chance a plasma shot sputters out and nothing fires (no charge spent).
@export_range(0.0, 1.0, 0.05) var systems_heavy_shot_misfire_chance: float = 0.12
## Heavy (systems or legs): the burst's kick in metres per second (it knocks the robot off its
## feet). Heavy systems: how far off level the cone can go, up or down, in degrees.
@export var systems_heavy_burst_knockback: float = 18.0
@export var systems_heavy_burst_angle_error: Vector2 = Vector2(3.0, 10.0)
## Fault: how far through heating the burst's arm gets before it jams (fraction, random).
@export var systems_fault_jam_at: Vector2 = Vector2(0.3, 0.6)
@export_subgroup("Stumbles")
## A stumble: input muted while the robot staggers and catches itself, in seconds.
@export var stumble_time: float = 0.55
## A knockdown: seconds lying on the floor, then seconds getting back up.
@export var knockdown_time: float = 0.8
@export var get_up_time: float = 1.1

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

@export_group("Turning")
## After a reversal has braked to a stop and the facing has flipped, the robot holds still
## this long, in seconds, before accelerating the new way.
@export var turn_pause: float = 0.12
## Time to brake from run_speed to a stop, in seconds, when stopping or reversing from a run.
## Gentler than decel_time, so the robot skids (about 17 px at the default).
@export var run_stop_time: float = 0.35

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

@export_group("Landing")
## Fall speed in m/s at or above which a landing is hard: the robot crouches to absorb it and
## ignores all input until it stands back up. Slower landings are absorbed by the legs alone.
## 4.5 m/s is a drop of about 2.5 m (40 px); a charged jump from flat ground lands at ~4 m/s.
@export var hard_landing_speed: float = 4.5
## Fall speed in m/s that gets the longest recovery.
@export var hard_landing_max_speed: float = 9.0
## Time locked after a hard landing, in seconds, at hard_landing_speed and at the max speed.
@export var hard_landing_recovery: Vector2 = Vector2(0.9, 2.0)

@export_group("Posture")
## Hitbox while on all fours (running, dashing) and while crouched (charged jump ready, hard
## landing), in pixels. The standing size is the scene's collision shape.
@export var low_hitbox_size: Vector2 = Vector2(22, 18)
@export var crouch_hitbox_size: Vector2 = Vector2(14, 22)
## Hitbox while lying or crawling on the floor.
@export var prone_hitbox_size: Vector2 = Vector2(24, 10)

@export_group("Charged jump")
## Shortest wind-up before a normal jump takes off, in seconds: the crouch always gets this
## long, even if Z is only tapped. The run-up slows to the jump's speed over the same time.
@export var jump_windup_time: float = 0.1
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
## Maximum reach of the wire, in metres (10 m = 160 px).
@export var wire_range: float = 10.0
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
## Speed the hook flies out at, and is wound back in at after a miss or a release, in m/s.
@export var hook_speed: float = 45.0
@export var hook_return_speed: float = 30.0
## How far the wire droops at its middle when the hook first bites, in pixels: just a slight
## curve (only while there is wire left to give).
@export var wire_attach_sag: float = 2.5
## Push along the swing from the arrow keys while hanging from a taut wire, in m/s squared.
## Small on purpose: holding it barely tilts a still hang, but pushing in time with the swing
## (alternating left and right) builds it up.
@export var swing_push_accel: float = 0.6
## The arrow keys stop adding swing speed above this, in metres per second.
@export var swing_max_speed: float = 6.0

@export_group("Ledge climb")
## Highest ledge, in pixels above the feet, that walking into simply steps up onto.
@export var step_max_height: float = 10.0
## Highest ledge, in pixels above the feet, that walking into mantles without a jump.
@export var climb_auto_height: float = 16.0
## Highest ledge top a jump can grab and climb, in pixels above the feet (24 is just below the
## shoulders).
@export var climb_max_height: float = 24.0
## Charge a climb costs. With less than this the ledge isn't grabbed.
@export var climb_cost: float = 10.0
## Seconds hanging from the edge, taking the weight, before pulling up.
@export var climb_grab_time: float = 0.34
## Seconds for the climb after the grab, and the share of it spent hauling up (the rest is
## moving over onto the ledge). The two overlap, so it is one continuous motion.
@export var climb_time: float = 1.05
## Mantling a ledge from the ground: seconds reaching up to plant the hands, then seconds
## pushing up and over.
@export var mantle_reach_time: float = 0.2
@export var mantle_time: float = 0.8
@export_range(0.1, 0.9, 0.05) var climb_rise_share: float = 0.65
## Heavy core damage: chance a climb fails, and how far through the climb (after the grab) the
## grip gives way.
@export_range(0.0, 1.0, 0.05) var climb_fail_chance: float = 0.4
@export_range(0.1, 0.9, 0.05) var climb_fail_at: float = 0.4

@export_group("Combat")
## S: charge per melee strike, and seconds after a strike in which S continues the combo.
@export var melee_cost: float = 10.0
@export var melee_chain_time: float = 0.35
## D: charge per plasma shot, seconds between shots, and the bolt's speed in m/s.
@export var shot_cost: float = 20.0
@export var shot_cooldown: float = 0.2
@export var shot_speed: float = 55.0
## D: seconds to raise the arm before the bolt leaves, and to hold it out after.
@export var shot_raise_time: float = 0.06
@export var shot_hold_time: float = 0.3
## F: charge per burst; seconds to brace, to heat the arm, and to recover after firing.
@export var burst_cost: float = 500.0
@export var burst_brace_time: float = 0.25
@export var burst_heat_time: float = 1.0
@export var burst_recover_time: float = 0.9
## F: the cone's full angle in degrees. It reaches to the edge of the screen.
@export var burst_angle: float = 60.0
## F: full angle of the cone the attack hitbox covers, in degrees: a little wider than the
## visible blast, so it feels generous.
@export var burst_hit_angle: float = 75.0
## F: cannon charges (ammo); each burst uses one, and F does nothing at zero.
@export var cannon_charges: int = 0:
	set(value):
		cannon_charges = maxi(value, 0)
		cannon_charges_changed.emit(cannon_charges)
## F: speed the robot is flung back at (m/s) and how hard it brakes sliding (m/s²).
@export var burst_knockback: float = 11.0
@export var burst_slide_decel: float = 22.0

@export_group("Dev tools")
## Fly mode speed, up, down and sideways, in metres per second.
@export var fly_speed: float = 4.0

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

## Current charge, from 0 to max_charge. Changed only through _set_charge() so the HUD hears
## about it.
var charge: float = 0.0

## Dev tool: Z rises, C sinks, nothing held hovers. No jump, dash or wire, and no charge drain.
var fly_mode: bool = false:
	set(value):
		fly_mode = value
		if value:
			_detach_wire()
			_jump_charging = false
			_jump_ready = false
			_dash_remaining_px = 0.0
## Dev tool: walls don't stop the robot, though floors still hold it up (flying with it on
## ignores everything). Future hazards and damage should skip the robot while this is on.
var noclip: bool = false
## Dev tool: nothing drains charge (costs are still needed to act, but never taken).
var dev_no_charge_use: bool = false
## Dev tool: charge refills continuously at DEV_REGEN_RATE per second.
var dev_infinite_regen: bool = false
const DEV_REGEN_RATE: float = 100.0

## While true the robot ignores every control and just idles, e.g. while the pause menu is open.
## Locking also drops a jump being charged, so releasing Z later doesn't fire it.
var controls_locked: bool = false:
	set(value):
		controls_locked = value
		if value:
			_jump_charging = false
			_jump_ready = false

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
## Z was released but the wind-up isn't over yet: take off when it is.
var _jump_release_pending: bool = false
## Horizontal speed the wind-up slows to, and how fast, in px/s and px/s².
var _windup_target_x: float = 0.0
var _windup_rate: float = 0.0
## Distance left in the current dash, in pixels; 0 when not dashing.
var _dash_remaining_px: float = 0.0
var _dash_dir: float = 0.0
var _wire_attached: bool = false
## Grapple point in global coordinates.
var _wire_anchor: Vector2
## Current rope length in pixels. The player can move freely inside it; reeling shortens it.
var _wire_length: float = 0.0
var _hook: Hook = Hook.STOWED
## The hook's position, and where a flying hook is headed, in global coordinates.
var _hook_pos: Vector2
var _hook_target: Vector2
## True if the flying hook will bite when it gets there (false: a miss).
var _hook_bites: bool = false
## Where the drawn wire leaves the launcher hand, in global coordinates.
var _wire_origin: Vector2
## Simulated rope points (global) and their previous positions, launcher end first.
var _rope: PackedVector2Array = []
var _rope_prev: PackedVector2Array = []
var _rope_point_query := PhysicsPointQueryParameters2D.new()
## Seconds left recovering from a hard landing; all input is ignored while above zero.
var _recovery_left: float = 0.0
## Direction a ground reversal is waiting to face once stopped, or 0.
var _turn_pending: float = 0.0
## Seconds left holding still after a turn's flip.
var _turn_pause_left: float = 0.0
## True while skidding to a stop from faster than a walk.
var _skidding: bool = false
var _run_brake_px: float
## Length of the current hard landing's recovery, in seconds.
var _recovery_total: float = 0.0
## True while a held jump on the ground is charged and ready to fire.
var _jump_ready: bool = false
var _posture: Posture = Posture.STAND
## Hitbox size per posture.
var _posture_sizes: Dictionary[Posture, Vector2] = {}
## Local y of the hitbox's bottom edge, which every posture keeps.
var _hitbox_bottom: float = 0.0
var _posture_query := PhysicsShapeQueryParameters2D.new()

var _damage: Array[Damage] = [Damage.HEALTHY, Damage.HEALTHY, Damage.HEALTHY]
## Seconds left in a stumble, and its full length.
var _stumble_left: float = 0.0
var _stumble_total: float = 0.0
## Seconds left down after a knockdown (lying, then getting up), and the get-up part's length.
var _down_left: float = 0.0
var _get_up_total: float = 0.0
## Seconds left in a core drain surge.
var _surge_left: float = 0.0
## Heavy core charging: the current stutter multiplier and seconds until it changes.
var _charge_stutter: float = 1.0
var _charge_stutter_left: float = 0.0
## Seconds since the core faulted (death), for the eye's fade.
var _dead_time: float = 0.0
## True while the last jump hasn't landed yet (heavy legs may trip on its landing).
var _jumped: bool = false
## Melee strikes, in combo order: total seconds, the share of it the hitbox is live, the
## hitbox (pixels, facing right, from the body's origin, which sits 16 px above the feet;
## each box covers where that strike's fist, knee or foot lands), and the forward step speed in
## px/s.
const MELEE_MOVES: Array[Dictionary] = [
	{"name": &"jab", "time": 0.24, "hit": Vector2(0.3, 0.55), "box": Rect2(5, -16, 20, 7),
			"lunge": 30.0},
	{"name": &"cross", "time": 0.28, "hit": Vector2(0.32, 0.56), "box": Rect2(5, -18, 21, 8),
			"lunge": 40.0},
	{"name": &"knee", "time": 0.32, "hit": Vector2(0.36, 0.6), "box": Rect2(-2, -6, 14, 10),
			"lunge": 45.0},
	{"name": &"front_kick", "time": 0.4, "hit": Vector2(0.38, 0.62), "box": Rect2(3, -1, 18, 8),
			"lunge": 25.0},
	{"name": &"sweep", "time": 0.42, "hit": Vector2(0.38, 0.64), "box": Rect2(0, 9, 20, 7),
			"lunge": 20.0},
	{"name": &"roundhouse", "time": 0.55, "hit": Vector2(0.4, 0.64), "box": Rect2(1, -16, 19, 10),
			"lunge": 50.0},
]

## Ledge climb: progress 0 to 1 while climbing (-1 when not), where it starts and ends, the
## ledge's top corner, and whether this climb will fail.
var _climb_t: float = -1.0
## Melee: the strike playing (-1: none), seconds into it, S pressed during it, the strike the
## combo continues with, and seconds left to continue it.
var _melee_index: int = -1
var _melee_t: float = 0.0
var _melee_queued: bool = false
var _melee_next: int = 0
var _melee_chain_left: float = 0.0
var _melee_hitbox: AttackHitbox
var _melee_shape: CollisionShape2D
## Plasma shot: seconds since D (-1: arm down), whether the bolt has left, and cooldown left.
var _shot_t: float = -1.0
var _shot_fired: bool = false
## When this shot's bolt leaves (shot_raise_time plus any damage delay), and whether the bolt
## will fizzle instead.
var _shot_fire_at: float = 0.0
var _shot_dud: bool = false
var _shot_cooldown_left: float = 0.0
## Burst: seconds since F (-1: not bracing), and whether it has fired.
var _burst_t: float = -1.0
var _burst_fired: bool = false
## Systems fault: the burst jams. Heat it reaches before jamming, and its flicker after.
var _burst_dud: bool = false
var _burst_jam_at: float = 0.0
var _burst_flicker: float = 1.0
## Seconds left of the long slide after a heavy-damage burst knocked the robot down.
var _fling_left: float = 0.0
## The near hand's tip as the animator last drew it, and the physics frame it was set on.
var _arm_tip := Vector2.ZERO
var _arm_tip_frame: int = -100
var _climb_from: Vector2
var _climb_to: Vector2
var _climb_edge: Vector2
var _climb_fail: bool = false
## This climb started from the ground (a mantle), and its grab and climb seconds.
var _climb_mantle: bool = false
var _climb_grab: float = 0.3
var _climb_dur: float = 0.8
## Seconds since the last climb slipped, for the animator (INF if none recently).
var _climb_slip_time: float = INF

@onready var _wire_line: Line2D = $Wire
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# Movement dust and weapon smoke.
	var fx := PlayerFx.new()
	fx.player = self
	add_child(fx)
	var pixels_per_meter := PIXELS_PER_METER
	_gravity_px = gravity * pixels_per_meter
	_walk_speed_px = walk_speed * pixels_per_meter
	_run_speed_px = run_speed * pixels_per_meter
	_accel_px = _walk_speed_px / maxf(accel_time, 0.001)
	_decel_px = _walk_speed_px / maxf(decel_time, 0.001)
	_run_brake_px = _run_speed_px / maxf(run_stop_time, 0.001)
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
	# Own copy of the shape, since postures resize it.
	_collision.shape = _collision.shape.duplicate()
	var stand_size := (_collision.shape as RectangleShape2D).size
	_posture_sizes = {
		Posture.STAND: stand_size, Posture.LOW: low_hitbox_size,
		Posture.CROUCH: crouch_hitbox_size, Posture.PRONE: prone_hitbox_size,
	}
	_hitbox_bottom = _collision.position.y + stand_size.y / 2.0
	_posture_query.collision_mask = collision_mask
	_posture_query.exclude = [get_rid()]
	_melee_hitbox = AttackHitbox.new()
	_melee_hitbox.name = "MeleeHitbox"
	_melee_hitbox.attacker = self
	_melee_shape = CollisionShape2D.new()
	_melee_shape.shape = RectangleShape2D.new()
	_melee_hitbox.add_child(_melee_shape)
	add_child(_melee_hitbox)
	_set_charge(max_charge)


func _physics_process(delta: float) -> void:
	if dev_infinite_regen and not is_dead():
		_set_charge(charge + DEV_REGEN_RATE * delta)
	if fly_mode:
		_fly(delta)
		return
	_climb_slip_time += delta
	if is_climbing():
		_update_climb(delta)
		return
	var was_airborne := not is_on_floor()
	var fall_speed := velocity.y
	_recovery_left = maxf(_recovery_left - delta, 0.0)
	_fling_left = maxf(_fling_left - delta, 0.0)
	_update_damage(delta)
	var locked := is_recovering() or is_stumbling() or is_down() or is_dead()
	var attacking := is_meleeing() or is_bracing()
	# Ground speed before the wall stops it, kept when stepping up a low ledge.
	var stride_vx := 0.0

	# Read every frame, even airborne, so key order is tracked correctly on landing.
	var direction := _read_direction()
	if charge <= 0.0 or locked or attacking:
		# Out of charge: the motors stop, on the ground and in the air. Recovering from a hard
		# landing does the same until the robot is back on its feet.
		direction = 0.0
	_update_facing(direction)
	_turn_pause_left = maxf(_turn_pause_left - delta, 0.0)
	# Turning on the ground: no drive until stopped, flipped and paused.
	var move_direction := direction
	if _turn_pending != 0.0 or _turn_pause_left > 0.0:
		move_direction = 0.0

	# The wire works in every state, including mid-dash.
	if _action_just_pressed("wire") and not locked:
		_on_wire_pressed()

	if _wire_attached:
		if _winch_input() < 0.0:
			_drain(reel_drain * delta)
		elif not is_on_floor() and is_wire_taut():
			_drain(hang_drain * delta)
		if charge <= 0.0:
			_detach_wire()

	_update_attacks(delta, locked)
	if is_meleeing() or is_bracing():
		_update_attack_motion(delta)
		_move()
	elif (
		_dash_remaining_px <= 0.0
		and not locked
		and _action_just_pressed("dash")
		and _can_dash()
	):
		_drain(dash_cost)
		_dash_dir = signf(velocity.x)
		_dash_remaining_px = _dash_distance_px * _leg_strength()
		_jump_charging = false
		_jump_ready = false
		_update_dash(delta)
	elif _dash_remaining_px > 0.0:
		_update_dash(delta)
	else:
		if is_on_floor():
			_update_ground(move_direction, delta)
			stride_vx = velocity.x
		else:
			_update_air(direction, delta)
		_move()

	if was_airborne and is_on_floor():
		_on_landed(fall_speed)
	elif not is_on_floor() and not locked:
		_try_grab_ledge()
	elif is_on_floor() and not locked and not attacking and _dash_remaining_px <= 0.0:
		_try_step_or_mantle(direction, stride_vx)

	_update_posture(direction)
	_update_wire_line(delta)


## Picks the posture the body should be in and resizes the hitbox to it, if there is room.
func _update_posture(direction: float) -> void:
	var wanted := Posture.STAND
	if is_dashing():
		wanted = Posture.LOW
	elif is_on_floor():
		if is_down() or is_dead() or is_crawling():
			wanted = Posture.PRONE
		elif is_bracing():
			wanted = Posture.CROUCH
		elif is_recovering() or _jump_ready:
			wanted = Posture.CROUCH
		elif direction != 0.0 and _is_running() and not _wire_attached:
			wanted = Posture.LOW
		elif _skidding and _posture == Posture.LOW:
			# Skidding out of a run stays low until stopped.
			wanted = Posture.LOW
	if wanted != _posture:
		_try_posture(wanted)


## Resizes the hitbox for posture, keeping its bottom edge. A wider box may shift sideways
## off a wall to fit. Returns false, changing nothing, when there is no room.
func _try_posture(posture: Posture) -> bool:
	var size: Vector2 = _posture_sizes[posture]
	var old_size := (_collision.shape as RectangleShape2D).size
	var shape := RectangleShape2D.new()
	# A hair smaller, so resting on the floor or touching a wall doesn't count as overlap.
	shape.size = size - Vector2(0.2, 0.2)
	_posture_query.shape = shape
	var centre := Vector2(0.0, _hitbox_bottom - size.y / 2.0)
	var grow := maxf((size.x - old_size.x) / 2.0, 0.0)
	for nudge: float in [0.0, grow, -grow]:
		_posture_query.transform = global_transform.translated(centre + Vector2(nudge, -0.1))
		if get_world_2d().direct_space_state.intersect_shape(_posture_query, 1).is_empty():
			position.x += nudge
			(_collision.shape as RectangleShape2D).size = size
			_collision.position = centre
			_posture = posture
			return true
		if grow == 0.0:
			break
	return false


## The hitbox's current posture.
func get_posture() -> Posture:
	return _posture


## Facing follows the held direction. On the ground a reversal waits until the robot has
## stopped, so the flip never happens with velocity left over; in the air it is immediate.
func _update_facing(direction: float) -> void:
	if direction == 0.0 or direction == _facing:
		_turn_pending = 0.0
		return
	if not is_on_floor() or is_dashing() or fly_mode:
		_turn_pending = 0.0
		_facing = direction
		return
	_turn_pending = direction
	if absf(velocity.x) < 0.01:
		_facing = direction
		_turn_pending = 0.0
		_turn_pause_left = turn_pause


## True while braking, flipping or pausing to turn around on the ground.
func is_turning() -> bool:
	return _turn_pending != 0.0 or _turn_pause_left > 0.0


## True while skidding to a stop from faster than a walk.
func is_skidding() -> bool:
	return _skidding


## True while a dash is moving the player.
func is_dashing() -> bool:
	return _dash_remaining_px > 0.0


## How far through the current dash, from 0 to 1.
func dash_progress() -> float:
	return 1.0 - _dash_remaining_px / maxf(_dash_distance_px, 0.001)


## True while the dash is braking to its stop.
func is_dash_braking() -> bool:
	return is_dashing() and _dash_remaining_px < _dash_brake_distance_px


## True while jump is held on the ground, before release.
func is_jump_charging() -> bool:
	return _jump_charging


## Seconds Z has been held on the ground for the current jump (0 when not winding up).
func jump_hold_time() -> float:
	return _jump_hold_time if _jump_charging else 0.0


## How far a held jump is towards being charged, from 0 to 1.
func jump_charge_fraction() -> float:
	return clampf(_jump_hold_time / maxf(charge_time, 0.001), 0.0, 1.0) if _jump_charging else 0.0


## True while a held jump is charged: releasing fires a charged jump.
func is_jump_charged() -> bool:
	return _jump_ready


func is_wire_attached() -> bool:
	return _wire_attached


## True while the wire line is drawn (attached, or briefly after a miss).
func is_wire_shown() -> bool:
	return _hook != Hook.STOWED


## Global position of the wire's far end: the hook, flying, anchored or returning.
func wire_end() -> Vector2:
	return _hook_pos


## Where the wire heads from the launcher hand: a point a little way along the drawn rope, so
## the arm follows a sagging wire instead of pointing at the anchor through it.
func wire_lead() -> Vector2:
	if _rope.size() < 3:
		return _hook_pos
	return _rope[mini(3, _rope.size() - 1)]


## Where the wire pulls on the body: the launcher shoulder, three quarters up the hitbox. All the
## rope physics (length, slack, tension) is measured from here, not from the feet.
func wire_mount() -> Vector2:
	var size := (_collision.shape as RectangleShape2D).size
	return global_position + Vector2(0.0, _collision.position.y - size.y * 0.25)


## Wire not yet taken up: how much longer the rope is than the straight line to the anchor.
func wire_slack() -> float:
	if not _wire_attached:
		return 0.0
	return maxf(_wire_length - wire_mount().distance_to(_wire_anchor), 0.0)


## True while the rope is pulled straight and holding the body.
func is_wire_taut() -> bool:
	return _wire_attached and wire_slack() < 0.5


## Moves the drawn wire's start to a global point (the hand that fired it). Physics still
## pulls on the body's centre.
func set_wire_origin(global_point: Vector2) -> void:
	_wire_origin = global_point


## Starts the recovery lock on a hard landing, and tells listeners how hard it was.
func _on_landed(fall_speed_px: float) -> void:
	var speed := maxf(fall_speed_px, 0.0) / PIXELS_PER_METER
	var hard := speed >= hard_landing_speed
	if hard:
		var t := clampf(
			inverse_lerp(hard_landing_speed, hard_landing_max_speed, speed), 0.0, 1.0
		)
		_recovery_left = lerpf(hard_landing_recovery.x, hard_landing_recovery.y, t)
		_recovery_total = _recovery_left
		_jump_charging = false
	var from_jump := _jumped
	_jumped = false
	landed.emit(speed, hard)
	if not hard and from_jump and _damage[Part.LEGS] == Damage.HEAVY:
		if randf() < legs_heavy_fall_chance:
			knock_down()


## True while getting back up after a hard landing; all input is ignored meanwhile.
func is_recovering() -> bool:
	return _recovery_left > 0.0


## Seconds left until the robot is back on its feet after a hard landing.
func recovery_left() -> float:
	return _recovery_left


## Full length of the current (or last) hard landing's recovery, in seconds.
func recovery_total() -> float:
	return _recovery_total


## Dev fly mode: free movement on both axes, easing to the target speed.
func _fly(delta: float) -> void:
	var direction := _read_direction()
	_update_facing(direction)
	var speed := fly_speed * PIXELS_PER_METER
	var rise := 0.0
	if _action_pressed("jump"):
		rise -= 1.0
	if _action_pressed("wire"):
		rise += 1.0
	var target := Vector2(direction, rise) * speed
	velocity = velocity.move_toward(target, speed * 6.0 * delta)
	if noclip:
		global_position += velocity * delta
	else:
		move_and_slide()
	_update_wire_line(delta)


## move_and_slide() with the wire's rope constraint around it. In noclip the sideways part skips
## collision, so walls are passed through while the floor still catches the robot.
func _move() -> void:
	if noclip and not _wire_attached:
		var step_x := velocity.x * get_physics_process_delta_time()
		var keep_x := velocity.x
		velocity.x = 0.0
		move_and_slide()
		velocity.x = keep_x
		global_position.x += step_x
		return
	if _wire_attached:
		_constrain_velocity_to_wire()
	move_and_slide()
	if _wire_attached:
		_settle_wire_length()


func _update_ground(direction: float, delta: float) -> void:
	if is_recovering() or is_stumbling() or is_down() or is_dead():
		# Crouched after a hard landing, staggering or on the floor: slide to a stop.
		_jump_charging = false
		_jump_ready = false
		# Thrown down by the burst's kick: a long slide rather than the usual quick stop.
		var decel := burst_slide_decel * PIXELS_PER_METER if _fling_left > 0.0 else _decel_px
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)
		_air_velocity_x = velocity.x
		_air_target_x = velocity.x
		return

	if _wire_attached:
		# Z reels instead of jumping while attached; reeling is applied in the rope constraint.
		_jump_charging = false
		_jump_ready = false
		velocity.x = _ground_velocity_x(direction, delta)
		_drain_walking(direction, delta)
		return

	# Only jumps lock the air; walking or dashing off a ledge falls unlocked.
	_air_lock_left = 0.0
	if is_crawling():
		# Dragging itself on the arms: no jumping, and no crawling while an arm is aiming.
		_jump_charging = false
		_jump_ready = false
		velocity.x = _ground_velocity_x(0.0 if is_shooting() else direction, delta)
		_drain_walking(direction, delta)
		_air_velocity_x = velocity.x
		_air_target_x = velocity.x
		return
	if _action_just_pressed("jump"):
		_jump_charging = true
		_jump_hold_time = 0.0
		_jump_release_pending = false
		# Winding up: the run-up slows to the jump's speed already, before takeoff.
		_windup_target_x = _jump_velocity_x(velocity.x)
		_windup_rate = absf(velocity.x - _windup_target_x) / maxf(jump_windup_time, 0.001)
	if _jump_charging:
		_jump_hold_time += delta

	var charged := (
		_jump_charging
		and _jump_hold_time >= charge_time
		and charge >= charged_jump_cost
		and charge_ratio() >= critical_ratio
		and _damage[Part.LEGS] < Damage.HEAVY
	)
	_jump_ready = charged
	if charged:
		# Charged: brake to a stop and ignore movement input until Z is released.
		_skidding = false
		velocity.x = move_toward(velocity.x, 0.0, _decel_px * delta)
	elif _jump_charging:
		_skidding = false
		velocity.x = move_toward(velocity.x, _windup_target_x, _windup_rate * delta)
	else:
		velocity.x = _ground_velocity_x(direction, delta)
		_drain_walking(direction, delta)

	if _jump_charging and _action_just_released("jump"):
		_jump_release_pending = true
	# A quick tap still gets the whole wind-up before taking off.
	if _jump_charging and _jump_release_pending and _jump_hold_time >= jump_windup_time:
		_jump_charging = false
		_jump_ready = false
		_jump_release_pending = false
		if charged:
			_drain(charged_jump_cost)
			var charged_x := _facing * _charged_jump_speed_px
			_launch(charged_x, charged_x, _charged_jump_velocity_px)
			jumped.emit(true)
			return
		if charge >= jump_cost and charge_ratio() >= failing_ratio:
			_drain(jump_cost)
			# Already slowed during the wind-up.
			_launch(velocity.x, velocity.x, _jump_velocity_px)
			jumped.emit(false)
			return

	# Walking off a ledge keeps the current speed with no reduction.
	_air_velocity_x = velocity.x
	_air_target_x = velocity.x


func _update_air(direction: float, delta: float) -> void:
	# A charge only builds on the ground; leaving it cancels the jump.
	_skidding = false
	_jump_charging = false
	_jump_ready = false
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
	var offset := wire_mount() - _wire_anchor
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
	return (
		is_on_floor()
		and _damage[Part.LEGS] < Damage.HEAVY
		and not _wire_attached
		and not _jump_charging
		and velocity.x != 0.0
		and charge >= dash_cost
		and charge_ratio() >= critical_ratio
	)


## C fires a wire, or releases the attached one without firing another.
func _on_wire_pressed() -> void:
	if _wire_attached or _hook == Hook.FLYING:
		_detach_wire()
		return
	if _hook != Hook.STOWED:
		# Still winding the last shot back in.
		return
	if charge < wire_cost or charge_ratio() < failing_ratio:
		return
	var systems := _damage[Part.SYSTEMS]
	if systems == Damage.FAULT:
		return
	if systems == Damage.HEAVY and randf() < systems_heavy_misfire_chance:
		# Misfire: the launcher clicks and nothing comes out.
		wire_misfired.emit()
		return
	_drain(wire_cost)
	var aim := _wire_aim()
	var reach := _wire_range_px
	if systems >= Damage.MILD:
		var heavy := systems == Damage.HEAVY
		var error := systems_heavy_aim_error if heavy else systems_mild_aim_error
		aim = aim.rotated(deg_to_rad(randf_range(-error, error)))
		if randf() < (systems_heavy_short_chance if heavy else systems_mild_short_chance):
			var most := systems_heavy_short_reach if heavy else systems_mild_short_reach
			reach *= randf_range(most * 0.5, most)
	# The hook flies straight at what the search found, or out to full reach on a miss.
	_hook_bites = _find_grapple_point(aim, reach)
	_hook_target = _wire_anchor if _hook_bites else global_position + aim * reach
	_hook = Hook.FLYING
	if _wire_origin == Vector2.ZERO:
		_wire_origin = global_position
	_hook_pos = _wire_origin
	_reset_rope()


## Letting go mid-air keeps the swing's momentum with no air lock, so drag and air control apply.
func _detach_wire() -> void:
	_wire_attached = false
	if _hook == Hook.FLYING or _hook == Hook.ATTACHED:
		_hook = Hook.RETURNING


## The hook reaches its target: it bites, with a touch of slack if there is wire to spare, or
## (a miss) starts winding back in.
func _on_hook_arrived() -> void:
	if not _hook_bites:
		_hook = Hook.RETURNING
		return
	_hook = Hook.ATTACHED
	_wire_attached = true
	var distance := wire_mount().distance_to(_wire_anchor)
	# A shallow curve of sag d over a span L takes about 8d²/3L of extra wire.
	var slack := 8.0 * wire_attach_sag * wire_attach_sag / (3.0 * maxf(distance, 1.0))
	_wire_length = minf(distance + slack, maxf(_wire_range_px, distance))
	_jump_charging = false
	_jump_ready = false
	_air_lock_left = 0.0


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
func _find_grapple_point(aim: Vector2, reach: float) -> bool:
	var space := get_world_2d().direct_space_state
	var origin := global_position
	_wire_query.from = origin
	var steps := int(wire_search_angle / WIRE_SEARCH_STEP_DEG)

	for i in steps + 1:
		var offset := deg_to_rad(i * WIRE_SEARCH_STEP_DEG)
		var best_distance := INF
		for side in 2:
			# side 0 rotates one way, side 1 the other; offset 0 only needs one ray.
			_wire_query.to = origin + aim.rotated(offset * (1 - 2 * side)) * reach
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
	return _action_axis("jump", "dash")


## Keeps the player inside the rope: removes any velocity stretching it. Reeling guarantees at
## least reel_speed towards the anchor; paying out lets the player move away at up to
## extend_speed until the rope reaches wire_range. Gravity plus this makes the pendulum.
func _constrain_velocity_to_wire() -> void:
	var offset := wire_mount() - _wire_anchor
	var distance := offset.length()
	var winch := _winch_input()
	# Slack: the rope isn't pulling yet. Reeling winds the slack in first; only once it is
	# straight does it start hauling the body.
	if distance < 0.001 or distance < _wire_length - 0.01:
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
	var offset := wire_mount() - _wire_anchor
	var distance := offset.length()
	var winch := _winch_input()
	var delta := get_physics_process_delta_time()
	if winch < 0.0:
		# Reeling in winds rope in at reel speed: slack shortens first, tension comes after.
		_wire_length = maxf(_wire_length - _reel_speed_px * delta, 4.0)
	elif winch > 0.0:
		# Paying out feeds rope at extend speed, held or not: hanging, the body lowers that fast;
		# standing still, the slack piles up and hangs.
		_wire_length = minf(_wire_length + _extend_speed_px * delta, _wire_range_px)
	if distance > _wire_length:
		move_and_collide(-offset / distance * (distance - _wire_length))


func _update_wire_line(delta: float) -> void:
	if _wire_origin == Vector2.ZERO or _hook == Hook.STOWED:
		_wire_origin = global_position
	match _hook:
		Hook.FLYING:
			_hook_pos = _hook_pos.move_toward(_hook_target, hook_speed * PIXELS_PER_METER * delta)
			if _hook_pos.is_equal_approx(_hook_target):
				_on_hook_arrived()
		Hook.ATTACHED:
			_hook_pos = _wire_anchor
		Hook.RETURNING:
			_hook_pos = _hook_pos.move_toward(
				_wire_origin, hook_return_speed * PIXELS_PER_METER * delta
			)
			if _hook_pos.distance_to(_wire_origin) < 1.0:
				_hook = Hook.STOWED
	if _hook == Hook.STOWED:
		_wire_line.visible = false
		_rope.clear()
		return
	_simulate_rope(delta)
	_wire_line.visible = true
	_wire_line.default_color = STEEL
	var local := PackedVector2Array()
	local.resize(_rope.size())
	for i in _rope.size():
		local[i] = to_local(_rope[i]).round()
	_wire_line.points = local


## Lays the rope out straight from the launcher to the hook.
func _reset_rope() -> void:
	_rope.clear()
	_rope_prev.clear()
	for i in 2:
		_rope.append(_wire_origin)
		_rope_prev.append(_wire_origin)


## A chain of point masses (Verlet): pinned to the launcher and the hook, sagging under gravity
## where there is slack, lying on whatever it falls onto. Flying or winding in it is let out or
## taken up as it goes, so it stays straight; anchored, its length is the rope length the
## physics uses, so it is taut while it holds the robot and hangs loose when it doesn't.
func _simulate_rope(delta: float) -> void:
	var span := _wire_origin.distance_to(_hook_pos)
	# Drawn from the hand, with exactly the slack the physics has: straight when it holds the body.
	var length := span + (wire_slack() if _hook == Hook.ATTACHED else 0.0)
	var count := clampi(ceili(length / ROPE_SEGMENT) + 1, 2, ROPE_MAX_POINTS)
	if count != _rope.size():
		_resample_rope(count)
	var segment := length / float(count - 1)
	_rope_point_query.collision_mask = collision_mask
	_rope_point_query.exclude = [get_rid()]
	var space := get_world_2d().direct_space_state
	var gravity := Vector2(0.0, ROPE_GRAVITY * delta * delta)
	for i in range(1, count - 1):
		var p := _rope[i]
		var next := p + (p - _rope_prev[i]) * ROPE_DAMPING + gravity
		_rope_prev[i] = p
		_rope[i] = next
	for _pass in ROPE_ITERATIONS:
		_rope[0] = _wire_origin
		_rope[count - 1] = _hook_pos
		for i in count - 1:
			var a := _rope[i]
			var b := _rope[i + 1]
			var d := b - a
			var dist := d.length()
			if dist <= segment or dist < 0.0001:
				continue
			var fix := d * ((dist - segment) / dist)
			if i == 0:
				_rope[i + 1] = b - fix
			elif i + 1 == count - 1:
				_rope[i] = a + fix
			else:
				_rope[i] = a + fix * 0.5
				_rope[i + 1] = b - fix * 0.5
		# Steel is springy: a joint can only bend so far, so slack bows out in a loop instead of
		# folding up on itself. A dead-straight bit being squeezed gets a nudge to buckle.
		var bend_min := 2.0 * segment * ROPE_STIFFNESS
		for i in count - 2:
			var a := _rope[i]
			var c := _rope[i + 2]
			var d := c - a
			var dist := d.length()
			if dist >= bend_min:
				continue
			if dist < 0.0001:
				d = Vector2.DOWN
				dist = 1.0
			var push := d * ((bend_min - dist) / dist) * 0.25
			var b := _rope[i + 1]
			if absf((b - a).cross(c - b)) < 0.01:
				_rope[i + 1] = b + Vector2(-d.y, d.x).normalized() * 0.05 * float(_facing)
			if i > 0:
				_rope[i] = a - push
			if i + 2 < count - 1:
				_rope[i + 2] = c + push
	_rope[0] = _wire_origin
	_rope[count - 1] = _hook_pos
	if _hook != Hook.ATTACHED or wire_slack() < 0.02:
		# Pulled tight (or flying): a dead-straight line, whatever shape it had a moment ago.
		for i in range(1, count - 1):
			_rope[i] = _wire_origin.lerp(_hook_pos, float(i) / float(count - 1))
			_rope_prev[i] = _rope[i]
		return
	# Resting on the ground: a point that ended up inside rock goes back where it was, stopped.
	for i in range(1, count - 1):
		_rope_point_query.position = _rope[i]
		if not space.intersect_point(_rope_point_query, 1).is_empty():
			_rope[i] = _rope_prev[i]


## Re-spaces the rope to count points along its current shape.
func _resample_rope(count: int) -> void:
	if _rope.size() < 2:
		_reset_rope()
	var old := _rope.duplicate()
	var lengths: Array[float] = [0.0]
	for i in range(1, old.size()):
		lengths.append(lengths[i - 1] + old[i - 1].distance_to(old[i]))
	var total: float = lengths[lengths.size() - 1]
	_rope.resize(count)
	_rope_prev.resize(count)
	var k := 0
	for i in count:
		var target := total * float(i) / float(count - 1)
		while k < old.size() - 2 and lengths[k + 1] < target:
			k += 1
		var seg: float = lengths[k + 1] - lengths[k]
		var t: float = 0.0 if seg <= 0.0001 else (target - lengths[k]) / seg
		_rope[i] = old[k].lerp(old[k + 1], clampf(t, 0.0, 1.0))
		_rope_prev[i] = _rope[i]


## Leaves the ground at takeoff_x, then eases horizontally to target_x over jump_slowdown_time.
func _launch(takeoff_x: float, target_x: float, launch_velocity: float) -> void:
	_jumped = true
	var strength := _leg_strength()
	takeoff_x *= strength
	target_x *= strength
	launch_velocity *= sqrt(strength)
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
	if direction == 0.0 or vx * direction < 0.0:
		# Stopping (or turning round, which stops first). Out of a run it's a skid: gentler
		# braking, until back down to a stop.
		if absf(vx) > _walk_speed_px * 1.05:
			_skidding = true
		var rate := _run_brake_px if _skidding else _decel_px
		vx = move_toward(vx, 0.0, rate * delta)
		if vx == 0.0:
			_skidding = false
		return vx
	_skidding = false

	var top_speed := _run_speed_px if _is_running() else _walk_speed_px
	if charge_ratio() < failing_ratio:
		top_speed *= failing_walk_factor
	match _damage[Part.LEGS]:
		Damage.MILD:
			top_speed *= legs_mild_speed
		Damage.HEAVY:
			top_speed *= legs_heavy_speed
		Damage.FAULT:
			top_speed = crawl_speed * PIXELS_PER_METER
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


## Adds charge, capped at max_charge. A charging station calls this every physics frame while
## the player is inside it.
func recharge(amount: float) -> void:
	if is_dead():
		return
	match _damage[Part.CORE]:
		Damage.MILD:
			amount *= core_mild_charge_factor
		Damage.HEAVY:
			amount *= core_heavy_charge_factor * _charge_stutter
	_set_charge(charge + amount)


## Removes charge, stopping at zero. A damaged core leaks more.
func _drain(amount: float) -> void:
	if dev_no_charge_use:
		return
	match _damage[Part.CORE]:
		Damage.MILD:
			amount *= core_mild_drain_factor
		Damage.HEAVY:
			amount *= core_heavy_drain_factor
			if _surge_left > 0.0:
				amount *= core_heavy_surge_factor
	_set_charge(charge - amount)


## Walking or running drain for one frame while an arrow key is held on the ground.
func _drain_walking(direction: float, delta: float) -> void:
	if direction == 0.0:
		return
	_drain((run_drain if _is_running() else walk_drain) * delta)


## Last non-zero input direction: 1 for right, -1 for left. The visual faces this way.
func get_facing() -> float:
	return _facing


## Charge as a fraction of max_charge, from 0 to 1.
func charge_ratio() -> float:
	return charge / max_charge if max_charge > 0.0 else 0.0


## Run is held and there's enough charge to run.
func _is_running() -> bool:
	return (
		_action_pressed("run")
		and charge_ratio() >= failing_ratio
		and _damage[Part.LEGS] < Damage.HEAVY
	)


func _set_charge(value: float) -> void:
	value = clampf(value, 0.0, max_charge)
	if value == charge:
		return
	charge = value
	charge_changed.emit(charge, max_charge)


## Returns -1, 0 or 1. When both keys are held, the most recently pressed one wins.
func _read_direction() -> float:
	var left := _action_pressed("move_left")
	var right := _action_pressed("move_right")

	if left and right:
		if _action_just_pressed("move_left"):
			_input_dir = -1.0
		elif _action_just_pressed("move_right"):
			_input_dir = 1.0
	elif left:
		_input_dir = -1.0
	elif right:
		_input_dir = 1.0
	else:
		_input_dir = 0.0

	return _input_dir


#region Attacks

## True during a melee strike.
func is_meleeing() -> bool:
	return _melee_index >= 0


## Which melee strike is playing (index into MELEE_MOVES), or -1.
func melee_move() -> int:
	return _melee_index


## How far through the current strike, 0 to 1.
func melee_progress() -> float:
	if _melee_index < 0:
		return 0.0
	return clampf(_melee_t / float(MELEE_MOVES[_melee_index].time), 0.0, 1.0)


## True while the arm is raised for a plasma shot.
func is_shooting() -> bool:
	return _shot_t >= 0.0


## How far the shooting arm is raised (0 to 1), and how much it is still kicking back from the
## shot (1 the instant the bolt leaves, easing to 0).
func shot_raise() -> float:
	return smoothstep(0.0, maxf(shot_raise_time, 0.001), _shot_t) if _shot_t >= 0.0 else 0.0


func shot_recoil() -> float:
	if not _shot_fired or _shot_t < 0.0:
		return 0.0
	return 1.0 - smoothstep(0.0, 0.15, _shot_t - _shot_fire_at)


## True from pressing F until the robot has recovered from the burst.
func is_bracing() -> bool:
	return _burst_t >= 0.0


## True once the burst has fired (still bracing while it recovers).
func is_burst_fired() -> bool:
	return _burst_fired


## How far into the braced stance, 0 standing to 1 fully braced; eases out at the end of the
## recovery.
func burst_brace() -> float:
	if _burst_t < 0.0:
		return 0.0
	var end := burst_brace_time + burst_heat_time + burst_recover_time
	var into := smoothstep(0.0, maxf(burst_brace_time, 0.001), _burst_t)
	return into * (1.0 - smoothstep(end - burst_recover_time * 0.55, end, _burst_t))


## The arm's heat: 0 cold, rising to 1 (white hot) at the moment it fires, then cooling.
func burst_heat() -> float:
	if _burst_t < 0.0:
		return 0.0
	var fire_at := burst_brace_time + burst_heat_time
	if _burst_dud:
		# Jammed: it climbs to where it jams, then flickers out.
		var heat := clampf((_burst_t - burst_brace_time) / maxf(burst_heat_time, 0.001), 0.0, 1.0)
		if heat <= _burst_jam_at:
			return heat
		return _burst_jam_at * _burst_flicker if _burst_t < fire_at else 0.0
	if _burst_t < fire_at:
		return clampf((_burst_t - burst_brace_time) / maxf(burst_heat_time, 0.001), 0.0, 1.0)
	return 1.0 - smoothstep(0.0, burst_recover_time * 0.7, _burst_t - fire_at)


## True from the moment a plasma bolt leaves the arm until the arm comes down (not for a shot
## that fizzled).
func has_shot_fired() -> bool:
	return _shot_t >= 0.0 and _shot_fired and not _shot_dud


## True while the burst is jammed by a systems fault (it heats, sputters, never fires).
func is_burst_jammed() -> bool:
	return _burst_dud


## The kick of the burst: 1 as it fires, easing to 0 over the recovery.
func burst_recoil() -> float:
	if not _burst_fired or _burst_dud:
		return 0.0
	var since := _burst_t - burst_brace_time - burst_heat_time
	return 1.0 - smoothstep(0.0, burst_recover_time, since)


## True while the near arm should point straight ahead (aiming a shot or the burst).
func is_arm_forward() -> bool:
	return is_shooting() or is_bracing()


## The animator reports where the near hand's tip is drawn, for the muzzle.
func set_arm_tip(global_point: Vector2) -> void:
	_arm_tip = global_point
	_arm_tip_frame = Engine.get_physics_frames()


## Where shots leave: the drawn hand, or about where it would be if the animator hasn't said.
func muzzle() -> Vector2:
	if Engine.get_physics_frames() - _arm_tip_frame <= 3:
		return _arm_tip
	return global_position + Vector2(_facing * 14.0, -28.0)


## Adds cannon charges (burst ammo).
func add_cannon_charge(count: int = 1) -> void:
	cannon_charges += count


func _update_attacks(delta: float, locked: bool) -> void:
	_shot_cooldown_left = maxf(_shot_cooldown_left - delta, 0.0)
	_melee_chain_left = maxf(_melee_chain_left - delta, 0.0)
	if _melee_chain_left <= 0.0 and not is_meleeing():
		_melee_next = 0
	if locked or charge <= 0.0 and not _burst_fired:
		_cancel_attacks()
		return
	if is_meleeing() and not is_on_floor():
		# Stepped off an edge mid-strike: the strike is lost.
		_end_melee()
	if _action_just_pressed("attack"):
		if is_meleeing():
			_melee_queued = true
		elif _can_melee():
			_start_melee(_melee_next)
	if _action_just_pressed("shoot") and _can_shoot():
		_start_shot()
	if _action_just_pressed("burst") and _can_burst():
		_burst_t = 0.0
		_burst_fired = false
		# A systems fault jams the burst partway through heating.
		_burst_dud = _damage[Part.SYSTEMS] == Damage.FAULT
		_burst_jam_at = randf_range(systems_fault_jam_at.x, systems_fault_jam_at.y)
		_burst_flicker = 1.0
		_stop_jump_and_skid()
	if is_meleeing():
		_update_melee(delta)
	if _shot_t >= 0.0:
		_update_shot(delta)
	if is_bracing():
		_update_burst()
		_burst_t += delta


func _stop_jump_and_skid() -> void:
	_jump_charging = false
	_jump_ready = false
	_jump_release_pending = false
	_skidding = false


func _can_melee() -> bool:
	return (
		is_on_floor() and not is_dashing() and not is_bracing() and not is_shooting()
		and not is_crawling() and not _wire_attached and charge >= melee_cost and charge_ratio() >= failing_ratio
	)


func _can_shoot() -> bool:
	return (
		not is_shooting() and _shot_cooldown_left <= 0.0 and not is_meleeing()
		and not is_bracing() and not is_dashing() and _hook == Hook.STOWED
		and charge >= shot_cost and charge_ratio() >= failing_ratio
	)


func _can_burst() -> bool:
	return (
		is_on_floor() and not is_bracing() and not is_meleeing() and not is_shooting()
		and not is_dashing() and _hook == Hook.STOWED
		and charge >= burst_cost and charge_ratio() >= critical_ratio and cannon_charges > 0
	)


func _start_melee(index: int) -> void:
	_drain(melee_cost)
	_melee_index = index
	_melee_t = 0.0
	_melee_queued = false
	_stop_jump_and_skid()
	var box: Rect2 = MELEE_MOVES[index].box
	(_melee_shape.shape as RectangleShape2D).size = box.size
	_melee_hitbox.position = Vector2(_facing * box.get_center().x, box.get_center().y)


func _update_melee(delta: float) -> void:
	_melee_t += delta
	var move: Dictionary = MELEE_MOVES[_melee_index]
	var p := _melee_t / float(move.time)
	var hit: Vector2 = move.hit
	_melee_hitbox.set_active(p >= hit.x and p < hit.y)
	if p < 1.0:
		return
	var queued := _melee_queued
	_end_melee()
	if queued and _can_melee():
		_start_melee(_melee_next)


## Ends the strike playing; the combo carries on from the next one if S comes soon enough.
func _end_melee() -> void:
	if _melee_index < 0:
		return
	_melee_hitbox.set_active(false)
	_melee_next = (_melee_index + 1) % MELEE_MOVES.size()
	_melee_chain_left = melee_chain_time
	_melee_index = -1
	_melee_queued = false


## Raises the arm for a shot. Damaged systems can hold the bolt in the arm a moment (mild and
## heavy), or let it fizzle out (heavy, sometimes; fault, always).
func _start_shot() -> void:
	_shot_t = 0.0
	_shot_fired = false
	_shot_fire_at = shot_raise_time
	_shot_dud = false
	match _damage[Part.SYSTEMS]:
		Damage.MILD:
			if randf() < systems_mild_shot_delay_chance:
				_shot_fire_at += randf_range(systems_mild_shot_delay.x, systems_mild_shot_delay.y)
		Damage.HEAVY:
			_shot_dud = randf() < systems_heavy_shot_misfire_chance
			if not _shot_dud and randf() < systems_heavy_shot_delay_chance:
				_shot_fire_at += randf_range(systems_heavy_shot_delay.x, systems_heavy_shot_delay.y)
		Damage.FAULT:
			_shot_dud = true


func _update_shot(delta: float) -> void:
	var before := _shot_t
	_shot_t += delta
	# A held-up bolt stutters at the muzzle when it should have left.
	if _shot_fire_at > shot_raise_time and before < shot_raise_time and _shot_t >= shot_raise_time:
		_fizzle(0.6)
	if not _shot_fired and _shot_t >= _shot_fire_at:
		_shot_fired = true
		_shot_cooldown_left = shot_cooldown
		if _shot_dud:
			_fizzle(1.0)
		else:
			_drain(shot_cost)
			var spread := 0.0
			match _damage[Part.SYSTEMS]:
				Damage.MILD:
					spread = systems_mild_shot_spread
				Damage.HEAVY:
					spread = systems_heavy_shot_spread
			var bolt := PlasmaShot.new()
			bolt.direction = Vector2(_facing, 0.0).rotated(deg_to_rad(randf_range(-spread, spread)))
			bolt.speed = shot_speed * PIXELS_PER_METER
			bolt.shooter = self
			bolt.position = get_parent().to_local(muzzle()) if get_parent() is Node2D else muzzle()
			get_parent().add_child(bolt)
	if _shot_t >= _shot_fire_at + shot_hold_time:
		_shot_t = -1.0
		_shot_fired = false


## A sputter of sparks and smoke from the muzzle: a weapon failing to fire.
func _fizzle(strength: float) -> void:
	var fizzle := Fizzle.new()
	fizzle.direction = Vector2(_facing, 0.0)
	fizzle.strength = strength
	fizzle.position = get_parent().to_local(muzzle()) if get_parent() is Node2D else muzzle()
	get_parent().add_child(fizzle)


func _update_burst() -> void:
	var fire_at := burst_brace_time + burst_heat_time
	if _burst_dud:
		_update_jammed_burst(fire_at)
		return
	if not _burst_fired and _burst_t >= fire_at:
		_burst_fired = true
		_drain(burst_cost)
		cannon_charges -= 1
		var at := muzzle()
		# Out to the edge of the screen in front.
		var viewport := get_viewport()
		var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
		var edge := view.end.x - at.x if _facing > 0.0 else at.x - view.position.x
		var blast := FlareBlast.new()
		blast.direction = Vector2(_facing, 0.0)
		var heavy := _damage[Part.SYSTEMS] == Damage.HEAVY
		if heavy:
			# The aim wanders a little up or down.
			var off := randf_range(systems_heavy_burst_angle_error.x, systems_heavy_burst_angle_error.y)
			blast.direction = blast.direction.rotated(deg_to_rad(off * (1.0 if randf() < 0.5 else -1.0)))
		blast.angle = burst_angle
		blast.hit_angle = burst_hit_angle
		blast.reach = maxf(edge, 32.0)
		blast.attacker = self
		# Placed before it enters the tree: it scorches and spawns from where it is in _ready.
		blast.position = get_parent().to_local(at) if get_parent() is Node2D else at
		get_parent().add_child(blast)
		# Heavy systems or legs damage: the kick is too much for it. Thrown off its feet, it
		# slides a long way on its back (crawling, it's already down: it just slides further).
		var hard := heavy or _damage[Part.LEGS] == Damage.HEAVY
		if hard and is_crawling():
			velocity.x = -_facing * systems_heavy_burst_knockback * PIXELS_PER_METER
		elif hard:
			velocity.x = -_facing * systems_heavy_burst_knockback * PIXELS_PER_METER
			_burst_t = -1.0
			_burst_fired = false
			knock_down()
			_fling_left = 1.5
			return
		velocity.x = -_facing * burst_knockback * PIXELS_PER_METER
	if _burst_t >= fire_at + burst_recover_time:
		_burst_t = -1.0
		_burst_fired = false


## Systems fault: the arm heats, the light stutters and dies, and at the moment it should fire
## it only sputters. No charge or cannon charge is spent and there's no kick.
func _update_jammed_burst(fire_at: float) -> void:
	var heat := (_burst_t - burst_brace_time) / maxf(burst_heat_time, 0.001)
	if heat > _burst_jam_at:
		# Flickering out: it cuts in and out, ever weaker.
		var fade := 1.0 - clampf((heat - _burst_jam_at) / maxf(1.0 - _burst_jam_at, 0.01), 0.0, 1.0)
		_burst_flicker = (randf_range(0.5, 1.0) if randf() < 0.55 * fade + 0.1 else 0.0) * fade
	if not _burst_fired and _burst_t >= fire_at:
		_burst_fired = true
		_fizzle(2.0)
	if _burst_t >= fire_at + burst_recover_time:
		_burst_t = -1.0
		_burst_fired = false
		_burst_dud = false


## Footwork while attacking: a small step into each strike; braced, the robot stands its
## ground, then slides back from the burst's kick.
func _update_attack_motion(delta: float) -> void:
	if not is_on_floor():
		velocity.y += _gravity_px * delta
	if is_meleeing():
		var move: Dictionary = MELEE_MOVES[_melee_index]
		var p := melee_progress()
		velocity.x = _facing * float(move.lunge) * (1.0 - smoothstep(0.15, 0.6, p))
	elif _burst_fired:
		velocity.x = move_toward(velocity.x, 0.0, burst_slide_decel * PIXELS_PER_METER * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, _decel_px * delta)
	_air_velocity_x = velocity.x
	_air_target_x = velocity.x


func _cancel_attacks() -> void:
	_end_melee()
	_melee_next = 0
	_shot_t = -1.0
	_shot_fired = false
	if not _burst_fired:
		_burst_t = -1.0
		_burst_dud = false

#endregion


#region Ledge climb

## True while hoisting up and over a ledge.
func is_climbing() -> bool:
	return _climb_t >= 0.0


## How far through the climb after the grab, from 0 (still hanging) to 1 (standing on top).
func climb_progress() -> float:
	return clampf((_climb_t - _climb_grab) / maxf(_climb_dur, 0.01), 0.0, 1.0)


## How far through the grab, from 0 (just caught the edge) to 1 (weight taken, about to pull).
func climb_grip() -> float:
	return clampf(_climb_t / maxf(_climb_grab, 0.01), 0.0, 1.0)


## True when this climb started standing on the ground (a mantle, no hanging).
func is_mantling() -> bool:
	return is_climbing() and _climb_mantle


## Share of the height hauled so far, from 0 to 1.
func climb_rise() -> float:
	# Eases in as the arms take the strain, then keeps going without stopping at the top.
	var u := clampf(climb_progress() / climb_rise_share, 0.0, 1.0)
	return u * u * (2.0 - u)


## Share of the way moved over onto the ledge, from 0 to 1.
func climb_over() -> float:
	# Starts moving over before the haul is quite done, so the body rolls straight onto the
	# ledge instead of stopping at the top first.
	var start := climb_rise_share * 0.9
	var u := clampf((climb_progress() - start) / (1.0 - start), 0.0, 1.0)
	return u * (2.0 - u) if u > 0.0 else 0.0


## The grabbed ledge's top corner, in global coordinates.
func climb_edge() -> Vector2:
	return _climb_edge


## Seconds since the last climb lost its grip (INF if it never did).
func climb_slip_time() -> float:
	return _climb_slip_time


## Mid-jump, against a wall in the facing direction: grabs its top if it is low enough, there
## is open air above it, and the robot fits standing on it.
func _try_grab_ledge() -> void:
	if not _jumped or _wire_attached or is_crawling() or is_dead() or charge < climb_cost:
		return
	var ledge := _find_ledge(climb_max_height)
	if not ledge.is_empty():
		_start_climb(ledge, false)


## On the floor, pushing into a wall: steps up onto it when it's low (step_max_height), or
## mantles it when it's a little higher (climb_auto_height). Taller needs a jump.
func _try_step_or_mantle(direction: float, stride_vx: float) -> void:
	if direction == 0.0 or signf(direction) != _facing or _wire_attached or is_dead():
		return
	if is_dashing() or is_meleeing() or is_bracing() or is_shooting():
		return
	var ledge := _find_ledge(climb_auto_height)
	if ledge.is_empty():
		return
	var feet := global_position.y + _hitbox_bottom
	var height: float = feet - float(ledge.top)
	if height <= 0.5:
		return
	if height <= step_max_height:
		# Straight up onto it, keeping the stride, if the body fits there as it is.
		var size := (_collision.shape as RectangleShape2D).size
		var up := Vector2(global_position.x, float(ledge.top) - _hitbox_bottom - 0.05)
		var shape := RectangleShape2D.new()
		shape.size = size - Vector2(0.4, 0.4)
		_posture_query.shape = shape
		_posture_query.transform = Transform2D(0.0, up + Vector2(0.0, _hitbox_bottom - size.y * 0.5))
		if not get_world_2d().direct_space_state.intersect_shape(_posture_query, 1).is_empty():
			return
		global_position = up
		# Keep the stride, and cover this frame's lost ground.
		velocity.x = stride_vx
		move_and_collide(Vector2(stride_vx * get_physics_process_delta_time(), 0.0))
		stepped_up.emit(height)
		return
	if is_crawling() or charge < climb_cost or charge_ratio() < failing_ratio:
		return
	_start_climb(ledge, true)


## The ledge in front, if the robot is against a wall in the facing direction whose top is at
## most max_height above the feet, with open air above it and room to stand on it. Returns
## {face_x, top, target} (target: where the body ends up standing), or {} when there's none.
func _find_ledge(max_height: float) -> Dictionary:
	if not test_move(global_transform, Vector2(_facing, 0.0)):
		return {}
	var size := (_collision.shape as RectangleShape2D).size
	var feet := global_position.y + _hitbox_bottom
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(Vector2.ZERO, Vector2.ZERO, collision_mask, [get_rid()])
	# The wall's face, just above the feet.
	query.from = Vector2(global_position.x, feet - 2.0)
	query.to = query.from + Vector2(_facing * (size.x * 0.5 + 4.0), 0.0)
	var wall := space.intersect_ray(query)
	if wall.is_empty():
		return {}
	var face_x: float = wall.position.x
	# The ledge top, a little way in from the face. Starting inside rock (wall too tall) gives no
	# hit, so only a free top within reach counts.
	var probe_x := face_x + _facing * 3.0
	query.from = Vector2(probe_x, feet - max_height - 0.5)
	query.to = Vector2(probe_x, feet - 1.0)
	var top_hit := space.intersect_ray(query)
	if top_hit.is_empty():
		return {}
	var top: float = top_hit.position.y
	# Room to stand up there.
	var stand: Vector2 = _posture_sizes[Posture.STAND]
	var target := Vector2(face_x + _facing * (stand.x * 0.5 + 1.0), top - _hitbox_bottom - 0.05)
	var shape := RectangleShape2D.new()
	shape.size = stand - Vector2(0.4, 0.4)
	_posture_query.shape = shape
	_posture_query.transform = Transform2D(0.0, target + Vector2(0.0, _hitbox_bottom - stand.y * 0.5))
	if not space.intersect_shape(_posture_query, 1).is_empty():
		return {}
	return {"face_x": face_x, "top": top, "target": target}


func _start_climb(ledge: Dictionary, mantle: bool) -> void:
	_try_posture(Posture.STAND)
	_drain(climb_cost)
	_climb_t = 0.0
	_climb_mantle = mantle
	_climb_grab = mantle_reach_time if mantle else climb_grab_time
	_climb_dur = mantle_time if mantle else climb_time
	_climb_from = global_position
	_climb_to = ledge.target
	_climb_edge = Vector2(float(ledge.face_x), float(ledge.top))
	_climb_fail = (
		not mantle and _damage[Part.CORE] == Damage.HEAVY and randf() < climb_fail_chance
	)
	# The climb cancels any jump or stride: no momentum is kept.
	velocity = Vector2.ZERO
	_air_velocity_x = 0.0
	_air_target_x = 0.0
	_air_lock_left = 0.0
	_jumped = false
	_jump_charging = false
	_jump_ready = false
	_skidding = false


## Scripted climb: hangs from the edge taking the weight, hauls straight up beside the wall
## until the feet clear the top, then moves over onto it. _climb_t counts seconds.
func _update_climb(delta: float) -> void:
	_climb_t += delta
	if _climb_fail and climb_progress() >= climb_fail_at:
		# The grip gives way: it drops back down the wall.
		_climb_t = -1.0
		_climb_slip_time = 0.0
		velocity = Vector2(-_facing * 10.0, 0.0)
		return
	# Catching its weight: the body sags a little on the arms, then holds (not when mantling
	# from the ground, where the feet still carry it).
	var sag := 0.0 if _climb_mantle else 2.5 * sin(PI * clampf(_climb_t / (_climb_grab * 1.6), 0.0, 1.0))
	var rise := climb_rise()
	var over := climb_over()
	global_position = Vector2(
		lerpf(_climb_from.x, _climb_to.x, over),
		lerpf(_climb_from.y, _climb_to.y, rise) + sag * (1.0 - rise)
	)
	velocity = Vector2.ZERO
	if climb_progress() >= 1.0:
		_climb_t = -1.0
		# Standing on the ledge, whatever is held: settle onto its floor so the next frame
		# counts as standing.
		global_position = _climb_to
		velocity = Vector2(0.0, 1.0)
		move_and_slide()
		velocity = Vector2.ZERO
		_air_velocity_x = 0.0
		_air_target_x = 0.0
	_update_wire_line(delta)

#endregion


#region Damage

## Sets one part's damage state. Healing a leg or core fault gets the robot back up.
func set_damage(part: Part, state: Damage) -> void:
	match part:
		Part.CORE:
			core_damage = state
		Part.LEGS:
			legs_damage = state
		Part.SYSTEMS:
			systems_damage = state


func _apply_damage(part: Part, state: Damage) -> void:
	var was := _damage[part]
	if was == state:
		return
	_damage[part] = state
	if state == Damage.FAULT:
		_climb_t = -1.0
		_stumble_left = 0.0
		_down_left = 0.0
		_jump_charging = false
		_jump_ready = false
		_dash_remaining_px = 0.0
		if part == Part.SYSTEMS or part == Part.CORE:
			_detach_wire()
		if part == Part.CORE:
			_dead_time = 0.0
	elif was == Damage.FAULT and (part == Part.LEGS or part == Part.CORE):
		if not is_crawling() and not is_dead():
			# Back on its feet: after a revive it lies a moment first, then gets up.
			_get_up_total = get_up_time
			_down_left = get_up_time + (0.8 if part == Part.CORE else 0.0)
	damage_changed.emit()


func get_damage(part: Part) -> Damage:
	return _damage[part]


## True with the core faulted: the robot lies dead and ignores every control.
func is_dead() -> bool:
	return _damage[Part.CORE] == Damage.FAULT


## Seconds since the core faulted.
func dead_time() -> float:
	return _dead_time


## True with the legs faulted: the robot drags itself along on its arms.
func is_crawling() -> bool:
	return _damage[Part.LEGS] == Damage.FAULT and not is_dead()


## A quick stagger: input muted for stumble_time while the robot catches itself.
func stumble() -> void:
	if is_climbing() or not is_on_floor() or is_down() or is_dead() or is_crawling() or is_dashing():
		return
	_stumble_total = stumble_time
	_stumble_left = stumble_time
	_jump_charging = false
	_jump_ready = false


func is_stumbling() -> bool:
	return _stumble_left > 0.0


## How far through the current stumble, from 0 to 1.
func stumble_progress() -> float:
	return 1.0 - _stumble_left / maxf(_stumble_total, 0.001)


## Throws the robot to the floor: it lies for knockdown_time, then gets up over get_up_time.
func knock_down() -> void:
	if is_climbing() or is_dead() or is_crawling():
		return
	_stumble_left = 0.0
	_down_left = knockdown_time + get_up_time
	_get_up_total = get_up_time
	_jump_charging = false
	_jump_ready = false
	_dash_remaining_px = 0.0


## True while knocked down, lying or getting up.
func is_down() -> bool:
	return _down_left > 0.0


## 0 while lying on the floor, rising to 1 as the robot gets back up.
func get_up_progress() -> float:
	if _down_left <= 0.0:
		return 1.0
	return clampf(1.0 - _down_left / maxf(_get_up_total, 0.001), 0.0, 1.0)


func _update_damage(delta: float) -> void:
	_stumble_left = maxf(_stumble_left - delta, 0.0)
	if is_crawling() or is_dead():
		_down_left = 0.0
	else:
		_down_left = maxf(_down_left - delta, 0.0)
	if is_dead():
		_dead_time += delta
		return
	var moving := is_on_floor() and absf(velocity.x) > 4.0 and not is_dashing()
	var busy := is_stumbling() or is_down() or is_recovering() or is_crawling()
	if moving and not busy:
		if _damage[Part.LEGS] == Damage.HEAVY and randf() < legs_heavy_stumble_rate * delta:
			stumble()
		elif _damage[Part.CORE] == Damage.HEAVY and randf() < core_heavy_stumble_rate * delta:
			if randf() < core_heavy_fall_share:
				knock_down()
			else:
				stumble()
	if _damage[Part.CORE] == Damage.HEAVY:
		_surge_left = maxf(_surge_left - delta, 0.0)
		if _surge_left <= 0.0 and randf() < core_heavy_surge_rate * delta:
			_surge_left = randf_range(core_heavy_surge_time.x, core_heavy_surge_time.y)
		# Charging stutters: it cuts out, crawls and spikes at random, averaging about 1.
		_charge_stutter_left -= delta
		if _charge_stutter_left <= 0.0:
			_charge_stutter_left = randf_range(0.15, 0.6)
			var roll := randf()
			if roll < 0.25:
				_charge_stutter = 0.0
			elif roll > 0.8:
				_charge_stutter = randf_range(1.6, 2.4)
			else:
				_charge_stutter = randf_range(0.5, 1.1)
	else:
		_surge_left = 0.0
		_charge_stutter = 1.0


## Strength multiplier for a jump or dash: mild leg damage sometimes weakens one.
func _leg_strength() -> float:
	if _damage[Part.LEGS] == Damage.MILD and randf() < legs_mild_weak_chance:
		return randf_range(legs_mild_weak_strength.x, legs_mild_weak_strength.y)
	return 1.0

#endregion

# Control reads go through these so controls_locked can mute them all in one place.
## Where the player is looking: x -1 or 1 while left or right is held (whether or not the robot
## can move), y -1 while look up is held and 1 for look down. Zero while the controls are
## locked or the robot is dead. Steers the camera (PlayerCamera) and the head.
func look_input() -> Vector2:
	if is_dead():
		return Vector2.ZERO
	var x := float(_action_pressed(&"move_right")) - float(_action_pressed(&"move_left"))
	var y := float(_action_pressed(&"look_down")) - float(_action_pressed(&"look_up"))
	return Vector2(x, y)


func _action_pressed(action: StringName) -> bool:
	return not controls_locked and Input.is_action_pressed(action)


func _action_just_pressed(action: StringName) -> bool:
	return not controls_locked and Input.is_action_just_pressed(action)


func _action_just_released(action: StringName) -> bool:
	return not controls_locked and Input.is_action_just_released(action)


func _action_axis(negative: StringName, positive: StringName) -> float:
	return 0.0 if controls_locked else Input.get_axis(negative, positive)
