class_name CatController
extends CharacterBody3D
## Third-person cat controller. Movement input only: every action is a
## movement verb (move, jump, sprint, crouch). Camera-relative.
##
## Feel: light and quick. Walk and Run are blended by speed in an
## AnimationTree, every state change is a crossfade, the body banks into turns,
## and CatSecondaryMotion adds head lead and tail lag after the animation.
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
const SecondaryMotion := preload("res://scripts/player/cat_secondary_motion.gd")

@export_group("Speed")
@export var walk_speed := 2.3
@export var run_speed := 5.0
@export var crouch_speed := 1.1
## Ground acceleration (m/s^2). Walk speed is reached in about 0.1 s.
@export var ground_acceleration := 24.0
## Extra multiplier on acceleration while below start_burst_fraction of the
## target speed: a cat bursts into motion.
@export var start_burst_multiplier := 1.6
@export_range(0.0, 1.0) var start_burst_fraction := 0.4
@export var ground_deceleration := 26.0
## Below stop_soft_speed (m/s) the deceleration eases to this fraction, so the
## cat settles instead of dead-stopping.
@export_range(0.1, 1.0) var stop_softness := 0.5
@export var stop_soft_speed := 1.0
## Extra acceleration when the wish direction is more than ~60 degrees off the
## current velocity, so sharp turns carve quickly instead of drifting.
@export var turn_acceleration_boost := 1.5

@export_group("Turning")
## Natural frequency (rad/s) of the yaw spring. Higher is snappier.
@export var turn_response := 19.0
## 1.0 settles without overshoot; below 1.0 gives a hint of life.
@export var turn_damping := 0.85
@export var max_turn_rate := 15.0 ## rad/s
## Roll into a turn: degrees of lean per (rad/s of yaw rate) per (m/s of speed).
@export var lean_per_turn_rate := 0.55
@export var max_lean_degrees := 11.0
## Nose pitch from acceleration, degrees per (m/s^2). Negative lifts the nose
## when speeding up and dips it when braking.
@export var accel_pitch_gain := -0.18
@export var max_accel_pitch_degrees := 5.0
## Nose up while rising and down while falling, degrees per (m/s) of vertical speed.
@export var air_pitch_per_speed := 2.2
@export var max_air_pitch_degrees := 14.0
@export var lean_smoothing := 12.0

@export_group("Air")
## Take-off speed (m/s). With gravity 17 and the apex hang the cat peaks at
## roughly 0.85 m, about 3.5x its shoulder height.
@export var jump_velocity := 5.5
@export var gravity := 17.0
@export var fall_gravity_multiplier := 1.3
## Gravity is scaled by this near the top of the arc for a little hang time.
@export_range(0.1, 1.0) var apex_gravity_multiplier := 0.45
## Vertical speed (m/s) below which the apex hang is fully in effect.
@export var apex_window := 1.8
@export var max_fall_speed := 20.0
@export var jump_cut_multiplier := 0.55 ## Applied once to upward speed when jump is released early.
@export var air_acceleration := 16.0
@export var air_deceleration := 2.5
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12

@export_group("Crouch")
## Collider heights for the 0.13 scale tabby (about 3.0x and 2.4x cat_scale);
## the capsule radius is 0.156, so crouch_height cannot go below 0.312.
@export var stand_height := 0.39
@export var crouch_height := 0.312
@export var crouch_model_scale := 0.8

@export_group("Model")
## Uniform scale of the cat model. The GLB is ~4.6 units nose to rump, so 0.13
## makes a 0.6 m cat. Retune stand_height, crouch_height and the capsule radius
## (roughly 3.0 / 2.4 / 1.2 x scale), the camera, and the anim ref speeds with it.
@export var cat_scale := 0.13
## Idle: seconds of stillness before the cat sits down.
@export var sit_delay := 1.5
@export var breathing_amount := 0.015
@export var breathing_period := 3.2

@export_group("Squash and Stretch")
@export var jump_stretch := Vector3(0.95, 1.08, 0.95)
@export var land_squash_max := Vector3(1.09, 0.88, 1.09)
@export var squash_recovery := 12.0

