class_name CoreLight
extends Node2D
## Dev view (SHOW HEALTH in the dev menu): a small light floating above a body showing its core
## stage, in the HUD's colours: steady green when healthy, a slow yellow pulse when mild, an
## orange to red throb when heavy and solid bright red at fault. Drawn only while
## CoreDamage.show_lights is on.
##
## Robot and enemies each add one as a child. It asks its parent for core_stage() and sits
## height pixels above the parent's origin.

const GREEN := Color(0.25, 0.95, 0.45)
const YELLOW := Color(1.0, 0.84, 0.22)
const ORANGE := Color(1.0, 0.52, 0.1)
const RED_ORANGE := Color(1.0, 0.27, 0.07)
const FAULT_RED := Color(1.0, 0.12, 0.09)
const RIM := Color(0.04, 0.04, 0.05)

## Pixels above the parent's origin.
var height: float = 30.0

var _clock: float = 0.0


func _ready() -> void:
	z_index = 90
	position = Vector2(0.0, -height)


func _process(delta: float) -> void:
	_clock += delta
	visible = CoreDamage.show_lights
	if visible:
		queue_redraw()


func _draw() -> void:
	var parent := get_parent()
	if parent == null or not parent.has_method(&"core_stage"):
		return
	var stage: int = parent.call(&"core_stage")
	var color := GREEN
	match stage:
		1:
			color = YELLOW.darkened(0.35 * (0.5 + 0.5 * sin(_clock * 4.0)))
		2:
			color = ORANGE.lerp(RED_ORANGE, 0.5 + 0.5 * sin(_clock * 9.0))
		3:
			color = FAULT_RED
	# A 2x2 light in a dark rim, with a faint glow around it.
	var glow := color
	glow.a = 0.25
	draw_rect(Rect2(-3, -3, 6, 6), glow)
	draw_rect(Rect2(-2, -2, 4, 4), RIM)
	draw_rect(Rect2(-1, -1, 2, 2), color)
