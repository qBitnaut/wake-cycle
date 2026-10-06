class_name KitPatrolBot
extends KitEnemy
## The patrol bot, smaller (the Legacy Collection biped at 0.7: about 1.3 tiles) and
## armed. It walks, turns at walls and edges, and when the cat is in front of it in
## its line (same height, in range, in sight) it STOPS, flares its eyes for `aim_time`
## (a clear warning), then fires a short red laser burst forward, then walks on.
##
## Defeat: a plain cat bounces off. With a power a stomp stuns it and a second stomp
## finishes it; the shockwave stuns; the pound destroys. (The room patrol bot,
## PatrolBot, is unchanged: this is the kit's armed sibling.)

enum Mode { WALK, AIM, BURST, COOL }

@export var speed := 40.0
@export var laser_range := 190.0
@export var aim_time := 0.7
@export var burst_time := 0.35
@export var cooldown := 1.6
## Vertical reach of "in its line", in px (half height, around the muzzle).
@export var line_half_height := 26.0
@export var shoots := true

var mode := Mode.WALK
var dir := -1
var bursts := 0

var _edge: RayCast2D
var _beam: KitBeam
var _m_t := 0.0
var _muzzle_art := Vector2(22, -30)


func _init() -> void:
	actor_id = "patrol_bot"
	points = 200
	explosion_size = 1.0


func _setup() -> void:
	_edge = RayCast2D.new()
	_edge.collision_mask = 1
	_edge.target_position = Vector2(0, 28)
	add_child(_edge)
	_beam = KitBeam.new()
	_beam.reach = laser_range
	add_child(_beam)
	sprite.play("walk")


func _muzzle_pos() -> Vector2:
	return to_global(Vector2(_muzzle_art.x * dir * art_scale, _muzzle_art.y * art_scale))


func _tick(delta: float) -> void:
	_m_t += delta
	match mode:
		Mode.WALK:
			_walk()
			if shoots and _cat_in_line():
				mode = Mode.AIM
				_m_t = 0.0
				begin_telegraph()
				velocity.x = 0.0
				sprite.play("aim")
				KitSfx.play(self, "laser_charge")
		Mode.AIM:
			velocity.x = 0.0
			var pulse := 1.0 + 1.2 * absf(sin(_m_t * 16.0))
			tint = Color(pulse, pulse * 0.6, pulse * 0.55)
			if _m_t >= aim_time:
				end_telegraph()
				tint = Color.WHITE
				mode = Mode.BURST
				_m_t = 0.0
				bursts += 1
				_beam.global_position = _muzzle_pos()
				_beam.rotation = 0.0 if dir > 0 else PI
				_beam.fire(burst_time)
				KitSfx.play(self, "laser_zap")
		Mode.BURST:
			velocity.x = 0.0
			if _m_t >= burst_time:
				mode = Mode.COOL
				_m_t = 0.0
				sprite.play("walk")
		Mode.COOL:
			_walk()
			if _m_t >= cooldown:
				mode = Mode.WALK


func _walk() -> void:
	_edge.position.x = dir * 16.0 * art_scale / 0.7
	_edge.force_raycast_update()
	var blocked := is_on_wall() and get_wall_normal().x * dir < 0.0
	if is_on_floor() and (blocked or not _edge.is_colliding()):
		dir = -dir
	velocity.x = dir * speed
	sprite.flip_h = dir < 0
	facing = dir


func _cat_in_line() -> bool:
	var c := cat()
	if c == null or c.dead:
		return false
	var target := cat_centre()
	var m := _muzzle_pos()
	var dx := (target.x - m.x) * dir
	if dx < 0.0 or dx > laser_range:
		return false
	if absf(target.y - m.y) > line_half_height:
		return false
	return line_clear(m, target)


func _on_stunned() -> void:
	if telegraphing:
		end_telegraph()
	tint = Color.WHITE
	mode = Mode.COOL
	_m_t = 0.0
	_beam.firing = false
	_beam.active = false
	_beam.queue_redraw()


func _recovered() -> void:
	mode = Mode.WALK
	sprite.flip_h = dir < 0
