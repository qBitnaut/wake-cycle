class_name HopperBot
extends KitEnemy
## Hopper bot: a spring-legged robot that hops toward the cat in arcs. It squats for
## `squat_time` (a visible wind-up, eyes blinking) and then springs; the hop is aimed
## at where the cat stood when it launched, so a sidestep or a jump beats it. After
## each landing it rests briefly. Touching it from the side or below hurts.
##
## Defeat: with a power a stomp stuns it (a second stomp finishes it), the shockwave
## stuns, the pound destroys.

enum Mode { IDLE, SQUAT, AIR, REST }

@export var detect_range := 230.0
@export var squat_time := 0.55
@export var hop_speed := 130.0
@export var hop_height := 64.0
@export var rest_time := 0.8

var mode := Mode.IDLE
var hops := 0

var _m_t := 0.0


func _init() -> void:
	actor_id = "hopper_bot"
	points = 200
	explosion_size = 0.9


func _tick(delta: float) -> void:
	_m_t += delta
	match mode:
		Mode.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			sprite.play("idle")
			if is_on_floor() and _cat_near():
				mode = Mode.SQUAT
				_m_t = 0.0
				begin_telegraph()
				sprite.play("squat")
				KitSfx.play(self, "hopper_squat")
		Mode.SQUAT:
			velocity.x = 0.0
			tint = Color(1.5, 1.2, 1.2) if int(_m_t * 14.0) % 2 == 0 else Color.WHITE
			if _m_t >= squat_time:
				end_telegraph()
				tint = Color.WHITE
				_hop()
		Mode.AIR:
			sprite.play("up" if velocity.y < 0.0 else "fall")
			if is_on_floor() and _m_t > 0.08:
				mode = Mode.REST
				_m_t = 0.0
				velocity.x = 0.0
				sprite.play("idle")
				KitSfx.play(self, "hopper_land")
				Debris.burst(get_parent(), global_position, Color(0.7, 0.72, 0.8), 3)
		Mode.REST:
			velocity.x = 0.0
			if _m_t >= rest_time:
				mode = Mode.IDLE


func _cat_near() -> bool:
	var c := cat()
	if c == null or c.dead:
		return false
	var t := cat_centre()
	return absf(t.x - global_position.x) <= detect_range and absf(t.y - global_position.y) <= 140.0


func _hop() -> void:
	var t := cat_centre()
	var dx := t.x - global_position.x
	facing = 1 if dx > 0.0 else -1
	sprite.flip_h = facing < 0
	hops += 1
	# Flight time of the arc, so the horizontal speed lands it near the cat (capped).
	var air := 2.0 * sqrt(2.0 * hop_height / 1600.0)
	velocity.x = clampf(dx / maxf(air, 0.1), -hop_speed, hop_speed)
	velocity.y = -sqrt(2.0 * 1600.0 * hop_height)
	mode = Mode.AIR
	_m_t = 0.0


func _on_stunned() -> void:
	mode = Mode.REST
	_m_t = 0.0
	tint = Color.WHITE
	end_telegraph()


func _recovered() -> void:
	mode = Mode.IDLE
	sprite.play("idle")
