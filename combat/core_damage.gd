class_name CoreDamage
extends RefCounted
## Core damage without a health bar. A body's core is in one of four stages: healthy, mild,
## heavy, fault (fault: an enemy is destroyed, the robot dies). Every attack has a damage number
## and every body a resistance number. Each hit may push the core one stage on, or with a strong
## enough hit several, decided by the two numbers:
##
## - The odds. x = log2(damage / resistance), so doubling the damage or halving the resistance
##   moves it by one step. The chance a hit advances a stage is a smooth S-curve in x:
##   damage = resistance gives about 40%, twice the resistance 75%, four times 93%, half the
##   resistance 13%, a quarter 3%. Damage below a quarter of the resistance (x < NO_EFFECT) does
##   nothing at all, however often it lands: it just glances off.
## - The limits. Each hit adds its chance to a running total (progress) for the current stage.
##   Until the total reaches MIN_SHARE (half an "expected hit's worth") a hit can't advance it, so
##   a 5% hit needs at least 10 hits and can never get lucky on the first. Once the total reaches
##   MAX_SHARE (twice the expected) the hit advances it for sure, so an 80% hit never fails more
##   than twice in a row. In between, each hit rolls its own chance. With one kind of hit:
##   min hits = ceil(MIN_SHARE / chance), max hits = ceil(MAX_SHARE / chance). Mixed hits add
##   up fairly, since each counts for its own chance. Advancing a stage starts the total over.
## - Several stages at once. A hit that advances a stage rolls again for the next one as if its
##   damage were a quarter (x - EXTRA_STEP), and so on: damage around 4x the resistance
##   sometimes takes two stages, around 16x it usually does and can take all three. These extra
##   rolls ignore the limits (it's one big hit).
## - Overwhelming hits. Damage at least 2^INSTANT_FAULT (256) times the resistance goes straight
##   to fault, no rolls (the antimatter cannon against nearly anything).
##
## Each body keeps one CoreDamage (stage and progress). hit() returns how many stages it went.

## Healthy, mild, heavy, fault.
const FAULT: int = 3
## The chance curve: 50% at x = CURVE_MID (damage about 1.2x resistance), CURVE_STEEP sets how
## quickly it goes from unlikely to sure.
const CURVE_MID: float = 0.25
const CURVE_STEEP: float = 1.5
## Below this x (damage under a quarter of the resistance) a hit does nothing.
const NO_EFFECT: float = -2.0
## Hit limits, in "expected hits" (summed chances): no advance before MIN_SHARE, certain at
## MAX_SHARE.
const MIN_SHARE: float = 0.5
const MAX_SHARE: float = 2.0
## Each extra stage in one hit is rolled as if the damage were 2^EXTRA_STEP times smaller.
const EXTRA_STEP: float = 2.0
## From this x on (damage 256x the resistance) a hit is straight to fault.
const INSTANT_FAULT: float = 8.0

## Dev menu SHOW HEALTH: a light above every body showing its core stage.
static var show_lights: bool = false

## Current stage, 0 (healthy) to FAULT.
var stage: int = 0
## Summed chances of the hits since the last advance.
var progress: float = 0.0


## log2(damage / resistance).
static func power(damage: float, resistance: float) -> float:
	if damage <= 0.0:
		return -INF
	return log(damage / maxf(resistance, 0.001)) / log(2.0)


## Chance one hit at this power advances a stage (0 below NO_EFFECT).
static func chance_at(x: float) -> float:
	if x < NO_EFFECT:
		return 0.0
	return 1.0 / (1.0 + exp(-CURVE_STEEP * (x - CURVE_MID)))


static func chance(damage: float, resistance: float) -> float:
	return chance_at(power(damage, resistance))


## Fewest and most hits of this one kind to advance a stage (-1, -1 when it can't).
static func hit_limits(damage: float, resistance: float) -> Vector2i:
	var c := chance(damage, resistance)
	if c <= 0.0:
		return Vector2i(-1, -1)
	return Vector2i(maxi(1, ceili(MIN_SHARE / c - 0.000001)), maxi(1, ceili(MAX_SHARE / c - 0.000001)))


## A hit lands. Returns how many stages the core went on (0 if none).
func hit(damage: float, resistance: float) -> int:
	if stage >= FAULT:
		return 0
	var x := power(damage, resistance)
	if x >= INSTANT_FAULT:
		var all := FAULT - stage
		stage = FAULT
		progress = 0.0
		return all
	var c := chance_at(x)
	if c <= 0.0:
		return 0
	progress += c
	var advance := false
	if progress + 0.000001 >= MAX_SHARE:
		advance = true
	elif progress + 0.000001 >= MIN_SHARE:
		advance = randf() < c
	if not advance:
		return 0
	progress = 0.0
	var stages := 1
	while stage + stages < FAULT and randf() < chance_at(x - EXTRA_STEP * stages):
		stages += 1
	stage += stages
	return stages


## Sets the stage from outside (repairs, the dev menu), starting the count over if it changed.
func set_stage(value: int) -> void:
	value = clampi(value, 0, FAULT)
	if value != stage:
		stage = value
		progress = 0.0
