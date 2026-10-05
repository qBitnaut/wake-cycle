class_name Cat
extends CharacterBody2D
## The player: a brown tabby with Apogee-tight movement and modern forgiveness.
## Movement input only: move_left/right/up/down, jump, dash.

## Emitted for every burst; the level turns it into ShockwaveFX (see Level).
## source is "shock" (double jump) or "pound" (ground pound).
signal shockwave(pos: Vector2, radius: float, source: String)
signal hurt_taken(hp: int)
signal died

# --- Tuning (pixels, seconds). The view is 640x360 and tiles are 32 px. ---
# Every length, speed and acceleration is the old 18 px tuning times 32/18
# (1.78), so a jump is still about 3.1 tiles and the feel is unchanged.
@export_group("Run")
@export var run_speed := 178.0
@export var accel := 1956.0
@export var turn_accel := 3022.0
@export var ground_friction := 2667.0
@export var air_accel := 1511.0
@export var air_friction := 747.0
@export var crouch_speed := 40.0  # a stalk: the crawl's planted paws then match the ground (see _paw_scale)
@export_group("Jump")
@export var gravity := 1600.0
@export var fall_gravity_mult := 1.45
@export var max_fall := 480.0
@export var jump_velocity := 565.0  # ~3.1 tiles (100 px)
@export var double_jump_velocity := 507.0
@export var jump_cut := 0.45
@export var coyote_time := 0.10
@export var jump_buffer := 0.12
@export_group("Abilities")
@export var shockwave_radius := 64.0  # 2 tiles
@export var pound_radius := 46.0
@export var pound_speed := 711.0
@export var dash_speed := 409.0
@export var dash_time := 0.16
@export var dash_cooldown := 0.45
@export var surge_mult := 1.5
@export var spring_mult := 1.48  # Spring's first jump: 211 px, 6.6 tiles (plain: 95 px)
@export var spring_air_mult := 0.6  # Spring's second (air) jump: a small extra (Spring is the high first jump), so its double reach stays 255 px across, 238 px up
@export_group("Health")
@export var invulnerable_time := 1.4

const STAND_H := 26.0
const CROUCH_H := 14.0
const WIDTH := 22.0
const SIT_AFTER := 3.0
const LICK_AFTER := 6.0
const SLEEP_AFTER := 14.0
## The push pose holds this long after contact with the crate drops, so the
## contact flickering on and off each physics frame cannot thrash the animation.
const PUSH_HOLD := 0.15
const PUSH_SLOW_SCALE := 0.7  # walk playback speed while pushing, when there is no push animation

var death_y := 100000.0
var facing := 1
var dead := false
var crouched := false
var pounding := false
var dash_left := 0.0
## False while a cutscene owns the cat: input is ignored (it still falls and
## settles on the floor). Use set_can_move().
var can_move := true
## While not empty this animation plays instead of the automatic one.
var forced_anim := ""
## Multiplies the sprite colour each frame: the hook for cutscene tints.
var fx_tint := Color.WHITE

var _coyote := 0.0
var _jump_buf := 0.0
var _air_jumps := 1
var _jumping := false
var _invuln := 0.0
var _dash_cd := 0.0
var _ghost_t := 0.0
var _was_on_floor := false
var _idle_t := 0.0
var _oneshot := 0.0
var _slept := false
var _fall_speed := 0.0
var _push_t := 0.0
## Number of animation changes made by _play(): an audit hook (flicker counting).
var anim_switches := 0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var body_shape: CollisionShape2D = $Shape
@onready var camera: Camera2D = $Camera


func _ready() -> void:
	add_to_group("player")
	sprite.sprite_frames = CatFrames.build()
	sprite.play("idle")
	_set_crouch(false)


func set_camera_limits(r: Rect2i) -> void:
	camera.limit_left = r.position.x
	camera.limit_top = r.position.y
	camera.limit_right = r.end.x
	camera.limit_bottom = r.end.y


## Hand the cat to a cutscene (false) or give control back (true).
## Locking releases held input state so nothing carries over.
func set_can_move(v: bool) -> void:
	can_move = v
	if not v:
		_jump_buf = 0.0
		_jumping = false
		if crouched and _can_stand():
			_set_crouch(false)


