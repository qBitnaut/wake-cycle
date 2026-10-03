class_name FollowCamera
extends Node3D
## Automatic third-person follow camera. There is deliberately NO camera
## input of any kind (movement-only restriction): it trails the cat, lags
## smoothly, and swings behind the cat's heading on its own.
## A SpringArm3D pulls the camera in so it never clips through walls.

@export var target_path: NodePath
@export var arm_length := 1.55 ## Tuned for the 0.13 scale tabby; scale with cat_scale.
@export var pitch_degrees := -22.0
@export var pivot_height := 0.21
@export var position_smoothing := 11.0
## How fast the camera yaw chases the heading (rad/s at full strength).
@export var yaw_follow_speed := 1.5
## Heading error (degrees) below which the camera holds still.
@export var yaw_deadzone_degrees := 12.0
## Beyond this angle the cat is running toward the camera, so we do not orbit.
@export var yaw_max_follow_degrees := 150.0
@export var min_speed_to_rotate := 0.8

var _target: CharacterBody3D
var _yaw := 0.0

@onready var _arm: SpringArm3D = $SpringArm3D
@onready var _camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	_target = get_node_or_null(target_path) as CharacterBody3D
	_arm.spring_length = arm_length
	if _target:
		_arm.add_excluded_object(_target.get_rid())
		global_position = _target.global_position + Vector3.UP * pivot_height
		var heading := _target_heading()
		_yaw = atan2(-heading.x, -heading.z)
	_apply_rotation()
	_camera.current = true


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var goal := _target.global_position + Vector3.UP * pivot_height
	global_position = global_position.lerp(goal, 1.0 - exp(-position_smoothing * delta))

	var horizontal := Vector3(_target.velocity.x, 0.0, _target.velocity.z)
	if horizontal.length() > min_speed_to_rotate:
		var desired := atan2(-horizontal.x, -horizontal.z)
		var diff := wrapf(desired - _yaw, -PI, PI)
		var abs_deg := rad_to_deg(absf(diff))
		var dead := yaw_deadzone_degrees
		var max_deg := yaw_max_follow_degrees
		var weight := clampf((abs_deg - dead) / 30.0, 0.0, 1.0)
		# Sideways travel (about 90 degrees off) turns the camera gently so a held
		# strafe does not whip the view around.
		weight *= 1.0 - 0.55 * clampf((abs_deg - 50.0) / 40.0, 0.0, 1.0)
		if abs_deg > max_deg:
			weight *= clampf(1.0 - (abs_deg - max_deg) / 20.0, 0.0, 1.0)
		var step := signf(diff) * minf(absf(diff), yaw_follow_speed * weight * delta)
		_yaw += step
	_apply_rotation()


func _apply_rotation() -> void:
	rotation = Vector3(deg_to_rad(pitch_degrees), _yaw, 0.0)


func _target_heading() -> Vector3:
	if _target.has_method("get_heading"):
		return _target.get_heading()
	return -_target.global_basis.z
