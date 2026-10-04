class_name PatrolBot
extends CharacterBody2D
## Gum Bot patrol robot. Turns at walls and edges, hurts on side contact.
## Stomp it or shockwave it to stun; after 3 stomps it becomes friendly.

enum State { PATROL, STUNNED, FRIENDLY }

const SHEET := "res://assets/sprites/robots/gum_bot_keyed.png"
const CELL := 32

@export var speed := 26.0
@export var stun_time := 3.0
@export var stomps_to_befriend := 3

var state := State.PATROL
var dir := -1
var stomps := 0

var _stun_left := 0.0
var _stomp_lock := 0.0
var _t := 0.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hitbox: Area2D = $Hitbox
@onready var edge: RayCast2D = $EdgeCast


## Box centre (offset from origin) and half size, used for shockwave range checks.
var shock_offset := Vector2(0, -8)
var shock_half := Vector2(6, 8)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("shock_receiver")
	add_to_group("enemy")
	hitbox.collision_layer = 0
	hitbox.collision_mask = 2
	sprite.sprite_frames = _build_frames()
	sprite.play("walk")


func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var tex: Texture2D = load(SHEET)
	var defs := {
		"walk": [[Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)], 6.0],
		"stun": [[Vector2i(4, 3)], 1.0],
		"happy": [[Vector2i(1, 1), Vector2i(2, 1)], 5.0],
	}
	for n in defs:
		sf.add_animation(n)
		sf.set_animation_speed(n, defs[n][1])
		for cell: Vector2i in defs[n][0]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
			sf.add_frame(n, at)
	return sf


func _physics_process(delta: float) -> void:
	_t += delta
	_stomp_lock = maxf(_stomp_lock - delta, 0.0)
	velocity.y = minf(velocity.y + 900.0 * delta, 300.0)
	match state:
		State.PATROL:
			edge.position.x = dir * 8.0
			edge.force_raycast_update()
			var blocked := is_on_wall() and get_wall_normal().x * dir < 0.0
			if is_on_floor() and (blocked or not edge.is_colliding()):
				dir = -dir
			velocity.x = dir * speed
			sprite.flip_h = dir > 0
		State.STUNNED:
			velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
			_stun_left -= delta
			sprite.position.x = roundf(sin(_t * 40.0))
			if _stun_left <= 0.0:
				sprite.position.x = 0.0
				state = State.PATROL
				sprite.play("walk")
		State.FRIENDLY:
			velocity.x = 0.0
			sprite.modulate = Color.from_hsv(fmod(_t * 1.5, 1.0), 0.35, 1.6) if int(_t * 10.0) % 2 == 0 else Color.WHITE
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
	var above := cat.global_position.y <= global_position.y - 9.0 and cat.velocity.y > 0.0
	if above:
		if _stomp_lock <= 0.0:
			_stomp(cat)
	elif state == State.PATROL:
		cat.hurt(global_position)


func _stomp(cat: Cat) -> void:
	_stomp_lock = 0.3
	cat.bounce(260.0)
	stomps += 1
	Sfx.play(self, "land", -4.0, 0.8)
	if stomps >= stomps_to_befriend:
		befriend()
	else:
		stun(stun_time)


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
	Sfx.play(self, "power_up", -6.0, 1.4)


func on_shockwave(origin: Vector2, _radius: float, _source: String) -> void:
	if state == State.FRIENDLY:
		velocity.y = -90.0
		return
	velocity.y = -90.0
	velocity.x = signf(global_position.x - origin.x) * 60.0
	stun(stun_time)
