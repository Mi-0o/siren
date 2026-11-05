class_name ScrapDebris
extends Node2D
## Dirt kicked up off a metal floor: puffs of dust, glinting metal flecks and dark bits of scrap
## that bounce and settle. Used when enemies rummage on the floor, burrow into it, come back up
## and squeeze through vents.
##
## ScrapDebris.kick() spawns one burst in the current scene; the node frees itself once every
## particle is gone. The floor is a flat line at the burst's own height (its origin), which is
## where the kicking happens. Whether a burst is essential (it shows where an enemy went, for
## the particles setting) is up to the caller.

const DUST := [Color(0.42, 0.38, 0.33, 0.55), Color(0.3, 0.28, 0.25, 0.4)]
const METAL := [Color(0.78, 0.8, 0.82), Color(0.55, 0.57, 0.6), Color(0.85, 0.66, 0.38)]
const SCRAP := [Color(0.16, 0.15, 0.15), Color(0.3, 0.17, 0.1), Color(0.24, 0.24, 0.25)]
const GRAVITY: float = 140.0

enum Kind { DUST, METAL, SCRAP }

var _p: Array[Dictionary] = []


## One burst at world pos (on the floor), thrown towards dir (x: -1 left, 1 right, 0 both ways;
## always upwards), with amount as a rough size (1 = a scratch, 4 = a hole dug).
static func kick(at: Vector2, dir: float, amount: float, essential: bool = false) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var fx := ScrapDebris.new()
	fx.z_index = 3
	tree.current_scene.add_child(fx)
	fx.global_position = at.round()
	fx._emit(dir, amount, essential)


func _emit(dir: float, amount: float, essential: bool) -> void:
	var dust := GameSettings.particle_count(roundi(3.0 * amount), essential)
	var metal := GameSettings.particle_count(roundi(2.0 * amount), essential)
	var scrap := GameSettings.particle_count(roundi(1.5 * amount), essential)
	for i in dust:
		_add(Kind.DUST, Vector2(randf_range(-2.0, 2.0), 0.0),
				Vector2(_side(dir) * randf_range(4.0, 18.0), randf_range(-14.0, -4.0)),
				randf_range(0.6, 1.3), DUST.pick_random())
	for i in metal:
		_add(Kind.METAL, Vector2(randf_range(-1.0, 1.0), -1.0),
				Vector2(_side(dir) * randf_range(15.0, 45.0), randf_range(-55.0, -20.0)),
				randf_range(0.5, 1.0), METAL.pick_random())
	for i in scrap:
		_add(Kind.SCRAP, Vector2(randf_range(-1.0, 1.0), -1.0),
				Vector2(_side(dir) * randf_range(8.0, 30.0), randf_range(-40.0, -15.0)),
				randf_range(1.2, 2.2), SCRAP.pick_random())
	if _p.is_empty():
		queue_free()


func _side(dir: float) -> float:
	if dir == 0.0:
		return -1.0 if randf() < 0.5 else 1.0
	return dir if randf() < 0.85 else -dir


func _add(kind: Kind, pos: Vector2, vel: Vector2, life: float, color: Color) -> void:
	_p.append({"kind": kind, "pos": pos, "vel": vel, "life": life, "max": life, "color": color,
			"size": 2 if kind == Kind.DUST and randf() < 0.4 else 1, "bounced": false})


func _process(delta: float) -> void:
	for i in range(_p.size() - 1, -1, -1):
		var p := _p[i]
		p.life -= delta
		if p.life <= 0.0:
			_p.remove_at(i)
			continue
		match p.kind:
			Kind.DUST:
				# Drifts up and out, slowing down.
				p.vel *= pow(0.25, delta)
				p.vel.y -= 3.0 * delta
			_:
				p.vel.y += GRAVITY * delta
		p.pos += p.vel * delta
		if p.kind != Kind.DUST and p.pos.y > 0.0:
			# Hits the floor: bounces once, then lies there.
			p.pos.y = 0.0
			if not p.bounced and p.vel.y > 25.0:
				p.bounced = true
				p.vel = Vector2(p.vel.x * 0.5, -p.vel.y * 0.3)
			else:
				p.vel = Vector2.ZERO
	if _p.is_empty():
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for p in _p:
		var c: Color = p.color
		var t: float = p.life / p.max
		match p.kind:
			Kind.DUST:
				c.a *= t
			Kind.METAL:
				# Glints as it tumbles.
				c.a = 1.0 if fmod(p.life * 23.0, 1.0) > 0.35 else 0.45
				c.a *= minf(t * 3.0, 1.0)
			_:
				c.a = minf(t * 2.5, 1.0)
		var at := (p.pos as Vector2).round() + Vector2(0.0, -1.0)
		draw_rect(Rect2(at, Vector2.ONE * p.size), c)
