class_name Scorch
extends Node2D
## Burn marks left on surfaces by the burst: patches of charred metal with molten spots that glow
## orange-white and cool to dark red, smouldering with wisps of smoke. They hold for hold_time
## (a minute), then fade out slowly over fade_time, smoking less and less.
##
## The marks are built pixel by pixel, and each pixel is only kept if it lies inside solid
## geometry (a physics point query), so a burn near a platform's edge stops at the edge
## instead of hanging out into the air.
##
## Every scorch joins the "burns" group, so the dev menu's REMOVE BURNS clears them.

const GROUP: StringName = &"burns"
const CHAR := Color(0.055, 0.045, 0.04)
const SOOT := Color(0.13, 0.11, 0.1)
const MOLTEN: Array[Color] = [
	Color(1.0, 0.95, 0.7), Color(1.0, 0.6, 0.15), Color(0.85, 0.22, 0.05), Color(0.35, 0.07, 0.03),
]

## Seconds the marks stay at full strength, and seconds they then take to fade away.
var hold_time: float = 60.0
var fade_time: float = 30.0
## Seconds molten spots take to cool from white hot to dark.
var cool_time: float = 7.0

var _age: float = 0.0
## Pixel (global, whole) -> [darkness 0..1, molten 0..1, smoke weight].
var _pixels: Dictionary[Vector2i, Vector3] = {}
## Spots that smoke: global point and the normal out of the surface.
var _vents: Array[Vector4] = []
var _smoke: Smoke
var _smoke_wait: float = 0.0
var _redraw_wait: float = 0.0
var _space: PhysicsDirectSpaceState2D
var _query := PhysicsPointQueryParameters2D.new()
## Pixel -> whether it is inside solid geometry, so each is only queried once.
var _solid: Dictionary[Vector2i, bool] = {}


## The physics world and layers that count as solid. Without it, burns aren't clipped.
func set_solids(space: PhysicsDirectSpaceState2D, mask: int, exclude: Array[RID] = []) -> void:
	_space = space
	_query.collision_mask = mask
	_query.exclude = exclude
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_solid.clear()


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 15
	_smoke = Smoke.new()
	_smoke.free_when_empty = false
	_smoke.buoyancy = 10.0
	_smoke.z_index = 10
	add_child(_smoke)


## Burns a patch into the surface at a global point, normal pointing out of it. size scales the
## patch (1 for a direct hit).
func burn(point: Vector2, normal: Vector2, size: float = 1.0) -> void:
	var tangent := Vector2(-normal.y, normal.x)
	var kept := 0
	var half := int(round(randf_range(5.0, 9.0) * size))
	var halo := 3
	for i in range(-half - halo, half + halo + 1):
		var edge := absf(float(i)) / float(half + 1)
		# Deep and black in the middle, shallower and sootier out to ragged ends, with a faint
		# heat-stained halo round it all.
		var depth := int(round(lerpf(5.0, 1.0, minf(edge, 1.0)) * size + randf_range(-0.6, 0.8)))
		for d in range(0, depth + 3):
			var p := point + tangent * float(i) - normal * (float(d) + 0.5)
			var key := Vector2i(floori(p.x), floori(p.y))
			if not _is_solid(key):
				continue
			var stain := edge > 1.0 or d > depth
			if stain and randf() < 0.5:
				continue
			if not stain and randf() < edge * 0.45:
				continue
			var dark := 0.18 if stain else clampf(
				1.0 - edge * 0.55 - float(d) * 0.07 + randf_range(-0.15, 0.1), 0.3, 1.0
			)
			var molten := 0.0
			if not stain and d <= 1 and edge < 0.7 and randf() < 0.5:
				molten = randf_range(0.6, 1.0)
			var old: Vector3 = _pixels.get(key, Vector3.ZERO)
			_pixels[key] = Vector3(maxf(old.x, dark), maxf(old.y, molten), 0.0)
			kept += 1
	if kept > 0:
		_vents.append(Vector4(point.x, point.y, normal.x, normal.y))
	queue_redraw()


func is_empty() -> bool:
	return _pixels.is_empty()


func _is_solid(key: Vector2i) -> bool:
	if _space == null:
		return true
	if _solid.has(key):
		return _solid[key]
	_query.position = Vector2(key) + Vector2(0.5, 0.5)
	var inside := not _space.intersect_point(_query, 1).is_empty()
	_solid[key] = inside
	return inside


func _process(delta: float) -> void:
	_age += delta
	var strength := _strength()
	if strength <= 0.0:
		queue_free()
		return
	# Smoulder: thick at first, then thinner as it cools, then fading with the marks.
	_smoke_wait -= delta
	if _smoke_wait <= 0.0 and not _vents.is_empty():
		var heat := 1.0 - smoothstep(0.0, cool_time * 2.0, _age)
		_smoke_wait = lerpf(0.5, 0.06, heat) / maxf(sqrt(float(_vents.size())) * 0.35, 1.0)
		var v: Vector4 = _vents.pick_random()
		var at := to_local(Vector2(v.x, v.y)) + Vector2(v.z, v.w) * 1.5
		_smoke.puff(at, Vector2(v.z, v.w) * 6.0 + Vector2(randf_range(-3, 3), -4.0),
				randf_range(1.2, 2.4), 1.0, randf_range(3.0, 5.5), 0.35 * strength + 0.1 * heat,
				0.6 * heat)
	# Repaint while cooling and fading; in between the marks hold still.
	_redraw_wait -= delta
	if _redraw_wait <= 0.0 and (_age < cool_time or _age > hold_time):
		_redraw_wait = 0.1
		queue_redraw()


## 1 while holding, easing to 0 over the fade.
func _strength() -> float:
	return 1.0 - smoothstep(hold_time, hold_time + fade_time, _age)


func _draw() -> void:
	var strength := _strength()
	var cool := clampf(_age / cool_time, 0.0, 1.0)
	for key: Vector2i in _pixels:
		var px: Vector3 = _pixels[key]
		var color := SOOT.lerp(CHAR, px.x)
		color.a = (0.55 + 0.4 * px.x) * strength
		if px.y > 0.0 and cool < 1.0:
			# Molten: white hot, through orange and red, to the char colour.
			var heat := px.y * (1.0 - cool)
			var f := (1.0 - heat) * float(MOLTEN.size() - 1)
			var i := mini(int(f), MOLTEN.size() - 2)
			var glow := MOLTEN[i].lerp(MOLTEN[i + 1], f - float(i))
			color = glow.lerp(color, smoothstep(0.55, 1.0, 1.0 - heat))
			color.a = maxf(color.a, heat)
		draw_rect(Rect2(to_local(Vector2(key)), Vector2.ONE), color)
