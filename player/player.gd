extends CharacterBody2D
## Test player: walks left and right with the arrow keys and falls under gravity.

## Horizontal walking speed, in pixels per second.
@export var walk_speed: float = 120.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

	var direction := Input.get_axis("move_left", "move_right")
	velocity.x = direction * walk_speed

	move_and_slide()
