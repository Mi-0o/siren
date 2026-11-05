class_name Enemy
extends CharacterBody2D
## Base for every enemy. It holds what all of them share, so each enemy script only adds its
## own behaviour:
## - Physics: the same gravity and world scale as the robot (Player.PIXELS_PER_METER), with the
##   body's origin at its feet. Enemies sit on their own physics layer (ENEMY_LAYER) and collide
##   with the world and the robot (the robot shoves them, by weight), but pass through each
##   other, except two enemies fighting each other (set_aggro()), which collide. Their senses
##   (rays, shape probes) only look at the world. Attack hitboxes look at every layer.
## - The target: the robot it reacts to, found in the scene on its own (or set by a spawner).
## - Senses: ground_depth() for ledges, is_blocked() for walls, and predict_jump(), which flies a
##   jump through the level before it's taken and says where (and whether) it lands.
## - Hooks for systems to come: take_hit() and the hit_taken and died signals. Nothing deals
##   damage to enemies yet.
## - Going under the floor: burrowing (dig in, tunnel along, dig out somewhere else) and floor
##   vents (squeeze in, travel the duct, come out of another vent). While under, the enemy is
##   hidden, doesn't collide, isn't in GROUP (so nothing aims at it) but in UNDER_GROUP, and moves
##   along at its underground speed. Subclasses call update_underground() first thing each
##   physics frame and skip their own brain while it returns true. Visuals read sink (px the body
##   has gone into the floor) to draw it going in and coming out.
## - Packs: pack_centre() finds where the others of its kind nearby are, to keep together.
## - Rummaging: find_rummage_spot() finds the nearest spot against a wall, where scrap gathers.
## - Hurt and dead: at a heavy core (is_hurt()) it sparks and smokes (WreckFx) and subclasses
##   slow down and act hurt. At fault it dies (die()) but stays as a wreck (is_wreck): lying on
##   the floor, the eye out, no collision with anything but the level, not in GROUP. It smokes
##   and sparks for wreck_smoke_time seconds, then goes cold. After wreck_linger seconds it's
##   removed, but only while off screen. Other enemies scavenge wrecks (find_wreck()): they
##   rummage at them and eat them away (consume()), and an eaten-up wreck is gone.
## - Clean-up: an enemy that has been falling for despawn_fall_time seconds has left the level
##   and is removed.
##
## Every enemy is in the "enemies" group (GROUP), which the dev menu uses to clear them.

## Emitted by take_hit(), for whatever reacts to hits later (health, effects, AI).
signal hit_taken(damage: float, from: Node)
## Emitted when a hit pushes the core to a new stage (0 healthy to 3 fault).
signal core_changed(stage: int)
## Emitted when the enemy is gone for good (die(), or falling out of the level).
signal died
## Emitted when it has gone under the floor (burrowed or into a vent), and when it's back up.
signal went_under
signal resurfaced

const GROUP: StringName = &"enemies"
## Enemies under the floor (out of GROUP meanwhile).
const UNDER_GROUP: StringName = &"enemies_under"
## Wrecks (dead enemies still lying about).
const WRECK_GROUP: StringName = &"enemy_wrecks"

enum Under { NONE, DIGGING, TUNNELLING, EMERGING, VENT_IN, DUCT, VENT_OUT }
## Physics layer 3: enemies. They collide with layer 1 (the level) only.
const ENEMY_LAYER: int = 1 << 2
## Extra layer for enemies fighting another enemy: foes collide through it (and everyone else
## fighting is kept out with collision exceptions).
const AGGRO_LAYER: int = 1 << 3
const WORLD_MASK: int = 1
const PX: float = Player.PIXELS_PER_METER
## Fallback gravity (m/s²) when there's no robot to copy it from.
const DEFAULT_GRAVITY: float = 4.0
## Time step for predict_jump's flight, in seconds.
const PREDICT_STEP: float = 1.0 / 30.0
## A landing spot needs floor this far (px) either side of the body's middle.
const FOOTING_HALF: float = 2.0

@export_group("Physics")
## Weight in kg (the robot is 150). The wire reels in anything lighter than its drag weight (200)
## to the robot, faster the lighter it is; anything heavier is an anchor the robot pulls itself
## to.
@export var weight: float = 50.0
## How hard it is to damage, against an attack's damage (see CoreDamage). The robot is 48.
@export var resistance: float = 20.0
## Multiplies the robot's gravity, so enemies fall the way it does.
@export var gravity_scale: float = 1.0
## Fastest fall, in metres per second.
@export var max_fall_speed: float = 14.0
## Seconds of falling after which the enemy counts as lost (fallen out of the level) and is
## removed.
@export var despawn_fall_time: float = 4.0

