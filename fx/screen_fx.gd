class_name ScreenFx
extends Node
## Whole-screen effects: shaking the world, and glare (the picture washing out white as if the
## camera took in far too much light). One instance lives under the scene tree's root, made the
## first time anything asks for an effect, so it survives scene changes.
##
## The shake moves the world only (through the active Camera2D's offset, or the canvas when there
## is no camera); HUD and menus on CanvasLayers stay still. The glare
## sits above everything, HUD included, as a real overexposure would.

## Layer the glare draws on, above the HUD and menus.
const GLARE_LAYER: int = 120

static var _instance: ScreenFx

var _shake_time: float = 0.0
var _shake_total: float = 0.0
var _shake_strength: float = 0.0
var _shake_offset := Vector2.ZERO
var _glare_time: float = 0.0
var _glare_total: float = 0.0
var _glare_strength: float = 0.0
var _glare: ColorRect
## The camera the shake offset was last added to (null: the canvas itself).
var _shaken_camera: Camera2D


## Shakes the world by up to strength pixels, easing out over time seconds. A stronger shake
## replaces a weaker one in progress.
static func shake(from: Node, strength: float, time: float) -> void:
	# The screen shake setting turns every shake off.
	if not GameSettings.screen_shake:
		return
	var fx := _fx_for(from)
	if fx == null:
		return
	if strength * time >= fx._shake_strength * fx._shake_time:
		fx._shake_strength = strength
		fx._shake_time = time
		fx._shake_total = time


## Washes the screen out to white: strength 1 is a full white-out, fading over time seconds.
static func glare(from: Node, strength: float, time: float) -> void:
	var fx := _fx_for(from)
	if fx == null:
		return
	fx._glare_strength = maxf(strength, fx._glare_strength * fx._glare_fraction())
	fx._glare_time = time
	fx._glare_total = time


static func _fx_for(from: Node) -> ScreenFx:
	if is_instance_valid(_instance):
		return _instance
	if from == null or not from.is_inside_tree():
		return null
	_instance = ScreenFx.new()
	_instance.name = "ScreenFx"
	from.get_tree().root.add_child.call_deferred(_instance)
	return _instance


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = GLARE_LAYER
	add_child(layer)
	_glare = ColorRect.new()
	_glare.color = Color(1.0, 0.98, 0.94, 0.0)
	_glare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glare.set_anchors_preset(Control.PRESET_FULL_RECT)
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glare.material = material
	layer.add_child(_glare)


func _glare_fraction() -> float:
	return _glare_time / _glare_total if _glare_total > 0.0 else 0.0


func _process(delta: float) -> void:
	var viewport := get_viewport()
	# Take back last frame's offset, so whatever else moves the view keeps working. With a
	# camera the shake goes through its offset (the camera sets the canvas itself).
	if is_instance_valid(_shaken_camera):
		_shaken_camera.offset -= _shake_offset
	else:
		viewport.canvas_transform.origin -= _shake_offset
	_shake_offset = Vector2.ZERO
	_shaken_camera = null
	if _shake_time > 0.0:
		_shake_time = maxf(_shake_time - delta, 0.0)
		var k := _shake_time / _shake_total
		var amount := _shake_strength * k * k
		_shake_offset = Vector2(randf_range(-amount, amount), randf_range(-amount, amount)).round()
		if _shake_time <= 0.0:
			_shake_strength = 0.0
	var camera := viewport.get_camera_2d()
	if camera != null:
		_shaken_camera = camera
		camera.offset += _shake_offset
	else:
		var transform := viewport.canvas_transform
		transform.origin += _shake_offset
		viewport.canvas_transform = transform

	var a := 0.0
	if _glare_time > 0.0:
		_glare_time = maxf(_glare_time - delta, 0.0)
		# Blinding at first, then the eye adjusts quickly and the scene comes back.
		var f := _glare_fraction()
		a = _glare_strength * f * f
		if _glare_time <= 0.0:
			_glare_strength = 0.0
	_glare.color.a = a
	_glare.visible = a > 0.001
