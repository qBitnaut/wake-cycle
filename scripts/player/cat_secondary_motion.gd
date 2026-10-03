class_name CatSecondaryMotion
extends SkeletonModifier3D
## Procedural secondary motion layered over the animation (runs after the
## AnimationTree): the head leads turns and the tail lags and sways. Rotations
## are applied about skeleton-space axes (Y up, Z nose) so they do not depend
## on the imported bones' local axes. CatController feeds the inputs each tick.

## Radians the head leads the body into a turn (positive turns toward +X).
var head_lead := 0.0
## Body yaw rate, rad/s.
var yaw_rate := 0.0
## Vertical speed while airborne, m/s (0 on the ground).
var vertical_speed := 0.0
var move_speed := 0.0

var sway_degrees := 5.0
var sway_speed := 1.4
var tail_lag_per_turn_rate := 3.5
var tail_air_pitch := 1.5

## Fraction of the head lead taken by each neck bone, root first.
const NECK := {"Bone.004": 0.3, "Bone.005": 0.7}
const TAIL: Array[String] = ["Bone.016", "Bone.017", "Bone.018", "Bone.019"]
## Tail spring stiffness (rad/s) per segment; the tip is the loosest.
const TAIL_OMEGA := [16.0, 12.0, 9.0, 7.0]
const TAIL_ZETA := 0.45

var _neck: Array[int] = []
var _neck_weight: Array[float] = []
var _tail: Array[int] = []
var _tail_yaw := [0.0, 0.0, 0.0, 0.0]
var _tail_vel := [0.0, 0.0, 0.0, 0.0]
var _tail_pitch := 0.0
var _head := 0.0
var _time := 0.0
var _resolved := false


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if not _resolved:
		_resolve(skeleton)
	_time += delta
	var k := 1.0 - exp(-14.0 * delta)
	_head = lerpf(_head, head_lead, k)
	for i in _neck.size():
		_rotate(skeleton, _neck[i], Vector3.UP, _head * _neck_weight[i])

	# Tail: each segment is an underdamped spring chasing its share of the lag
	# target, so velocity changes whip through the chain with a delay.
	var sway := deg_to_rad(sway_degrees) * sin(_time * TAU * sway_speed * 0.5) \
			* (1.0 - clampf(move_speed / 4.0, 0.0, 0.6))
	var target := deg_to_rad(yaw_rate * tail_lag_per_turn_rate) + sway
	target = clampf(target, -0.9, 0.9)
	var pitch_target := deg_to_rad(clampf(-vertical_speed * tail_air_pitch, -25.0, 25.0))
	_tail_pitch = lerpf(_tail_pitch, pitch_target, 1.0 - exp(-6.0 * delta))
	for i in _tail.size():
		var omega: float = TAIL_OMEGA[i]
		var accel: float = omega * omega * (target / _tail.size() - _tail_yaw[i]) \
				- 2.0 * omega * TAIL_ZETA * _tail_vel[i]
		_tail_vel[i] += accel * delta
		_tail_yaw[i] += _tail_vel[i] * delta
		_rotate(skeleton, _tail[i], Vector3.UP, _tail_yaw[i])
		_rotate(skeleton, _tail[i], Vector3.RIGHT, _tail_pitch / _tail.size())


func _resolve(skeleton: Skeleton3D) -> void:
	_resolved = true
	for prefix in NECK:
		var idx := _find_bone(skeleton, prefix)
		if idx >= 0:
			_neck.append(idx)
			_neck_weight.append(NECK[prefix])
	for prefix in TAIL:
		var idx := _find_bone(skeleton, prefix)
		if idx >= 0:
			_tail.append(idx)


func _find_bone(skeleton: Skeleton3D, prefix: String) -> int:
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).begins_with(prefix + "_"):
			return i
	return -1


## Rotates a bone about a skeleton-space axis, keeping its position.
func _rotate(skeleton: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var global_basis := skeleton.get_bone_global_pose(bone).basis
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var rotated := Basis(axis, angle) * global_basis
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * rotated).orthonormalized().get_rotation_quaternion())
