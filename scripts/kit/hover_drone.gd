class_name HoverDrone
extends KitEnemy
## Hover drone. It patrols the air on a sine bob; when the cat is below it (inside
## `drop_window` px sideways and `drop_range` px down) it hangs still, arms its bomb
## bay for `arm_time` (the bay glows red, the rotors race) and drops a BOMB (or a
## SPARK) straight down; then it cools down and flies on.
##
## Defeat: with a power a stomp (it is flimsy) or the pound destroys it; the
## shockwave knocks it out of the sky (stunned: it falls and fizzles on the floor,
## then rises again). A plain cat just avoids it.

enum Mode { PATROL, ARM, COOL }
enum Drop { BOMB, SPARK }

@export var patrol_range := 110.0
@export var speed := 46.0
@export var drop_window := 26.0
@export var drop_range := 230.0
@export var arm_time := 0.7
@export var cooldown := 2.4
@export var drop_kind: Drop = Drop.BOMB
@export var bob := 3.0

var mode := Mode.PATROL
var dir := 1
var drops := 0

var _home := Vector2.ZERO
var _m_t := 0.0
var _hum: LoopSfx


func _init() -> void:
	actor_id = "hover_drone"
	uses_gravity = false
	falls_when_stunned = true
	stomp_effect = "destroy"
	shock_effect = "stun"
	pound_effect = "destroy"
	points = 150
	explosion_size = 0.8
	body_shrink = 0.85


func _setup() -> void:
	collision_mask = 1
	_home = global_position
	sprite.play("fly")
	_hum = KitSfx.loop(self, "drone_hover", 360.0)


func _tick(delta: float) -> void:
	_m_t += delta
	var target_y := _home.y + sin(_t * 2.2) * bob
	velocity.y = (target_y - global_position.y) * 8.0
	match mode:
		Mode.PATROL:
			velocity.x = dir * speed
			if global_position.x > _home.x + patrol_range:
				dir = -1
			elif global_position.x < _home.x - patrol_range or is_on_wall():
				dir = 1 if global_position.x < _home.x else dir
			sprite.flip_h = dir < 0
			if _cat_below():
				mode = Mode.ARM
				_m_t = 0.0
				begin_telegraph()
				sprite.play("arm")
				KitSfx.play(self, "laser_charge", -4.0, 1.4)
		Mode.ARM:
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
			sprite.position.x = roundf(sin(_m_t * 50.0)) * 1.0
			if _m_t >= arm_time:
				end_telegraph()
				_drop()
				mode = Mode.COOL
				_m_t = 0.0
				sprite.play("fly")
		Mode.COOL:
			velocity.x = dir * speed * 0.6
			if is_on_wall():
				dir = -dir
			if _m_t >= cooldown:
				mode = Mode.PATROL
	if _hum:
		_hum.active = true


func _cat_below() -> bool:
	var c := cat()
	if c == null or c.dead:
		return false
	var t := cat_centre()
	var dy := t.y - global_position.y
	return absf(t.x - global_position.x) <= drop_window and dy >= 14.0 and dy <= drop_range \
		and line_clear(global_position, t)


func _drop() -> void:
	drops += 1
	var pos := to_global(Vector2(0, rect.end.y))
	if drop_kind == Drop.BOMB:
		Projectile.spawn(get_parent(), pos, Vector2(0, 30), Projectile.Kind.BOMB)
	else:
		Projectile.spawn(get_parent(), pos, Vector2(0, 80), Projectile.Kind.SPARK)


func _on_stunned() -> void:
	mode = Mode.COOL
	_m_t = 0.0
	if telegraphing:
		end_telegraph()
	if _hum:
		_hum.active = false


func _recovered() -> void:
	mode = Mode.PATROL
	sprite.play("fly")


func _on_defeated() -> void:
	if _hum:
		_hum.retire()
