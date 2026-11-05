class_name WatcherBot
extends Enemy
## The watcher: a lanky, uncanny rabbit-shaped machine, 24 px tall on all fours. It can unfold
## onto its hind legs, about 38 px tall, to scout around. It walks, runs and hops, and like the
## rabbit bot it never takes a hop or a drop deeper than max_safe_drop.
##
## Moods:
## - CALM: it wanders (sitting, walking, strings of hops) and now and then stands up to scout,
##   turning its head around, or goes rummaging: to the nearest wall, where scrap gathers, to
##   rake at the floor with a claw, head down, kicking up dust, metal flecks and scrap, as if
##   after loose cable to feed on. Once in a while it slips into a floor vent and travels the
##   ducts to another. Seeing the robot within notice_radius for the first time, it
##   stands up to look at it.
## - WARY (the robot is within keep_distance): it keeps its distance, walking away, or running
##   when the robot is within run_distance or coming at it. Meanwhile it gets annoyed: the robot
##   being within pester_radius builds annoyance (faster when it's coming closer), and it fades
##   while the robot keeps away.
## - Warning: once annoyance is full, or it's cornered (no safe way away) with the robot within
##   warn_radius, it stands up tall facing the robot, jaw open, eyes hot: a warning. If the
##   robot backs off beyond warn_radius in time (warn_time), it drops back down, still wary and
##   half annoyed. If not, it turns HOSTILE. Cornered next to a vent, it escapes down the vent
##   instead.
## - HOSTILE: it only fights in self defence. Being hit by the robot (melee, a shot, the cannon)
##   turns it hostile at once, from any mood. It runs at the robot and attacks: a lunge (a low
##   leap with the claws out) from lunge_range, or a standing claw swipe up close. It lets the
##   robot go once the robot runs away (moving off beyond warn_radius for let_go_time, or past
##   keep_distance), or simply hasn't hit it for grudge_time; then it backs off, wary.
##
## Hurt (a heavy core): it's done fighting. It sparks and smokes, moves slower with a limp, never
## warns or attacks, and just gets away from the robot (down a vent if it's cornered by one);
## a hit only sends it running. Destroyed, it's a wreck on the floor (see Enemy).
##
## Scavenging: calm, it goes for any wreck within scavenge_reach, walks (and hops) over to it and
## rummages at it, eating it away (at most wreck_limit watchers on one wreck). A rabbit eating
## at its wreck is a thief: it goes for the rabbit (lunge, swipe) until the rabbit's been hit
## or driven guard_radius off, or chase_time is up, then goes back to eating. The two collide
## while they fight; everyone else passes through.
##
## Packs: watchers keep together. Calm, one that's strayed more than pack_spread from the others
## within pack_radius heads back to them. Hit by the robot, it calls the pack: every packmate
## within backup_radius that isn't hurt turns on the robot too (the same self defence rules let
## them all go again).
##
## Attacks use an AttackHitbox (red in SHOW HITBOXES). Hits do nothing yet: they're reported by
## the attack_landed signal, for combat to come.
##
## The body is drawn by the WatcherBotVisual child, which reads state, mood, facing and velocity.

## An attack touched the robot (attack is "lunge" or "swipe"). Nothing happens yet.
signal attack_landed(attack: StringName, victim: Node2D)

enum State { IDLE, WALK, RUN, WINDUP, AIR, LAND, STAND, WARN, LUNGE_WINDUP, LUNGE, SWIPE, RECOVER,
		RUMMAGE }
enum Mood { CALM, WARY, HOSTILE }

@export_group("Moving")
## Walking and running speeds, in metres per second (the robot walks at 3 and runs at 6).
@export var walk_speed: float = 1.1
@export var run_speed: float = 4.8
## Time to reach full speed, and to stop, in seconds.
@export var accel_time: float = 0.25
## Seconds of sitting between calm moves, and of walking in one go: random between x and y.
@export var idle_time := Vector2(1.0, 3.0)
@export var walk_time := Vector2(1.0, 3.0)
## Chance that a calm move is a string of hops, and hops in a string.
@export_range(0.0, 1.0, 0.05) var hop_chance: float = 0.35
@export var hop_chain := Vector2i(1, 3)
## Wandering hop height (m) and speed (m/s), and the highest hop for climbing.
@export var hop_height: float = 0.7
@export var hop_speed: float = 2.0
@export var max_hop_height: float = 2.2
## Deepest drop it will hop or step down, in metres.
@export var max_safe_drop: float = 3.0
@export var windup_time: float = 0.18
@export var land_time: float = 0.2

