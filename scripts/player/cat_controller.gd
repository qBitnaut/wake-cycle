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
## Emitted by show_augments() once the robotic parts are revealed.
signal augments_shown
## Emitted by hide_augments().
signal augments_hidden
## Emitted when the cat has been still long enough and starts to sit.
signal sat_down
## Emitted when a sitting cat gets up again.
signal stood_up

enum State { GROUND, RISING, FALLING }

## Raw model units from the origin down to the paws (the GLB is not centred
## on its feet); multiplied by cat_scale to stand the cat on the ground.
const FEET_OFFSET := 1.65

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
## Collider heights for the 0.1 scale tabby; the capsule radius is 0.12, so
## crouch_height cannot go below 0.24. Retune with cat_scale.
@export var stand_height := 0.3
@export var crouch_height := 0.24
@export var crouch_model_scale := 0.78

@export_group("Model")
## Uniform scale of the cat model. The GLB is ~4.6 units nose to rump, so 0.1
## makes a 0.46 m cat. Raise it for readability, then retune stand_height,
## crouch_height and the capsule radius to match (roughly 1.2 / 3.0 / 2.4 x scale).
@export var cat_scale := 0.1
## Idle: seconds of stillness before the cat sits down.
@export var sit_delay := 1.5
@export var breathing_amount := 0.015
@export var breathing_period := 3.2

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
## Ground speed (m/s) at which Walk / Run play at 1x. The clips have short
## strides (about 0.2 m/s of foot travel at 1x for a 0.1 scale cat), so true
## foot-lock at walk_speed would need ~14x playback. These values land at about
## 1.8x at walk_speed and run_speed, a brisk trot that still reads as a cat.
@export var anim_walk_ref_speed := 1.7
@export var anim_run_ref_speed := 3.4
@export var anim_speed_range := Vector2(0.5, 2.2)

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
var _idle_time := 0.0
var _land_hold := 0.0
var _landing := false
var _just_landed := false
var _breath_time := 0.0
var _breath_weight := 0.0
var _augments := {} ## Socket_* name -> hidden "Augment" Node3D.

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _model: Node3D = $Model
@onready var _cat: Node3D = $Model/Cat
@onready var _anim: AnimationPlayer = $Model/Cat/AnimationPlayer
@onready var _capsule: CapsuleShape3D = _collision.shape


## Applies cat_scale before the children (CatSkin, NanotechInfusion) run their
## _ready, so their bind-pose maths sees the final transform.
func _enter_tree() -> void:
	var cat := get_node_or_null("Model/Cat") as Node3D
	if cat:
		cat.scale = Vector3.ONE * cat_scale
		cat.position.y = FEET_OFFSET * cat_scale


func _ready() -> void:
	_spawn_transform = global_transform
	_model.rotation.y = PI ## Spawn facing -Z (the mesh itself faces +Z).
	_capsule = _capsule.duplicate()
	_collision.shape = _capsule
	_apply_height(stand_height)
	_anim.animation_finished.connect(_on_anim_finished)
	_collect_augments()
	_play(&"Stand")


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
	_update_animation(delta, input.length())

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


## Reveals the robotic augments on the sockets (all of them, or just the named
## ones, e.g. [&"Socket_Head"]). The sockets are BoneAttachment3D nodes on the
## skeleton, named Socket_Head, Socket_Spine, Socket_Tail, Socket_ForelegL/R and
## Socket_HindlegL/R (see scripts/import/cat_post_import.gd for the bones). Each
## has an empty, hidden "Augment" Node3D child: parent the robot parts there.
## Stub: it only toggles visibility and emits augments_shown; the parts and any
## reveal effect are future work.
func show_augments(sockets: Array[StringName] = []) -> void:
	for socket_name in _augments:
		if sockets.is_empty() or socket_name in sockets:
			(_augments[socket_name] as Node3D).visible = true
	augments_shown.emit()


func hide_augments() -> void:
	for socket_name in _augments:
		(_augments[socket_name] as Node3D).visible = false
	augments_hidden.emit()


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
		_just_landed = true
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
	# Subtle breathing while standing still, before the cat sits.
	_breath_weight = move_toward(_breath_weight, 1.0 if _current_anim == &"Stand" else 0.0, delta * 3.0)
	_breath_time += delta
	var breath := sin(_breath_time * TAU / breathing_period) * breathing_amount * _breath_weight
	target *= Vector3(1.0 - breath * 0.4, 1.0 + breath, 1.0 - breath * 0.4)
	_model.scale = _model.scale.lerp(target * _squash, 1.0 - exp(-20.0 * delta))


func _update_animation(delta: float, input_strength: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var moving := input_strength > 0.05 or horizontal_speed > 0.25
	if state != State.GROUND:
		_idle_time = 0.0
		_landing = false
		_land_hold = 0.0
		if not _air_anim_started:
			_air_anim_started = true
			# Walking off a ledge skips the push-off.
			if state == State.RISING:
				_play(&"Jump_Start", 0.05, 2.0)
			else:
				_play(&"Jump_Air", 0.15)
		elif _current_anim != &"Jump_Start" and _current_anim != &"Jump_Air":
			_play(&"Jump_Air", 0.15)
		return
	var was_airborne := _air_anim_started
	_air_anim_started = false
	if _just_landed:
		_just_landed = false
		# Only a real airborne spell lands; stepping off a kerb does not.
		_landing = was_airborne
		if _landing:
			_land_hold = 0.12 if moving else 0.45
			_play(&"Land", 0.05, 1.6)
	if _landing:
		_land_hold -= delta
		if _land_hold > 0.0:
			return
		_landing = false
	if moving:
		_idle_time = 0.0
		if _current_anim == &"Sit_Down" or _current_anim == &"Idle_Sit":
			stood_up.emit()
		# Quick blend out of a sit so control stays responsive.
		var blend := 0.1 if _current_anim == &"Sit_Down" or _current_anim == &"Idle_Sit" else 0.15
		if horizontal_speed > (walk_speed + run_speed) * 0.5 and not is_crouching:
			_play(&"Run", blend)
			_anim.speed_scale = clampf(horizontal_speed / anim_run_ref_speed, anim_speed_range.x, anim_speed_range.y)
		else:
			_play(&"Walk", blend)
			_anim.speed_scale = clampf(horizontal_speed / anim_walk_ref_speed, anim_speed_range.x, anim_speed_range.y)
		return
	_idle_time += delta
	if _idle_time >= sit_delay and not is_crouching:
		if _current_anim != &"Sit_Down" and _current_anim != &"Idle_Sit":
			_play(&"Sit_Down", 0.25)
			sat_down.emit()
	else:
		_play(&"Stand", 0.2)


## Plays a clip with a crossfade. speed is the playback rate for the new clip.
func _play(anim_name: StringName, blend := 0.15, speed := 1.0) -> void:
	if _current_anim == anim_name:
		return
	_current_anim = anim_name
	_anim.speed_scale = 1.0
	_anim.play(anim_name, blend, speed)


func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name == &"Jump_Start" and state != State.GROUND:
		_current_anim = &""
		_play(&"Jump_Air", 0.05)
	elif anim_name == &"Sit_Down" and _current_anim == &"Sit_Down":
		_play(&"Idle_Sit", 0.3)


func _collect_augments() -> void:
	for node in _cat.find_children("Socket_*", "BoneAttachment3D", true, false):
		var augment := node.get_node_or_null("Augment") as Node3D
		if augment:
			_augments[node.name] = augment