## Who the enemy reacts to: the robot. Found on its own when left empty.
var target: Node2D
## 1 facing right, -1 facing left.
var facing: float = 1.0
var dead: bool = false
## True while the robot's wire is stuck in it. It doesn't count as falling meanwhile (dangling
## from the wire won't despawn it).
var wire_held: bool = false
## Core damage stage and the hits counting towards the next.
var core := CoreDamage.new()

@export_group("Wreck")
## Seconds a wreck smokes and sparks before it goes cold, and lies about (at least) before it's
## cleared away, out of sight.
@export var wreck_smoke_time: float = 14.0
@export var wreck_linger: float = 60.0
## How much there is to eat: seconds of one scavenger eating at a rate of 1.
@export var wreck_material: float = 12.0

## Seconds since it died.
var dead_time: float = 0.0
## What's left of the wreck to eat, 1 (whole) to 0 (eaten up).
var remains: float = 1.0

@export_group("Underground")
## Seconds to dig into the floor, and to dig back out.
@export var dig_time: float = 1.0
@export var emerge_time: float = 0.7
## Seconds to squeeze into a vent, and out of one.
@export var vent_in_time: float = 0.8
@export var vent_out_time: float = 0.6
## Speed while tunnelling, and along vent ducts, in metres per second.
@export var tunnel_speed: float = 2.0
@export var duct_speed: float = 3.0
## How tall the body is when drawn, in px (how far it sinks to be fully under).
@export var body_height: float = 14.0

## Where it is under the floor (Under.NONE when it isn't).
var under: Under = Under.NONE
## Seconds into the current underground step.
var under_time: float = 0.0
## How far the body has sunk into the floor, in px (0 up, body_height fully under).
var sink: float = 0.0

var _under_length: float = 0.0
var _under_from := Vector2.ZERO
var _under_to := Vector2.ZERO
var _vent_in: FloorVent
var _vent_out: FloorVent
var _layer_before: int = 0
var _mask_before: int = 0
var _aggro_refresh: float = 0.0
## Enemies it's fighting (they collide with it).
var foes: Array[Enemy] = []
var _debris_left: float = 0.0

## Gravity in px/s².
var _gravity_px: float = DEFAULT_GRAVITY * PX
var _fall_time: float = 0.0
var _ray := PhysicsRayQueryParameters2D.new()
var _shape_query := PhysicsShapeQueryParameters2D.new()

@onready var collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = ENEMY_LAYER
	# The level and the robot (both on layer 1). Other enemies are passed through, unless
	# they're fighting (set_aggro()). Senses only look at the level.
	collision_mask = WORLD_MASK
	floor_snap_length = 3.0
	# Dev view: the core light (SHOW HEALTH), a little above the top of the body.
	var light := CoreLight.new()
	light.height = _core_light_height()
	add_child(light)
	add_child(WreckFx.new())
	if target == null:
		target = find_target()
	var world_gravity := DEFAULT_GRAVITY
	if target is Player:
		world_gravity = (target as Player).gravity
	_gravity_px = world_gravity * gravity_scale * PX
	_ray.collision_mask = WORLD_MASK
	_shape_query.collision_mask = WORLD_MASK
	_shape_query.shape = collision.shape
	var exclude: Array[RID] = [get_rid()]
	if target is CollisionObject2D:
		exclude.append((target as CollisionObject2D).get_rid())
	_ray.exclude = exclude
	_shape_query.exclude = exclude


## The first robot in the current scene, or null.
func find_target() -> Node2D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for node in scene.find_children("*", "CharacterBody2D", true, false):
		if node is Player:
			return node
	return null


## True while the target exists and isn't dead.
func target_alive() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return not (target.has_method("is_dead") and target.call("is_dead"))


## Where the target's feet are (the robot's origin is the middle of its body).
func target_feet() -> Vector2:
	if target is Player:
		var shape := ((target as Player).get_node("CollisionShape2D") as CollisionShape2D)
		var rect := shape.shape as RectangleShape2D
		return target.global_position + Vector2(0.0, shape.position.y + rect.size.y * 0.5)
	return target.global_position