@export_group("Scouting")
## Chance, when a calm sit ends, to stand up and look around instead of moving.
@export_range(0.0, 1.0, 0.05) var scout_chance: float = 0.3
## Seconds standing up to scout: random between x and y.
@export var scout_time := Vector2(2.5, 4.5)
## Within this distance (m) it notices the robot, standing up to look at it the first time.
@export var notice_radius: float = 11.0

@export_group("Keeping away")
## It wants the robot farther than this (m), and runs (instead of walking) within run_distance
## or when the robot comes at it faster than approach_speed (m/s).
@export var keep_distance: float = 6.0
## Once wary, it keeps going until the robot is this much farther than keep_distance (m).
@export var calm_margin: float = 2.0
@export var run_distance: float = 3.5
@export var approach_speed: float = 1.5
## Within this distance the robot pesters it: annoyance fills in pester_time seconds (twice as
## fast while the robot comes closer), and empties in forgive_time once the robot keeps away.
@export var pester_radius: float = 4.5
@export var pester_time: float = 3.0
@export var forgive_time: float = 5.0
## The robot only counts within this vertical distance, in metres.
@export var vertical_reach: float = 3.5

@export_group("Warning")
## Cornered with the robot this close (m), it warns at once. The robot must be farther than
## this (plus back_off_margin) by the end of warn_time to call it off.
@export var warn_radius: float = 3.5
@export var back_off_margin: float = 1.0
@export var warn_time: float = 1.6

@export_group("Attacking")
## Lunge: from this distance (m), a leap of lunge_speed (m/s) and lunge_height (m).
@export var lunge_range := Vector2(1.6, 4.5)
@export var lunge_speed: float = 6.5
@export var lunge_height: float = 0.5
@export var lunge_windup: float = 0.35
## Swipe: within this distance (m), a standing claw swipe lasting swipe_time.
@export var swipe_range: float = 1.6
@export var swipe_time: float = 0.45
## After an attack it stays put this long, in seconds.
@export var recover_time: float = 0.6
## Damage an attack deals, for when combat exists.
@export var attack_damage: float = 1.0

@export_group("Self defence")
## Hostile, it gives up when the robot hasn't hit it for grudge_time seconds (a hit, or ignoring
## its warning, starts the grudge over), or when the robot has been running off, beyond
## warn_radius + back_off_margin, for let_go_time seconds, or is past keep_distance.
@export var grudge_time: float = 6.0
@export var let_go_time: float = 0.6

@export_group("Scavenging")
## Chance, when a calm sit ends, to go rummaging at the nearest wall within rummage_reach m (or,
## with no wall about, right where it is).
@export_range(0.0, 1.0, 0.05) var rummage_chance: float = 0.25
@export var rummage_reach: float = 12.0
@export var rummage_time := Vector2(2.5, 6.0)
## Chance, when a calm sit ends, to wander into a vent within vent_reach m and out of another.
@export_range(0.0, 1.0, 0.01) var calm_vent_chance: float = 0.05
@export var vent_reach: float = 10.0
## Wrecks within scavenge_reach (m) draw it, scavenge_chance of the times a calm sit ends; it
## eats at eat_rate (Enemy.wreck_material seconds of eating a wreck, at 1).
@export var scavenge_reach: float = 18.0
@export_range(0.0, 1.0, 0.05) var scavenge_chance: float = 0.8
@export var eat_rate: float = 1.0
@export var wreck_limit: int = 2
## A rabbit thief is chased for at most chase_time seconds, and let go once it's guard_radius (m)
## from the wreck.
@export var chase_time: float = 5.0
@export var guard_radius: float = 5.0

@export_group("Pack")
## Others within pack_radius (m) are its pack; it heads back to them once it's pack_spread (m)
## from their middle. Hit by the robot, packmates within backup_radius (m) join in.
@export var pack_radius: float = 24.0
@export var pack_spread: float = 5.0
@export var backup_radius: float = 9.0

@export_group("Hurt")
## With a heavy core it moves at this share of its usual speeds, and keeps this much farther
## away (m).
@export_range(0.1, 1.0, 0.05) var hurt_pace: float = 0.55
@export var hurt_extra_distance: float = 3.0

