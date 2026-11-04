class_name Smoke
extends Node2D
## Pixel smoke: soft round puffs that drift, rise, swell and thin out. Each puff is a pre-built
## pixel disc with a dithered rim, so it stays crisp on the game's pixel grid. Positions are in
## this node's local space.
##
## Burn smoke (the burst's aftermath and smouldering scorch marks) joins the "burns" group, so
## the dev menu's REMOVE BURNS clears it.

const MAX_RADIUS: int = 32

static var _discs: Array[ImageTexture] = []

## Upward pull in px/s², and the share of speed kept per second.
var buoyancy: float = 14.0
var damping: float = 0.25
## Free this node once its last puff is gone (for one-off smoke; scorch smoke stays).
var free_when_empty: bool = true
## Whether this smoke carries gameplay information; non-essential smoke is thinned out much
## more by the particles setting (GameSettings.particle_scale).
var essential: bool = false

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _r0 := PackedFloat32Array()
var _r1 := PackedFloat32Array()
var _alpha := PackedFloat32Array()
var _warm := PackedFloat32Array()
var _shade := PackedFloat32Array()


func _ready() -> void:
	disc(0)


## The pixel disc texture of radius r (0 to MAX_RADIUS), for anything drawing soft round blobs.
static func disc(r: int) -> ImageTexture:
	if _discs.is_empty():
		for i in MAX_RADIUS + 1:
			_discs.append(_make_disc(i))
	return _discs[clampi(r, 0, MAX_RADIUS)]


## Adds a puff at local point at, moving at velocity, lasting life seconds, swelling from r0 to
## r1 pixels. alpha is its peak opacity; warm (0 to 1) tints it with fire glow at first.
func puff(at: Vector2, velocity: Vector2, life: float, r0: float, r1: float, alpha: float,
		warm: float = 0.0) -> void:
	if not GameSettings.particle_keep(essential):
		return
	_pos.append(at)
	_vel.append(velocity)
	_age.append(0.0)
	_life.append(life)
	_r0.append(r0)
	_r1.append(minf(r1, MAX_RADIUS))
	_alpha.append(alpha)
	_warm.append(warm)
	_shade.append(randf_range(0.85, 1.15))


func is_empty() -> bool:
	return _pos.is_empty()


func _process(delta: float) -> void:
	var keep := pow(damping, delta)
	var i := _pos.size() - 1
	while i >= 0:
		_age[i] += delta
		if _age[i] >= _life[i]:
			for arr in [_pos, _vel, _age, _life, _r0, _r1, _alpha, _warm, _shade]:
				arr.remove_at(i)
		else:
			var v := _vel[i] * keep + Vector2(0.0, -buoyancy * delta)
			_vel[i] = v
			_pos[i] += v * delta
		i -= 1
	if _pos.is_empty() and free_when_empty:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for i in _pos.size():
		var t := _age[i] / _life[i]
		var r := int(round(lerpf(_r0[i], _r1[i], 1.0 - pow(1.0 - t, 2.0))))
		# Fades in fast, thins out slowly.
		var a := _alpha[i] * smoothstep(0.0, 0.08, t) * pow(1.0 - t, 1.3)
		var grey := Color(0.2, 0.19, 0.18) * _shade[i]
		var warm := Color(0.62, 0.32, 0.14).lerp(grey, smoothstep(0.0, 0.35, t))
		var color := grey.lerp(warm, _warm[i])
		color.a = a
		draw_texture(_discs[r], (_pos[i] - Vector2(r, r)).floor(), color)


## A white disc of radius r with a checkered rim.
static func _make_disc(r: int) -> ImageTexture:
	var size := 2 * r + 1
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - r, y - r).length()
			var a := 0.0
			if d <= r - 0.6:
				a = 1.0
			elif d <= r + 0.4 and (x + y) % 2 == 0:
				a = 0.6
			image.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(image)
