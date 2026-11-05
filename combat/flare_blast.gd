class_name FlareBlast
extends Node2D
## The charged burst going off: an instant, blinding explosion filling a cone (angle degrees
## wide) from the arm out to the edge of the screen. The cone of light itself lasts only a blink
## (flash_time); what follows is the aftermath: fireballs blooming through the cone, electric
## arcs crackling across it, sparks and embers flung everywhere and a thick bank of smoke that
## rolls up and hangs for seconds. It shakes the screen and washes it almost white. Every
## surface in the cone is scorched (Scorch): charred, with molten spots, smouldering.
##
## The cone is drawn as one polygon with a brightness gradient, and every glow is additive, so
## nothing shows overlapping layers as it fades.
##
## The explosion itself is a field of fireballs that fills the whole cone: it rolls out from the
## muzzle to the edge in a tenth of a second, each fireball swelling white-yellow to orange to a
## dull red, with smaller secondary pops going off after, a shockwave front racing out ahead and
## dark debris flung through it. Overlapping fireballs add up, so the cone has no gaps.
##
## Its AttackHitbox covers a wider cone (hit_angle) out to the same reach, for the flash only.

const WHITE := Color(1.0, 1.0, 1.0)
const WARM := Color(1.0, 0.9, 0.7)
const FIRE := Color(1.0, 0.62, 0.22)
const ARC := Color(0.75, 0.93, 1.0)
const ARC_CORE := Color(0.95, 1.0, 1.0)
const FIRE_OUTER := Color(0.85, 0.25, 0.06)
const FIRE_MID := Color(1.0, 0.58, 0.16)
const FIRE_CORE := Color(1.0, 0.93, 0.7)
const DEBRIS: Array[Color] = [
	Color(0.16, 0.15, 0.14), Color(0.1, 0.09, 0.09), Color(0.24, 0.2, 0.17), Color(0.08, 0.07, 0.07),
]
## Fireballs filling the cone, and the smaller pops that go off after.
const FIREBALLS: int = 120
const POPS: int = 36
## Seconds the shockwave front takes to cross the cone.
const SHOCK_TIME: float = 0.22
## Smoke puffs that roll in as the fire dies.
const SMOKE_PUFFS: int = 90
## Points along the cone's far edge.
const EDGE_POINTS: int = 13
## Rays cast across the cone to find surfaces to scorch.
const SCORCH_RAYS: int = 56

## Direction the cone points (unit, horizontal), its full angle in degrees, and how far out it
## reaches horizontally, in pixels.
var direction := Vector2.RIGHT
var angle: float = 60.0
## Full angle of the attack hitbox's cone, in degrees, a little wider than the visible blast.
var hit_angle: float = 75.0
var reach: float = 240.0
## Seconds the cone of light lasts, and seconds the arcs crackle.
var flash_time: float = 0.11
var arc_time: float = 0.45
var damage: float = 10.0
var attacker: Node

var _age: float = 0.0
var _hitbox: AttackHitbox
var _light: Node2D
var _sparks := PixelSparks.new()
var _embers := PixelSparks.new()
var _debris := PixelSparks.new()
var _dark: Node2D
## Fireballs: position, drift velocity, start delay, life and full radius.
var _fb_pos := PackedVector2Array()
var _fb_vel := PackedVector2Array()
var _fb_delay := PackedFloat32Array()
var _fb_life := PackedFloat32Array()
var _fb_radius := PackedFloat32Array()
var _arcs: Array[PackedVector2Array] = []
var _arc_wait: float = 0.0
var _smoke: Smoke
var _smoke_left: int = SMOKE_PUFFS
var _ray := PhysicsRayQueryParameters2D.new()