@export_group("Body")
## Hitbox on all fours and standing, in px. The bottom edge stays at the feet.
@export var quad_size := Vector2(12, 14)
@export var stand_size := Vector2(9, 30)

var state: State = State.AIR
var mood: Mood = Mood.CALM
var state_time: float = 0.0
## 0 to 1: how fed up it is with the robot.
var annoyance: float = 0.0
## True while it's standing up (scouting, warning, swiping): the visual unfolds it.
var standing: bool = false
## True while it's looking at the robot (noticed it, warning, hostile).
var watching: bool = false

var _state_length: float = 0.0
var _hops_left: int = 0
var _planned_hop := Vector2.ZERO
var _noticed: bool = false
## True while a scouting stand is looking at the robot.
var _scout_watch: bool = false
## The mood when the current state began.
var _move_mood: Mood = Mood.CALM
var _rng := RandomNumberGenerator.new()
var _hitbox: AttackHitbox
var _hitbox_shape: RectangleShape2D
var _attack_name: StringName = &""
## The rabbit it's chasing off its food, the wreck it's guarding, and seconds of chasing.
var prey: Enemy
var _guarding: Enemy
var _chase_left: float = 0.0
## Seconds of grudge left while hostile, and of the robot running off before letting it go.
var _grudge: float = 0.0
var _let_go_left: float = 0.0
## Walking to a rummage spot (RUMMAGE) or a vent (VENT), at _goal_x.
var _goal: StringName = &""
var _goal_x: float = 0.0
var _goal_vent: FloorVent
var _kick_left: float = 0.0
## Which side the wall is on while it rummages (-1, 1, or 0 in the open).
var rummage_wall: float = 0.0


func _ready() -> void:
	collision.shape = collision.shape.duplicate()
	super()
	_rng.randomize()
	facing = -1.0 if _rng.randf() < 0.5 else 1.0
	_set_body_size(quad_size)
	_hitbox = AttackHitbox.new()
	_hitbox.name = "AttackHitbox"
	_hitbox.attacker = self
	_hitbox.damage = attack_damage
	var shape := CollisionShape2D.new()
	_hitbox_shape = RectangleShape2D.new()
	shape.shape = _hitbox_shape
	_hitbox.add_child(shape)
	add_child(_hitbox)
	_hitbox.hit.connect(_on_attack_hit)
	hit_taken.connect(_on_hit_taken)
	core_changed.connect(_on_core_changed)
	resurfaced.connect(func() -> void: _sit(0.5))


func _physics_process(delta: float) -> void:
	if update_wreck(delta):
		return
	if update_underground(delta):
		return
	update_aggro(delta)
	state_time += delta
	_update_mood(delta)
	_update_prey(delta)
	match state:
		State.IDLE:
			_idle(delta)
		State.WALK, State.RUN:
			_move(delta)
		State.WINDUP:
			_brake(delta)
			if state_time >= _state_length:
				velocity = _planned_hop
				_set_state(State.AIR)
		State.LAND, State.RECOVER:
			_brake(delta)
			if state_time >= _state_length:
				_decide()
		State.STAND:
			_scout(delta)
		State.WARN:
			_warn(delta)
		State.LUNGE_WINDUP:
			_brake(delta)
			if target_alive():
				facing = _toward()
			if state_time >= _state_length:
				_launch_lunge()
		State.SWIPE:
			_swipe(delta)
		State.RUMMAGE:
			_rummage(delta)
		_:
			pass
	apply_gravity(delta)
	move_and_slide()
	slip_off_enemies()
	if state in [State.AIR, State.LUNGE] and is_on_floor() and state_time > 0.05:
		_end_attack()
		velocity.x = 0.0
		if state == State.LUNGE:
			_set_state(State.RECOVER, recover_time)
		else:
			_set_state(State.LAND, land_time)
	elif state not in [State.AIR, State.LUNGE] and not is_on_floor() and velocity.y > 30.0:
		_end_attack()
		_stand(false)
		_set_state(State.AIR)


func _set_state(new_state: State, length: float = 0.0) -> void:
	state = new_state
	_move_mood = mood
	state_time = 0.0
	_state_length = length


# --- Mood --------------------------------------------------------------------------------------


