class_name Fizzle
extends Node2D
## A weapon that fails to fire: a sputter of a few weak sparks from the muzzle and a wisp of
## smoke. Used when damaged systems make the plasma shot misfire or jam the burst, and as the
## stutter before a delayed shot.

const SPARK := Color(1.0, 0.85, 0.55)
const HOT := Color(1.0, 0.5, 0.15)

## Which way the muzzle points (unit), and how big the sputter is (1 normal; the jammed burst is
## bigger).
var direction := Vector2.RIGHT
var strength: float = 1.0

var _light: Node2D
var _sparks := PixelSparks.new()
var _smoke: Smoke


func _ready() -> void:
	z_index = 20
	_light = Node2D.new()
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light.material = material
	add_child(_light)
	_light.draw.connect(func() -> void: _sparks.draw(_light))
	_sparks.colors = [SPARK, HOT, Color(0.7, 0.2, 0.06, 0.7)]
	# The sputter is the only sign the weapon failed (essential); the smoke is decoration.
	_sparks.essential = true
	_sparks.gravity = 260.0
	_sparks.damping = 0.1
	_sparks.emit(Vector2.ZERO, int(round(5.0 * strength)), direction.angle(), 0.9, 30.0,
			90.0 * sqrt(strength), 0.08, 0.28)
	_smoke = Smoke.new()
	_smoke.free_when_empty = false
	_smoke.z_index = -1
	add_child(_smoke)
	for i in int(ceil(strength * 1.5)):
		_smoke.puff(direction * 2.0, direction * randf_range(4.0, 10.0) + Vector2(0, -6),
				randf_range(0.6, 1.0) * sqrt(strength), 1.0, randf_range(2.5, 4.0) * sqrt(strength),
				0.4, 0.0)


func _process(delta: float) -> void:
	_sparks.update(delta)
	if _sparks.is_empty() and _smoke.is_empty():
		queue_free()
		return
	_light.queue_redraw()