## Half the body's width, in px.
func half_width() -> float:
	return (collision.shape as RectangleShape2D).size.x * 0.5


## Adds gravity, capped at max_fall_speed, and keeps track of long falls.
func apply_gravity(delta: float) -> void:
	if is_on_floor() or wire_held:
		_fall_time = 0.0
	if is_on_floor():
		return
	velocity.y = minf(velocity.y + _gravity_px * delta, max_fall_speed * PX)
	if velocity.y > 0.0:
		_fall_time += delta
		if _fall_time >= despawn_fall_time:
			# Fallen out of the level: gone.
			dead = true
			queue_free()


## How far below the feet the floor is at x_offset px to the side (positive is ahead when
## facing right), looking no deeper than max_depth px. INF when there's nothing.
func ground_depth(x_offset: float, max_depth: float) -> float:
	var space := get_world_2d().direct_space_state
	var from := global_position + Vector2(x_offset, -2.0)
	_ray.from = from
	_ray.to = global_position + Vector2(x_offset, max_depth)
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return INF
	return (hit.position as Vector2).y - global_position.y


## Like ground_depth, at world x, looking from up px above the feet to down px below them.
func ground_depth_at(world_x: float, up: float, down: float) -> float:
	var space := get_world_2d().direct_space_state
	_ray.from = Vector2(world_x, global_position.y - up)
	_ray.to = Vector2(world_x, global_position.y + down)
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return INF
	return (hit.position as Vector2).y - global_position.y


## True when walking on in direction dir would step off a ledge (a drop of more than 3 px just
## ahead) or bump into a wall.
func ledge_or_wall_ahead(dir: float) -> bool:
	var front := dir * (half_width() + 1.0)
	var ledge := ground_depth(front, 4.0) > 3.0 and ground_depth(front + dir * 2.0, 4.0) > 3.0
	return ledge or is_blocked(dir * 2.0)


## The launch velocity (px/s) of a safe hop in direction dir, or ZERO when there's none.
## heights (m) and speeds (m/s) are tried in order, every speed for each height. A hop is safe
## when predict_jump says it lands on a floor no more than max_drop metres down, at least 3 px
## along. With prefer_far, the farthest safe hop of the first height that has any wins;
## otherwise the first safe one.
func find_safe_hop(dir: float, heights: Array, speeds: Array, max_drop: float,
		prefer_far: bool = false) -> Vector2:
	var best := Vector2.ZERO
	var best_reach := 0.0
	for height: float in heights:
		for speed: float in speeds:
			var vel := Vector2(dir * speed * PX, launch_speed(height * PX))
			var flight := predict_jump(vel, max_drop * PX)
			if not flight.landed:
				continue
			var reach := ((flight.position as Vector2).x - global_position.x) * dir
			if reach < 3.0:
				continue
			if not prefer_far:
				return vel
			if reach > best_reach:
				best_reach = reach
				best = vel
		if best != Vector2.ZERO:
			return best
	return best


## Heights (m) to try for climbing hops: from start, growing by 40%, up to top.
static func climb_heights(start: float, top: float) -> Array:
	var out: Array = []
	var h := start
	while h < top:
		out.append(h)
		h *= 1.4
	out.append(top)
	return out


## True when moving dx px sideways would bump into something (tested 1 px up, clear of the
## floor).
func is_blocked(dx: float) -> bool:
	var from := global_transform.translated(Vector2(0.0, -1.0))
	return test_move(from, Vector2(dx, 0.0))