## Distance to the robot in px (INF when it doesn't count), and whether it's coming closer.
func _robot_distance() -> float:
	if not target_alive():
		return INF
	var to_robot := target_feet() - global_position
	if absf(to_robot.y) > vertical_reach * PX:
		return INF
	return absf(to_robot.x)


## True while the robot is moving away from it.
func _robot_leaving() -> bool:
	if not target_alive() or not (target is CharacterBody2D):
		return false
	var dir := signf(target_feet().x - global_position.x)
	return (target as CharacterBody2D).velocity.x * dir > 0.5 * PX


## Hit by the robot: packmates close by turn on it too.
func _call_pack() -> void:
	for mate in pack_mates(backup_radius * PX):
		var watcher := mate as WatcherBot
		if watcher == null or watcher.is_hurt() or watcher.is_hidden() or watcher.dead:
			continue
		if watcher.mood != Mood.HOSTILE:
			watcher._turn_hostile()
			if watcher.state in [State.IDLE, State.WALK, State.STAND, State.WARN, State.RUMMAGE,
					State.LAND, State.RUN]:
				watcher._hunt()


## Hurt badly: it stops whatever attack it was in and gets away.
func _on_core_changed(_stage: int) -> void:
	if not is_hurt():
		return
	_end_attack()
	if mood == Mood.HOSTILE:
		mood = Mood.WARY
	if state in [State.LUNGE_WINDUP, State.SWIPE, State.WARN, State.RUN, State.WALK, State.STAND,
			State.IDLE, State.RUMMAGE]:
		_decide()


func _on_death() -> void:
	_end_chase()
	_end_attack()
	_stand(false)
	standing = false


## Speed share: slower when hurt.
func _pace() -> float:
	return hurt_pace if is_hurt() else 1.0


## Where to stand to eat wreck: right beside it, on this side.
func _wreck_spot(wreck: Enemy) -> float:
	var side := signf(global_position.x - wreck.global_position.x)
	if side == 0.0:
		side = 1.0
	return wreck.global_position.x + side * (wreck.half_width() + half_width() + 1.0)


## Turns hostile (or stays it) with a fresh grudge.
func _turn_hostile() -> void:
	mood = Mood.HOSTILE
	annoyance = 1.0
	_grudge = grudge_time
	_let_go_left = let_go_time


## Stops fighting: it backs off, wary (and quickly forgiving, if the robot ran).
func _let_go(ran_off: bool) -> void:
	annoyance = 0.0 if ran_off else 0.35
	mood = Mood.WARY if _robot_distance() <= (keep_distance + calm_margin) * PX else Mood.CALM


## Hit by the robot (melee, a shot, the cannon): it fights back.
func _on_hit_taken(_damage: float, from: Node) -> void:
	if dead or is_underground() or not target_alive() or is_hurt():
		return
	if from != target and not (from != null and target.is_ancestor_of(from)):
		return
	var was := mood
	_turn_hostile()
	if was != Mood.HOSTILE:
		_call_pack()
	if was != Mood.HOSTILE and state in [State.IDLE, State.WALK, State.STAND, State.WARN,
			State.RUMMAGE, State.LAND]:
		_hunt()


func _robot_approaching() -> bool:
	if not target_alive() or not (target is CharacterBody2D):
		return false
	var dir := signf(global_position.x - target_feet().x)
	return (target as CharacterBody2D).velocity.x * dir > approach_speed * PX


