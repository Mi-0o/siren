class_name PlayerVisual
extends Node2D
## The robot's body: a Skeleton2D rig with one bone and one pixel-art part per body segment,
## ready for procedural animation. Only presentation lives here; the parent Player owns all
## physics and never reads anything back.
##
## The rig is rendered at native pixel scale inside the Rig SubViewport, so rotated limbs land
## on the game's pixel grid instead of turning into smooth high-resolution pixels when the window
## is scaled up. Display shows that render with a 1 px silhouette outline. Facing flips the
## skeleton around the hip.
##
## Bones, from the root: Hip, then ThighFar/ShinFar and ThighNear/ShinNear (no feet: the shins
## end in bare pegs), then Waist1/Waist2/Waist3 up to Ribcage, which carries Neck/Head and
## UpperArmFar/ForearmFar and UpperArmNear/ForearmNear. The rest pose saved in the scene is only
## an editor preview: in game the Animator sets every bone each frame.
##
## Motion comes from the Animator child (PlayerAnimator); this script only renders: facing,
## wires, and the eye with its scan beam.
##
## Exposed wires are drawn in code between points on two bones, so they stay attached and sag
## naturally whatever pose the bones are in. Loose ends hang towards the ground and trail behind
## movement. The red eye is the only light: it dims and stutters as charge falls through the
## Player's warning, critical and failing ratios, and goes dark at zero.

## Red glow around the eye: [pixel offset from the eye, opacity at full strength]. A soft
## diamond rather than a square, so it reads as light and not as a box.
const HALO: Array = [
	[Vector2(-1, 0), 0.3], [Vector2(1, 0), 0.3], [Vector2(0, -1), 0.3], [Vector2(0, 1), 0.3],
	[Vector2(-1, -1), 0.12], [Vector2(1, -1), 0.12], [Vector2(-1, 1), 0.12], [Vector2(1, 1), 0.12],
	[Vector2(-2, 0), 0.1], [Vector2(2, 0), 0.1], [Vector2(0, -2), 0.1], [Vector2(0, 2), 0.1],
]
const EYE_RED := Color(1.0, 0.16, 0.12)
## The eye's hot pixel, in the Head bone's local space.
const EYE_POINT := Vector2(5, -3)
## Scan beam: ray angles around the head's forward direction (radians), and length in pixels.
const SCAN_RAYS: Array[float] = [-0.14, -0.07, 0.0, 0.07, 0.14]
const SCAN_LENGTH: int = 22
## Offset to a pixel's centre, so mirrored lookups land on the same pixel.
const PIXEL_CENTER := Vector2(0.5, 0.5)
const WIRE_RED := Color(0.42, 0.12, 0.11)
const WIRE_GREEN := Color(0.17, 0.33, 0.21)
const WIRE_BLUE := Color(0.17, 0.24, 0.4)
const WIRE_BLACK := Color(0.09, 0.09, 0.1)
## Far-side wires get the same darkening as far-side limbs.
const FAR_TINT := Color(0.58, 0.6, 0.72)
## Wires strung between two bones: [from bone, from point, to bone, to point, sag in pixels,
## colour, in front of the body]. Points are pixels in each bone's local space.
const WIRES: Array = [
	[&"Head", Vector2(-2, 0), &"Ribcage", Vector2(-2, -6), 2.0, WIRE_RED, true],
	[&"Ribcage", Vector2(-2, -2), &"Hip", Vector2(-2, 0), 1.0, WIRE_BLUE, false],
	[&"Ribcage", Vector2(1, -1), &"Hip", Vector2(2, 0), 3.0, WIRE_GREEN, true],
	[&"ThighNear", Vector2(-1, 1), &"ShinNear", Vector2(-1, 3), 1.0, WIRE_BLACK, true],
	[&"ThighFar", Vector2(-1, 1), &"ShinFar", Vector2(-1, 3), 1.0, WIRE_BLACK, false],
	[&"UpperArmNear", Vector2(-1, 1), &"ForearmNear", Vector2(-1, 4), 1.0, WIRE_BLACK, true],
]
## Loose wires hanging from one bone: [bone, point, length in pixels, colour, in front].
## Their free ends are little pendulums in world space, so they swing with every lurch.
const LOOSE_WIRES: Array = [
	[&"Ribcage", Vector2(2, -3), 6.0, WIRE_RED, true],
	[&"Ribcage", Vector2(-2, -5), 5.0, WIRE_BLUE, false],
	[&"Hip", Vector2(1, 1), 5.0, WIRE_GREEN, true],
	[&"ForearmNear", Vector2(0, 5), 3.0, WIRE_RED, true],
	[&"Head", Vector2(0, 0), 3.0, WIRE_GREEN, true],
]
## Loose wire ends: gravity in px/s², and the fraction of speed kept per second.
const LOOSE_GRAVITY: float = 300.0
const LOOSE_DAMPING: float = 0.08
## The burst's heat line along the near arm: [bone, from, to] in each bone's local space, and
## its colour from cold to white hot.
const HEAT_LINE: Array = [
	[&"UpperArmNear", Vector2(0, 2), Vector2(0, 7)],
	[&"ForearmNear", Vector2(0, 1), Vector2(0, 9)],
]
const HEAT_RAMP: Array[Color] = [
	Color(0.45, 0.04, 0.02), Color(1.0, 0.12, 0.06), Color(1.0, 0.5, 0.1),
	Color(1.0, 0.9, 0.35), Color(1.0, 1.0, 1.0),
]
## Seconds the eye takes to stutter out after a core fault.
const DEATH_EYE_TIME: float = 2.2

