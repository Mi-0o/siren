extends Control
## HUD charge gauge: a grimy, chamfered metal housing with a segmented cell, drawn in code at
## native pixel scale.
##
## Draining heats the gauge. Every drain adds the fraction of max charge lost to the heat, which
## cools off exponentially, so a slow drain (walking) barely glows while a lump cost (dash)
## flares hard. Glow, electric arcs and how fast sparks fly all follow the heat; the number of
## sparks follows the share of charge lost (sparks_per_percent). Charge just lost lingers as a
## hot ghost segment before burning away. Everything works in fractions of max charge, so it all
## scales when max charge or the costs change.
##
## Low charge warnings follow the player's tier ratios:
## - Warning: the cell pulses slowly towards orange.
## - Critical: a pulsing red glow, shaking cells, stray sparks, and drain effects boosted so even
##   walking shows.
## - Failing: no drain effects; a fast, bright red pulse with constant sparks that twitches and
##   cuts out completely now and then.
## - Empty: no effects at all.

enum Tier { NORMAL, WARNING, CRITICAL, FAILING, EMPTY }

## Size of the housing plate, in pixels.
const PLATE_SIZE := Vector2(124, 13)
const RIVETS: Array = [Vector2(2, 2), Vector2(121, 10)]
const LABEL_COLOR := Color(0.62, 0.45, 0.12)
const LABEL_POS := Vector2(4, 4)
## The cell's inner area. 100 px wide: 20 segments of 5 px.
const CELL := Rect2(18, 4, 100, 5)
const SEGMENT_WIDTH: int = 5
const WELL_COLOR := Color(0.02, 0.02, 0.03)
const EMPTY_COLOR := Color(0.12, 0.11, 0.09)
const DIVIDER_COLOR := Color(0.03, 0.03, 0.03, 0.85)
const FILL_COLOR := Color(1.0, 0.78, 0.14)
const FILL_HOT := Color(1.0, 0.98, 0.86)
const ORANGE := Color(1.0, 0.5, 0.1)
const RED := Color(0.95, 0.16, 0.08)
const RED_HOT := Color(1.0, 0.42, 0.32)
const GHOST_COLOR := Color(1.0, 0.42, 0.12)
const HALO_COLOR := Color(1.0, 0.7, 0.2)
const ARC_COLOR := Color(0.7, 0.95, 1.0)
const HAZARD_COLOR := Color(0.55, 0.4, 0.08)

## Player whose charge is shown. Its warning, critical and failing ratios set the tiers.
@export var player: Player

@export_group("Drain effects")
## Time for heat to cool to about a third, in seconds. Longer keeps steady drains brighter.
@export var heat_cool_time: float = 0.25
## Heat, as a fraction of max charge, at which glow reaches half strength. Walking sits near
## 0.001, a dash at max 500 adds 0.05.
@export var heat_half_point: float = 0.016
## Shapes how glow rises with heat. Below 1 it lifts the low end, so the small gap between
## walking and running heat shows clearly (running crosses into arcs, walking doesn't) while big
## costs still top out near full glow.
@export_range(0.1, 1.0, 0.05) var glow_curve: float = 0.6
## Sparks emitted per 1% of max charge lost.
@export var sparks_per_percent: float = 3.0
## How long a lost chunk stays as a ghost before burning away, in seconds.
@export var ghost_hold_time: float = 0.25
## How fast the ghost burns away, in fractions of the bar per second.
@export var ghost_burn_speed: float = 0.6
## In the critical tier, heat counts this many times more, so walking glows and arcs.
@export var critical_heat_boost: float = 12.0
## In the critical tier, drains throw this many times more sparks.
@export var critical_spark_boost: float = 4.0

@export_group("Warnings")
## Pulses per second in the warning tier.
@export var warning_pulse_rate: float = 1.2
## Pulses per second of the red glow in the critical tier.
@export var critical_pulse_rate: float = 2.0
## Stray sparks per second in the critical tier.
@export var critical_idle_sparks: float = 4.0
## Chance per frame that a cell jolts a pixel up or down in the critical tier.
@export_range(0.0, 1.0, 0.01) var critical_shake_chance: float = 0.15
## Pulses per second in the failing tier.
@export var failing_pulse_rate: float = 5.0
## Sparks per second in the failing tier.
@export var failing_sparks: float = 20.0
## How long the gauge stays lit between cut-outs in the failing tier, min and max seconds.
@export var failing_on_time := Vector2(0.06, 0.35)
## How long each cut-out lasts in the failing tier, min and max seconds.
@export var failing_off_time := Vector2(0.03, 0.15)