func _update_mood(delta: float) -> void:
	var dist := _robot_distance()
	if is_hurt():
		# Done fighting: it only keeps away, further than usual, and never warns.
		watching = false
		annoyance = 0.0
		var far := (keep_distance + hurt_extra_distance) * PX
		if dist <= far:
			mood = Mood.WARY
		elif dist > far + calm_margin * PX:
			mood = Mood.CALM
		elif mood == Mood.HOSTILE:
			mood = Mood.WARY
		return
	watching = mood == Mood.HOSTILE or state == State.WARN or (state == State.STAND and _scout_watch)
	if mood == Mood.HOSTILE:
		if not target_alive():
			mood = Mood.CALM
			annoyance = 0.0
			return
		# Self defence only: let the robot go once it runs off, or leaves it be long enough.
		_grudge -= delta
		var ran_off := dist > keep_distance * PX \
				or (_robot_leaving() and dist > (warn_radius + back_off_margin) * PX)
		if ran_off:
			_let_go_left -= delta
		else:
			_let_go_left = let_go_time
		if _grudge <= 0.0 or _let_go_left <= 0.0:
			_let_go(ran_off)
		return
	if dist <= pester_radius * PX:
		var rate := 2.0 if _robot_approaching() else 1.0
		annoyance = minf(annoyance + rate * delta / maxf(pester_time, 0.01), 1.0)
	elif dist > keep_distance * PX:
		annoyance = maxf(annoyance - delta / maxf(forgive_time, 0.01), 0.0)
	# Wary within keep_distance, calm again only past keep_distance + calm_margin.
	if dist <= keep_distance * PX:
		mood = Mood.WARY
	elif dist > (keep_distance + calm_margin) * PX:
		mood = Mood.CALM
	if not _noticed and dist <= notice_radius * PX and state in [State.IDLE, State.WALK]:
		_noticed = true
		_start_scout(1.6, true)
	if dist > notice_radius * PX * 1.5:
		_noticed = false
	if state not in [State.WARN, State.AIR, State.WINDUP, State.LAND] and annoyance >= 1.0:
		_start_warning()


## Direction to the robot, and away from it.
func _toward() -> float:
	if mood == Mood.CALM and _prey_active():
		var px := prey.global_position.x - global_position.x
		return signf(px) if absf(px) > 0.5 else facing
	if not target_alive():
		return facing
	var dx := target_feet().x - global_position.x
	return signf(dx) if absf(dx) > 0.5 else facing


func _away() -> float:
	return -_toward()


# --- What to do next ---------------------------------------------------------------------------


## Picks the next action from the mood (after a landing, a recovery, a sit...).
func _decide() -> void:
	_stand(false)
	if mood == Mood.CALM and _goal != &"" and state == State.LAND:
		# Hopped up or down on the way somewhere: carry on.
		_set_state(State.WALK, 0.0)
		return
	_goal = &""
	eating = null
	if mood == Mood.CALM and _prey_active():
		# Still after a thief.
		facing = _toward()
		_set_state(State.RUN, 0.0)
		return
	match mood:
		Mood.HOSTILE:
			_hunt()
		Mood.WARY:
			_keep_away()
		_:
			if _hops_left > 0:
				_hops_left -= 1
				if _try_hop(facing, hop_height, hop_speed):
					return
				facing = -facing
			_sit()


func _sit(length: float = -1.0) -> void:
	eating = null
	_goal = &""
	if length < 0.0:
		length = _rng.randf_range(idle_time.x, idle_time.y)
	_set_state(State.IDLE, length)


func _idle(delta: float) -> void:
	_brake(delta)
	if mood != Mood.CALM:
		_decide()
		return
	if state_time < _state_length:
		return
	if _rng.randf() < scavenge_chance:
		var wreck := find_wreck(scavenge_reach * PX, wreck_limit)
		if wreck != null:
			eating = wreck
			_walk_to(&"wreck", _wreck_spot(wreck))
			return
	var roll := _rng.randf()
	if roll < scout_chance and not is_hurt():
		_start_scout(_rng.randf_range(scout_time.x, scout_time.y), false)
		return
	# Scavenging instead of moving on, now and then.
	var scavenge := _rng.randf()
	if scavenge < rummage_chance:
		var spot := find_rummage_spot(rummage_reach * PX)
		if spot.is_empty():
			_start_rummage(0.0)
		else:
			_walk_to(&"rummage", spot.x - spot.wall * (half_width() + 1.0))
			rummage_wall = spot.wall
		return
	if scavenge < rummage_chance + calm_vent_chance:
		var vent := find_vent(vent_reach * PX)
		if vent != null:
			_goal_vent = vent
			_walk_to(&"vent", vent.global_position.x)
			return
	var dir := -1.0 if _rng.randf() < 0.5 else 1.0
	var centre := pack_centre(pack_radius * PX)
	if _robot_distance() <= notice_radius * PX:
		# It knows the robot is around: wander away from it.
		dir = _away()
	elif not is_nan(centre) and absf(centre - global_position.x) > pack_spread * PX:
		# Strayed from the pack: back to it.
		dir = signf(centre - global_position.x)
	if roll < scout_chance + hop_chance * (1.0 - scout_chance):
		_hops_left = _rng.randi_range(hop_chain.x, hop_chain.y) - 1
		if _try_hop(dir, hop_height, hop_speed) or _try_hop(-dir, hop_height, hop_speed):
			return
		_sit()
		return
	facing = dir
	_set_state(State.WALK, _rng.randf_range(walk_time.x, walk_time.y))