## Flies a jump with launch velocity vel (px/s) from the current spot, before taking it.
## Returns {
##   "landed": true when it comes down on a floor within max_drop px below the start,
##   "position": where the feet end up,
##   "drop": how far below the start that is (negative when higher),
##   "bumped": true if it hits a wall or ceiling first,
##   "time": the flight time.
## }
func predict_jump(vel: Vector2, max_drop: float, max_time: float = 3.0) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var offset := collision.position
	var start := global_position + Vector2(0.0, -0.5)
	var pos := start
	var v := vel
	var t := 0.0
	var result := {"landed": false, "position": pos, "drop": 0.0, "bumped": false, "time": 0.0}
	while t < max_time:
		var next_v := Vector2(v.x, minf(v.y + _gravity_px * PREDICT_STEP, max_fall_speed * PX))
		var motion := (v + next_v) * 0.5 * PREDICT_STEP
		_shape_query.transform = Transform2D(0.0, pos + offset)
		_shape_query.motion = motion
		var fractions := space.cast_motion(_shape_query)
		if fractions.size() == 2 and fractions[0] < 1.0:
			var contact := pos + motion * float(fractions[0])
			# What was touched: probe a hair further along the motion.
			_shape_query.transform = Transform2D(0.0, pos + offset + motion * float(fractions[1]))
			_shape_query.motion = Vector2.ZERO
			var info := space.get_rest_info(_shape_query)
			var normal: Vector2 = info.get("normal", Vector2.UP)
			result.position = contact
			result.time = t
			result.drop = contact.y - global_position.y
			if normal.y < -0.5 and v.y >= 0.0:
				# Grazing a floor's corner doesn't count: the middle of the body must come down
				# on it, or it would slide off the edge.
				result.landed = result.drop <= max_drop and has_footing(contact)
			else:
				result.bumped = true
			return result
		pos += motion
		v = next_v
		t += PREDICT_STEP
		if pos.y - global_position.y > max_drop + 2.0:
			break
	result.position = pos
	result.drop = pos.y - global_position.y
	result.time = t
	return result


