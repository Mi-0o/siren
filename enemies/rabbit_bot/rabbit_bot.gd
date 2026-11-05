class_name RabbitBot
extends Enemy
## A scrawny little rabbit-like scavenger bot, about 14 px tall with its ears up. Harmless: it
## potters about and keeps away from the robot as best it can.
##
## Wandering: it sits for a while (idle_time), then creeps along (walk_time at walk_speed),
## does a short string of hops (hop_chain), or goes rummaging: to the nearest wall (where scrap
## gathers) to scratch at the floor for a while, nose down, kicking up dust, metal flecks and bits
## of scrap. Now and then it wanders into a floor vent and pops out of another. When the robot is
## near it prefers to wander away from it.
##
## Never falling to its death: before every hop it flies the hop through the level
## (Enemy.predict_jump) and only takes it if it lands on a floor no more than max_safe_drop
## below. Walking up to a ledge, it stops and either hops down or across (if a safe hop exists)
## or turns back. Walls are hopped onto when a hop up to max_hop_height clears them, otherwise
## it turns back too. It passes through other enemies (and they through it), unless it's
## fighting one (Enemy.set_aggro).
##
## Keeping away from the robot: once the robot is within notice_radius it freezes and watches
## it (ears up). Within flee_radius (larger when the robot comes at it) it runs: quick, long, low
## hops away, until the robot is beyond calm_radius. A watcher chasing it off its food is a
## threat just the same (the nearer of the two is the one it runs from), and a hit from one
## scares it badly. Its fear builds the longer it's chased: a bit
## scared, it makes for a vent ahead and escapes through the ducts. Cornered (no safe hop away),
## it cowers, trembling with its ears flat; if the robot comes within bolt_radius it leaps right
## over it when that's safe; and only when it's very scared and still cornered does it burrow into
## the floor and tunnel off to come up somewhere far from the robot.
##
## Hurt (a heavy core), it sparks and smokes, limps along slower and hops shorter and slower.
## Destroyed, it's a wreck on the floor (see Enemy). Calm, it goes for any wreck within
## scavenge_reach: it hops over to it and rummages at it, eating it away bit by bit.
##
## Packs: rabbits keep together. Calm, one that's strayed more than pack_spread from the others
## within pack_radius heads back to them, and they scavenge together (up to wreck_limit of them
## on one wreck). One that sees a threat and runs sets off every packmate within alarm_radius,
## which bolts from the same threat.
##
## The body is drawn by the RabbitBotVisual child, which reads state, facing and velocity.

enum State { IDLE, WALK, WINDUP, AIR, LAND, COWER, RUMMAGE }
## What a hop is for, which decides the hops tried first.
enum HopStyle { WANDER, FLEE }
## Where a walk is heading.
enum Goal { NONE, RUMMAGE, VENT, WRECK }

@export_group("Wandering")
## Creeping speed, in metres per second.
@export var walk_speed: float = 0.8
## Seconds of sitting between moves: random between x and y.
@export var idle_time := Vector2(0.8, 2.6)
## Seconds of creeping in one go: random between x and y.
@export var walk_time := Vector2(0.6, 2.0)
## Chance that a move is a string of hops rather than a creep.
@export_range(0.0, 1.0, 0.05) var hop_chance: float = 0.55
## Hops in a string: random between x and y.
@export var hop_chain := Vector2i(1, 3)

@export_group("Hops")
## Height and forward speed of a wandering hop, in metres and metres per second.
@export var hop_height: float = 0.55
@export var hop_speed: float = 1.5
## Height and forward speed of a fleeing hop: low and long, quicker than the robot walks (3 m/s)
## and slower than it runs (6 m/s).
@export var flee_hop_height: float = 0.5
@export var flee_hop_speed: float = 4.2
## Highest hop, in metres, for getting up onto steps and ledges.
@export var max_hop_height: float = 1.9
## Deepest drop it will hop or step down, in metres. Anything deeper counts as deadly.
@export var max_safe_drop: float = 2.5
## Crouch before a hop, and squat after landing, in seconds.
@export var windup_time: float = 0.14
@export var flee_windup_time: float = 0.06
@export var land_time: float = 0.16
@export var flee_land_time: float = 0.05

