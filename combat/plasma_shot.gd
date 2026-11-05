class_name PlasmaShot
extends Node2D
## A plasma bolt from the robot's arm cannon: a hot white core in an amber glow with a short
## streak behind it, flying straight and very fast. It carries its AttackHitbox with it and,
## the moment it touches anything solid or an enemy, goes off in a tiny explosion (PlasmaBurst);
## an enemy it hits takes the hit (Enemy.take_hit). A bolt
## that hits nothing is dropped once it is DESPAWN_MARGIN pixels off screen.
##
## Collision is a ray along each frame's travel, so even at this speed it can't skip through a
## thin wall.

const CORE := Color(1.0, 0.98, 0.9)
const HOT := Color(1.0, 0.82, 0.45)
const GLOW := Color(1.0, 0.55, 0.15)
## Streak length behind the bolt, in pixels.
const TRAIL: float = 12.0
## A bolt that hit nothing is dropped once it is this far outside the screen, in pixels.
const DESPAWN_MARGIN: float = 100.0

## Flight direction (unit) and speed in pixels per second.
var direction := Vector2.RIGHT
var speed: float = 880.0
## Who fired it: never hit.
var shooter: CollisionObject2D
var damage: float = 1.0

var _hitbox: AttackHitbox
var _ray := PhysicsRayQueryParameters2D.new()
var _age: float = 0.0
var _spawn: Vector2


func _ready() -> void:
	z_index = 20
	_spawn = global_position
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	self.material = material
	_hitbox = AttackHitbox.new()
	_hitbox.attacker = shooter
	_hitbox.damage = damage
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6, 4)
	shape.shape = rect
	_hitbox.add_child(shape)
	_hitbox.rotation = direction.angle()
	add_child(_hitbox)
	_hitbox.set_active(true)
	# The level and every enemy (the shooter's own mask covers both for the robot).
	_ray.collision_mask = (shooter.collision_mask if shooter != null else 0xFFFFFFFF) | Enemy.ENEMY_LAYER
	if shooter != null:
		_ray.exclude = [shooter.get_rid()]
	_ray.collide_with_areas = false


func _physics_process(delta: float) -> void:
	_age += delta
	var viewport := get_viewport()
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	if not view.grow(DESPAWN_MARGIN).has_point(global_position):
		queue_free()
		return
	var step := direction * speed * delta
	_ray.from = global_position
	_ray.to = global_position + step
	var hit := get_world_2d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		# The bolt's hitbox may already have hit it (it reaches a little ahead); either way it's
		# one hit, so the hitbox is told not to count it again.
		if hit.collider is Enemy and not (hit.collider in _hitbox._hit_this_time):
			_hitbox._hit_this_time.append(hit.collider)
			(hit.collider as Enemy).take_hit(damage, shooter)
		_burst(hit.position, hit.normal)
		return
	global_position += step
	queue_redraw()


func _burst(point: Vector2, normal: Vector2) -> void:
	var burst := PlasmaBurst.new()
	burst.normal = normal
	burst.position = get_parent().to_local(point) if get_parent() is Node2D else point
	get_parent().add_child(burst)
	queue_free()


func _draw() -> void:
	# Never trail back past the muzzle.
	var trail := minf(TRAIL, global_position.distance_to(_spawn))
	var back := -direction
	for i in int(trail):
		var t := float(i) / TRAIL
		var c := GLOW
		c.a = 0.55 * (1.0 - t)
		draw_rect(Rect2((back * float(i)).floor(), Vector2.ONE), c)
		if i < trail * 0.5:
			var h := HOT
			h.a = 0.6 * (1.0 - t * 2.0)
			draw_rect(Rect2((back * float(i)).floor(), Vector2.ONE), h)
	# Halo, then hot ring, then core.
	var flicker := 0.85 + 0.15 * sin(_age * 90.0)
	for offset: Vector2 in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		draw_rect(Rect2(offset + Vector2(-0.5, -0.5), Vector2.ONE), Color(GLOW, 0.35 * flicker))
	for offset: Vector2 in [
		Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
		Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1),
	]:
		draw_rect(Rect2(offset + Vector2(-0.5, -0.5), Vector2.ONE), Color(HOT, 0.6 * flicker))
	draw_rect(Rect2(Vector2(-1.0, -0.5), Vector2(2, 1)), CORE)