## True when there's floor right under feet at pos, across the middle of the body
## (FOOTING_HALF px either side of the centre).
func has_footing(pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	for dx in [-FOOTING_HALF, 0.0, FOOTING_HALF]:
		_ray.from = pos + Vector2(dx, -2.0)
		_ray.to = pos + Vector2(dx, 3.0)
		if space.intersect_ray(_ray).is_empty():
			return false
	return true


## Launch velocity (px/s, upward is negative) that peaks height px above the start.
func launch_speed(height: float) -> float:
	return -sqrt(2.0 * _gravity_px * maxf(height, 0.0))


# --- Under the floor ---------------------------------------------------------------------------


## True while it's anywhere in the underground cycle (going in, under, coming out).
func is_underground() -> bool:
	return under != Under.NONE


## True while it's out of sight (fully under).
func is_hidden() -> bool:
	return under in [Under.TUNNELLING, Under.DUCT]


## Digs in here and tunnels to exit (a spot on the floor from find_burrow_exit()).
func start_burrow(exit: Vector2) -> void:
	_begin_under(Under.DIGGING, dig_time)
	_under_to = exit


## Squeezes into vent and travels the ducts to exit_vent.
func start_vent(vent: FloorVent, exit_vent: FloorVent) -> void:
	_vent_in = vent
	_vent_out = exit_vent
	global_position.x = vent.global_position.x
	_begin_under(Under.VENT_IN, vent_in_time)
	_under_to = exit_vent.global_position


func _begin_under(step: Under, length: float) -> void:
	under = step
	under_time = 0.0
	_under_length = length
	_under_from = global_position
	velocity = Vector2.ZERO
	_debris_left = 0.0


## Runs the underground cycle. Call it first in _physics_process; while it returns true the
## enemy's own behaviour waits.
func update_underground(delta: float) -> bool:
	if under == Under.NONE:
		return false
	under_time += delta
	var t := clampf(under_time / maxf(_under_length, 0.01), 0.0, 1.0)
	_debris_left -= delta
	match under:
		Under.DIGGING:
			sink = body_height * t * t
			if _debris_left <= 0.0:
				_debris_left = 0.12
				ScrapDebris.kick(global_position, -facing, 1.5, true)
			if t >= 1.0:
				_hide(Under.TUNNELLING, global_position.distance_to(_under_to) / (tunnel_speed * PX))
		Under.VENT_IN:
			sink = body_height * smoothstep(0.15, 1.0, t)
			_vent_in.open = minf(t * 3.0, 1.0)
			if _debris_left <= 0.0:
				_debris_left = 0.2
				_vent_in.rattle(0.2)
				ScrapDebris.kick(_vent_in.global_position, 0.0, 0.6, true)
			if t >= 1.0:
				var length := absf(_under_to.x - global_position.x) / (duct_speed * PX) + 0.6
				_hide(Under.DUCT, length)
		Under.TUNNELLING, Under.DUCT:
			global_position = _under_from.lerp(_under_to, t)
			if under == Under.DUCT:
				if t < 0.15:
					_vent_in.open = 1.0 - t / 0.15
				if _debris_left <= 0.0:
					# Something's moving in the ducts: every vent rattles now and then.
					_debris_left = randf_range(0.5, 1.2)
					var vents := get_tree().get_nodes_in_group(FloorVent.GROUP)
					if not vents.is_empty():
						(vents.pick_random() as FloorVent).rattle(0.15)
			if t >= 1.0:
				if not _exit_clear():
					# Something's standing on the way out: wait under it.
					under_time = _under_length
					return true
				_show(Under.VENT_OUT if under == Under.DUCT else Under.EMERGING)
		Under.EMERGING, Under.VENT_OUT:
			sink = body_height * (1.0 - smoothstep(0.0, 1.0, t))
			if under == Under.VENT_OUT:
				_vent_out.open = 1.0 if t < 0.8 else (1.0 - t) * 5.0
			if t >= 1.0:
				sink = 0.0
				under = Under.NONE
				if _vent_out != null:
					_vent_out.open = 0.0
				_vent_in = null
				_vent_out = null
				resurfaced.emit()
	return true


func _hide(step: Under, length: float) -> void:
	sink = body_height
	visible = false
	_layer_before = collision_layer
	_mask_before = collision_mask
	collision_layer = 0
	collision_mask = 0
	remove_from_group(GROUP)
	add_to_group(UNDER_GROUP)
	_begin_under(step, length)
	went_under.emit()


func _show(step: Under) -> void:
	global_position = _under_to
	visible = true
	collision_layer = _layer_before
	collision_mask = _mask_before
	remove_from_group(UNDER_GROUP)
	add_to_group(GROUP)
	var length := vent_out_time if step == Under.VENT_OUT else emerge_time
	_begin_under(step, length)
	if step == Under.VENT_OUT:
		_vent_out.rattle(0.4)
		ScrapDebris.kick(_vent_out.global_position, 0.0, 1.5, true)
	else:
		ScrapDebris.kick(global_position, 0.0, 3.0, true)


## True when nothing (level, robot, enemy) is in the way of coming up at _under_to.
func _exit_clear() -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.transform = Transform2D(0.0, _under_to + collision.position + Vector2(0.0, -1.0))
	query.collision_mask = WORLD_MASK | ENEMY_LAYER
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


## Where to come back up after tunnelling: a clear spot on the same floor, between min_dist and
## max_dist px away, as far from the robot as possible (and at least avoid px from it). It can
## tunnel under blocks standing on the floor, but not past where the floor itself ends.
## Vector2.INF when there's none.
func find_burrow_exit(min_dist: float, max_dist: float, avoid: float) -> Vector2:
	var space := get_world_2d().direct_space_state
	var best := Vector2.INF
	var best_score := -INF
	var robot_x := target_feet().x if target_alive() else INF
	for dir: float in [-1.0, 1.0]:
		var d := 4.0
		while d <= max_dist:
			var x := global_position.x + dir * d
			_ray.from = Vector2(x, global_position.y - 1.0)
			_ray.to = Vector2(x, global_position.y + 3.0)
			var hit := space.intersect_ray(_ray)
			if hit.is_empty():
				break
			var spot := Vector2(x, (hit.position as Vector2).y)
			if d >= min_dist and _spot_clear(spot) and has_footing(spot):
				var from_robot := absf(x - robot_x)
				if from_robot >= avoid:
					var score := minf(from_robot, 400.0) + d * 0.1
					if score > best_score:
						best_score = score
						best = spot
			d += 4.0
	return best


func _spot_clear(spot: Vector2) -> bool:
	_shape_query.transform = Transform2D(0.0, spot + collision.position + Vector2(0.0, -1.0))
	_shape_query.motion = Vector2.ZERO
	return get_world_2d().direct_space_state.intersect_shape(_shape_query, 1).is_empty()


## The nearest floor vent on its own floor level within max_dist px, preferring direction dir
## (0 for either). null when there's none.
func find_vent(max_dist: float, dir: float = 0.0) -> FloorVent:
	var best: FloorVent = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(FloorVent.GROUP):
		var vent := node as FloorVent
		if vent == null or vent.others().is_empty():
			continue
		var dx := vent.global_position.x - global_position.x
		if absf(vent.global_position.y - global_position.y) > 4.0 or absf(dx) > max_dist:
			continue
		if dir != 0.0 and signf(dx) != dir and absf(dx) > 4.0:
			continue
		if absf(dx) < best_d:
			best_d = absf(dx)
			best = vent
	return best


## The vent to come out of after going into vent: the one farthest from the robot, or a random
## one when calm.
func pick_exit_vent(vent: FloorVent, away_from_robot: bool) -> FloorVent:
	var others := vent.others()
	if others.is_empty():
		return null
	if not away_from_robot or not target_alive():
		return others.pick_random()
	var robot_x := target_feet().x
	var best: FloorVent = others[0]
	for other in others:
		if absf(other.global_position.x - robot_x) > absf(best.global_position.x - robot_x):
			best = other
	return best


# --- Phasing -----------------------------------------------------------------------------------


## Starts (on) or stops fighting other, both ways: the two collide while they fight. Every
## other enemy is still passed through.
func set_aggro(other: Enemy, on: bool) -> void:
	if other == null or other == self:
		return
	if on:
		if other not in foes:
			foes.append(other)
		if self not in other.foes:
			other.foes.append(self)
	else:
		foes.erase(other)
		other.foes.erase(self)
	_aggro_refresh = 0.0
	other._aggro_refresh = 0.0


## Keeps the fighting layer and exceptions in step with foes. Call each physics frame.
func update_aggro(delta: float) -> void:
	for i in range(foes.size() - 1, -1, -1):
		var foe := foes[i]
		if not is_instance_valid(foe) or foe.dead or foe.is_hidden() or dead:
			foes.remove_at(i)
			_aggro_refresh = 0.0
	_aggro_refresh -= delta
	if _aggro_refresh > 0.0:
		return
	_aggro_refresh = 0.25
	if foes.is_empty():
		# Not fighting: nothing to collide with but the level and the robot.
		collision_layer &= ~AGGRO_LAYER
		collision_mask &= ~AGGRO_LAYER
		return
	if collision_layer != 0:
		collision_layer |= AGGRO_LAYER
		collision_mask |= AGGRO_LAYER
	# Everyone else that's fighting (someone else) is kept out; foes aren't.
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Enemy
		if other == null or other == self:
			continue
		if other in foes:
			remove_collision_exception_with(other)
			other.remove_collision_exception_with(self)
		else:
			add_collision_exception_with(other)
			other.add_collision_exception_with(self)


## Standing on an enemy's back (only a foe can be stood on): slide off it.
func slip_off_enemies() -> void:
	if not is_on_floor():
		return
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var other := hit.get_collider() as Enemy
		if other != null and hit.get_normal().y < -0.5:
			global_position.x += signf(global_position.x - other.global_position.x + 0.01) * 1.0
			return


# --- Rummaging ---------------------------------------------------------------------------------


## The nearest spot within max_dist px where the floor meets a wall (where scrap gathers), as
## a world x for the feet, and which side the wall is on. Stops looking at ledges. Returns
## {"x": float, "wall": -1 or 1}, or {} when there's none.
func find_rummage_spot(max_dist: float) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var best := {}
	var best_d := INF
	for dir: float in [-1.0, 1.0]:
		var d := 0.0
		while d <= max_dist:
			var pos := global_position + Vector2(dir * d, -1.0)
			if ground_depth_at(pos.x + dir * half_width(), 2.0, 4.0) > 3.0:
				break
			_shape_query.transform = Transform2D(0.0, pos + collision.position + Vector2(dir * 3.0, 0.0))
			_shape_query.motion = Vector2.ZERO
			if not space.intersect_shape(_shape_query, 1).is_empty():
				if d < best_d:
					best_d = d
					best = {"x": global_position.x + dir * d, "wall": dir}
				break
			d += 3.0
	return best


## A hit landed on the enemy: it may push the core on a stage or more (CoreDamage, against
## resistance); at fault the enemy is destroyed.
func take_hit(damage: float, from: Node = null) -> void:
	if dead:
		return
	var stages := core.hit(damage, resistance)
	hit_taken.emit(damage, from)
	if stages > 0:
		core_changed.emit(core.stage)
		if core.stage >= CoreDamage.FAULT:
			die()


## Height of the dev core light above the feet: just over the top of the hitbox.
func _core_light_height() -> float:
	var rect := collision.shape as RectangleShape2D
	if rect == null:
		return 20.0
	return -collision.position.y + rect.size.y * 0.5 + 6.0


## Core stage: 0 healthy, 1 mild, 2 heavy, 3 fault (Player.Damage order).
func core_stage() -> int:
	return core.stage


## True from a heavy core on: it sparks, smokes, slows down and acts hurt.
func is_hurt() -> bool:
	return core.stage >= 2 and not dead


## Sets the core stage directly (the dev menu), dying at fault.
func set_core_stage(stage: int) -> void:
	if dead or stage == core.stage:
		return
	core.set_stage(stage)
	core_changed.emit(core.stage)
	if core.stage >= CoreDamage.FAULT:
		die()


## Destroyed: it drops where it is and stays as a wreck (see the doc above). Subclasses hook
## _on_death() to tidy their own state.
func die() -> void:
	if dead:
		return
	dead = true
	dead_time = 0.0
	if is_underground():
		# Can't happen while hidden (nothing touches it); halfway in or out, it just stops.
		under = Under.NONE
		sink = 0.0
		visible = true
	for foe in foes.duplicate():
		set_aggro(foe, false)
	velocity.x *= 0.5
	collision_layer = 0
	collision_mask = WORLD_MASK
	remove_from_group(GROUP)
	remove_from_group(UNDER_GROUP)
	add_to_group(WRECK_GROUP)
	_on_death()
	died.emit()


## Override: the subclass's own tidying up when it dies.
func _on_death() -> void:
	pass


## Runs a wreck: lying there, falling if the floor goes, cleared away out of sight once it's
## been about long enough. Call it first in _physics_process; while it returns true the
## enemy's brain is off.
func update_wreck(delta: float) -> bool:
	if not dead:
		return false
	dead_time += delta
	velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta) if is_on_floor() else velocity.x
	apply_gravity(delta)
	move_and_slide()
	if dead_time >= wreck_linger and not on_screen(24.0):
		queue_free()
	return true


