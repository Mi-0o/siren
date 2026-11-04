class_name AttackHitbox
extends Area2D
## The damaging area of an attack: a melee strike, a plasma bolt, the charged burst. It only
## detects while active, so an attack can keep one around and switch it on for the frames that
## hit. Every active hitbox is in the "attack_hitboxes" group, which the dev menu's
## SHOW HITBOXES overlay draws in red.
##
## There is nothing to hit yet: hits are reported through the hit signal for enemies and
## breakables to come.

## Emitted once per target per activation, for any body or area that isn't the attacker.
signal hit(target: Node2D)

const GROUP: StringName = &"attack_hitboxes"

## Damage this hit deals, for whatever takes it.
@export var damage: float = 1.0
## Who made the attack: never hit, and never reported.
var attacker: Node

var _active: bool = false
var _hit_this_time: Array[Node] = []


func _init() -> void:
	# Attacks don't get hit by anything themselves; they look for everything.
	collision_layer = 0
	collision_mask = 0xFFFFFFFF
	monitorable = false
	monitoring = false


func _ready() -> void:
	body_entered.connect(_on_touch)
	area_entered.connect(_on_touch)


func is_active() -> bool:
	return _active


## Switches detection on or off. Each activation can hit the same target again.
func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	set_deferred(&"monitoring", active)
	if active:
		_hit_this_time.clear()
		add_to_group(GROUP)
	else:
		remove_from_group(GROUP)


func _on_touch(target: Node2D) -> void:
	if not _active or target == attacker or target in _hit_this_time:
		return
	if target is AttackHitbox:
		return
	_hit_this_time.append(target)
	hit.emit(target)
