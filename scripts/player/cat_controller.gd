class_name CatController
extends CharacterBody3D
## Third-person cat controller. Movement input only: every action is a
## movement verb (move, jump, sprint, crouch). Camera-relative.
##
## Future ability hooks are intentionally empty. Search for "HOOK" below.

signal jumped
signal landed(impact_speed: float)
signal crouch_changed(is_crouching: bool)
signal ability_unlocked(ability: StringName)
## HOOK: emitted when dash is pressed in the air (or standing still).
signal dash_requested(direction: Vector3)
## HOOK: emitted when crouch is pressed in mid-air.
signal ground_pound_requested
signal fell_out_of_world

enum State { GROUND, RISING, FALLING }

@export_group("Speed")
@export var walk_speed := 3.0
@export var run_speed := 6.2
@export var crouch_speed := 1.4
@export var ground_acceleration := 28.0
@export var ground_deceleration := 34.0
@export var turn_smoothing := 14.0 ## Higher turns the model faster.

@export_group("Air")
@export var jump_velocity := 8.0
@export var gravity := 24.0
@export var fall_gravity_multiplier := 1.35
@export var max_fall_speed := 30.0
@export var jump_cut_multiplier := 0.5 ## Applied to upward speed when jump is released early.
@export var air_acceleration := 14.0
@export var air_deceleration := 3.0
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12

@export_group("Crouch")
@export var stand_height := 0.56
@export var crouch_height := 0.36
@export var crouch_model_scale := 0.78

@export_group("Squash and Stretch")
@export var jump_stretch := Vector3(0.86, 1.25, 0.86)
@export var land_squash_max := Vector3(1.25, 0.7, 1.25)
@export var squash_recovery := 12.0

@export_group("Misc")
## Cutscenes (wake-up intro, transformation) clear this to freeze player input.
@export var can_move := true
@export var respawn_below_y := -25.0
## The cat mesh faces +Z; rotate the model so its nose points along travel.
@export var model_yaw_offset := 0.0
@export var anim_walk_ref_speed := 2.6
@export var anim_run_ref_speed := 6.0

## HOOK: future abilities scale these. Both are consumed by the movement code.
var speed_multiplier := 1.0
var jump_multiplier := 1.0
## HOOK: future abilities are unlocked here (speed_boost, high_jump, dash, ground_pound).
var abilities := {
	&"speed_boost": false,
	&"high_jump": false,
	&"dash": false,
	&"ground_pound": false,
}

var state := State.GROUND
var is_crouching := false
var is_sprinting := false

var _coyote := 0.0
var _jump_buffer := 0.0
var _was_on_floor := true
var _last_fall_speed := 0.0
var _ground_speed := 0.0
var _squash := Vector3.ONE
var _spawn_transform: Transform3D
var _current_anim := &""
var _air_anim_started := false

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _model: Node3D = $Model
@onready var _anim: AnimationPlayer = $Model/Cat/AnimationPlayer
@onready var _capsule: CapsuleShape3D = _collision.shape


func _ready() -> void:
	_spawn_transform = global_transform
	_model.rotation.y = PI ## Spawn facing -Z (the mesh itself faces +Z).
	_capsule = _capsule.duplicate()
	_collision.shape = _capsule
	_apply_height(stand_height)
	_anim.animation_finished.connect(_on_anim_finished)
	_play(&"Idle")


func _physics_process(delta: float) -> void:
	var input := _get_input_vector() if can_move else Vector2.ZERO
	var wish_dir := _camera_relative(input)

	_update_crouch(delta)
	_update_timers(delta)
	_handle_jump_input()
	_apply_gravity(delta)
	_apply_horizontal(wish_dir, input.length(), delta)

	_last_fall_speed = velocity.y
	move_and_slide()
	_post_move()

	_update_facing(wish_dir, delta)
	_update_squash(delta)
	_update_animation()

	if global_position.y < respawn_below_y:
		respawn()


## Teleports back to where the cat started. Also resets physics interpolation.
func respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	fell_out_of_world.emit()


func set_can_move(value: bool) -> void:
	can_move = value


# --- HOOKS for future abilities (not implemented yet) ------------------------

## HOOK: called by a speed pad. Will set speed_multiplier for `duration` seconds.
func apply_speed_boost(_multiplier: float, _duration: float) -> void:
	pass


## HOOK: called by a jump pad. Will set jump_multiplier for `duration` seconds.
func apply_high_jump(_multiplier: float, _duration: float) -> void:
	pass


## HOOK: dash. Triggered by the dash input while airborne or standing still.
func perform_dash(direction: Vector3) -> void:
	dash_requested.emit(direction)


## HOOK: ground pound. Triggered by crouch input in mid-air.
func perform_ground_pound() -> void:
	ground_pound_requested.emit()


func unlock_ability(ability: StringName) -> void:
	if abilities.has(ability):
		abilities[ability] = true
		ability_unlocked.emit(ability)


# --- Input -------------------------------------------------------------------

func _get_input_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _camera_relative(input: Vector2) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	var yaw := cam.global_rotation.y if cam else 0.0
	var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	return dir.normalized() * minf(input.length(), 1.0)


