class_name PixelSparks
extends RefCounted
## Lightweight one-pixel particles, drawn by whatever CanvasItem owns them. Positions are in the
## owner's local space and snapped to whole pixels when drawn, so they stay crisp in pixel art.
## Fast particles get a one-pixel tail behind them.

## Speed above which a particle draws a tail, in pixels per second.
const TAIL_SPEED: float = 40.0

## Colours from a fresh particle to a dying one, picked by remaining life.
var colors: Array[Color] = [Color.WHITE]
## Downward acceleration, in pixels per second squared. Negative floats upwards.
var gravity: float = 0.0
## Fraction of velocity kept per second, for drag. 1 means none.
var damping: float = 1.0
## Whether these particles carry gameplay information. The particles setting thins out
## non-essential ones much more (GameSettings.particle_scale). Read at each emit, so one
## emitter can switch it between calls.
var essential: bool = false

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()


## Emits count particles from origin, aimed at angle (radians, 0 = right, -PI/2 = up) give or
## take spread on each side.
func emit(
	origin: Vector2,
	count: int,
	angle: float,
	spread: float,
	speed_min: float,
	speed_max: float,
	life_min: float,
	life_max: float
) -> void:
	for i in GameSettings.particle_count(count, essential):
		var a := angle + randf_range(-spread, spread)
		_pos.append(origin)
		_vel.append(Vector2.from_angle(a) * randf_range(speed_min, speed_max))
		var life := randf_range(life_min, life_max)
		_life.append(life)
		_max_life.append(life)


func update(delta: float) -> void:
	var keep := pow(damping, delta)
	var i := _pos.size() - 1
	while i >= 0:
		_life[i] -= delta
		if _life[i] <= 0.0:
			_pos.remove_at(i)
			_vel.remove_at(i)
			_life.remove_at(i)
			_max_life.remove_at(i)
		else:
			_vel[i] = Vector2(_vel[i].x * keep, _vel[i].y * keep + gravity * delta)
			_pos[i] += _vel[i] * delta
		i -= 1


func clear() -> void:
	_pos.clear()
	_vel.clear()
	_life.clear()
	_max_life.clear()


func is_empty() -> bool:
	return _pos.is_empty()


func draw(canvas: CanvasItem) -> void:
	var last := colors.size() - 1
	for i in _pos.size():
		var t := 1.0 - _life[i] / _max_life[i]
		var color := colors[mini(int(t * colors.size()), last)]
		var p := _pos[i].floor()
		canvas.draw_rect(Rect2(p, Vector2.ONE), color)
		if _vel[i].length() > TAIL_SPEED:
			var tail := color
			tail.a *= 0.5
			canvas.draw_rect(Rect2((p - _vel[i].normalized()).floor(), Vector2.ONE), tail)