@export_group("Wariness")
## Within this distance (metres) it notices the robot: it freezes and watches it.
@export var notice_radius: float = 7.0
## Within this distance it runs. Multiplied by approach_factor when the robot comes at it.
@export var flee_radius: float = 4.0
@export var approach_factor: float = 1.5
## Robot speed towards it (m/s) that counts as coming at it.
@export var approach_speed: float = 1.0
## It calms down once the robot is farther than this.
@export var calm_radius: float = 9.0
## The robot only counts within this vertical distance, in metres.
@export var vertical_reach: float = 3.0
## Cornered, it leaps right over the robot when the robot gets within bolt_radius (metres),
## if the landing on the far side is safe.
@export var bolt_when_cornered: bool = true
@export var bolt_radius: float = 2.5

@export_group("Fear")
## Fear builds by 1 a second while it's running from the robot, and fades by fear_decay a
## second otherwise. With fear of vent_fear or more it runs for a vent ahead of it (within
## vent_reach m). Only very scared (burrow_fear) and cornered (cowering burrow_cower_time
## seconds) does it burrow into the floor and tunnel away, coming up between burrow_range.x and
## burrow_range.y metres off, at least burrow_avoid metres from the robot.
@export var fear_decay: float = 0.25
@export var vent_fear: float = 1.5
@export var vent_reach: float = 8.0
@export var burrow_fear: float = 5.0
@export var burrow_cower_time: float = 0.6
@export var burrow_range := Vector2(5.0, 15.0)
@export var burrow_avoid: float = 6.0

@export_group("Pack")
## Others within pack_radius (m) are its pack; it heads back to them once it's pack_spread (m)
## from their middle. A packmate running scared within alarm_radius (m) sets it running.
@export var pack_radius: float = 18.0
@export var pack_spread: float = 3.0
@export var alarm_radius: float = 6.0

@export_group("Scavenging")
## At most this many rabbits eat one wreck.
@export var wreck_limit: int = 5
## Wrecks within scavenge_reach (m) draw it, scavenge_chance of the times a calm sit ends; it
## eats at eat_rate (Enemy.wreck_material seconds of eating a wreck, at 1).
@export var scavenge_reach: float = 16.0
@export_range(0.0, 1.0, 0.05) var scavenge_chance: float = 0.85
@export var eat_rate: float = 0.6
## Hurt (heavy core), it moves at this share of its usual speeds.
@export_range(0.1, 1.0, 0.05) var hurt_pace: float = 0.6
## Chance, when a calm sit ends, to go rummaging: at the nearest wall within rummage_reach m,
## or (rarely, rummage_open_chance of those times) right where it is.
@export_range(0.0, 1.0, 0.05) var rummage_chance: float = 0.3
@export var rummage_reach: float = 10.0
@export_range(0.0, 1.0, 0.05) var rummage_open_chance: float = 0.25
## Seconds of rummaging: random between x and y.
@export var rummage_time := Vector2(2.0, 5.0)
## Chance, when a calm sit ends, to wander into a vent within vent_reach and pop out of another.
@export_range(0.0, 1.0, 0.01) var calm_vent_chance: float = 0.05

var state: State = State.AIR
## Seconds spent in the current state.
var state_time: float = 0.0
## True while it is running from the robot.
var fleeing: bool = false
## True while it has noticed the robot (watching it, or running).
var alert: bool = false
## How scared it is: seconds of being chased, give or take (see the Fear group).
var fear: float = 0.0
## What it's running from: the robot, or a watcher chasing it. null when there's nothing.
var threat: Node2D
## True while it's running from a threat it sensed itself (that's what alarms the pack).
var spooked: bool = false
## Which side the wall is on while it rummages (-1, 1, or 0 in the open).
var rummage_wall: float = 0.0

var _state_length: float = 0.0
var _hops_left: int = 0
var _planned_hop := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
## Seconds until the next check for a way out while cowering.
var _cower_check: float = 0.0
var _goal: Goal = Goal.NONE
var _goal_x: float = 0.0
var _goal_vent: FloorVent
var _kick_left: float = 0.0
var _eat_offset: float = 0.0
## Seconds left backing off for a run-up at a wall, and run-ups tried.
var _run_up: float = 0.0
var _run_ups: int = 0


func _ready() -> void:
	super()
	_rng.randomize()
	facing = -1.0 if _rng.randf() < 0.5 else 1.0
	resurfaced.connect(_on_resurfaced)
	hit_taken.connect(_on_hit)