## Play `anim` until cleared with an empty string (only while input is locked).
func set_forced_anim(anim: String) -> void:
	forced_anim = anim
	if anim != "":
		sprite.speed_scale = 1.0
		if sprite.animation != anim or not sprite.is_playing():
			sprite.play(anim)


func is_phasing() -> bool:
	return dash_left > 0.0


func _physics_process(delta: float) -> void:
	if dead:
		velocity.y = minf(velocity.y + gravity * delta, max_fall)
		position += velocity * delta
		return
	var dir := Input.get_axis("move_left", "move_right") if can_move else 0.0
	var on_floor := is_on_floor()
	_timers(delta, on_floor)
	if can_move:
		_crouch(on_floor)
		_start_actions(on_floor, dir)
	if dash_left > 0.0:
		_dash_step(delta)
	else:
		_move(delta, dir, on_floor)
	_was_on_floor = on_floor
	var pre_vx := velocity.x
	move_and_slide()
	_push_bodies(pre_vx)
	if is_on_floor() and not on_floor:
		_land()
	if global_position.y > death_y:
		kill()
	_animate(dir, on_floor, delta)
	_track_fall()


func _timers(delta: float, on_floor: bool) -> void:
	if on_floor:
		_coyote = coyote_time
		_air_jumps = 1
		_jumping = false
	else:
		_coyote -= delta
	_jump_buf -= delta
	if can_move and Input.is_action_just_pressed("jump"):
		_jump_buf = jump_buffer
	_invuln = maxf(_invuln - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	dash_left = maxf(dash_left - delta, 0.0)
	_oneshot = maxf(_oneshot - delta, 0.0)
	_push_t = maxf(_push_t - delta, 0.0)


func _crouch(on_floor: bool) -> void:
	var want := Input.is_action_pressed("move_down") and (on_floor or crouched)
	if want and not crouched and not pounding:
		_set_crouch(true)
	elif crouched and not want and _can_stand():
		_set_crouch(false)


func _set_crouch(on: bool) -> void:
	crouched = on
	var h := CROUCH_H if on else STAND_H
	(body_shape.shape as RectangleShape2D).size = Vector2(WIDTH, h)
	body_shape.position = Vector2(0, -h / 2.0)


func _can_stand() -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(WIDTH - 2.0, STAND_H - 2.0)
	q.shape = r
	q.transform = Transform2D(0.0, global_position + Vector2(0, -STAND_H / 2.0 - 1.0))
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _start_actions(on_floor: bool, _dir: float) -> void:
	var power := GameState.power
	var is_spring := power == NanoPalette.Power.SPRING
	var spring := spring_mult if is_spring else 1.0
	var spring_air := spring_air_mult if is_spring else 1.0
	if _jump_buf > 0.0 and not pounding:
		if _coyote > 0.0 and (not crouched or _can_stand()):
			if crouched:
				_set_crouch(false)
			velocity.y = -jump_velocity * spring
			_jump_buf = 0.0
			_coyote = 0.0
			_jumping = true
			Sfx.play(self, "jump")
			_stretch(Vector2(0.85, 1.2))
		elif _air_jumps > 0 and not on_floor:
			velocity.y = -double_jump_velocity * spring_air
			_air_jumps -= 1
			_jump_buf = 0.0
			_jumping = true
			Sfx.play(self, "double_jump")
			_flip()
			if GameState.shockwave_unlocked:
				_burst(global_position + Vector2(0, -12), shockwave_radius, "shock")
	if Input.is_action_just_released("jump") and _jumping and velocity.y < 0.0:
		velocity.y *= jump_cut
		_jumping = false
	if (
		power == NanoPalette.Power.PHASE
		and Input.is_action_just_pressed("dash")
		and _dash_cd <= 0.0
		and not pounding
	):
		dash_left = dash_time
		_dash_cd = dash_cooldown
		_ghost_t = 0.0
		Sfx.play(self, "double_jump", -8.0, 1.7)
	if (
		power == NanoPalette.Power.IMPACT
		and not on_floor
		and not pounding
		and Input.is_action_just_pressed("move_down")
	):
		pounding = true
		velocity = Vector2(0, pound_speed)


func _move(delta: float, dir: float, on_floor: bool) -> void:
	if pounding:
		velocity.x = 0.0
		velocity.y = pound_speed
		return
	var speed := run_speed * (surge_mult if GameState.power == NanoPalette.Power.SURGE else 1.0)
	if crouched:
		speed = crouch_speed
	var target := dir * speed
	var a := ground_friction if on_floor else air_friction
	if dir != 0.0:
		a = accel if on_floor else air_accel
		if signf(dir) != signf(velocity.x) and absf(velocity.x) > 5.0:
			a = turn_accel
		facing = 1 if dir > 0.0 else -1
		sprite.flip_h = facing < 0
	velocity.x = move_toward(velocity.x, target, a * delta)
	var g := gravity * (fall_gravity_mult if velocity.y > 0.0 else 1.0)
	velocity.y = minf(velocity.y + g * delta, max_fall)


func _dash_step(delta: float) -> void:
	velocity = Vector2(facing * dash_speed, 0.0)
	_ghost_t -= delta
	if _ghost_t <= 0.0:
		_ghost_t = 0.03
		_spawn_ghost()


func _spawn_ghost() -> void:
	var g := Sprite2D.new()
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	g.texture = tex
	g.flip_h = sprite.flip_h
	g.offset = sprite.offset
	g.modulate = Color(NanoPalette.PHASE, 0.55)
	g.global_position = global_position
	g.z_index = z_index - 1
	get_parent().add_child(g)
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.18)
	tw.tween_callback(g.queue_free)


