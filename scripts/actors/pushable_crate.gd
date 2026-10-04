extends RigidBody2D
## Pushable crate. The cat shoves it by walking into it; the shockwave kicks it.


## Box centre (offset from origin) and half size, used for shockwave range checks.
var shock_offset := Vector2(0, -8)
var shock_half := Vector2(8, 8)


func _ready() -> void:
	add_to_group("pushable")
	add_to_group("shock_receiver")
	lock_rotation = true
	collision_layer = 1
	collision_mask = 1 | 16
	can_sleep = true


func on_shockwave(origin: Vector2, _radius: float, _source: String) -> void:
	sleeping = false
	var dir := (global_position - origin)
	var side := signf(dir.x) if absf(dir.x) > 1.0 else 1.0
	apply_central_impulse(Vector2(side * 110.0, -90.0) * mass)
