class_name PatrolBot
extends CharacterBody2D
## Patrol robot (ansimuz Warped bipedal unit, harmonised: red glow = hostile).
## Turns at walls, edges and bot-stoppers, hurts on side contact.
##
## A plain cat cannot hurt it: stomping bounces the cat off its head with a
## clank and a flinch, nothing more, and it keeps patrolling. Once the cat has
## powers (`can_be_harmed()`: the shockwave, or any enhancement; later the
## "supervisor" mechanic) a stomp stuns it, and after 3 stomps it becomes
## friendly. The shockwave and ground pound stun it regardless (only a cat with
## powers can fire them). Set `armoured = false` for a bot that always yields.
##
## Stoppers: StaticBody2D on physics layer 7 ("bot_bounds"), invisible and
## solid only to bots, keep it off places it must not wander (cracked floor,
## spikes, doors).

enum State { PATROL, STUNNED, FRIENDLY }

const SHEET := "res://assets/art_hd/robots/bipedal.png"
const CELL := Vector2i(80, 64)
const BOUNDS_MASK := 64

@export var speed := 46.0
@export var stun_time := 3.0
@export var stomps_to_befriend := 3
## True: a cat without powers bounces off harmlessly (see above).
@export var armoured := true
## True: plated against everything but the ground pound. Stomps and the
## double-jump shockwave only clank off the plating (Room 4's armoured bot).
@export var shielded := false
## 1 = the size the rooms use. Smaller shrinks the art and every box with it (the kit
## runs patrol bots at about 0.7, 1.3 tiles tall). Boxes follow the art.
@export var sprite_scale := 1.0

var state := State.PATROL
var dir := -1
var stomps := 0

var _stun_left := 0.0
var _stomp_lock := 0.0
var _t := 0.0
var _flinch := 0.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hitbox: Area2D = $Hitbox
@onready var edge: RayCast2D = $EdgeCast


## Box centre (offset from origin) and half size, used for shockwave range checks.
var shock_offset := Vector2(0, -26)
var shock_half := Vector2(16, 26)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | BOUNDS_MASK
	add_to_group("shock_receiver")
	add_to_group("enemy")
	hitbox.collision_layer = 0
	hitbox.collision_mask = 2
	sprite.sprite_frames = _build_frames()
	sprite.play("walk")
	KitGlow.attach(sprite)
	_apply_scale()
	if shielded:
		sprite.self_modulate = Color(1.0, 0.92, 0.72)


func _apply_scale() -> void:
	if is_equal_approx(sprite_scale, 1.0):
		return
	var k := sprite_scale
	sprite.scale = Vector2(k, k)
	sprite.position.y = -32.0 * k
	for cs: CollisionShape2D in [$Shape, $Hitbox/Shape]:
		var r := (cs.shape as RectangleShape2D).duplicate() as RectangleShape2D
		r.size *= k
		cs.shape = r
		cs.position *= k
	edge.position.y *= k
	edge.target_position *= k
	shock_offset *= k
	shock_half *= k


func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var tex: Texture2D = load(SHEET)
	var defs := {
		"walk": [[0, 1, 2, 3, 4, 5, 6], 9.0],
		"stun": [[3], 1.0],
		"happy": [[0, 4], 4.0],
	}
	for n in defs:
		sf.add_animation(n)
		sf.set_animation_speed(n, defs[n][1])
		for i: int in defs[n][0]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * CELL.x, 0, CELL.x, CELL.y)
			sf.add_frame(n, at)
	return sf


