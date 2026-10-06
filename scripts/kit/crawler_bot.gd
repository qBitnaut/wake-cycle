class_name CrawlerBot
extends KitEnemy
## Ceiling crawler / roller. It creeps along a ceiling (origin = the ceiling surface;
## it hangs below). When the cat passes beneath (`trigger_half` px sideways, within
## `drop_range` px down, in sight) it shudders and drips dust for `tell_time`, then
## DROPS, lands, and curls into a spiked ball that ROLLS along the floor toward the
## cat, bouncing off walls, for `roll_time` seconds; then it burns out (stunned and
## harmless until something finishes it).
##
## Defeat: a shockwave shakes it off the ceiling stunned / stuns a roller; the pound
## destroys; with a power a stomp stuns a roller (a second finishes it). On the
## ceiling only the shockwave reaches it. `mount_floor = true` places it on the floor
## as a roller already crawling.

enum Mode { CRAWL, TELL, FALL, ROLL, SPENT }

@export var crawl_range := 60.0
@export var crawl_speed := 18.0
@export var trigger_half := 24.0
@export var drop_range := 240.0
@export var tell_time := 0.6
@export var roll_speed := 105.0
@export var roll_time := 5.0
@export var mount_floor := false

var mode := Mode.CRAWL
var dir := 1

var _home_x := 0.0
var _home_set := false
var _m_t := 0.0
var _ceiling := true


func _init() -> void:
	actor_id = "crawler"
	uses_gravity = false
	points = 200
	explosion_size = 0.8
	stomp_effect = "stun"
	shock_effect = "stun"
	pound_effect = "destroy"


func _setup() -> void:
	collision_mask = 1
	_ceiling = not mount_floor
	if _ceiling:
		_to_ceiling_pose()
	else:
		mode = Mode.CRAWL
		uses_gravity = true
		sprite.play("crawl")


## Upside-down on the ceiling: the art is mirrored, the boxes hang below the origin.
func _to_ceiling_pose() -> void:
	sprite.scale.y = -art_scale
	var r := Rect2(rect.position.x, 0.0, rect.size.x, rect.size.y)
	body_cs.position = r.get_center()
	hitbox.get_child(0).position = r.get_center()
	rect = r
	_refresh_shock_box()
	stompable = false
	sprite.play("crawl")


func _to_floor_pose() -> void:
	_ceiling = false
	sprite.scale.y = art_scale
	var b := KitArt.bounds(actor_id)
	rect = Rect2(b.position * art_scale, b.size * art_scale)
	body_cs.position = rect.get_center()
	hitbox.get_child(0).position = rect.get_center()
	_refresh_shock_box()
	stompable = true
	uses_gravity = true


## Let go of the ceiling: the art turns upright and the boxes move down to where the
## hanging body was, so nothing overlaps the ceiling.
func _drop_pose() -> void:
	var h := rect.size.y
	_to_floor_pose()
	global_position.y += h


func _physics_process(delta: float) -> void:
	if not _home_set:
		_home_x = global_position.x
		_home_set = true
	super(delta)


func _tick(delta: float) -> void:
	_m_t += delta
	match mode:
		Mode.CRAWL:
			velocity.x = dir * crawl_speed
			if absf(global_position.x - _home_x) > crawl_range:
				dir = int(-signf(global_position.x - _home_x))
			elif is_on_wall():
				dir *= -1
			sprite.flip_h = dir < 0
			if _ceiling and _cat_beneath():
				mode = Mode.TELL
				_m_t = 0.0
				begin_telegraph()
				velocity.x = 0.0
				sprite.play("tell")
				KitSfx.play(self, "hopper_squat", -2.0, 0.6)
			elif not _ceiling and _cat_beneath(true):
				_start_roll()
		Mode.TELL:
			velocity.x = 0.0
			sprite.position.x = roundf(sin(_m_t * 55.0)) * 1.5
			if int(_m_t * 20.0) % 2 == 0:
				Debris.burst(get_parent(), global_position + Vector2(randf_range(-8, 8), 4), Color(0.45, 0.5, 0.55), 1)
			if _m_t >= tell_time:
				end_telegraph()
				sprite.position.x = 0.0
				mode = Mode.FALL
				_m_t = 0.0
				_drop_pose()
				stompable = false
				KitSfx.play(self, "crawler_drop")
		Mode.FALL:
			sprite.play("tell")
			if is_on_floor() and _m_t > 0.05:
				_start_roll()
				KitSfx.play(self, "hopper_land")
				Debris.burst(get_parent(), global_position, Color(0.7, 0.72, 0.8), 4)
		Mode.ROLL:
			velocity.x = dir * roll_speed
			if is_on_wall():
				dir = -dir
				velocity.x = dir * roll_speed
			sprite.flip_h = false
			if _m_t >= roll_time:
				mode = Mode.SPENT
				stun(INF)


func _cat_beneath(any_side := false) -> bool:
	var c := cat()
	if c == null or c.dead:
		return false
	var t := cat_centre()
	var dy := t.y - global_position.y
	if any_side:
		return absf(t.x - global_position.x) <= 200.0 and absf(dy) < 60.0
	return absf(t.x - global_position.x) <= trigger_half and dy >= 14.0 and dy <= drop_range \
		and line_clear(global_position + Vector2(0, 6), t)


func _start_roll() -> void:
	mode = Mode.ROLL
	_m_t = 0.0
	stompable = true
	sprite.play("roll")
	var c := cat()
	dir = 1 if c == null or c.global_position.x >= global_position.x else -1


func _on_stunned() -> void:
	if telegraphing:
		end_telegraph()
	sprite.position.x = 0.0
	if _ceiling:
		# Shaken off the ceiling: it falls and lies stunned.
		_drop_pose()
	if mode != Mode.SPENT:
		mode = Mode.FALL


func _recovered() -> void:
	if _ceiling:
		return
	_start_roll()


func _recover() -> void:
	if _stun_left == INF:
		return
	super()


func _stun_tick(delta: float) -> void:
	if mode == Mode.SPENT:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		_spark_t -= delta
		if _spark_t <= 0.0:
			_spark_t = 0.5
			Debris.burst(get_parent(), centre(), Color(1.0, 0.8, 0.3), 2)
		return
	super(delta)
