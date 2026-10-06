class_name SentryTurret
extends KitEnemy
## Sentry turret, on the floor, a ceiling or a wall. It tracks the cat while it is
## in range and in sight, CHARGES (the barrel glows and whines, aim locks for the
## last 0.25 s), then fires one slow energy bolt the cat can dodge or jump, and
## cools down.
##
## Defeat: a shockwave stuns it, a ground pound destroys it. It cannot be stomped
## (the gun faces up: a stomp only clanks). A stunned turret is finished by a pound.
## Alarm: `alert(seconds)` (a security camera calls it) wakes a `dormant` turret and
## makes any turret charge twice as fast for that long.
## Origin = the foot of the mount, on the surface it is bolted to.

enum Mount { FLOOR, CEILING, WALL_LEFT, WALL_RIGHT }
enum Phase { IDLE, CHARGE, FIRE, COOL }

@export var mount: Mount = Mount.FLOOR
@export var detect_range := 280.0
@export var charge_time := 0.9
@export var cooldown := 2.2
@export var bolt_speed := 110.0
@export_range(0.0, 1.0) var aim_lock := 0.25
## Needs an alarm (see SecurityCamera) before it wakes up.
@export var dormant := false

var phase := Phase.IDLE
var shots := 0
var alert_left := 0.0
var aim := Vector2.RIGHT

var _head: AnimatedSprite2D
var _p_t := 0.0
const BARREL_LEN := 24.0
var _muzzle_local := Vector2(14, -17)


func _init() -> void:
	actor_id = "sentry_turret"
	static_body = true
	uses_gravity = false
	stomp_effect = "none"
	shock_effect = "stun"
	pound_effect = "destroy"
	points = 250
	explosion_size = 0.9
	touch_damage = false
	stompable = false
	stun_time = 3.5


func _setup() -> void:
	add_to_group("kit_turret")
	rotation = [0.0, PI, PI * 0.5, -PI * 0.5][mount]
	_head = KitArt.make_sprite(actor_id, "head", art_scale)
	_head.name = "Head"
	add_child(_head)
	KitGlow.attach(_head)
	_muzzle_local = _head.position
	# Rotated mounts: the cat's range check wants a global-axis box.
	var c := rect.get_center()
	shock_offset = c.rotated(rotation)
	shock_half = rect.size * 0.5 if mount in [Mount.FLOOR, Mount.CEILING] else Vector2(rect.size.y, rect.size.x) * 0.5
	if dormant:
		_head.play("stun")
		tint = Color(0.7, 0.7, 0.8)


func is_awake() -> bool:
	return not dormant or alert_left > 0.0


func alert(seconds: float) -> void:
	alert_left = maxf(alert_left, seconds)
	if dormant and life == Life.ACTIVE:
		_head.play("idle")
		tint = Color.WHITE


## The barrel tip: the head's pivot plus the aim direction x 24 px, right for both facings
## (the head sprite is mirrored when it aims left, but the aim vector is not).
func muzzle() -> Vector2:
	return to_global(_head.position + aim_local() * BARREL_LEN * art_scale)


func aim_local() -> Vector2:
	return aim.rotated(-rotation)


func _tick(delta: float) -> void:
	alert_left = maxf(alert_left - delta, 0.0)
	if dormant and alert_left <= 0.0:
		if tint != Color(0.7, 0.7, 0.8):
			tint = Color(0.7, 0.7, 0.8)
			_head.play("stun")
		return
	if dormant and tint != Color.WHITE:
		tint = Color.WHITE
		_head.play("idle")
	_p_t += delta
	var c := cat()
	var target := cat_centre()
	var seen := c != null and not c.dead and global_position.distance_to(target) <= detect_range * (1.4 if alert_left > 0.0 else 1.0) \
		and line_clear(to_global(_muzzle_local), target)
	match phase:
		Phase.IDLE:
			if seen:
				_track(target, delta)
				begin_telegraph()
				phase = Phase.CHARGE
				_p_t = 0.0
				_head.play("charge")
				KitSfx.play(self, "turret_charge")
		Phase.CHARGE:
			var ct := charge_time * (0.6 if alert_left > 0.0 else 1.0)
			var lock_at := ct * (1.0 - aim_lock)
			if _p_t < lock_at and c != null:
				_track(target, delta)
			if not seen and _p_t < lock_at:
				# Lost the cat: stand down quietly.
				end_telegraph()
				phase = Phase.IDLE
				_head.play("idle")
			elif _p_t >= ct:
				end_telegraph()
				_fire()
		Phase.FIRE:
			if _p_t >= 0.12:
				phase = Phase.COOL
				_p_t = 0.0
				_head.play("idle")
		Phase.COOL:
			if _p_t >= cooldown * (0.6 if alert_left > 0.0 else 1.0):
				phase = Phase.IDLE
	_aim_head()


func _track(target: Vector2, _delta: float) -> void:
	var d := (target - to_global(_muzzle_local)).rotated(-rotation)
	if d.length() < 1.0:
		return
	var a := d.normalized()
	# It cannot point into the surface it is bolted to.
	if a.y > 0.15:
		a = Vector2(signf(a.x) if a.x != 0.0 else 1.0, 0.0)
	aim = a.rotated(rotation)


func _aim_head() -> void:
	var a := aim_local()
	if a.x >= 0.0:
		_head.rotation = a.angle()
		_head.scale = Vector2(art_scale, art_scale)
	else:
		_head.rotation = a.angle() - PI
		_head.scale = Vector2(-art_scale, art_scale)


func _fire() -> void:
	phase = Phase.FIRE
	_p_t = 0.0
	shots += 1
	_head.play("fire")
	KitSfx.play(self, "turret_fire")
	Projectile.spawn(get_parent(), muzzle(), aim * bolt_speed, Projectile.Kind.BOLT)


func _recovered() -> void:
	phase = Phase.COOL
	_p_t = 0.0
	_head.play("idle")


func _on_stunned() -> void:
	phase = Phase.IDLE
	_head.play("stun")


func _recover() -> void:
	life = Life.ACTIVE
	sprite.play("idle")
	_head.play("idle")
	_recovered()


func _apply_look() -> void:
	super()
	_head.modulate = sprite.modulate
	if telegraphing:
		var pulse := 1.0 + 0.8 * absf(sin(_tele_t * 14.0))
		_head.modulate = Color(pulse, pulse * 0.85, pulse * 0.8)
