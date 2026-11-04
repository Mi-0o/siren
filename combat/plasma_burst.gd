class_name PlasmaBurst
extends Node2D
## Where a plasma bolt hits: a tiny explosion. A white-hot pop for a couple of frames, a spray of
## sparks thrown off the surface, a few embers dropping, and a little puff of smoke that curls
## up and thins out.

const FLASH := Color(1.0, 0.97, 0.88)
const HOT := Color(1.0, 0.72, 0.3)
const FLASH_TIME: float = 0.09

## Surface normal at the hit, so the blast throws off it.
var normal := Vector2.LEFT

var _age: float = 0.0
var _light: Node2D
var _sparks := PixelSparks.new()
var _embers := PixelSparks.new()
var _smoke: Smoke


func _ready() -> void:
	z_index = 20
	var away := normal.angle() if normal != Vector2.ZERO else PI
	_light = Node2D.new()
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light.material = material
	_light.z_index = 1
	add_child(_light)
	_light.draw.connect(_draw_light)
	_sparks.colors = [FLASH, Color(1.0, 0.88, 0.55), HOT, Color(0.9, 0.35, 0.1, 0.7)]
	# The impact sparks show where it hit (essential); embers and smoke are decoration.
	_sparks.essential = true
	_sparks.gravity = 200.0
	_sparks.damping = 0.03
	_sparks.emit(Vector2.ZERO, 18, away, 1.3, 90.0, 220.0, 0.08, 0.3)
	_embers.colors = [HOT, Color(0.95, 0.4, 0.1), Color(0.6, 0.18, 0.05, 0.8)]
	_embers.gravity = 240.0
	_embers.damping = 0.4
	_embers.emit(Vector2.ZERO, 6, away - PI / 2.0 * signf(normal.x + 0.001), 1.0, 20.0, 60.0,
			0.35, 0.7)
	_smoke = Smoke.new()
	_smoke.z_index = -1
	add_child(_smoke)
	_smoke.free_when_empty = false
	for i in 5:
		var drift := Vector2.from_angle(away + randf_range(-0.9, 0.9)) * randf_range(8.0, 22.0)
		_smoke.puff(normal * 2.0 + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)),
				drift, randf_range(0.6, 1.1), 1.0, randf_range(3.0, 5.0), 0.55, 0.8)


func _process(delta: float) -> void:
	_age += delta
	_sparks.update(delta)
	_embers.update(delta)
	if _age > FLASH_TIME and _sparks.is_empty() and _embers.is_empty() and _smoke.is_empty():
		queue_free()
		return
	_light.queue_redraw()


func _draw_light() -> void:
	if _age < FLASH_TIME:
		# The pop: a hot blob that swells a pixel and is gone.
		var t := _age / FLASH_TIME
		var r := 2 + int(t * 2.0)
		_light.draw_texture(Smoke.disc(r), Vector2(-r, -r), Color(HOT, 0.8 * (1.0 - t)))
		_light.draw_texture(Smoke.disc(maxi(r - 2, 1)), Vector2(-maxi(r - 2, 1), -maxi(r - 2, 1)),
				Color(FLASH, 1.0 - t))
	_sparks.draw(_light)
	_embers.draw(_light)