## Moves away from the robot: walking, or running when it's close or coming at it. Cornered,
## it warns once the robot is within warn_radius.
func _keep_away() -> void:
	var dist := _robot_distance()
	var run := dist <= run_distance * PX or _robot_approaching()
	var dir := _away()
	if ledge_or_wall_ahead(dir):
		var speed := run_speed if run else hop_speed
		if _try_hop(dir, hop_height, speed):
			return
		# Cornered: down a vent right here, if there is one.
		var vent := find_vent(2.0 * PX)
		if vent != null:
			_enter_vent(vent, true)
			return
		# Otherwise face the robot and hold still until it comes too close (hurt, it just
		# cowers there).
		facing = _toward()
		if dist <= warn_radius * PX and not is_hurt():
			_start_warning()
		else:
			_sit(0.25)
		return
	facing = dir
	_set_state(State.RUN if run else State.WALK, 0.5)


func _move(delta: float) -> void:
	if mood != _move_mood:
		# The mood changed under it (the robot came close, or went away): think again.
		_decide()
		return
	if mood == Mood.HOSTILE and state == State.RUN:
		# Chasing: attack once in range.
		var dist := _robot_distance()
		facing = _toward()
		if dist <= swipe_range * PX:
			_start_swipe()
			return
		if dist <= lunge_range.y * PX and dist >= lunge_range.x * PX and _lunge_is_safe():
			_start_lunge()
			return
	elif mood == Mood.CALM and state == State.RUN and _prey_active():
		# Chasing a thief off its food.
		var gap := absf(prey.global_position.x - global_position.x)
		facing = _toward()
		if gap <= swipe_range * PX:
			_start_swipe()
			return
		if gap <= lunge_range.y * PX and gap >= lunge_range.x * PX and _lunge_is_safe():
			_start_lunge()
			return
	elif mood == Mood.CALM and state == State.RUN:
		# The thief got away (or it gave up): back to wandering.
		_sit(0.4)
		return
	elif mood == Mood.CALM and state == State.WALK:
		if _goal == &"wreck":
			if not is_instance_valid(eating) or eating.remains <= 0.0:
				_goal = &""
				eating = null
				_sit(0.5)
				return
			_goal_x = _wreck_spot(eating)
		if _goal != &"":
			var dx := _goal_x - global_position.x
			# There, or as near as it gets (a ledge, a wall, someone else in the corner).
			if absf(dx) <= 2.0 or (_goal in [&"rummage", &"wreck"] and absf(dx) <= 24.0
					and (is_on_wall() or ledge_or_wall_ahead(signf(dx)))):
				_arrive()
				return
			facing = signf(dx)
		elif state_time >= _state_length:
			_sit()
			return
	elif state_time >= _state_length:
		_decide()
		return
	var speed := (run_speed if state == State.RUN else walk_speed) * PX * _pace()
	if ledge_or_wall_ahead(facing):
		velocity.x = 0.0
		var hop_vel := run_speed if state == State.RUN else hop_speed
		if _try_hop(facing, hop_height, hop_vel):
			return
		if mood == Mood.CALM:
			_goal = &""
			facing = -facing
			_sit(0.5)
		elif mood == Mood.WARY:
			_keep_away()
		else:
			# Can't reach the robot from here: wait and watch.
			_sit(0.3)
		return
	var accel := run_speed * PX / maxf(accel_time, 0.01)
	velocity.x = move_toward(velocity.x, facing * speed, accel * delta)


func _walk_to(goal: StringName, x: float) -> void:
	_goal = goal
	_goal_x = x
	facing = signf(x - global_position.x) if absf(x - global_position.x) > 0.5 else facing
	_set_state(State.WALK, 0.0)


func _arrive() -> void:
	velocity.x = 0.0
	var goal := _goal
	_goal = &""
	if goal == &"wreck" and is_instance_valid(eating):
		var wreck := eating
		_start_rummage(signf(wreck.global_position.x - global_position.x))
		eating = wreck
		_state_length = 1000.0
	elif goal == &"rummage":
		_start_rummage(rummage_wall)
	elif goal == &"vent" and _goal_vent != null:
		_enter_vent(_goal_vent, false)
	else:
		_sit()


