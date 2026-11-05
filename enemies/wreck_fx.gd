class_name WreckFx
extends Node2D
## Sparks and smoke off a damaged enemy (its parent). From a heavy core on, it spits a few
## sparks now and then and trails a thin smoke. Once it's dead the wreck smokes harder and
## sparks often, both dying down over Enemy.wreck_smoke_time until it's cold. Nothing comes off
## it while it's hidden under the floor.
##
## It draws in world space (top level, at the origin), so sparks and smoke stay where they were
## thrown while the body moves on.

const SPARK_COLORS: Array[Color] = [Color(1.0, 0.97, 0.8), Color(1.0, 0.8, 0.35),
		Color(1.0, 0.5, 0.15), Color(0.6, 0.2, 0.08)]

var body: Enemy

var _sparks := PixelSparks.new()
var _smoke: Smoke
var _next_spark: float = 0.5
var _next_puff: float = 0.0


func _ready() -> void:
	body = get_parent() as Enemy
	top_level = true
	global_position = Vector2.ZERO
	z_index = 4
	_sparks.colors = SPARK_COLORS
	_sparks.gravity = 120.0
	_sparks.damping = 0.4
	_sparks.essential = true
	_smoke = Smoke.new()
	_smoke.free_when_empty = false
	_smoke.buoyancy = 10.0
	_smoke.z_index = -1
	add_child(_smoke)


func _process(delta: float) -> void:
	if body == null:
		return
	global_position = Vector2.ZERO
	_sparks.update(delta)
	var heat := 0.0
	if body.dead:
		heat = body.wreck_heat()
	elif body.is_hurt() and not body.is_hidden():
		heat = 0.35
	if heat > 0.0:
		_emit(heat, delta)
	queue_redraw()


## Sparks and smoke at a rate set by heat (0.35 hurt, 1 just dead down to 0 cold).
func _emit(heat: float, delta: float) -> void:
	var top := body.global_position + Vector2(0.0, -_height() * (0.35 if body.dead else 0.6))
	_next_spark -= delta
	if _next_spark <= 0.0:
		# Bursts come closer together the hotter it is, with the odd long pause.
		_next_spark = randf_range(0.25, 1.4) / maxf(heat, 0.2)
		var at := top + Vector2(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0))
		_sparks.emit(at, roundi(randf_range(2.0, 6.0) * (0.6 + heat)), -PI / 2.0, 1.2,
				20.0, 60.0 * (0.5 + heat), 0.15, 0.45)
	_next_puff -= delta
	if _next_puff <= 0.0:
		_next_puff = lerpf(0.6, 0.15, heat)
		var at := top + Vector2(randf_range(-3.0, 3.0), 0.0)
		var drift := Vector2(randf_range(-4.0, 4.0), randf_range(-10.0, -4.0))
		_smoke.essential = body.dead
		_smoke.puff(at, drift, randf_range(1.6, 2.8) * (0.6 + heat), 1.0,
				lerpf(3.0, 7.0, heat), lerpf(0.18, 0.45, heat), 0.3 * heat)


func _height() -> float:
	var rect := body.collision.shape as RectangleShape2D if is_instance_valid(body.collision) else null
	return rect.size.y if rect != null else 12.0


func _draw() -> void:
	_sparks.draw(self)