var _ratio: float = 1.0
var _ghost_ratio: float = 1.0
var _ghost_hold_left: float = 0.0
var _last_charge: float = -1.0
var _tier := Tier.NORMAL
var _time: float = 0.0
var _heat: float = 0.0
## 0 to 1, derived from _heat.
var _glow: float = 0.0
## Fractional sparks owed, carried between frames so slow drains still spark now and then.
var _spark_budget: float = 0.0
var _sparks := PixelSparks.new()
## Pre-rolled grime pixels on the housing, from HudDraw.roll_grime().
var _grime: Array = []
## Vertical jolt of each segment's fill this frame, in pixels.
var _shake := PackedInt32Array()
## Failing tier: whether the gauge is currently cut out, and for how much longer.
var _cut_out: bool = false
var _cut_left: float = 0.0
## Failing tier: horizontal twitch of the cell contents this frame, in pixels.
var _twitch: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sparks.colors = [FILL_HOT, FILL_COLOR, GHOST_COLOR, Color(0.5, 0.15, 0.05)]
	_sparks.gravity = 260.0
	_sparks.damping = 0.2
	# Essential for the particles setting: on a slow drain (walking) they're the only clear
	# sign that charge is going.
	_sparks.essential = true
	_shake.resize(int(CELL.size.x) / SEGMENT_WIDTH)
	var label_rect := Rect2(LABEL_POS, Vector2(HudDraw.text_width("CHG"), HudDraw.GLYPH_HEIGHT))
	_grime = HudDraw.roll_grime(PLATE_SIZE, 7, 40, [CELL.grow(1), label_rect])
	if player == null:
		return
	player.charge_changed.connect(_on_charge_changed)
	_on_charge_changed(player.charge, player.max_charge)


func _process(delta: float) -> void:
	_time += delta
	_heat *= exp(-delta / maxf(heat_cool_time, 0.001))
	var half := heat_half_point
	if _tier == Tier.CRITICAL:
		half /= maxf(critical_heat_boost, 0.001)
	_glow = pow(_heat / (_heat + half), glow_curve) if _heat > 0.0 else 0.0

	_shake.fill(0)
	_twitch = 0
	match _tier:
		Tier.CRITICAL:
			_spark_budget += critical_idle_sparks * delta
			for i in _shake.size():
				if randf() < critical_shake_chance:
					_shake[i] = 1 if randf() < 0.5 else -1
		Tier.FAILING:
			_update_cut_out(delta)
			if not _cut_out:
				_spark_budget += failing_sparks * delta
				if randf() < 0.3:
					_twitch = 1 if randf() < 0.5 else -1

	var sparks := int(_spark_budget)
	if sparks > 0:
		_spark_budget -= sparks
		var speed := lerpf(30.0, 110.0, _glow)
		_sparks.emit(
			_tip() + Vector2(0, randf_range(0, CELL.size.y)),
			sparks, -PI / 2.0, 1.3, speed * 0.4, speed, 0.15, 0.45
		)
	_sparks.update(delta)

	_ghost_hold_left -= delta
	if _ghost_hold_left <= 0.0:
		_ghost_ratio = move_toward(_ghost_ratio, _ratio, ghost_burn_speed * delta)
	queue_redraw()


func _draw() -> void:
	_draw_housing()

	var lit := not (_tier == Tier.FAILING and _cut_out) and _tier != Tier.EMPTY
	if lit:
		_draw_halos()
	# After the halos, so the warning glow never eats into the lettering.
	HudDraw.draw_text(self, "CHG", LABEL_POS, LABEL_COLOR)

	draw_rect(CELL.grow(1), WELL_COLOR)
	draw_rect(CELL, EMPTY_COLOR)

	if lit:
		var fill_w := roundf(CELL.size.x * _ratio)
		if _ratio > 0.0:
			# Never let a sliver of charge round down to an empty-looking cell.
			fill_w = maxf(fill_w, 1.0)
		var ghost_w := roundf(CELL.size.x * _ghost_ratio)
		if ghost_w > fill_w:
			var ghost := GHOST_COLOR.lerp(FILL_HOT, _glow * 0.5)
			draw_rect(
				Rect2(CELL.position.x + fill_w, CELL.position.y, ghost_w - fill_w, CELL.size.y), ghost
			)
		_draw_fill(fill_w)

	for x in range(SEGMENT_WIDTH - 1, int(CELL.size.x) - 1, SEGMENT_WIDTH):
		draw_rect(Rect2(CELL.position.x + x, CELL.position.y, 1, CELL.size.y), DIVIDER_COLOR)

	if lit:
		_draw_arcs()
	_sparks.draw(self)


## Glow rings around the cell: the drain glow in amber, plus the red warning glow when low.
func _draw_halos() -> void:
	var warn := 0.0
	match _tier:
		Tier.CRITICAL:
			warn = lerpf(0.15, 0.5, _pulse(critical_pulse_rate))
		Tier.FAILING:
			warn = lerpf(0.35, 0.9, _pulse(failing_pulse_rate))
	for ring in 2:
		var falloff := 1.0 if ring == 0 else 0.4
		if _glow > 0.02:
			var halo := HALO_COLOR
			halo.a = 0.55 * _glow * falloff
			draw_rect(CELL.grow(2 + ring), halo, false, 1.0)
		if warn > 0.0:
			var red := RED_HOT if _tier == Tier.FAILING else RED
			red.a = warn * falloff
			draw_rect(CELL.grow(2 + ring), red, false, 1.0)