func _physics_process(delta: float) -> void:
	if update_wreck(delta):
		return
	if update_underground(delta):
		return
	update_aggro(delta)
	state_time += delta
	_update_wariness(delta)
	match state:
		State.IDLE:
			_idle()
		State.WALK:
			_walk()
		State.WINDUP:
			velocity.x = 0.0
			if state_time >= _state_length:
				velocity = _planned_hop
				_set_state(State.AIR)
		State.AIR:
			pass
		State.LAND:
			velocity.x = 0.0
			if state_time >= _state_length:
				_next_move()
		State.COWER:
			_cower(delta)
		State.RUMMAGE:
			_rummage(delta)
	apply_gravity(delta)
	move_and_slide()
	slip_off_enemies()
	if state == State.AIR and is_on_floor() and state_time > 0.05:
		velocity.x = 0.0
		_set_state(State.LAND, flee_land_time if fleeing else land_time)
	elif state in [State.IDLE, State.WALK, State.COWER, State.RUMMAGE] and not is_on_floor():
		# Lost the floor (it moved away, or a spawn in mid-air): just fall.
		_set_state(State.AIR)


func _set_state(new_state: State, length: float = 0.0) -> void:
	if new_state not in [State.WALK, State.RUMMAGE, State.WINDUP, State.AIR, State.LAND] \
			or fleeing:
		eating = null
	state = new_state
	state_time = 0.0
	_state_length = length


func _on_resurfaced() -> void:
	# Out of the ground or a vent: it's got away, for now.
	fear = minf(fear, vent_fear * 0.5)
	_goal = Goal.NONE
	_sit(0.4)


# --- The robot ---------------------------------------------------------------------------------


## Notices, flees from and calms down about its threat; fear builds while it runs. A spooked
## packmate nearby sets it running too.
func _update_wariness(delta: float) -> void:
	if fleeing:
		fear += delta
	else:
		fear = maxf(fear - fear_decay * delta, 0.0)
	_pick_threat()
	if threat == null:
		fleeing = false
		alert = false
	else:
		var to_threat := _threat_feet() - global_position
		var dist := absf(to_threat.x)
		if absf(to_threat.y) > vertical_reach * PX:
			dist = INF
		var run_radius := flee_radius * PX
		var threat_vx: float = (threat as CharacterBody2D).velocity.x \
				if threat is CharacterBody2D else 0.0
		if -signf(to_threat.x) * threat_vx > approach_speed * PX:
			run_radius *= approach_factor
		if threat != target:
			# A watcher after it: run as soon as it comes.
			run_radius = maxf(run_radius, notice_radius * PX)
		if dist <= run_radius:
			fleeing = true
		elif dist > calm_radius * PX:
			fleeing = false
		alert = fleeing or dist <= notice_radius * PX
	spooked = fleeing
	if fleeing:
		return
	# The pack: a packmate bolting nearby sets it off, from the same threat.
	for mate in pack_mates(alarm_radius * PX):
		var rabbit := mate as RabbitBot
		if rabbit != null and rabbit.spooked and is_instance_valid(rabbit.threat):
			threat = rabbit.threat
			fleeing = true
			alert = true
			return


## The nearer of the robot and any watcher fighting it.
func _pick_threat() -> void:
	threat = null
	var best := INF
	if target_alive():
		threat = target
		best = absf(target_feet().x - global_position.x)
	for foe in foes:
		if foe is WatcherBot and is_instance_valid(foe) and not foe.dead:
			var d := absf(foe.global_position.x - global_position.x)
			if d < best:
				best = d
				threat = foe


func _threat_ok() -> bool:
	return threat != null and is_instance_valid(threat)


## The threat's feet (the robot's are below its middle).
func _threat_feet() -> Vector2:
	return target_feet() if threat == target else threat.global_position


## Hit by a watcher (it got caught on the watcher's food): badly scared.
func _on_hit(_damage: float, from: Node) -> void:
	if from is WatcherBot:
		fear += 2.0


## Direction away from the threat (or the way it faces with none).
func _away() -> float:
	if not _threat_ok():
		return facing
	var dx := global_position.x - _threat_feet().x
	if absf(dx) < 0.5:
		return facing
	return signf(dx)


# --- States ------------------------------------------------------------------------------------


func _idle() -> void:
	velocity.x = 0.0
	if fleeing:
		_flee()
		return
	if alert:
		# Freeze and watch the robot.
		_goal = Goal.NONE
		facing = -_away()
		if state_time >= _state_length:
			state_time = _state_length - 0.3
		return
	if state_time >= _state_length:
		_start_wander()