@export_group("Animation")
## Ground speed (m/s) at which the Walk / Run clips play at 1x with the stance
## paws locked to the ground. Measured from the clips at cat_scale 0.13: Walk
## stance paws travel 1.35 model units/s (0.175 m/s) and Run front paws 4.5
## units/s (0.585 m/s). The clips have short strides, so true foot-lock needs
## more playback than looks sane; anim_speed_max caps it.
@export var anim_walk_ref_speed := 0.175
@export var anim_run_ref_speed := 0.585
@export var anim_speed_min := 0.6
@export var anim_speed_max := 4.2
@export var anim_crouch_speed_max := 2.2
## Ground speed range (m/s) over which Walk is blended into Run.
@export var gait_blend_start := 1.2
@export var gait_blend_end := 3.2
## Speed (m/s) at which Stand is fully replaced by the gait blend.
@export var idle_blend_speed := 0.7
@export var gait_smoothing := 10.0
@export_group("Animation Crossfades")
@export var fade_to_ground := 0.18
@export var fade_ground_after_land_moving := 0.12
@export var fade_ground_after_land_still := 0.22
@export var fade_to_jump := 0.06
@export var fade_to_air := 0.12
@export var fade_to_land := 0.07
@export var fade_to_sit := 0.3
@export var fade_stand_up := 0.12
@export var jump_start_speed := 2.4
@export var land_speed := 1.6

@export_group("Secondary Motion")
@export var secondary_motion_enabled := true
## Head leads a turn by this fraction of the remaining turn angle.
@export_range(0.0, 1.0) var head_lead := 0.5
@export var head_lead_max_degrees := 24.0
## Tail yaw lag, degrees per (rad/s of body yaw rate).
@export var tail_lag_per_turn_rate := 3.5
@export var tail_sway_degrees := 5.0
@export var tail_sway_speed := 1.4
## Tail lifts when falling and lowers when rising, degrees per (m/s).
@export var tail_air_pitch := 1.5

@export_group("Misc")
## Cutscenes (wake-up intro, transformation) clear this to freeze player input.
@export var can_move := true
@export var respawn_below_y := -25.0
## The cat mesh faces +Z; rotate the model so its nose points along travel.
@export var model_yaw_offset := 0.0

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
var _air_anim_started := false
var _idle_time := 0.0
var _land_hold := 0.0
var _landing := false
var _just_landed := false
var _jump_cut_done := false
var _breath_time := 0.0
var _breath_weight := 0.0
var _augments := {} ## Socket_* name -> hidden "Augment" Node3D.

var _yaw := 0.0
var _yaw_velocity := 0.0
var _yaw_error := 0.0
var _roll := 0.0
var _pitch := 0.0
var _prev_horizontal := Vector3.ZERO
var _accel_forward := 0.0

var _tree: AnimationTree
var _state_node: AnimationNodeTransition
var _anim_state := &""
var _anim_state_time := 0.0
var _gait_weight := 0.0
var _gait_speed := 0.0
var _idle_amount := 0.0
var _modifier: SkeletonModifier3D

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
	_yaw = PI ## Spawn facing -Z (the mesh itself faces +Z).
	_apply_model_rotation()
	_capsule = _capsule.duplicate()
	_collision.shape = _capsule
	_apply_height(stand_height)
	_collect_augments()
	_build_animation_tree()
	_build_secondary_motion()
	_go(&"ground", 0.0)


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
	_update_lean(delta)
	_update_squash(delta)
	_update_animation(delta, input.length())

	if global_position.y < respawn_below_y:
		respawn()