func _draw_fill(fill_w: float) -> void:
	var base := FILL_COLOR
	match _tier:
		Tier.WARNING:
			base = FILL_COLOR.lerp(ORANGE, lerpf(0.2, 0.55, _pulse(warning_pulse_rate)))
		Tier.CRITICAL:
			base = ORANGE.lerp(RED, lerpf(0.35, 0.8, _pulse(critical_pulse_rate)))
		Tier.FAILING:
			base = RED.lerp(RED_HOT, _pulse(failing_pulse_rate))
	var hot := _glow * 0.8
	var body := base.lerp(FILL_HOT, hot)
	var top := base.lightened(0.45).lerp(FILL_HOT, hot)
	var bottom := base.darkened(0.3).lerp(base, hot)

	# Drawn a segment at a time so each one can jolt on its own.
	for i in _shake.size():
		var x0 := i * SEGMENT_WIDTH
		var w := minf(SEGMENT_WIDTH, fill_w - x0)
		if w <= 0.0:
			break
		var pos := CELL.position + Vector2(x0 + _twitch, _shake[i])
		draw_rect(Rect2(pos, Vector2(w, CELL.size.y)), body)
		draw_rect(Rect2(pos, Vector2(w, 1)), top)
		draw_rect(Rect2(pos + Vector2(0, CELL.size.y - 1), Vector2(w, 1)), bottom)


func _draw_housing() -> void:
	HudDraw.draw_plate(self, PLATE_SIZE, _grime, RIVETS)
	# Worn hazard stripes on the right end cap.
	for y in range(4, 10):
		for x in range(120, 123):
			if (x + y) % 3 == 0:
				draw_rect(Rect2(x, y, 1, 1), HAZARD_COLOR)


## Jagged one-pixel arcs crawling back from the fill's tip. More, longer and brighter as the
## gauge heats up; nothing while it's cool.
func _draw_arcs() -> void:
	if _glow < 0.2 or randf() > _glow:
		return
	var count := 1 + int(_glow * 2.5)
	for i in count:
		var p := _tip() + Vector2(0, randi_range(0, int(CELL.size.y) - 1))
		var length := randi_range(4, int(8 + 18 * _glow))
		var arc := ARC_COLOR
		arc.a = clampf(0.4 + _glow, 0.0, 1.0)
		for step in length:
			p.x -= 1
			p.y = clampf(p.y + randi_range(-1, 1), CELL.position.y - 2, CELL.end.y + 1)
			if p.x < CELL.position.x:
				break
			draw_rect(Rect2(p, Vector2.ONE), arc)


## Failing tier: alternates between lit stretches and short cut-outs of random length.
func _update_cut_out(delta: float) -> void:
	_cut_left -= delta
	if _cut_left > 0.0:
		return
	_cut_out = not _cut_out
	var span := failing_off_time if _cut_out else failing_on_time
	_cut_left = randf_range(span.x, span.y)


## 0 to 1 and back, rate times per second.
func _pulse(rate: float) -> float:
	return 0.5 - 0.5 * cos(_time * rate * TAU)


## Top of the fill's right edge, where charge is being lost.
func _tip() -> Vector2:
	return Vector2(CELL.position.x + roundf(CELL.size.x * _ratio) + _twitch, CELL.position.y)


func _tier_for(ratio: float) -> Tier:
	if ratio <= 0.0:
		return Tier.EMPTY
	if ratio < player.failing_ratio:
		return Tier.FAILING
	if ratio < player.critical_ratio:
		return Tier.CRITICAL
	if ratio < player.warning_ratio:
		return Tier.WARNING
	return Tier.NORMAL


func _on_charge_changed(charge: float, max_charge: float) -> void:
	var new_ratio := charge / max_charge if max_charge > 0.0 else 0.0
	_tier = _tier_for(new_ratio)
	var drained := _last_charge >= 0.0 and charge < _last_charge
	if drained and _tier != Tier.FAILING and _tier != Tier.EMPTY:
		var lost := (_last_charge - charge) / max_charge
		_heat += lost
		var sparks := lost * 100.0 * sparks_per_percent
		if _tier == Tier.CRITICAL:
			sparks *= critical_spark_boost
		_spark_budget += sparks
		# Only lump costs (over 0.2% at once) hold the ghost; steady drains would otherwise keep
		# it from ever burning away.
		if lost >= 0.002:
			_ghost_hold_left = ghost_hold_time
	else:
		# Charging, the first reading, or a tier with no drain effects: nothing to burn away.
		_ghost_ratio = new_ratio
	if _tier == Tier.FAILING or _tier == Tier.EMPTY:
		_heat = 0.0
	if _tier == Tier.EMPTY:
		_sparks.clear()
		_spark_budget = 0.0
	if _tier != Tier.FAILING:
		_cut_out = false
		_cut_left = 0.0
	_last_charge = charge
	_ratio = new_ratio
