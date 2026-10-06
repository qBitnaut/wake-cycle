class_name HeavyMech
extends KitEnemy
## Heavy mech: the mini-boss for Room 4. Armoured: stomps and the shockwave only
## clank off its plating. Only the ground pound hurts it: each pound stuns it and
## takes one of its `armour_hits` (3); an explosive barrel's blast counts as a pound.
## It walks slowly, and when the cat is in front of it on its level it CHARGES: it
## crouches and vents steam for `tell_time` (the warning, with a roar), then runs
## flat out until a wall or `charge_time` s. A charge that ends in a wall dazes it
## (a free window to pound it). Touching it hurts. A phasing cat slips through.
## The last pound destroys it: a big explosion, 2000 points, a guaranteed data chip.

enum Mode { PATROL, TELL, CHARGE, DAZED, COOL }

@export var walk_speed := 26.0
@export var charge_speed := 215.0
@export var charge_time := 1.5
@export var tell_time := 0.9
@export var cooldown := 1.5
@export var daze_time := 2.0
@export var detect_range := 300.0

var mode := Mode.PATROL
var dir := -1
var charges := 0
var wall_slams := 0

var _edge: RayCast2D
var _m_t := 0.0


func _init() -> void:
	actor_id = "heavy_mech"
	armour_hits = 3
	stomp_effect = "none"
	shock_effect = "none"
	pound_effect = "stun"
	blast_effect = "stun"
	points = 2000
	explosion_size = 2.0
	chip_chance = 1.0
	stun_time = 2.5
	body_shrink = 0.7


func _setup() -> void:
	_edge = RayCast2D.new()
	_edge.collision_mask = 1
	_edge.target_position = Vector2(0, 40)
	add_child(_edge)
	sprite.play("walk")


func _tick(delta: float) -> void:
	_m_t += delta
	match mode:
		Mode.PATROL:
			_walk(walk_speed)
			sprite.speed_scale = 0.6
			if is_on_floor() and _cat_in_front():
				mode = Mode.TELL
				_m_t = 0.0
				begin_telegraph()
				velocity.x = 0.0
				sprite.play("charge")
				sprite.speed_scale = 0.3
				KitSfx.play(self, "mech_charge")
		Mode.TELL:
			velocity.x = 0.0
			var p := 1.0 + 0.9 * absf(sin(_m_t * 12.0))
			tint = Color(p, p * 0.6, p * 0.55)
			if int(_m_t * 14.0) % 2 == 0:
				Debris.burst(get_parent(), to_global(Vector2(-dir * rect.size.x * 0.3, rect.position.y * 0.7)), Color(0.85, 0.9, 1.0), 1)
			if _m_t >= tell_time:
				end_telegraph()
				tint = Color.WHITE
				mode = Mode.CHARGE
				_m_t = 0.0
				charges += 1
				sprite.speed_scale = 1.2
		Mode.CHARGE:
			velocity.x = dir * charge_speed
			if is_on_wall() and get_wall_normal().x * dir < 0.0:
				_slam()
			elif _m_t >= charge_time or (is_on_floor() and not _edge_ahead()):
				mode = Mode.COOL
				_m_t = 0.0
				sprite.play("walk")
		Mode.COOL:
			velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
			if _m_t >= cooldown:
				mode = Mode.PATROL
				sprite.play("walk")
	sprite.flip_h = dir < 0
	facing = dir


func _edge_ahead() -> bool:
	_edge.position.x = dir * (rect.size.x * 0.5 + 6.0)
	_edge.force_raycast_update()
	return _edge.is_colliding()


func _walk(spd: float) -> void:
	var blocked := is_on_wall() and get_wall_normal().x * dir < 0.0
	if is_on_floor() and (blocked or not _edge_ahead()):
		dir = -dir
	velocity.x = dir * spd


func _cat_in_front() -> bool:
	var c := cat()
	if c == null or c.dead:
		return false
	var t := cat_centre()
	var dx := (t.x - global_position.x) * dir
	return dx > 0.0 and dx <= detect_range and absf(t.y - centre().y) < 46.0 and line_clear(centre(), t)


func _slam() -> void:
	wall_slams += 1
	KitSfx.play(self, "mech_slam")
	ScreenShake.shake_at(self, 0.5, 0.35)
	Debris.burst(get_parent(), to_global(Vector2(dir * rect.size.x * 0.5, rect.position.y * 0.5)), Color(0.6, 0.62, 0.7), 8)
	velocity.x = -dir * 60.0
	sprite.speed_scale = 1.0
	stun(daze_time)


func _hurt_cat(c: Cat) -> void:
	c.hurt(global_position)


func _on_stunned() -> void:
	end_telegraph()
	tint = Color.WHITE
	sprite.speed_scale = 1.0


func _recovered() -> void:
	mode = Mode.COOL
	_m_t = 0.0
	sprite.play("walk")


func _draw() -> void:
	super()
	if life == Life.ACTIVE and hp > 0:
		# Plating pips: one gold bar per hit it can still take.
		var y := rect.position.y - 6.0
		for i in hp:
			draw_rect(Rect2(Vector2(rect.get_center().x - hp * 4.0 + i * 8.0, y), Vector2(6, 2)), Color(1.6, 1.2, 0.5))
