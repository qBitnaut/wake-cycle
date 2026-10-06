class_name SecurityCamera
extends KitEnemy
## Security camera. It sweeps a view cone between `sweep_min` and `sweep_max` degrees
## (0 = right, 90 = straight down). A cat inside the cone and in sight is SPOTTED:
## the lens goes amber and ticks for `spot_time` (the warning; leave the cone and it
## resets), then the ALARM sounds for `alarm_time`: every turret within `alarm_radius`
## wakes up (and fires faster), and the shutters in `shutters` (KitShutter paths) roll
## shut. A dashing (phasing) cat is not seen.
##
## Defeat: the shockwave stuns it (blind, the alarm stops); the pound destroys it.
## It cannot be stomped.

enum Mode { SWEEP, SPOT, ALARM }

@export var sweep_min := 20.0
@export var sweep_max := 100.0
@export var sweep_speed := 24.0
@export var half_angle := 17.0
@export var view_range := 210.0
@export var spot_time := 0.7
@export var alarm_time := 6.0
@export var alarm_radius := 360.0
@export var shutters: Array[NodePath] = []

var mode := Mode.SWEEP
var angle := 60.0
var alarms := 0

var _head: AnimatedSprite2D
var _sweep_dir := 1.0
var _m_t := 0.0
var _hum: LoopSfx
var _pivot_local := Vector2(0, -3)


func _init() -> void:
	actor_id = "security_camera"
	static_body = true
	uses_gravity = false
	touch_damage = false
	stompable = false
	stomp_effect = "none"
	shock_effect = "stun"
	pound_effect = "destroy"
	points = 150
	explosion_size = 0.7


func _setup() -> void:
	# The swivel is the head part's offset in the manifest (where the mount's arm ends).
	var off: Array = KitArt.part(actor_id, "head").get("offset", [0, -3])
	_pivot_local = Vector2(off[0], off[1])
	_head = KitArt.make_sprite(actor_id, "head", art_scale)
	_head.name = "Head"
	add_child(_head)
	KitGlow.attach(_head)
	angle = sweep_min
	_apply_angle()


func _tick(delta: float) -> void:
	_m_t += delta
	match mode:
		Mode.SWEEP:
			angle += _sweep_dir * sweep_speed * delta
			if angle >= sweep_max:
				angle = sweep_max
				_sweep_dir = -1.0
			elif angle <= sweep_min:
				angle = sweep_min
				_sweep_dir = 1.0
			if sees_cat():
				mode = Mode.SPOT
				_m_t = 0.0
				begin_telegraph()
				_head.play("alarm")
				KitSfx.play(self, "camera_spot")
		Mode.SPOT:
			if not sees_cat():
				end_telegraph()
				mode = Mode.SWEEP
				_head.play("idle")
			elif _m_t >= spot_time:
				end_telegraph()
				_raise_alarm()
		Mode.ALARM:
			if _m_t >= alarm_time:
				mode = Mode.SWEEP
				_head.play("idle")
				if _hum:
					_hum.retire()
					_hum = null
	_apply_angle()


func head_pos() -> Vector2:
	return to_global(_pivot_local * art_scale)


func view_dir() -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(angle) + rotation)


func sees_cat() -> bool:
	var c := cat()
	if c == null or c.dead or c.is_phasing():
		return false
	var t := cat_centre()
	var d := t - head_pos()
	if d.length() > view_range or d.length() < 4.0:
		return false
	if absf(rad_to_deg(view_dir().angle_to(d))) > half_angle:
		return false
	return line_clear(head_pos(), t)


func _raise_alarm() -> void:
	mode = Mode.ALARM
	_m_t = 0.0
	alarms += 1
	KitSfx.play(self, "camera_alarm")
	_hum = KitSfx.loop(self, "camera_alarm", 520.0)
	for t in get_tree().get_nodes_in_group("kit_turret"):
		if t.has_method("alert") and t.global_position.distance_to(global_position) <= alarm_radius:
			t.alert(alarm_time)
	for p in shutters:
		var s := get_node_or_null(p)
		if s and s.has_method("close_for"):
			s.close_for(alarm_time)
	for s in get_tree().get_nodes_in_group("alarm_shutter"):
		if shutters.is_empty() and s.global_position.distance_to(global_position) <= alarm_radius:
			s.close_for(alarm_time)


func _apply_angle() -> void:
	_head.position = _pivot_local * art_scale
	_head.rotation = deg_to_rad(angle)
	# Past straight down the housing would hang upside down: mirror it so the hood stays on top.
	_head.flip_v = angle > 90.0
	# The hit box follows the swivelling head (the stomp-free shock and pound ranges too).
	var c := rect.get_center() + Vector2.RIGHT.rotated(deg_to_rad(angle)) * 5.0 * art_scale
	if hitbox != null and hitbox.get_child_count() > 0:
		(hitbox.get_child(0) as Node2D).position = c
	shock_offset = c


func _on_stunned() -> void:
	end_telegraph()
	mode = Mode.SWEEP
	_head.play("stun")
	if _hum:
		_hum.retire()
		_hum = null


func _recover() -> void:
	life = Life.ACTIVE
	sprite.play("idle")
	_head.play("idle")


func _on_defeated() -> void:
	if _hum:
		_hum.retire()


func _apply_look() -> void:
	super()
	_head.modulate = sprite.modulate


func _draw() -> void:
	super()
	if life == Life.DEAD:
		return
	# The view cone: a soft wedge, amber while it makes up its mind, red in alarm.
	var col := Color(1.0, 0.95, 0.6, 0.10)
	if mode == Mode.SPOT:
		col = Color(1.0, 0.7, 0.2, 0.18 + 0.12 * sin(_t * 30.0))
	elif mode == Mode.ALARM:
		col = Color(1.0, 0.2, 0.15, 0.16 + 0.10 * sin(_t * 12.0))
	if life == Life.STUNNED:
		return
	var o := _pivot_local * art_scale
	var a0 := deg_to_rad(angle - half_angle)
	var a1 := deg_to_rad(angle + half_angle)
	var pts := PackedVector2Array([o])
	for i in 9:
		var a := lerpf(a0, a1, i / 8.0)
		pts.append(o + Vector2(cos(a), sin(a)) * view_range)
	draw_colored_polygon(pts, Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, col.a))