## Every Bone2D of the rig by name, for procedural animation.
var bones: Dictionary[StringName, Bone2D] = {}

## Eye light level, from 0 (dark) to 1, before flicker.
var _light: float = 1.0
## Seconds left in a flicker dropout.
var _dropout_left: float = 0.0
## World position and velocity of each loose wire's free end.
var _loose_tips: PackedVector2Array = []
var _loose_velocities: PackedVector2Array = []
var _eye_glow: Sprite2D

@onready var player: Player = get_parent()
@onready var skeleton: Skeleton2D = $Rig/Skeleton
@onready var _display: Sprite2D = $Display
@onready var _halo: Node2D = $Display/Halo
@onready var _wires_back: Node2D = $Rig/WiresBack
@onready var _wires_front: Node2D = $Rig/WiresFront
@onready var _animator: PlayerAnimator = $Animator


func _ready() -> void:
	# Assigned here as well as in the scene: a ViewportTexture saved in a scene that is instanced
	# elsewhere can lose its path, and this keeps the game working if it does.
	_display.texture = ($Rig as SubViewport).get_texture()
	_collect_bones(skeleton)
	_fit_to_hitbox()
	_animator.setup(self)
	_eye_glow = bones[&"Head"].get_node("Glow")
	_wires_back.draw.connect(_draw_wires.bind(_wires_back, false))
	_wires_front.draw.connect(_draw_wires.bind(_wires_front, true))
	_halo.draw.connect(_draw_halo)


func _process(delta: float) -> void:
	# The Animator sets the skeleton's facing itself, flipping it mid-turn.
	_animator.animate(delta)
	_update_light(delta)
	_update_loose_wires(delta)
	_wires_back.queue_redraw()
	_wires_front.queue_redraw()
	_halo.queue_redraw()


## Stands the rig's ground line on the bottom of the collision rectangle, so the hitbox can be
## resized freely.
func _fit_to_hitbox() -> void:
	var collision: CollisionShape2D = player.get_node("CollisionShape2D")
	var bottom := collision.position.y + (collision.shape as RectangleShape2D).size.y / 2.0
	_display.position = Vector2(-PlayerAnimator.RIG_HIP_X, bottom - skeleton.position.y)


func _collect_bones(node: Node) -> void:
	for child in node.get_children():
		if child is Bone2D:
			bones[child.name] = child
			_collect_bones(child)