func _enter_vent(vent: FloorVent, away: bool) -> void:
	var exit := pick_exit_vent(vent, away)
	if exit == null:
		_sit(0.5)
		return
	_end_attack()
	_stand(false)
	start_vent(vent, exit)


## Rakes at the floor with a claw, head down, facing the wall (wall: -1 or 1) or ahead (0).
func _start_rummage(wall: float) -> void:
	velocity.x = 0.0
	_stand(false)
	if wall != 0.0:
		facing = wall
	_kick_left = 0.5
	_set_state(State.RUMMAGE, _rng.randf_range(rummage_time.x, rummage_time.y))


func _rummage(delta: float) -> void:
	_brake(delta)
	if mood != Mood.CALM:
		eating = null
		_decide()
		return
	if eating != null:
		# Tearing at a wreck until it's gone.
		if not is_instance_valid(eating) or eating.remains <= 0.0:
			eating = null
			_sit()
			return
		eating.consume(eat_rate * delta)
	_kick_left -= delta
	if _kick_left <= 0.0:
		# Each rake of the claw throws dirt back past it.
		_kick_left = _rng.randf_range(0.35, 0.8)
		ScrapDebris.kick(global_position + Vector2(facing * 9.0, 0.0), -facing,
				_rng.randf_range(0.6, 1.3))
	if state_time >= _state_length:
		_sit()


func _brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, run_speed * PX / maxf(accel_time, 0.01) * delta)


# --- Hops --------------------------------------------------------------------------------------


func _try_hop(dir: float, height: float, speed: float) -> bool:
	var heights: Array = [height, height * 0.6]
	heights.append_array(climb_heights(height * 1.5, max_hop_height))
	var speeds: Array = [speed * _pace(), speed * 0.65 * _pace(), speed * 0.4 * _pace()]
	var hop := find_safe_hop(dir, heights, speeds, max_safe_drop)
	if hop == Vector2.ZERO:
		return false
	facing = dir
	_planned_hop = hop
	_stand(false)
	_set_state(State.WINDUP, windup_time * (0.5 if speed > hop_speed else 1.0))
	return true


# --- Standing up -------------------------------------------------------------------------------


## Grows or shrinks the hitbox, keeping its bottom on the feet. Standing needs head room.
func _stand(up: bool) -> bool:
	if up == standing:
		return true
	if up:
		var test := global_transform.translated(Vector2(0.0, -1.0))
		if test_move(test, Vector2(0.0, -(stand_size.y - quad_size.y))):
			return false
	standing = up
	_set_body_size(stand_size if up else quad_size)
	return true


func _set_body_size(size: Vector2) -> void:
	var rect := collision.shape as RectangleShape2D
	rect.size = size
	collision.position = Vector2(0.0, -size.y * 0.5)


## Stands up to look around (or at the robot, when looking_at_robot).
func _start_scout(length: float, looking_at_robot: bool) -> void:
	velocity.x = 0.0
	if not _stand(true):
		_sit(0.5)
		return
	_scout_watch = looking_at_robot
	watching = looking_at_robot
	if looking_at_robot:
		facing = _toward()
	_set_state(State.STAND, length)


func _scout(delta: float) -> void:
	_brake(delta)
	if watching and target_alive():
		facing = _toward()
	if mood != Mood.CALM:
		# The robot came within keep_distance: stop looking and get away.
		_decide()
		return
	if state_time >= _state_length:
		_scout_watch = false
		_decide()


func _start_warning() -> void:
	velocity.x = 0.0
	_stand(true)
	facing = _toward()
	_set_state(State.WARN, warn_time)


func _warn(delta: float) -> void:
	_brake(delta)
	facing = _toward()
	var dist := _robot_distance()
	if dist > (warn_radius + back_off_margin) * PX:
		# The robot backed off: drop down, still wary.
		annoyance = 0.5
		_decide()
		return
	if state_time >= _state_length:
		_turn_hostile()
		_hunt()


# --- Attacks -----------------------------------------------------------------------------------


func _hunt() -> void:
	_stand(false)
	facing = _toward()
	_set_state(State.RUN, 0.0)