func _walk() -> void:
	if fleeing:
		_flee()
		return
	if alert and _goal != Goal.NONE:
		_goal = Goal.NONE
		_sit()
		return
	if _goal == Goal.WRECK:
		if not is_instance_valid(eating) or eating.remains <= 0.0:
			_goal = Goal.NONE
			_sit(0.5)
			return
		_goal_x = _wreck_spot(eating)
	if _goal != Goal.NONE and _run_up > 0.0:
		# Backing off from a wall for a run-up at it.
		_run_up -= get_physics_process_delta_time()
		velocity.x = facing * walk_speed * _pace() * PX
		if ledge_or_wall_ahead(facing):
			_run_up = 0.0
		return
	if _goal != Goal.NONE:
		var dx := _goal_x - global_position.x
		if absf(dx) <= 2.0 or (_goal in [Goal.RUMMAGE, Goal.WRECK] and is_on_wall()
				and absf(dx) <= 16.0):
			_arrive()
			return
		facing = signf(dx)
	elif state_time >= _state_length:
		_sit()
		return
	velocity.x = facing * walk_speed * _pace() * PX
	if _goal != Goal.NONE and absf(_goal_x - global_position.x) > 12.0 \
			and is_blocked(facing * 8.0) and _try_hop_over(facing):
		# Heading somewhere with a wall in the way: hop it from a little way off, while
		# there's room to.
		return
	if ledge_or_wall_ahead(facing):
		velocity.x = 0.0
		if _goal in [Goal.RUMMAGE, Goal.WRECK] and absf(_goal_x - global_position.x) <= 8.0:
			_arrive()
			return
		# Hop on (down, across or up) if that's safe, or turn back.
		var walled := is_blocked(facing * 2.0)
		if (_goal == Goal.NONE or not walled) and _try_hop(facing, HopStyle.WANDER):
			return
		if _goal != Goal.NONE and walled:
			if _try_hop_over(facing):
				return
			if _run_ups < 2:
				# Too close to the wall to hop it: back off a little and try again.
				_run_ups += 1
				facing = -facing
				_run_up = 0.35
				return
		_run_ups = 0
		_goal = Goal.NONE
		facing = -facing
		_sit(0.4)


## A hop that gets over (or up onto) the wall ahead, not one that just bumps back down short
## of it.
func _try_hop_over(dir: float) -> bool:
	var hop := _plan_hop(dir, HopStyle.WANDER)
	if hop == Vector2.ZERO:
		return false
	var flight := predict_jump(hop, max_safe_drop * PX)
	var gain := ((flight.position as Vector2).x - global_position.x) * dir
	if gain < 6.0 and (flight.position as Vector2).y > global_position.y - 2.0:
		return false
	_take_hop(dir, hop, HopStyle.WANDER)
	return true


## Reached where it was walking to: start rummaging, or go into the vent.
func _arrive() -> void:
	velocity.x = 0.0
	_run_ups = 0
	match _goal:
		Goal.RUMMAGE:
			_goal = Goal.NONE
			_start_rummage(rummage_wall)
		Goal.VENT:
			_goal = Goal.NONE
			_enter_vent(_goal_vent, false)
		Goal.WRECK:
			_goal = Goal.NONE
			var wreck := eating
			_start_rummage(signf(wreck.global_position.x - global_position.x))
			eating = wreck
			_state_length = 1000.0


func _cower(delta: float) -> void:
	velocity.x = 0.0
	if not fleeing:
		_sit()
		return
	facing = _away()
	_cower_check -= delta
	if _cower_check > 0.0:
		return
	_cower_check = 0.25
	if _try_hop(_away(), HopStyle.FLEE):
		return
	# A vent close by, on its side of the robot?
	var vent := find_vent(3.0 * PX)
	if vent != null and fear >= vent_fear and _robot_not_between(vent.global_position.x):
		_enter_vent(vent, true)
		return
	if _threat_ok() and threat == target and bolt_when_cornered:
		var gap := absf(target_feet().x - global_position.x)
		if gap <= bolt_radius * PX and _try_bolt_over():
			return
	# The last resort: very scared and still cornered, it digs.
	if fear >= burrow_fear and state_time >= burrow_cower_time:
		var exit := find_burrow_exit(burrow_range.x * PX, burrow_range.y * PX, burrow_avoid * PX)
		if exit != Vector2.INF:
			start_burrow(exit)


func _robot_not_between(x: float) -> bool:
	if not _threat_ok():
		return true
	var robot_x := _threat_feet().x
	return signf(x - global_position.x) != signf(robot_x - global_position.x) \
			or absf(x - global_position.x) < absf(robot_x - global_position.x) - 12.0