## Eye level follows charge in the same tiers that restrict abilities: full above the warning
## ratio, dimmer and stuttering lower down, dark at zero. Dead (core fault), it stutters out.
func _update_light(delta: float) -> void:
	var ratio := player.charge_ratio()
	var target := 1.0
	var flicker_rate := 0.15
	if ratio <= 0.0:
		target = 0.0
	elif ratio < player.failing_ratio:
		target = 0.3
		flicker_rate = 6.0
	elif ratio < player.critical_ratio:
		target = 0.55
		flicker_rate = 2.5
	elif ratio < player.warning_ratio:
		target = 0.8
		flicker_rate = 0.8
	if player.is_dead():
		# Core fault: the eye stutters on as the body goes down, fading, then goes out.
		var t := player.dead_time()
		target = 0.0 if t > DEATH_EYE_TIME else 0.9 * (1.0 - t / DEATH_EYE_TIME)
		flicker_rate = 14.0
		_light = minf(_light, target + 0.1)
	_light = move_toward(_light, target, delta * 3.0)

	_dropout_left -= delta
	if target > 0.0 and _dropout_left <= 0.0 and randf() < delta * flicker_rate:
		_dropout_left = randf_range(0.03, 0.12)
	var level := _light * _animator.eye_level
	_eye_glow.modulate.a = level * (0.25 if _dropout_left > 0.0 else 1.0)


func _update_loose_wires(delta: float) -> void:
	var to_world := _display.get_global_transform()
	if _loose_tips.size() != LOOSE_WIRES.size():
		_loose_tips.resize(LOOSE_WIRES.size())
		_loose_velocities.resize(LOOSE_WIRES.size())
		for i in LOOSE_WIRES.size():
			var wire: Array = LOOSE_WIRES[i]
			_loose_tips[i] = to_world * _rig_point(wire[0], wire[1]) + Vector2(0, wire[2])
	var keep := pow(LOOSE_DAMPING, delta)
	for i in LOOSE_WIRES.size():
		var wire: Array = LOOSE_WIRES[i]
		var anchor := to_world * _rig_point(wire[0], wire[1])
		var velocity := _loose_velocities[i] * keep + Vector2(0, LOOSE_GRAVITY * delta)
		var tip := _loose_tips[i] + velocity * delta
		# The wire is a rope: the end can swing and fold in, but never stretch past its length.
		var offset := tip - anchor
		var length: float = wire[2]
		if offset.length() > length:
			var normal := offset.normalized()
			tip = anchor + normal * length
			velocity -= normal * maxf(velocity.dot(normal), 0.0)
		_loose_tips[i] = tip
		_loose_velocities[i] = velocity


## Converts a pixel in a bone's local space to the rig viewport's pixel space.
## Goes through the Animator so that mid-turn the point follows the part as it is drawn.
func _rig_point(bone_name: StringName, local: Vector2) -> Vector2:
	return _animator.view_point(bone_name, local + PIXEL_CENTER)


func _draw_wires(canvas: Node2D, front: bool) -> void:
	for wire in WIRES:
		if wire[6] != front:
			continue
		var a := _rig_point(wire[0], wire[1])
		var b := _rig_point(wire[2], wire[3])
		# Sag straight down from the midpoint, whatever the bones' rotation.
		var control := (a + b) * 0.5 + Vector2(0, wire[4] * 2.0)
		_draw_curve(canvas, a, control, b, _wire_color(wire[5], wire[0]))
	if _loose_tips.size() != LOOSE_WIRES.size():
		return
	var to_rig := _display.get_global_transform().affine_inverse()
	for i in LOOSE_WIRES.size():
		var wire: Array = LOOSE_WIRES[i]
		if wire[4] != front:
			continue
		var a := _rig_point(wire[0], wire[1])
		var end := to_rig * _loose_tips[i]
		var length: float = wire[2]
		# Bow the slack downwards when the end swings up towards the anchor.
		var control := a.lerp(end, 0.5) + Vector2(0, maxf(length - a.distance_to(end), 0.0) * 0.6)
		var color := _wire_color(wire[3], wire[0])
		_draw_curve(canvas, a, control, end, color)
		# Frayed end: the bare strands show as one lighter pixel.
		canvas.draw_rect(Rect2(end.floor(), Vector2.ONE), color.lightened(0.35))