# --- Movement ----------------------------------------------------------------

func _update_crouch(_delta: float) -> void:
	var want := can_move and Input.is_action_pressed("crouch")
	if want and not is_on_floor():
		if Input.is_action_just_pressed("crouch") and can_move:
			perform_ground_pound()
		want = false
	if want == is_crouching:
		return
	if not want and not _can_stand():
		return
	is_crouching = want
	_apply_height(crouch_height if want else stand_height)
	crouch_changed.emit(want)


func _can_stand() -> bool:
	var rise := stand_height - crouch_height
	return not test_move(global_transform, Vector3.UP * rise)


func _apply_height(height: float) -> void:
	_capsule.height = height
	_collision.position.y = height * 0.5


func _update_timers(delta: float) -> void:
	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	if can_move and Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)


func _handle_jump_input() -> void:
	if _jump_buffer > 0.0 and _coyote > 0.0 and not is_crouching:
		velocity.y = jump_velocity * jump_multiplier
		_jump_buffer = 0.0
		_coyote = 0.0
		_squash = jump_stretch
		_air_anim_started = false
		state = State.RISING
		jumped.emit()
	elif can_move and Input.is_action_just_pressed("dash") and not is_on_floor():
		perform_dash(-global_basis.z)
	# Variable jump height.
	if state == State.RISING and velocity.y > 0.0 and not Input.is_action_pressed("jump"):
		velocity.y *= jump_cut_multiplier


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := gravity
	if velocity.y < 0.0:
		g *= fall_gravity_multiplier
	velocity.y = maxf(velocity.y - g * delta, -max_fall_speed)


func _apply_horizontal(wish_dir: Vector3, strength: float, delta: float) -> void:
	var target_speed := walk_speed
	is_sprinting = false
	if is_crouching:
		target_speed = crouch_speed
	elif can_move and Input.is_action_pressed("dash") and is_on_floor():
		target_speed = run_speed
		is_sprinting = true
	target_speed *= speed_multiplier
	var on_floor := is_on_floor()
	if on_floor:
		_ground_speed = Vector2(velocity.x, velocity.z).length()
	else:
		# Keep sprint momentum through a jump instead of bleeding it off.
		target_speed = maxf(target_speed, _ground_speed)

	var target := wish_dir * target_speed * minf(strength, 1.0)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate: float
	if wish_dir == Vector3.ZERO:
		rate = ground_deceleration if on_floor else air_deceleration
	else:
		rate = ground_acceleration if on_floor else air_acceleration
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _post_move() -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		var impact := absf(_last_fall_speed)
		if impact > 3.0:
			var t := clampf(impact / 14.0, 0.0, 1.0)
			_squash = Vector3.ONE.lerp(land_squash_max, t)
		state = State.GROUND
		landed.emit(impact)
	if on_floor:
		state = State.GROUND
	elif state == State.GROUND:
		state = State.FALLING if velocity.y <= 0.0 else State.RISING
	if state == State.RISING and velocity.y <= 0.0:
		state = State.FALLING
	_was_on_floor = on_floor


# --- Visuals -----------------------------------------------------------------

func _update_facing(wish_dir: Vector3, delta: float) -> void:
	if wish_dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(wish_dir.x, wish_dir.z) + model_yaw_offset
	_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, 1.0 - exp(-turn_smoothing * delta))


## Facing direction of the cat's nose in world space (the camera follows this).
func get_heading() -> Vector3:
	return Vector3(sin(_model.rotation.y), 0.0, cos(_model.rotation.y))


func _update_squash(delta: float) -> void:
	_squash = _squash.lerp(Vector3.ONE, 1.0 - exp(-squash_recovery * delta))
	var crouch_scale := crouch_model_scale if is_crouching else 1.0
	var target := Vector3(1.0, crouch_scale, 1.0)
	_model.scale = _model.scale.lerp(target * _squash, 1.0 - exp(-20.0 * delta))


func _update_animation() -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if state != State.GROUND:
		if not _air_anim_started:
			_air_anim_started = true
			_play(&"Jump_Start", 0.05)
		elif _current_anim != &"Jump_Start" and _current_anim != &"Jump":
			_play(&"Jump", 0.15)
		return
	_air_anim_started = false
	if horizontal_speed < 0.25:
		_play(&"Idle", 0.2)
		_anim.speed_scale = 1.0
	elif horizontal_speed > (walk_speed + run_speed) * 0.5 and not is_crouching:
		_play(&"Run", 0.15)
		_anim.speed_scale = clampf(horizontal_speed / anim_run_ref_speed, 0.6, 1.6)
	else:
		_play(&"Walk", 0.15)
		_anim.speed_scale = clampf(horizontal_speed / anim_walk_ref_speed, 0.5, 1.6)


func _play(anim_name: StringName, blend := 0.15) -> void:
	if _current_anim == anim_name:
		return
	_current_anim = anim_name
	_anim.speed_scale = 1.0
	_anim.play(anim_name, blend)


func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name == &"Jump_Start" and state != State.GROUND:
		_current_anim = &""
		_play(&"Jump", 0.05)