## Runs: for a vent ahead if it's scared enough, else the next hop away from the robot, or
## cowering when there's no safe one.
func _flee() -> void:
	var away := _away()
	if fear >= vent_fear:
		var vent := find_vent(vent_reach * PX, away)
		if vent != null and _robot_not_between(vent.global_position.x):
			var dx := vent.global_position.x - global_position.x
			if absf(dx) <= 6.0:
				_enter_vent(vent, true)
				return
			# Hop towards it, short of overshooting.
			var hop := _plan_hop(signf(dx), HopStyle.FLEE, absf(dx) + 4.0)
			if hop != Vector2.ZERO:
				_take_hop(signf(dx), hop, HopStyle.FLEE)
				return
	if _try_hop(away, HopStyle.FLEE):
		return
	facing = away
	_cower_check = 0.0
	_set_state(State.COWER)


func _enter_vent(vent: FloorVent, scared: bool) -> void:
	var exit := pick_exit_vent(vent, scared)
	if exit == null:
		_sit(0.3)
		return
	start_vent(vent, exit)


## What to do after a landing.
func _next_move() -> void:
	if fleeing:
		_flee()
	elif _goal != Goal.NONE:
		_set_state(State.WALK, 0.0)
	elif _hops_left > 0:
		_hops_left -= 1
		if not _try_hop(facing, HopStyle.WANDER):
			facing = -facing
			_sit(0.4)
	else:
		_sit()


func _sit(length: float = -1.0) -> void:
	if length < 0.0:
		length = _rng.randf_range(idle_time.x, idle_time.y)
	_set_state(State.IDLE, length)


## Where to stand to eat wreck: right beside it, on this side.
func _wreck_spot(wreck: Enemy) -> float:
	var side := signf(global_position.x - wreck.global_position.x)
	if side == 0.0:
		side = 1.0
	return wreck.global_position.x + side * (wreck.half_width() + half_width() + 1.0 + _eat_offset)


## Speed share: slower when hurt.
func _pace() -> float:
	return hurt_pace if is_hurt() else 1.0


func _start_wander() -> void:
	if _rng.randf() < scavenge_chance:
		var wreck := find_wreck(scavenge_reach * PX, wreck_limit)
		if wreck != null:
			eating = wreck
			# Spread out round it with the rest of the pack.
			_eat_offset = _rng.randf_range(0.0, 8.0)
			_goal = Goal.WRECK
			_goal_x = _wreck_spot(wreck)
			_set_state(State.WALK, 0.0)
			return
	var roll := _rng.randf()
	var strayed := absf(pack_centre(pack_radius * PX) - global_position.x) > pack_spread * PX \
			if not is_nan(pack_centre(pack_radius * PX)) else false
	if strayed:
		roll = 1.0
	if roll < rummage_chance:
		var spot := find_rummage_spot(rummage_reach * PX)
		if not spot.is_empty():
			_goal = Goal.RUMMAGE
			_goal_x = spot.x - spot.wall * (half_width() + 1.0)
			rummage_wall = spot.wall
			_set_state(State.WALK, 0.0)
			return
		if _rng.randf() < rummage_open_chance:
			_start_rummage(0.0)
			return
	elif roll < rummage_chance + calm_vent_chance:
		var vent := find_vent(vent_reach * PX)
		if vent != null:
			_goal = Goal.VENT
			_goal_vent = vent
			_goal_x = vent.global_position.x
			_set_state(State.WALK, 0.0)
			return
	var dir := -1.0 if _rng.randf() < 0.5 else 1.0
	var centre := pack_centre(pack_radius * PX)
	if alert:
		dir = _away()
	elif not is_nan(centre) and absf(centre - global_position.x) > pack_spread * PX:
		# Strayed from the pack: back to it.
		dir = signf(centre - global_position.x)
	if _rng.randf() < hop_chance:
		_hops_left = _rng.randi_range(hop_chain.x, hop_chain.y) - 1
		if _try_hop(dir, HopStyle.WANDER) or _try_hop(-dir, HopStyle.WANDER):
			return
		_sit()
		return
	facing = dir
	_set_state(State.WALK, _rng.randf_range(walk_time.x, walk_time.y))


# --- Rummaging ---------------------------------------------------------------------------------


## Scratches at the floor, facing the wall (wall: -1 or 1) or wherever it faces (0).
func _start_rummage(wall: float) -> void:
	rummage_wall = wall
	if wall != 0.0:
		facing = wall
	_kick_left = 0.3
	_set_state(State.RUMMAGE, _rng.randf_range(rummage_time.x, rummage_time.y))