func _wire_color(color: Color, bone_name: StringName) -> Color:
	return color * Color.WHITE.lerp(FAR_TINT, _animator.shade(bone_name))


## Rasterises a quadratic curve to whole pixels.
func _draw_curve(canvas: Node2D, a: Vector2, control: Vector2, b: Vector2, color: Color) -> void:
	var steps := maxi(int(a.distance_to(b) * 2.0), 2)
	var last := Vector2(INF, INF)
	for i in steps + 1:
		var t := float(i) / steps
		var p := a.lerp(control, t).lerp(control.lerp(b, t), t).floor()
		if p != last:
			canvas.draw_rect(Rect2(p, Vector2.ONE), color)
			last = p


func _draw_halo() -> void:
	_draw_heat_line()
	var level := _eye_glow.modulate.a
	if level <= 0.0:
		return
	var p := _rig_point(&"Head", EYE_POINT).floor()
	var boost := 1.0 + _animator.scan
	for glow in HALO:
		var color := EYE_RED
		color.a = glow[1] * level * boost
		_halo.draw_rect(Rect2(p + glow[0], Vector2.ONE), color)
	if _animator.scan > 0.01:
		_draw_scan_beam(p, level * _animator.scan)


## The light along the near arm as the burst heats it: dull red, orange, yellow, white hot, with
## a glow spilling round it once it's hot.
func _draw_heat_line() -> void:
	var heat := player.burst_heat()
	if heat <= 0.01:
		return
	var color := _heat_color(heat)
	color.a = clampf(heat * 3.0, 0.0, 1.0)
	var glow := color
	glow.a = 0.35 * smoothstep(0.35, 1.0, heat)
	var drawn := {}
	for part in HEAT_LINE:
		var a := _rig_point(part[0], part[1]).floor()
		var b := _rig_point(part[0], part[2]).floor()
		var steps := maxi(int(a.distance_to(b)), 1)
		for i in steps + 1:
			var q := a.lerp(b, float(i) / float(steps)).round()
			if drawn.has(q):
				continue
			drawn[q] = true
	if glow.a > 0.0:
		for q: Vector2 in drawn:
			for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				if not drawn.has(q + o):
					_halo.draw_rect(Rect2(q + o, Vector2.ONE), glow)
	for q: Vector2 in drawn:
		_halo.draw_rect(Rect2(q, Vector2.ONE), color)


func _heat_color(heat: float) -> Color:
	var f := clampf(heat, 0.0, 1.0) * float(HEAT_RAMP.size() - 1)
	var i := mini(int(f), HEAT_RAMP.size() - 2)
	return HEAT_RAMP[i].lerp(HEAT_RAMP[i + 1], f - float(i))


## A faint dithered cone of red light from the eye, along the head's forward direction.
func _draw_scan_beam(eye: Vector2, strength: float) -> void:
	var head := bones[&"Head"].get_global_transform()
	# Mid-turn the beam points towards the camera and shortens with the yaw.
	var forward := _rig_point(&"Head", EYE_POINT + Vector2.RIGHT) - _rig_point(&"Head", EYE_POINT)
	forward = forward.normalized() * minf(forward.length() / head.x.length(), 1.0)
	if forward.length() < 0.2:
		return
	var drawn := {}
	for ray in SCAN_RAYS:
		var dir := forward.rotated(ray * signf(head.determinant()))
		for d in range(2, SCAN_LENGTH):
			var p := (eye + PIXEL_CENTER + dir * d).floor()
			if drawn.has(p) or int(p.x + p.y) % 2 != 0:
				continue
			drawn[p] = true
			var color := EYE_RED
			color.a = 0.22 * strength * (1.0 - float(d) / SCAN_LENGTH)
			_halo.draw_rect(Rect2(p, Vector2.ONE), color)