func _push_bodies(pre_vx: float) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody2D
		if rb and absf(c.get_normal().x) > 0.5:
			rb.sleeping = false
			if can_move and signf(pre_vx) == -signf(c.get_normal().x):
				_push_t = PUSH_HOLD
			rb.linear_velocity.x = move_toward(rb.linear_velocity.x, pre_vx * 0.85, 1067.0)


func _land() -> void:
	if pounding:
		pounding = false
		Sfx.play(self, "shockwave_thump", -2.0)
		_burst(global_position + Vector2(0, -8), pound_radius, "pound")
	elif _fall_speed > 249.0:
		Sfx.play(self, "land", -10.0)
		_stretch(Vector2(1.2, 0.8))
	_fall_speed = 0.0


func _track_fall() -> void:
	if not is_on_floor():
		_fall_speed = maxf(_fall_speed, velocity.y)


## Radial force burst. Receivers join the "shock_receiver" group and implement
## on_shockwave(origin, radius, source) with source "shock" or "pound".
func _burst(pos: Vector2, radius: float, source: String) -> void:
	shockwave.emit(pos, radius, source)
	for n in get_tree().get_nodes_in_group("shock_receiver"):
		if not n.has_method("on_shockwave"):
			continue
		# Distance from the burst to the receiver's box (shock_offset = box centre, shock_half = half size).
		var d: Vector2 = (pos - (n.global_position + Vector2(n.get("shock_offset")))).abs()
		d = (d - Vector2(n.get("shock_half"))).max(Vector2.ZERO)
		if d.length() <= radius:
			n.on_shockwave(pos, radius, source)


func bounce(v: float = 444.0) -> void:
	velocity.y = -v
	_air_jumps = 1
	_jumping = true
	pounding = false


func hurt(from_pos: Vector2) -> void:
	if _invuln > 0.0 or dead:
		return
	if GameState.health <= 0:
		kill()
		return
	GameState.set_health(GameState.health - 1)
	_invuln = invulnerable_time
	var away := signf(global_position.x - from_pos.x)
	velocity = Vector2((away if away != 0.0 else -facing) * 213.0, -302.0)
	pounding = false
	dash_left = 0.0
	Sfx.play(self, "hurt")
	hurt_taken.emit(GameState.health)


## Instant death (pits, spikes) or the fatal 4th hit.
func kill() -> void:
	if dead:
		return
	dead = true
	pounding = false
	velocity = Vector2(0, -338)
	body_shape.set_deferred("disabled", true)
	Sfx.play(self, "hurt", -3.0, 0.7)
	sprite.play("crouch")
	sprite.modulate = Color(2.5, 1.0, 1.0)
	died.emit()
	await get_tree().create_timer(0.9).timeout
	SaveSystem.respawn()