func _rummage(delta: float) -> void:
	velocity.x = 0.0
	if alert or fleeing:
		_sit(0.2)
		return
	if eating != null:
		# Gnawing at a wreck until it's gone (or something else takes it).
		if not is_instance_valid(eating) or eating.remains <= 0.0:
			eating = null
			_sit()
			return
		eating.consume(eat_rate * delta)
	_kick_left -= delta
	if _kick_left <= 0.0:
		_kick_left = _rng.randf_range(0.2, 0.5)
		# Scraped out from under it, backwards between its legs.
		ScrapDebris.kick(global_position + Vector2(facing * 4.0, 0.0), -facing,
				_rng.randf_range(0.4, 0.9))
	if state_time >= _state_length:
		_sit()


# --- Hops --------------------------------------------------------------------------------------


## Picks a safe hop in direction dir and crouches for it. False when there's none.
func _try_hop(dir: float, style: HopStyle) -> bool:
	var hop := _plan_hop(dir, style)
	if hop == Vector2.ZERO:
		return false
	_take_hop(dir, hop, style)
	return true


func _take_hop(dir: float, hop: Vector2, style: HopStyle) -> void:
	facing = dir
	_planned_hop = hop
	_set_state(State.WINDUP, flee_windup_time if style == HopStyle.FLEE else windup_time)


## The launch velocity of a safe hop in direction dir, or ZERO. Tries the style's usual hop
## first, then shorter ones, then higher ones (to get up onto things). A flee hop takes the
## one that gets farthest (up to max_reach px).
func _plan_hop(dir: float, style: HopStyle, max_reach: float = INF) -> Vector2:
	var heights: Array = []
	var speeds: Array = []
	if style == HopStyle.FLEE:
		heights = [flee_hop_height, flee_hop_height * 0.6]
		speeds = [flee_hop_speed, flee_hop_speed * 0.7, flee_hop_speed * 0.45, hop_speed * 0.5]
	else:
		heights = [hop_height, hop_height * 0.6]
		speeds = [hop_speed, hop_speed * 0.6, hop_speed * 0.35]
	if is_hurt():
		for i in speeds.size():
			speeds[i] *= _pace()
		for i in heights.size():
			heights[i] *= 0.8
	heights.append_array(climb_heights(maxf(hop_height, flee_hop_height) * 1.6, max_hop_height))
	if max_reach < INF:
		# Short of a spot: try slower and slower until one falls short of it.
		for height: float in heights:
			for speed: float in [flee_hop_speed, flee_hop_speed * 0.7, hop_speed, hop_speed * 0.5]:
				var vel := Vector2(dir * speed * PX, launch_speed(height * PX))
				var flight := predict_jump(vel, max_safe_drop * PX)
				if flight.landed and ((flight.position as Vector2).x - global_position.x) * dir <= max_reach:
					return vel
		return Vector2.ZERO
	return find_safe_hop(dir, heights, speeds, max_safe_drop, style == HopStyle.FLEE)


## Cornered: a leap right over the robot's head, landing safely on its far side.
func _try_bolt_over() -> bool:
	var dir := -_away()
	var robot_x := target_feet().x
	var gap := absf(robot_x - global_position.x)
	# How high it must be to clear the robot's head (its origin is its middle), and how far
	# either side of the robot (its half width plus its own).
	var head_y := target.global_position.y * 2.0 - target_feet().y
	var top := global_position.y - head_y + 3.0
	var reach := 7.0 + half_width() + 1.0
	for height: float in [2.8, 3.2, 3.6]:
		var vy := launch_speed(height * PX)
		var apex_t := -vy / _gravity_px
		for k: float in [1.0, 1.2, 0.85]:
			# Over the robot around the top of the leap, landing as far past it.
			var vx := maxf(gap, 18.0) / apex_t * k
			var ok := true
			for x: float in [gap - reach, gap + reach]:
				if x <= 0.0:
					ok = false
					break
				var t := x / vx
				if -vy * t - 0.5 * _gravity_px * t * t < top:
					ok = false
					break
			if not ok:
				continue
			var vel := Vector2(dir * vx, vy)
			var flight := predict_jump(vel, max_safe_drop * PX, 4.0)
			if flight.landed and ((flight.position as Vector2).x - robot_x) * dir >= reach:
				_take_hop(dir, vel, HopStyle.FLEE)
				return true
	return false