func _lunge_is_safe() -> bool:
	var vel := Vector2(facing * lunge_speed * PX, launch_speed(lunge_height * PX))
	var flight := predict_jump(vel, max_safe_drop * PX)
	return flight.landed


func _start_lunge() -> void:
	velocity.x = 0.0
	_stand(false)
	_set_state(State.LUNGE_WINDUP, lunge_windup)


func _launch_lunge() -> void:
	var vel := Vector2(facing * lunge_speed * PX, launch_speed(lunge_height * PX))
	if not predict_jump(vel, max_safe_drop * PX).landed:
		_set_state(State.RECOVER, 0.2)
		return
	velocity = vel
	_set_state(State.LUNGE)
	_begin_attack(&"lunge", Vector2(9.0, -8.0), Vector2(12.0, 8.0))


func _start_swipe() -> void:
	velocity.x = 0.0
	if not _stand(true):
		_stand(false)
	_set_state(State.SWIPE, swipe_time)


func _swipe(delta: float) -> void:
	_brake(delta)
	# The claws sweep through between 40% and 70% of the swipe.
	var t := state_time / maxf(swipe_time, 0.01)
	if t >= 0.4 and t < 0.7 and _attack_name == &"":
		_begin_attack(&"swipe", Vector2(15.0, -14.0), Vector2(24.0, 16.0))
	elif t >= 0.7:
		_end_attack()
	if state_time >= _state_length:
		_end_attack()
		_stand(false)
		_set_state(State.RECOVER, recover_time)


## Switches the attack hitbox on, centred at offset (px, x forward) with size.
func _begin_attack(attack: StringName, offset: Vector2, size: Vector2) -> void:
	_attack_name = attack
	# Only the robot, or the thief: never its packmates or anything else about.
	var victims: Array[Node] = []
	if target != null:
		victims.append(target)
	if mood == Mood.CALM and _prey_active():
		victims.append(prey)
	_hitbox.only = victims
	_hitbox_shape.size = size
	_hitbox.position = Vector2(offset.x * facing, offset.y)
	_hitbox.set_active(true)


func _end_attack() -> void:
	_attack_name = &""
	if _hitbox != null:
		_hitbox.set_active(false)


func _on_attack_hit(victim: Node2D) -> void:
	if victim == target:
		attack_landed.emit(_attack_name, victim)
	elif victim == prey:
		# Taught it a lesson: let it run.
		_chase_left = minf(_chase_left, 0.6)


# --- Thieves -------------------------------------------------------------------------------------


## True while it's chasing a rabbit off its food and the rabbit is still there to chase.
func _prey_active() -> bool:
	if prey == null or not is_instance_valid(prey) or prey.dead or prey.is_hidden():
		return false
	if absf(prey.global_position.y - global_position.y) > vertical_reach * PX:
		return false
	return _chase_left > 0.0


## Watches its wreck for rabbits eating it, and ends a chase that's run its course.
func _update_prey(delta: float) -> void:
	if prey != null:
		_chase_left -= delta
		var far := is_instance_valid(prey) and is_instance_valid(_guarding) \
				and absf(prey.global_position.x - _guarding.global_position.x) > guard_radius * PX
		if not _prey_active() or far:
			_end_chase()
		return
	if mood != Mood.CALM or is_hurt() or eating == null or not is_instance_valid(eating):
		return
	if state not in [State.RUMMAGE, State.WALK, State.IDLE]:
		return
	for node in get_tree().get_nodes_in_group(GROUP):
		var rabbit := node as RabbitBot
		if rabbit == null or rabbit.eating != eating or rabbit.is_hidden():
			continue
		if absf(rabbit.global_position.x - eating.global_position.x) <= guard_radius * PX:
			_start_chase(rabbit)
			return


func _start_chase(rabbit: Enemy) -> void:
	prey = rabbit
	_guarding = eating
	_chase_left = chase_time
	set_aggro(rabbit, true)
	_end_attack()
	_stand(false)
	_goal = &""
	facing = _toward()
	_set_state(State.RUN, 0.0)


func _end_chase() -> void:
	if prey != null and is_instance_valid(prey):
		set_aggro(prey, false)
	prey = null
	_guarding = null
	_chase_left = 0.0


## The attack currently swinging ("lunge", "swipe"), or empty.
func current_attack() -> StringName:
	return _attack_name
