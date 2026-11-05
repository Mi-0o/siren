class_name HitboxOverlay
extends Node2D
## Dev view of every hitbox in the running scene, switched by the dev menu's SHOW HITBOXES:
## collision shapes of solid things in blue, the robot's body in green, other areas in yellow
## and live attack hitboxes (AttackHitbox) in red. The robot's body turns white while a dash
## makes it invulnerable, and pale cyan while it is still passing through an enemy after that. Drawn over the world, under the HUD.
##
## One instance lives under the scene tree's root, so the setting carries across scene changes.

const SOLID := Color(0.35, 0.6, 1.0)
const BODY := Color(0.3, 1.0, 0.45)
const AREA := Color(1.0, 0.85, 0.2)
const ATTACK := Color(1.0, 0.18, 0.12)
const INVULNERABLE := Color(1.0, 1.0, 1.0)
const PHASING := Color(0.45, 0.9, 1.0)
const FILL_ALPHA: float = 0.22

## Whether the overlay draws. Set through set_enabled() so the overlay exists.
static var enabled: bool = false
static var _instance: HitboxOverlay


static func set_enabled(on: bool, from: Node) -> void:
	enabled = on
	if on and not is_instance_valid(_instance) and from != null and from.is_inside_tree():
		_instance = HitboxOverlay.new()
		_instance.name = "HitboxOverlay"
		from.get_tree().root.add_child.call_deferred(_instance)


func _ready() -> void:
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	_draw_tree(scene)


func _draw_tree(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionShape2D:
			_draw_shape(child)
		elif child is CollisionPolygon2D:
			_draw_polygon(child)
		if child is SubViewport:
			continue
		_draw_tree(child)


func _color_for(owner_node: Node) -> Color:
	if owner_node is AttackHitbox:
		return ATTACK
	if owner_node is Player:
		var player := owner_node as Player
		if player.is_invulnerable():
			return INVULNERABLE
		if player.is_phasing():
			return PHASING
	if owner_node is CharacterBody2D:
		return BODY
	if owner_node is Area2D:
		return AREA
	return SOLID


## Skips shapes that aren't live: disabled ones, and attack hitboxes between strikes.
func _live(shape_node: Node2D, disabled: bool) -> bool:
	if disabled or not shape_node.is_visible_in_tree():
		return false
	var owner_node := shape_node.get_parent()
	if owner_node is AttackHitbox:
		return (owner_node as AttackHitbox).is_active()
	return owner_node is CollisionObject2D


func _draw_shape(node: CollisionShape2D) -> void:
	if node.shape == null or not _live(node, node.disabled):
		return
	var color := _color_for(node.get_parent())
	var t := node.global_transform
	var points := PackedVector2Array()
	var shape := node.shape
	if shape is RectangleShape2D:
		var h := (shape as RectangleShape2D).size * 0.5
		points = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), h, Vector2(-h.x, h.y)])
	elif shape is CircleShape2D:
		points = _ellipse(Vector2.ONE * (shape as CircleShape2D).radius)
	elif shape is CapsuleShape2D:
		var c := shape as CapsuleShape2D
		var r := c.radius
		var half := c.height * 0.5 - r
		for i in 9:
			points.append(Vector2.from_angle(PI + PI * float(i) / 8.0) * r + Vector2(0, -half))
		for i in 9:
			points.append(Vector2.from_angle(PI * float(i) / 8.0) * r + Vector2(0, half))
	elif shape is ConvexPolygonShape2D:
		points = (shape as ConvexPolygonShape2D).points
	elif shape is SegmentShape2D:
		var s := shape as SegmentShape2D
		draw_line(t * s.a, t * s.b, color, 1.0)
		return
	else:
		return
	_fill(t * points, color)


func _draw_polygon(node: CollisionPolygon2D) -> void:
	if node.polygon.size() < 3 or not _live(node, node.disabled):
		return
	_fill(node.global_transform * node.polygon, _color_for(node.get_parent()))


func _ellipse(radius: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 16:
		points.append(Vector2.from_angle(TAU * float(i) / 16.0) * radius)
	return points


func _fill(points: PackedVector2Array, color: Color) -> void:
	if Geometry2D.triangulate_polygon(points).size() > 0:
		draw_colored_polygon(points, Color(color, FILL_ALPHA))
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, 1.0)