## How hot the wreck still is, 1 just dead to 0 cold (and 0 while alive).
func wreck_heat() -> float:
	if not dead:
		return 0.0
	return clampf(1.0 - dead_time / maxf(wreck_smoke_time, 0.01), 0.0, 1.0)


## True when its spot is within the camera's view (grown by margin px).
func on_screen(margin: float = 0.0) -> bool:
	var view := get_viewport()
	if view == null:
		return false
	var rect := view.get_canvas_transform().affine_inverse() * view.get_visible_rect()
	return rect.grow(margin).has_point(global_position)


## A scavenger eats seconds worth (at its rate) off the wreck. Gone when it's all eaten.
func consume(amount: float) -> void:
	if not dead or remains <= 0.0:
		return
	remains = maxf(remains - amount / maxf(wreck_material, 0.01), 0.0)
	if remains <= 0.0:
		ScrapDebris.kick(global_position, 0.0, 2.0)
		queue_free()


## The nearest wreck within max_dist px (on about its level: within max_rise px up or down)
## that fewer than limit of its own kind are eating already. null when there's none.
func find_wreck(max_dist: float, limit: int = 2, max_rise: float = 56.0) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(WRECK_GROUP):
		var wreck := node as Enemy
		if wreck == null or wreck == self or wreck.is_queued_for_deletion() or wreck.remains <= 0.0:
			continue
		var d := wreck.global_position - global_position
		if absf(d.x) > max_dist or absf(d.y) > max_rise or not wreck.is_on_floor():
			continue
		if _eaters(wreck) >= limit:
			continue
		if absf(d.x) < best_d:
			best_d = absf(d.x)
			best = wreck
	return best


## The wreck this enemy is eating (or walking to), for find_wreck() to spread scavengers out.
var eating: Enemy


func _eaters(wreck: Enemy) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group(GROUP):
		if node != self and node is Enemy and (node as Enemy).eating == wreck \
				and node.get_script() == get_script():
			n += 1
	return n


# --- Packs ---------------------------------------------------------------------------------------


## The others of its own kind within radius px (and about its level), awake and above ground.
func pack_mates(radius: float, max_rise: float = 48.0) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Enemy
		if other == null or other == self or other.get_script() != get_script():
			continue
		var d := other.global_position - global_position
		if absf(d.x) <= radius and absf(d.y) <= max_rise:
			out.append(other)
	return out


## Middle x of the pack mates within radius px, or NAN when it has none.
func pack_centre(radius: float) -> float:
	var mates := pack_mates(radius)
	if mates.is_empty():
		return NAN
	var sum := 0.0
	for mate in mates:
		sum += mate.global_position.x
	return sum / mates.size()