func _physics_process(delta: float) -> void:
	_t += delta
	_stomp_lock = maxf(_stomp_lock - delta, 0.0)
	_flinch = maxf(_flinch - delta, 0.0)
	velocity.y = minf(velocity.y + 1600.0 * delta, 533.0)
	match state:
		State.PATROL:
			edge.position.x = dir * 20.0 * sprite_scale
			edge.force_raycast_update()
			var blocked := is_on_wall() and get_wall_normal().x * dir < 0.0
			if is_on_floor() and (blocked or not edge.is_colliding()):
				dir = -dir
			velocity.x = dir * speed
			sprite.flip_h = dir < 0  # the art faces right
		State.STUNNED:
			velocity.x = move_toward(velocity.x, 0.0, 711.0 * delta)
			_stun_left -= delta
			sprite.position.x = roundf(sin(_t * 40.0)) * 2.0
			if _stun_left <= 0.0:
				sprite.position.x = 0.0
				state = State.PATROL
				sprite.play("walk")
		State.FRIENDLY:
			velocity.x = 0.0
			# Friendly: a soft white pulse (no power-hue tint).
			sprite.modulate = Color(1.5, 1.5, 1.5) if int(_t * 10.0) % 2 == 0 else Color.WHITE
	if state != State.FRIENDLY:
		_flinch_fx()
	if shielded:
		queue_redraw()
	move_and_slide()
	if global_position.y > 3000.0:
		queue_free()
	if state != State.FRIENDLY:
		for b in hitbox.get_overlapping_bodies():
			if b is Cat:
				_touch(b)


func _touch(cat: Cat) -> void:
	if cat.is_phasing() or cat.dead:
		return
	var above := cat.global_position.y <= global_position.y - 40.0 * sprite_scale and cat.velocity.y > 0.0
	if above:
		if _stomp_lock <= 0.0:
			_stomp(cat)
	elif state == State.PATROL:
		# Hopping over an armoured bot is free: only the sides hurt.
		if not can_be_harmed() and cat.global_position.y <= global_position.y - 40.0 * sprite_scale:
			return
		cat.hurt(global_position)


## A cat may damage the bot only with powers (or a bot that is not armoured).
func can_be_harmed() -> bool:
	return not armoured or GameState.shockwave_unlocked or GameState.power != NanoPalette.Power.NONE


func _stomp(cat: Cat) -> void:
	_stomp_lock = 0.3
	cat.bounce(462.0)
	if shielded or not can_be_harmed():
		_clank()
		return
	stomps += 1
	Sfx.play(self, "bot_stomp")
	if stomps >= stomps_to_befriend:
		befriend()
	else:
		stun(stun_time)


## The "that did nothing" read: a metal clank, a quick blink and a shudder.
func _clank() -> void:
	_flinch = 0.28
	Sfx.play(self, "bot_stomp", 0.0, 1.25)


func _flinch_fx() -> void:
	if _flinch > 0.0:
		sprite.modulate = Color(1.9, 1.9, 2.0) if int(_flinch * 36.0) % 2 == 0 else Color.WHITE
		sprite.position.x = roundf(sin(_flinch * 90.0)) * 1.0 if state == State.PATROL else sprite.position.x
	elif state == State.PATROL:
		sprite.modulate = Color.WHITE
		sprite.position.x = 0.0


func stun(t: float) -> void:
	if state == State.FRIENDLY:
		return
	state = State.STUNNED
	_stun_left = t
	sprite.play("stun")


func befriend() -> void:
	state = State.FRIENDLY
	sprite.play("happy")
	GameState.add_score(500)
	Sfx.play(self, "robot_chirp")


func on_shockwave(origin: Vector2, _radius: float, source: String) -> void:
	if shielded and source != "pound":
		_clank()
		return
	if state == State.FRIENDLY:
		velocity.y = -160.0
		return
	velocity.y = -160.0
	velocity.x = signf(global_position.x - origin.x) * 107.0
	stun(stun_time)


## The plating: a gold shell that fades while the bot is stunned.
func _draw() -> void:
	if not shielded:
		return
	var a := 0.55 if state == State.PATROL else 0.0
	var c := Color(NanoPalette.SHOCKWAVE, a * (0.7 + 0.3 * sin(_t * 5.0)))
	draw_arc(Vector2(0, -26), 31.0, -PI * 0.9, PI * 0.9, 18, c, 2.0)
	draw_arc(Vector2(0, -26), 27.0, -PI * 0.7, PI * 0.7, 14, Color(c, c.a * 0.5), 1.0)