func _ready() -> void:
	z_index = 30
	_light = Node2D.new()
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light.material = material
	_light.z_index = 2
	add_child(_light)
	_light.draw.connect(_draw_light)
	_dark = Node2D.new()
	_dark.z_index = 3
	add_child(_dark)
	_dark.draw.connect(_draw_dark)
	_smoke = Smoke.new()
	_smoke.free_when_empty = false
	_smoke.essential = true
	_smoke.add_to_group(Scorch.GROUP)
	_smoke.buoyancy = 9.0
	_smoke.damping = 0.35
	_smoke.z_index = 1
	add_child(_smoke)

	_hitbox = AttackHitbox.new()
	_hitbox.attacker = attacker
	_hitbox.damage = damage
	var polygon := CollisionPolygon2D.new()
	polygon.polygon = _cone(hit_angle)
	_hitbox.add_child(polygon)
	add_child(_hitbox)
	_hitbox.set_active(true)

	var half := deg_to_rad(angle) * 0.5
	var heading := direction.angle()
	# The fireball field: spread evenly over the cone's area, going off in a wave from the
	# muzzle out, bigger further out where the cone is wider.
	_add_fireball(Vector2.ZERO, 0.0, 0.5, 15.0)
	for i in FIREBALLS:
		var p := _point_in_cone(0.5)
		var d := p.length() / reach
		_add_fireball(p, d * 0.1 + randf_range(0.0, 0.03), randf_range(0.35, 0.65),
				randf_range(7.0, 11.0 + 17.0 * d))
	for i in POPS:
		var p := _point_in_cone(0.7)
		_add_fireball(p, randf_range(0.14, 0.5), randf_range(0.22, 0.4), randf_range(5.0, 12.0))
	_debris.colors = DEBRIS
	_debris.gravity = 320.0
	_debris.damping = 0.4
	# Particles setting: the cone's sparks, the debris and the smoke are essential (they show
	# the blast); the backward spray and the embers are decoration.
	_debris.essential = true
	_debris.emit(Vector2.ZERO, 60, heading, half, 140.0, 460.0, 0.5, 1.2)
	_sparks.colors = [WHITE, WARM, FIRE, Color(FIRE, 0.5)]
	_sparks.gravity = 90.0
	_sparks.damping = 0.08
	_sparks.essential = true
	_sparks.emit(Vector2.ZERO, 260, heading, half * 1.05, 120.0, 620.0, 0.15, 0.7)
	_sparks.essential = false
	_sparks.emit(Vector2.ZERO, 50, heading, PI, 40.0, 200.0, 0.1, 0.4)
	_embers.colors = [WARM, FIRE, Color(0.9, 0.3, 0.08), Color(0.5, 0.12, 0.04, 0.7)]
	_embers.gravity = 160.0
	_embers.damping = 0.3
	for i in 70:
		_embers.emit(_point_in_cone(), 1, -PI / 2.0, 1.4, 20.0, 90.0, 0.8, 2.2)
	_new_arcs()
	_scorch_surfaces()
	ScreenFx.shake(self, 9.0, 0.85)
	ScreenFx.glare(self, 0.97, 1.1)


func _process(delta: float) -> void:
	_age += delta
	_sparks.update(delta)
	_embers.update(delta)
	_debris.update(delta)
	var keep := pow(0.3, delta)
	for i in _fb_pos.size():
		if _age >= _fb_delay[i]:
			_fb_vel[i] = _fb_vel[i] * keep + Vector2(0.0, -40.0 * delta)
			_fb_pos[i] += _fb_vel[i] * delta
	if _age >= flash_time:
		_hitbox.set_active(false)
	# The smoke rolls in behind the fire over the first moments.
	var due := int(float(SMOKE_PUFFS) * smoothstep(0.05, 0.6, _age))
	while SMOKE_PUFFS - _smoke_left < due and is_instance_valid(_smoke):
		_smoke_left -= 1
		var p := _point_in_cone()
		var d := p.length() / reach
		_smoke.puff(p, direction * randf_range(5.0, 30.0) + Vector2(randf_range(-10, 10), -6),
				randf_range(2.5, 6.0), randf_range(4.0, 8.0), randf_range(9.0, 14.0 + 12.0 * d),
				randf_range(0.45, 0.7) * (1.0 - 0.3 * d), 1.0)
	if _age < arc_time:
		_arc_wait -= delta
		if _arc_wait <= 0.0:
			_arc_wait = 0.035
			_new_arcs()
	elif not _arcs.is_empty():
		_arcs.clear()
	var smoke_gone := not is_instance_valid(_smoke) or _smoke.is_empty()
	if _age > 1.5 and _sparks.is_empty() and _embers.is_empty() and _debris.is_empty() \
			and smoke_gone:
		queue_free()
		return
	_light.queue_redraw()
	_dark.queue_redraw()


func _add_fireball(at: Vector2, delay: float, life: float, radius: float) -> void:
	_fb_pos.append(at)
	_fb_vel.append(direction * randf_range(15.0, 60.0) + Vector2(0.0, -randf_range(5.0, 30.0)))
	_fb_delay.append(delay)
	_fb_life.append(life)
	_fb_radius.append(radius)


## A cone of full_angle degrees (the blast's own angle by default): from the muzzle out to
## reach, its far edge straight up and down.
func _cone(full_angle: float = -1.0) -> PackedVector2Array:
	var half := deg_to_rad(angle if full_angle < 0.0 else full_angle) * 0.5
	var points := PackedVector2Array([Vector2.ZERO])
	for i in EDGE_POINTS:
		var a := -half + 2.0 * half * float(i) / float(EDGE_POINTS - 1)
		points.append(_edge_point(a))
	return points


## Where a ray at angle a off the heading meets the cone's far edge.
func _edge_point(a: float) -> Vector2:
	var forward := reach
	return direction * forward + Vector2(-direction.y, direction.x) * forward * tan(a)


## A random point in the cone. bias 1.3 crowds them towards the muzzle, where the blast is
## densest; 0.5 spreads them evenly over the area.
func _point_in_cone(bias: float = 1.3) -> Vector2:
	var half := deg_to_rad(angle) * 0.5
	var a := randf_range(-half, half)
	var d := pow(randf(), bias)
	return _edge_point(a) * d