## Teleports back to where the cat started. Also resets physics interpolation.
func respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_yaw_velocity = 0.0
	_roll = 0.0
	_pitch = 0.0
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
		_jump_cut_done = false
		state = State.RISING
		jumped.emit()
	elif can_move and Input.is_action_just_pressed("dash") and not is_on_floor():
		perform_dash(-global_basis.z)
	# Variable jump height: releasing early trims the rise once.
	if state == State.RISING and velocity.y > 0.0 and not _jump_cut_done \
			and not Input.is_action_pressed("jump"):
		velocity.y *= jump_cut_multiplier
		_jump_cut_done = true


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := gravity
	if velocity.y < 0.0:
		g *= fall_gravity_multiplier
	# Float at the top of the arc: gravity eases off as vertical speed nears zero.
	var near_apex := 1.0 - clampf(absf(velocity.y) / apex_window, 0.0, 1.0)
	g *= lerpf(1.0, apex_gravity_multiplier, near_apex)
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
	var speed := horizontal.length()
	var rate: float
	if wish_dir == Vector3.ZERO:
		rate = ground_deceleration if on_floor else air_deceleration
		if on_floor:
			# Soft landing of the stop: ease off the braking at low speed.
			rate *= lerpf(stop_softness, 1.0, clampf(speed / stop_soft_speed, 0.0, 1.0))
	else:
		rate = ground_acceleration if on_floor else air_acceleration
		if on_floor:
			if speed < target.length() * start_burst_fraction:
				rate *= start_burst_multiplier
			if speed > 0.5 and horizontal.normalized().dot(wish_dir) < 0.5:
				rate *= turn_acceleration_boost
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _post_move() -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		var impact := absf(_last_fall_speed)
		if impact > 2.5:
			var t := clampf(impact / 10.0, 0.0, 1.0)
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

## Yaw is a damped spring toward the wish direction: a gentle ease-in, a quick
## swing, no overshoot to speak of. The remaining error drives the head lead.
func _update_facing(wish_dir: Vector3, delta: float) -> void:
	var has_wish := wish_dir.length_squared() >= 0.0001
	_yaw_error = 0.0
	if has_wish:
		var target_yaw := atan2(wish_dir.x, wish_dir.z) + model_yaw_offset
		_yaw_error = angle_difference(_yaw, target_yaw)
	var accel := turn_response * turn_response * _yaw_error \
			- 2.0 * turn_response * turn_damping * _yaw_velocity
	_yaw_velocity = clampf(_yaw_velocity + accel * delta, -max_turn_rate, max_turn_rate)
	_yaw = wrapf(_yaw + _yaw_velocity * delta, -PI, PI)