func _stretch(s: Vector2) -> void:
	var tw := create_tween()
	sprite.scale = s
	tw.tween_property(sprite, "scale", Vector2.ONE, 0.16)


func _flip() -> void:
	sprite.scale = Vector2(0.85, 1.25)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "scale", Vector2.ONE, 0.22)
	sprite.rotation = 0.0
	tw.tween_property(sprite, "rotation", TAU * facing, 0.3)
	tw.chain().tween_callback(func(): sprite.rotation = 0.0)


func _animate(dir: float, on_floor: bool, delta: float) -> void:
	# Invulnerability blink / hurt flash.
	if _invuln > 0.0:
		sprite.visible = int(_invuln * 16.0) % 2 == 0 or _invuln > invulnerable_time - 0.15
		sprite.modulate = Color(2.2, 2.2, 2.2) if _invuln > invulnerable_time - 0.12 else fx_tint
	else:
		sprite.visible = true
		sprite.modulate = fx_tint
	if forced_anim != "" and not can_move:
		_idle_t = 0.0
		_play(forced_anim)
		return
	var moving := absf(velocity.x) > 14.0
	var active := dir != 0.0 or not on_floor or crouched or Input.is_action_pressed("jump")
	if dash_left > 0.0:
		_play("run")
		return
	if crouched:
		_idle_t = 0.0
		var anim := "crawl" if moving and _has("crawl") else "crouch_idle" if not moving and _has("crouch_idle") else "crouch"
		_play(anim)
		if anim == "crawl":
			sprite.speed_scale = _paw_scale("crawl")
		elif anim == "crouch":  # the old two-frame crouch: frozen while still
			sprite.speed_scale = 1.0 if moving else 0.0
			if not moving:
				sprite.frame = 0
		else:
			sprite.speed_scale = 1.0
		return
	if _push_t > 0.0 and on_floor and dir != 0.0:
		_idle_t = 0.0
		_oneshot = 0.0
		var pushing := _has("push")
		_play("push" if pushing else "walk")
		sprite.speed_scale = _paw_scale("push") if pushing else PUSH_SLOW_SCALE
		return
	sprite.speed_scale = 1.0
	if not on_floor:
		_idle_t = 0.0
		_play("jump" if velocity.y < 0.0 else "fall")
	elif moving:
		_idle_t = 0.0
		_oneshot = 0.0
		_play("run" if absf(velocity.x) > 117.0 else "walk")
	elif active:
		_idle_t = 0.0
		_idle_wake()
	else:
		_idle_t += delta
		_idle_loop()


func _idle_wake() -> void:
	if _slept:
		_slept = false
		_oneshot = 0.8
		_play("stretch")
	elif _oneshot <= 0.0:
		_play("idle")


func _idle_loop() -> void:
	if _oneshot > 0.0:
		return
	if _idle_t >= SLEEP_AFTER:
		_slept = true
		_play("sleep1" if int(_idle_t / 1.2) % 2 == 0 else "sleep2")
	elif _idle_t >= LICK_AFTER:
		# Easter eggs while sitting, each once before the cat dozes off: a
		# paw-lick, a scratch, a meow.
		var eggs := ["lick1", "itch", "meow"]
		var period := (SLEEP_AFTER - LICK_AFTER) / eggs.size()
		var cycle := int((_idle_t - LICK_AFTER) / period)
		var phase := fmod(_idle_t - LICK_AFTER, period)
		if phase < 1.2:
			_play(eggs[cycle % eggs.size()])
		else:
			_play("sit")
	elif _idle_t >= SIT_AFTER:
		_play("sit")
	else:
		_play("idle")


## Playback speed that plants the paws: they travel 2 px per frame in crawl, push
## and crouch_idle, so scale = |vx| / (2 * fps), kept within a readable range.
func _paw_scale(anim: String) -> float:
	var fps := sprite.sprite_frames.get_animation_speed(anim)
	return clampf(absf(velocity.x) / (2.0 * fps), 0.5, 2.0)


func _has(anim: String) -> bool:
	return sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim)


func _play(anim: String) -> void:
	if sprite.animation != anim:
		anim_switches += 1
		sprite.play(anim)