## Fresh jagged arcs: bolts from the muzzle forking out through the cone, and short ones
## jumping between points inside it.
func _new_arcs() -> void:
	_arcs.clear()
	var fade := 1.0 - _age / arc_time
	var count := int(round(lerpf(3.0, 10.0, fade)))
	for i in count:
		var from := Vector2.ZERO if randf() < 0.5 else _point_in_cone() * 0.5
		var to := _point_in_cone()
		_arcs.append(_jagged(from, to))


func _jagged(from: Vector2, to: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([from])
	var steps := maxi(int(from.distance_to(to) / 7.0), 2)
	var side := (to - from).orthogonal().normalized()
	for i in range(1, steps):
		var p := from.lerp(to, float(i) / float(steps))
		points.append((p + side * randf_range(-4.0, 4.0)).round())
	points.append(to)
	return points


## Scorches whatever the cone hits first along a fan of rays.
func _scorch_surfaces() -> void:
	var space := get_world_2d().direct_space_state
	_ray.collide_with_areas = false
	if attacker is CollisionObject2D:
		# The level only: enemies don't stop the blast or take scorch marks.
		_ray.collision_mask = (attacker as CollisionObject2D).collision_mask & ~Enemy.ENEMY_LAYER
		_ray.exclude = [(attacker as CollisionObject2D).get_rid()]
	var scorch := Scorch.new()
	scorch.set_solids(space, _ray.collision_mask, _ray.exclude)
	var half := deg_to_rad(angle) * 0.5
	var burned := 0
	for i in SCORCH_RAYS:
		var a := -half + 2.0 * half * (float(i) + randf_range(0.2, 0.8)) / float(SCORCH_RAYS)
		_ray.from = global_position
		_ray.to = global_position + _edge_point(a) * 1.15
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			continue
		var d: float = global_position.distance_to(hit.position) / reach
		scorch.burn(hit.position, hit.normal, lerpf(1.3, 0.7, clampf(d, 0.0, 1.0)))
		burned += 1
	if burned > 0 and not scorch.is_empty():
		get_parent().add_child(scorch)
	else:
		scorch.free()


func _draw_light() -> void:
	# The flash: the whole cone blazing white at the muzzle, warm at the edge, gone in a blink.
	if _age < flash_time:
		var f := 1.0 - _age / flash_time
		var cone := _cone()
		var colors := PackedColorArray([Color(WHITE, f)])
		for i in range(1, cone.size()):
			colors.append(Color(WARM, 0.75 * f))
		_light.draw_polygon(cone, colors)
	# The shockwave front racing out ahead of the fire.
	if _age < SHOCK_TIME:
		var t := _age / SHOCK_TIME
		var radius := reach * 1.25 * (1.0 - pow(1.0 - t, 2.0))
		var half := deg_to_rad(angle) * 0.5
		var heading := direction.angle()
		_light.draw_arc(Vector2.ZERO, radius, heading - half, heading + half, 40,
				Color(WARM, 0.6 * (1.0 - t)), 4.0)
		_light.draw_arc(Vector2.ZERO, radius, heading - half, heading + half, 40,
				Color(WHITE, 0.9 * (1.0 - t)), 1.0)
	# The fireballs: each swells fast, burning white-yellow at the heart, then orange, then a
	# dull red as it dies.
	for i in _fb_pos.size():
		var t := (_age - _fb_delay[i]) / _fb_life[i]
		if t < 0.0 or t >= 1.0:
			continue
		var grow := 0.4 + 0.6 * sqrt(minf(t * 1.6, 1.0))
		var r := int(round(_fb_radius[i] * grow))
		var p := _fb_pos[i].floor()
		_blob(p, r, Color(FIRE_OUTER, 0.5 * pow(1.0 - t, 1.3)))
		_blob(p, int(round(r * 0.72)), Color(FIRE_MID, 0.7 * pow(1.0 - t, 1.8)))
		if t < 0.7:
			_blob(p, int(round(r * 0.42)), Color(FIRE_CORE, pow(1.0 - t / 0.7, 2.0)))
	# Arcs: a pale blue-white bolt with a brighter core.
	for arc in _arcs:
		_light.draw_polyline(arc, Color(ARC, 0.55), 2.0)
		_light.draw_polyline(arc, ARC_CORE, 1.0)
	# The muzzle stays white hot for a moment.
	if _age < 0.3:
		var r := int(round(6.0 * (1.0 - _age / 0.3))) + 1
		_light.draw_texture(Smoke.disc(r), Vector2(-r, -r), Color(WHITE, 1.0 - _age / 0.3))
	_sparks.draw(_light)
	_embers.draw(_light)


func _blob(at: Vector2, r: int, color: Color) -> void:
	if r < 1:
		return
	_light.draw_texture(Smoke.disc(r), at - Vector2(r, r), color)


## Debris: dark chunks of whatever was in the way, drawn normally (not additive).
func _draw_dark() -> void:
	_debris.draw(_dark)