## Bank into turns, tip the nose with acceleration and with the jump arc.
func _update_lean(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	var forward := get_heading()
	var accel := (horizontal - _prev_horizontal).dot(forward) / maxf(delta, 0.0001)
	_prev_horizontal = horizontal
	_accel_forward = lerpf(_accel_forward, accel, 1.0 - exp(-10.0 * delta))

	var on_ground := state == State.GROUND
	var roll_deg := clampf(-_yaw_velocity * speed * lean_per_turn_rate, -max_lean_degrees, max_lean_degrees)
	if not on_ground:
		roll_deg *= 0.5
	var pitch_deg := 0.0
	if on_ground:
		pitch_deg = clampf(_accel_forward * accel_pitch_gain, -max_accel_pitch_degrees, max_accel_pitch_degrees)
	else:
		pitch_deg = clampf(-velocity.y * air_pitch_per_speed, -max_air_pitch_degrees, max_air_pitch_degrees)
	var k := 1.0 - exp(-lean_smoothing * delta)
	_roll = lerpf(_roll, deg_to_rad(roll_deg), k)
	_pitch = lerpf(_pitch, deg_to_rad(pitch_deg), k)
	_apply_model_rotation()
	_feed_secondary_motion(speed)


func _apply_model_rotation() -> void:
	_model.rotation = Vector3(_pitch, _yaw, _roll)


## Facing direction of the cat's nose in world space (the camera follows this).
func get_heading() -> Vector3:
	return Vector3(sin(_yaw), 0.0, cos(_yaw))


func _update_squash(delta: float) -> void:
	_squash = _squash.lerp(Vector3.ONE, 1.0 - exp(-squash_recovery * delta))
	var crouch_scale := crouch_model_scale if is_crouching else 1.0
	var target := Vector3(1.0, crouch_scale, 1.0)
	# Subtle breathing while standing still, before the cat sits.
	_breath_weight = move_toward(_breath_weight, 1.0 if _anim_state == &"ground" and _idle_amount < 0.05 else 0.0, delta * 3.0)
	_breath_time += delta
	var breath := sin(_breath_time * TAU / breathing_period) * breathing_amount * _breath_weight
	target *= Vector3(1.0 - breath * 0.4, 1.0 + breath, 1.0 - breath * 0.4)
	_model.scale = _model.scale.lerp(target * _squash, 1.0 - exp(-20.0 * delta))


# --- Animation ---------------------------------------------------------------

## Builds the tree in code (the clips come from the GLB's AnimationPlayer):
## State (Transition, crossfaded) -> ground | jump_start | air | land | sit_down | idle_sit.
## ground = Blend2(Stand, TimeScale(BlendSpace1D(Walk, Run))), synced by phase.
func _build_animation_tree() -> void:
	var root := AnimationNodeBlendTree.new()

	var walk := AnimationNodeAnimation.new()
	walk.animation = &"Walk"
	var run := AnimationNodeAnimation.new()
	run.animation = &"Run"
	var gait := AnimationNodeBlendSpace1D.new()
	gait.min_space = 0.0
	gait.max_space = 1.0
	gait.sync = true
	gait.add_blend_point(walk, 0.0)
	gait.add_blend_point(run, 1.0)
	root.add_node(&"Gait", gait)
	var gait_scale := AnimationNodeTimeScale.new()
	root.add_node(&"GaitScale", gait_scale)
	root.connect_node(&"GaitScale", 0, &"Gait")

	var stand := AnimationNodeAnimation.new()
	stand.animation = &"Stand"
	root.add_node(&"Stand", stand)
	var idle_mix := AnimationNodeBlend2.new()
	root.add_node(&"IdleMix", idle_mix)
	root.connect_node(&"IdleMix", 0, &"Stand")
	root.connect_node(&"IdleMix", 1, &"GaitScale")

	_state_node = AnimationNodeTransition.new()
	_state_node.allow_transition_to_self = false
	var inputs: Array[StringName] = [&"ground", &"jump_start", &"air", &"land", &"sit_down", &"idle_sit"]
	_state_node.input_count = inputs.size()
	for i in inputs.size():
		_state_node.set_input_name(i, inputs[i])
		_state_node.set_input_reset(i, true)
	_state_node.set_input_reset(2, false)
	root.add_node(&"State", _state_node)
	root.connect_node(&"State", 0, &"IdleMix")

	var one_shots := [
		[&"JumpStart", &"Jump_Start", 1, true],
		[&"Air", &"Jump_Air", 2, false],
		[&"Land", &"Land", 3, true],
		[&"SitDown", &"Sit_Down", 4, false],
		[&"IdleSit", &"Idle_Sit", 5, false],
	]
	for entry in one_shots:
		var clip := AnimationNodeAnimation.new()
		clip.animation = entry[1]
		root.add_node(entry[0], clip)
		if entry[3]:
			var scale_node := AnimationNodeTimeScale.new()
			root.add_node(StringName(String(entry[0]) + "Scale"), scale_node)
			root.connect_node(StringName(String(entry[0]) + "Scale"), 0, entry[0])
			root.connect_node(&"State", entry[2], StringName(String(entry[0]) + "Scale"))
		else:
			root.connect_node(&"State", entry[2], entry[0])
	root.connect_node(&"output", 0, &"State")

	_tree = AnimationTree.new()
	_tree.name = &"AnimationTree"
	_tree.tree_root = root
	_cat.add_child(_tree)
	_tree.root_node = NodePath("..")
	_tree.anim_player = _tree.get_path_to(_anim)
	_tree.active = true
	_tree.set("parameters/JumpStartScale/scale", jump_start_speed)
	_tree.set("parameters/LandScale/scale", land_speed)


func _build_secondary_motion() -> void:
	var skeleton := _cat.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or not secondary_motion_enabled:
		return
	_modifier = SecondaryMotion.new()
	_modifier.name = &"SecondaryMotion"
	skeleton.add_child(_modifier)
	(_modifier as Object).set("sway_degrees", tail_sway_degrees)
	(_modifier as Object).set("sway_speed", tail_sway_speed)
	(_modifier as Object).set("tail_lag_per_turn_rate", tail_lag_per_turn_rate)
	(_modifier as Object).set("tail_air_pitch", tail_air_pitch)


func _feed_secondary_motion(speed: float) -> void:
	if _modifier == null:
		return
	var lead := clampf(_yaw_error * head_lead, -deg_to_rad(head_lead_max_degrees), deg_to_rad(head_lead_max_degrees))
	_modifier.set("head_lead", lead)
	_modifier.set("yaw_rate", _yaw_velocity)
	_modifier.set("vertical_speed", velocity.y if state != State.GROUND else 0.0)
	_modifier.set("move_speed", speed)


## Requests a state in the Transition node with its own crossfade time.
func _go(anim_state: StringName, fade: float) -> void:
	if _anim_state == anim_state:
		return
	_anim_state = anim_state
	_anim_state_time = 0.0
	_state_node.xfade_time = fade
	_tree.set("parameters/State/transition_request", anim_state)


func _update_animation(delta: float, input_strength: float) -> void:
	_anim_state_time += delta
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var moving := input_strength > 0.05 or horizontal_speed > 0.25
	_update_gait(delta, horizontal_speed)
	if state != State.GROUND:
		_idle_time = 0.0
		_landing = false
		_land_hold = 0.0
		if not _air_anim_started:
			_air_anim_started = true
			# Walking off a ledge skips the push-off.
			if state == State.RISING:
				_go(&"jump_start", fade_to_jump)
			else:
				_go(&"air", fade_to_air)
		elif _anim_state == &"jump_start":
			var push_off := 0.5 / jump_start_speed
			if _anim_state_time >= push_off or state == State.FALLING:
				_go(&"air", fade_to_air)
		elif _anim_state != &"air":
			_go(&"air", fade_to_air)
		return
	var was_airborne := _air_anim_started
	_air_anim_started = false
	if _just_landed:
		_just_landed = false
		# Only a real airborne spell lands; stepping off a kerb does not.
		_landing = was_airborne
		if _landing:
			_land_hold = 0.14 if moving else 0.4
			_go(&"land", fade_to_land)
	if _landing:
		_land_hold -= delta
		if _land_hold > 0.0:
			return
		_landing = false
		_go(&"ground", fade_ground_after_land_moving if moving else fade_ground_after_land_still)
	if moving:
		_idle_time = 0.0
		if _anim_state == &"sit_down" or _anim_state == &"idle_sit":
			stood_up.emit()
			_go(&"ground", fade_stand_up)
		else:
			_go(&"ground", fade_to_ground)
		return
	_idle_time += delta
	if _idle_time >= sit_delay and not is_crouching:
		if _anim_state != &"sit_down" and _anim_state != &"idle_sit":
			_go(&"sit_down", fade_to_sit)
			sat_down.emit()
		elif _anim_state == &"sit_down" and _anim_state_time >= 2.0:
			_go(&"idle_sit", fade_to_sit)
	else:
		_go(&"ground", fade_to_ground)


## Drives the Walk -> Run blend, the idle mix and the gait playback rate.
func _update_gait(delta: float, horizontal_speed: float) -> void:
	var k := 1.0 - exp(-gait_smoothing * delta)
	_gait_speed = lerpf(_gait_speed, horizontal_speed, k)
	var w := clampf(inverse_lerp(gait_blend_start, gait_blend_end, _gait_speed), 0.0, 1.0)
	_gait_weight = lerpf(_gait_weight, w, k)
	_idle_amount = lerpf(_idle_amount, clampf(horizontal_speed / idle_blend_speed, 0.0, 1.0), k)
	var ref_speed := lerpf(anim_walk_ref_speed, anim_run_ref_speed, _gait_weight)
	var cap := anim_crouch_speed_max if is_crouching else anim_speed_max
	var rate := clampf(_gait_speed / ref_speed, anim_speed_min, cap)
	_tree.set("parameters/Gait/blend_position", _gait_weight)
	_tree.set("parameters/GaitScale/scale", rate)
	_tree.set("parameters/IdleMix/blend_amount", _idle_amount)


func _collect_augments() -> void:
	for node in _cat.find_children("Socket_*", "BoneAttachment3D", true, false):
		var augment := node.get_node_or_null("Augment") as Node3D
		if augment:
			_augments[node.name] = augment
