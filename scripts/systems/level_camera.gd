class_name LevelCamera
extends Node
## The camera driver a Level owns (see the API at the top of level.gd). It runs after
## the cat in the physics frame (process_physics_priority) so the view and the cat
## move in the same tick: no one-frame lag, no jitter.
##
## It only acts when the level asks for it: `Level.camera_follow == TIERS`, or the room
## has CameraZones. Otherwise the cat's own camera (centred on the cat, limits from
## Level) is left exactly as it was, so the 360 px rooms play as before.
##
## The driver takes the clamping over from Camera2D (Godot applies a camera's offset AFTER
## its limits, which would put the view outside them): the Camera2D limits are opened wide
## and the driver keeps the view centre inside the exact limit rect (the level's `limits`, or
## the CameraZone's rect) itself, by steering the cat camera's offset.
##
## TIERS follow: the cat's Camera2D is a child of the cat, so the driver steers it by its offset. The view centre `_cy` keeps a vertical dead zone around the
## cat: inside it the view does not move (a plain jump never scrolls); outside it the
## view follows. Falling fast looks ahead (the view leads the cat downward); standing on
## a new tier the view eases back towards the cat. The centre is rounded to whole px.

const REST_OFFSET := -25.0     ## view centre sits this far above the cat's feet (as cat.tscn)
const FOLLOW_K := 0.25         ## per-frame pull when the cat leaves the dead zone
const CATCH_UP_K := 0.045      ## per-frame drift back to the cat when standing
const REST_BAND := 16.0        ## standing: the view stops drifting inside +-this
const LOOK_SPEED := 360.0      ## fall speed where the look-ahead starts
const LOOK_GAIN := 0.18
const LOOK_MAX := 80.0
const LOCK_K := 0.12
const OPEN := 100000           ## Camera2D limits while the driver clamps (CineZoom sets 10 million)

var level  ## the Level (untyped: Level and LevelCamera refer to each other)
var cat: Cat
var zones: Array[CameraZone] = []          ## CameraZones holding the cat
var managed := false
var _cx := 0.0                 ## view centre, world px
var _cy := 0.0
var _x_free := true            ## the view follows the cat horizontally (not locked)
var _y_free := true            ## CENTRED mode: the view is centred on the cat vertically
var _lim := Rect2()            ## exact view limits as applied (eased towards the target)
var _was_owned := false


func _init() -> void:
	name = "LevelCamera"
	process_physics_priority = 100


func setup(l, c: Cat, tiers: bool) -> void:
	level = l
	cat = c
	managed = tiers or not get_tree().get_nodes_in_group("camera_zone").is_empty()
	_lim = Rect2(l.limits)
	set_physics_process(managed)
	if not managed:
		return
	_poll_zones()
	_lim = target_limits()
	_cx = cat.global_position.x
	_cy = cat.global_position.y + REST_OFFSET
	var cam := cat.camera
	cam.limit_left = -OPEN
	cam.limit_top = -OPEN
	cam.limit_right = OPEN
	cam.limit_bottom = OPEN
	cam.offset = Vector2(0.0, REST_OFFSET)
	_cy = _clamp_y(_cy)
	_cx = _clamp_x(_cx)
	_apply()


func _poll_zones() -> void:
	var probe := cat.global_position + Vector2(0, -16)
	for z in get_tree().get_nodes_in_group("camera_zone"):
		var inside: bool = z.holds(probe)
		if inside and not zones.has(z):
			zones.append(z)
		elif not inside and zones.has(z):
			zones.erase(z)


## The zone in force: the highest zone_priority, the latest entered among equals.
func active_zone() -> CameraZone:
	var best: CameraZone = null
	for z in zones:
		if best == null or z.zone_priority >= best.zone_priority:
			best = z
	return best


## The limits the camera is heading for (the zone's, or the level's).
func target_limits() -> Rect2:
	var z := active_zone()
	return Rect2(z.camera_rect()) if z != null else Rect2(level.limits)


func view_size() -> Vector2:
	return get_viewport().get_visible_rect().size / cat.camera.zoom


func _clamp_y(y: float) -> float:
	var half := view_size().y * 0.5
	var lo := _lim.position.y + half
	return clampf(y, lo, maxf(_lim.end.y - half, lo))


func _clamp_x(x: float) -> float:
	var half := view_size().x * 0.5
	var lo := _lim.position.x + half
	return clampf(x, lo, maxf(_lim.end.x - half, lo))


func _physics_process(_delta: float) -> void:
	if cat == null or not is_instance_valid(cat):
		return
	var cam := cat.camera
	# A cutscene (CineZoom) lifts the limits and owns the camera: stay out of its way.
	if cam.limit_top < -1000000:
		_was_owned = true
		return
	if _was_owned:
		# Take over from wherever the cutscene left the view, and open the limits again.
		_was_owned = false
		var c := cam.get_screen_center_position()
		_cx = c.x
		_cy = c.y
		_x_free = false
		_y_free = level.camera_tiers()
	_poll_zones()
	_ease_limits()
	var z := active_zone()
	var locked := z != null and z.lock_framing
	var cp := cat.global_position
	if locked:
		var mid := Vector2(z.camera_rect().get_center())
		_x_free = false
		_y_free = false
		_cx = lerpf(_cx, mid.x, LOCK_K)
		_cy = lerpf(_cy, mid.y, LOCK_K)
	else:
		if not _x_free:
			_cx = lerpf(_cx, cp.x, LOCK_K)
			_x_free = absf(_cx - cp.x) < 1.0
		if _x_free:
			_cx = cp.x
		if level.camera_tiers():
			_follow_tiers()
		elif not _y_free:
			_cy = lerpf(_cy, cp.y + REST_OFFSET, LOCK_K)
			_y_free = absf(_cy - (cp.y + REST_OFFSET)) < 1.0
		if _y_free and not level.camera_tiers():
			_cy = cp.y + REST_OFFSET
	_cx = _clamp_x(_cx)
	_cy = _clamp_y(_cy)
	_apply()


func _follow_tiers() -> void:
	var t := cat.global_position.y + REST_OFFSET
	var vy := cat.velocity.y
	var look := 0.0
	if vy > LOOK_SPEED:
		look = minf((vy - LOOK_SPEED) * LOOK_GAIN, LOOK_MAX)
	var d := (t + look) - _cy
	var up: float = level.dead_zone_up
	var down: float = level.dead_zone_down
	if d > down:
		_cy += (t + look - down - _cy) * FOLLOW_K
	elif d < -up:
		_cy += (t + look + up - _cy) * FOLLOW_K
	if cat.is_on_floor():
		var dd := t - _cy
		if absf(dd) > REST_BAND:
			var goal := t - clampf(dd, -REST_BAND, REST_BAND)
			_cy += (goal - _cy) * CATCH_UP_K


func _ease_limits() -> void:
	var tgt := target_limits()
	var step: float = level.zone_ease_px
	var a := _lim.position
	var b := _lim.end
	a = Vector2(move_toward(a.x, tgt.position.x, step), move_toward(a.y, tgt.position.y, step))
	b = Vector2(move_toward(b.x, tgt.end.x, step), move_toward(b.y, tgt.end.y, step))
	_lim = Rect2(a, b - a)


## The view centre, whole px, as the camera offset (the camera sits on the cat).
func _apply() -> void:
	var cp := cat.global_position
	cat.camera.offset = Vector2(roundf(_cx) - cp.x, roundf(_cy) - cp.y)
