class_name KitPlatform
extends AnimatableBody2D
## Moving platforms for verticality. One-way (the cat jumps up through it and lands
## on it). Origin = the middle of the top surface.
##   HORIZONTAL / VERTICAL  ping-pong over `travel` px at `speed`, pausing at the ends
##   FALLING                holds still; `fall_delay` s after the cat stands on it
##                          (it shakes and crumbles: the warning, at least 0.4 s) it
##                          drops away; it returns after `respawn_time` s.

enum Mode { HORIZONTAL, VERTICAL, FALLING }

@export var mode: Mode = Mode.HORIZONTAL
@export var width_tiles := 2
@export var travel := 96.0
@export var speed := 48.0
@export var pause := 0.5
@export var fall_delay := 0.8
@export var respawn_time := 3.0

var state := "ride"  # FALLING: ride, shake, fall, gone
var rider := false
var last_warn := 0.0

var _start := Vector2.ZERO
var _start_set := false
var _s := 0.0
var _dir := 1.0
var _pause_left := 0.0
var _t := 0.0
var _st := 0.0
var _vy := 0.0
var _cs: CollisionShape2D
var _top: Area2D
var _tex: Array[Texture2D] = []
var _alpha := 1.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true
	add_to_group("kit_platform")
	var w := width_tiles * 32.0
	_cs = CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(w, 10.0)
	_cs.shape = sh
	_cs.position = Vector2(0, 5.0)
	_cs.one_way_collision = true
	_cs.one_way_collision_margin = 3.0
	add_child(_cs)
	for n in ["left", "mid", "right"]:
		_tex.append(KitArt.frame_texture("platform", "plate", n))
	_top = Area2D.new()
	_top.collision_layer = 0
	_top.collision_mask = 2
	var ts := CollisionShape2D.new()
	var tsh := RectangleShape2D.new()
	tsh.size = Vector2(w - 6.0, 8.0)
	ts.shape = tsh
	ts.position = Vector2(0, -5.0)
	_top.add_child(ts)
	add_child(_top)
	z_index = 2


func _axis() -> Vector2:
	return Vector2.RIGHT if mode == Mode.HORIZONTAL else Vector2.DOWN


func _physics_process(delta: float) -> void:
	if not _start_set:
		_start = global_position
		_start_set = true
	_t += delta
	if mode == Mode.FALLING:
		_falling(delta)
	else:
		_ping_pong(delta)
	queue_redraw()


func _ping_pong(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		return
	_s += _dir * speed * delta
	if _s >= travel:
		_s = travel
		_dir = -1.0
		_pause_left = pause
	elif _s <= 0.0:
		_s = 0.0
		_dir = 1.0
		_pause_left = pause
	global_position = _start + _axis() * _s


func _cat_on_top() -> bool:
	for b in _top.get_overlapping_bodies():
		if b is Cat and b.is_on_floor() and b.velocity.y >= -1.0 and not b.dead:
			return true
	return false


func _falling(delta: float) -> void:
	_st += delta
	match state:
		"ride":
			rider = _cat_on_top()
			if rider:
				state = "shake"
				_st = 0.0
				KitSfx.play(self, "platform_shake")
		"shake":
			global_position = _start + Vector2(roundf(sin(_t * 70.0)), 0)
			if int(_st * 16.0) % 2 == 0:
				Debris.burst(get_parent(), global_position + Vector2(randf_range(-20, 20), 8), Color(0.5, 0.58, 0.62), 1)
			if _st >= maxf(fall_delay, 0.4):
				last_warn = _st
				state = "fall"
				_st = 0.0
				_vy = 0.0
				KitSfx.play(self, "platform_fall")
		"fall":
			_vy = minf(_vy + 900.0 * delta, 600.0)
			global_position += Vector2(0, _vy * delta)
			_alpha = clampf(1.0 - _st / 1.2, 0.0, 1.0)
			if _st >= 1.2:
				state = "gone"
				_st = 0.0
				_cs.disabled = true
				global_position = _start
		"gone":
			_alpha = 0.0
			if _st >= respawn_time:
				state = "ride"
				_cs.disabled = false
				_alpha = 1.0
				global_position = _start


func _draw() -> void:
	if _tex.size() < 3 or _alpha <= 0.0:
		return
	var w := width_tiles
	for i in w:
		var t: Texture2D = _tex[0] if i == 0 else (_tex[2] if i == w - 1 else _tex[1])
		if w == 1:
			t = _tex[1]
		draw_texture(t, Vector2(-w * 16.0 + i * 32.0, 0), Color(1, 1, 1, _alpha))
