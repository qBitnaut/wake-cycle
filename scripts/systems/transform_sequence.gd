class_name TransformSequence
extends Node
## The hero moment: the nanotech goo takes the cat, and gives it back
## changed. About 10 s, with a slow cinematic zoom onto the cat throughout:
##
##   phase_started      beat
##   goo_rises          a  stuck: the cat churns and jitters, its feet sink,
##                         the pool grips and tendrils climb             1.0
##                      b  glossy goo climbs from the feet to the ears   2.6
##   veins_reach_eyes   c  circuit veins race up to the eyes; the eyes
##                         ignite and hold while a low hum swells        2.2
##   absorb             d  a bright pulse and a shake, then the goo
##                         soaks in                                      1.7
##   looks_normal       e  a beat: the cat looks normal                  0.6
##   augments_appear    f  the implants materialise and settle           1.1
##                      g  the zoom eases out, control returns           0.9
##
##     var seq := TransformSequence.play(cat)       # starts at once
##     seq.finished.connect(_on_transform_finished)
##
## Same API as the Room 1 stub: play() adds the node next to the cat and
## returns it; phase_started(phase) fires with the names above; `finished`
## comes last, after control is handed back, and the node then frees
## itself. Extra signals for audio and camera hooks: goo_rising (a),
## veins (c), absorbed (end of d) and augments_revealed (end of f).
##
## The cat: input is locked with Cat.set_can_move(false) and its animation
## held with Cat.set_forced_anim(); the sequence re-asserts its pose and
## sprite offset every frame after the level runs, so it owns the cat until
## `finished`. (A cat without those methods has its physics paused instead.)
## The goo, veins and augments are overlay sprites (CatNanotech,
## CatAugments): the cat's own sprite, material and fx_tint are untouched.
##
## Camera: the zoom is a CineZoom (native-resolution magnifier), so the
## level's Camera2D zoom is never changed and pixels stay crisp through
## every fractional zoom. The active camera (get_viewport().get_camera_2d())
## has its limits lifted and its offset eased only as far as the close-up
## needs; zoom, limits, offset, smoothing and any ScreenShake are saved and
## restored. The HUD (group "hud", or a CanvasLayer named "Hud") fades out
## and back. The goo pool is the nearest GooPool under the cat unless one
## is passed to play().

signal phase_started(phase: StringName)
signal finished
signal goo_rising
signal veins
signal absorbed
signal augments_revealed

enum ZoomMode { MAGNIFIER, CAMERA }

const GOO_RISES := &"goo_rises"
const VEINS_REACH_EYES := &"veins_reach_eyes"
const ABSORB := &"absorb"
const LOOKS_NORMAL := &"looks_normal"
const AUGMENTS_APPEAR := &"augments_appear"

const T_STUCK := 1.0
const T_RISE := 2.6
const T_VEINS := 1.8
const T_EYES := 0.4
const T_PULSE := 0.25
const T_ABSORB := 1.45
const T_STILL := 0.6
const T_REVEAL := 1.1
const T_RELEASE := 0.9

## Leave empty to use the nearest GooPool under the cat.
@export var pool: GooPool
## MAGNIFIER: CineZoom, smooth and crisp at any zoom (the default).
## CAMERA: the Camera2D's own zoom at the internal resolution; fractional
## steps there give uneven pixels that shimmer. Kept for comparison.
@export var zoom_mode := ZoomMode.MAGNIFIER
## Close-up magnification at the end of the absorb (held for e and f).
@export_range(1.0, 4.0, 0.05) var zoom_max := 3.0
## Where the view centres on the cat, relative to its origin (feet), px.
@export var focus_offset := Vector2(0, -16)
@export var letterbox := true
## Low hum under the veins (a loop, played pitched down).
@export var hum_stream: AudioStream = preload("res://assets/audio/sfx8bit/laser_hum_loop.ogg")
@export var hum_pitch := 0.45
@export_range(-60.0, 0.0, 0.5) var hum_volume_db := -11.0
## How far the feet sink into the goo while it holds the cat, px.
@export var sink_px := 4.0

var cat: Cat
var phase: StringName = &""
var running := false

var _sprite: AnimatedSprite2D
var _nano: CatNanotech
var _aug: CatAugments
var _cine: CineZoom
var _cam: Camera2D
var _cam_saved := {}
var _shakers: Array[Node] = []
var _hud: Array[CanvasItem] = []
var _pool_z := 0
var _sprite_pos := Vector2.ZERO
var _struggle := 0.0
var _sink := 0.0
var _t := 0.0
var _anim := ""
var _anim_speed := 1.0
var _anim_t := 0.0
var _frozen := false
var _paused_physics := false


## Start the sequence on `target` (optionally with its pool). The node is
## added next to the cat, plays at once, and frees itself after `finished`.
static func play(target: Cat, goo: GooPool = null) -> TransformSequence:
	var seq := TransformSequence.new()
	seq.name = "TransformSequence"
	seq.cat = target
	seq.pool = goo
	target.get_parent().add_child(seq)
	seq.start()
	return seq


## Run the whole sequence (play() calls this). Await `finished` to wait.
func start() -> void:
	if running or cat == null:
		return
	running = true
	process_priority = 100  # after the level, so the cat's pose is ours
	_sprite = cat.sprite
	_setup()

	# (a) Stuck: churning, jittering, feet sinking; the goo takes hold.
	_enter(GOO_RISES)
	goo_rising.emit()
	var cin := create_tween().set_parallel(true)
	var t_in := T_STUCK + T_RISE + T_VEINS + T_EYES + T_PULSE + T_ABSORB
	if zoom_mode == ZoomMode.CAMERA and _cam:
		cin.tween_property(_cam, "zoom", _cam.zoom * zoom_max, t_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		cin.tween_property(_cine, "zoom", zoom_max, t_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if letterbox:
		cin.tween_property(_cine, "bars", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	cin.tween_property(_cine, "vignette", 0.35, 2.0)
	_set_anim("walk", 1.8)
	_struggle = 1.0
	if pool:
		pool.grip(cat.global_position.x, 1.0, cat.z_index)
	create_tween().tween_property(self, "_sink", sink_px, T_STUCK + T_RISE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _wait(T_STUCK * 0.5)
	_sprite.flip_h = not _sprite.flip_h  # tries the other way
	await _wait(T_STUCK * 0.5)

	# (b) The goo rises; the struggle slows and the cat freezes.
	create_tween().tween_property(_nano, "goo_level", 1.0, T_RISE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var slow := create_tween().set_parallel(true)
	slow.tween_property(self, "_anim_speed", 0.4, T_RISE * 0.5)
	slow.tween_property(self, "_struggle", 0.0, T_RISE * 0.6)
	await _wait(T_RISE * 0.45)
	if pool:
		pool.grip(cat.global_position.x, 0.3, cat.z_index)  # tendrils sink into the coat
	await _wait(T_RISE * 0.15)
	_sprite.flip_h = not _sprite.flip_h
	_set_anim("idle", 1.0, true)
	await _wait(T_RISE * 0.4)

	# (c) Veins race up to the eyes; the eyes hold ablaze; the hum swells.
	_enter(VEINS_REACH_EYES)
	veins.emit()
	create_tween().tween_property(_nano, "vein_progress", 1.0, T_VEINS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var hum := _start_hum()
	if pool:
		pool.surge(1.0)
	await _wait(T_VEINS + T_EYES)

	# (d) Pulse, shake, then the goo soaks in.
	_enter(ABSORB)
	var pulse := create_tween()
	pulse.tween_property(_nano, "flash", 2.2, 0.06)
	pulse.tween_property(_nano, "flash", 0.0, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_cine.shake(0.75, 0.5)
	_burst_light()
	if pool:
		pool.surge(1.0)
		pool.release()
	if hum:
		var hf := create_tween()
		hf.tween_property(hum, "volume_db", -60.0, 0.35)
		hf.tween_callback(hum.queue_free)
	Sfx.play(self, "shockwave_thump", -4.0, 0.8)
	await _wait(T_PULSE)
	create_tween().tween_property(_nano, "absorb", 1.0, T_ABSORB) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	create_tween().tween_property(self, "_sink", 0.0, T_ABSORB * 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _wait(T_ABSORB * 0.8)
	var last := create_tween()  # one last faint flicker through the veins
	last.tween_property(_nano, "flash", 0.6, 0.07)
	last.tween_property(_nano, "flash", 0.0, 0.25)
	await _wait(T_ABSORB * 0.2)
	absorbed.emit()

	# (e) A beat of stillness: the cat looks normal.
	_enter(LOOKS_NORMAL)
	_nano.clear()
	_set_anim("idle")
	await _wait(T_STILL)

	# (f) The augments materialise.
	_enter(AUGMENTS_APPEAR)
	_aug.reveal(T_REVEAL)
	Sfx.play(self, "power_up", -12.0, 1.3)
	await _wait(T_REVEAL)
	augments_revealed.emit()

	# (g) Ease back out to gameplay, hand the cat back, then `finished`.
	await _release()
	running = false
	finished.emit()
	queue_free()


func _enter(p: StringName) -> void:
	phase = p
	phase_started.emit(p)


func _process(delta: float) -> void:
	if not running or _sprite == null:
		return
	_t += delta
	var jx := roundf(sin(_t * 41.0) * 1.2 * _struggle)
	_sprite.position = _sprite_pos + Vector2(jx, roundf(_sink))
	_hold_pose(delta)


## Plays `anim` at `speed`, or holds its first frame when `frozen`. The
## frame comes from our own clock, so a level that keeps forcing its own
## animation on the cat cannot knock the pose off.
func _set_anim(anim: String, speed := 1.0, frozen := false) -> void:
	_anim = anim
	_anim_speed = speed
	_anim_t = 0.0
	_frozen = frozen
	_hold_pose(0.0)


func _hold_pose(delta: float) -> void:
	if _anim == "" or _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(_anim):
		return
	if _sprite.animation != _anim:
		if cat.has_method("set_forced_anim"):
			cat.call("set_forced_anim", _anim)
		else:
			_sprite.play(_anim)
	if _sprite.is_playing():
		_sprite.pause()
	var sf := _sprite.sprite_frames
	var n := sf.get_frame_count(_anim)
	if _frozen:
		_sprite.frame = 0
		return
	_anim_t += delta * _anim_speed
	var f := int(_anim_t * sf.get_animation_speed(_anim))
	_sprite.frame = f % n if sf.get_animation_loop(_anim) else mini(f, n - 1)


func _wait(t: float) -> Signal:
	return get_tree().create_timer(t, false).timeout


func _setup() -> void:
	_t = 0.0
	_sink = 0.0
	_sprite_pos = _sprite.position
	if cat.has_method("set_can_move"):
		cat.call("set_can_move", false)
	else:
		cat.set_physics_process(false)  # older Cat: no cutscene lock
		_paused_physics = true
	cat.velocity.x = 0.0
	_nano = CatNanotech.attach(_sprite)
	_nano.clear()
	_aug = CatAugments.attach(cat, false)
	if pool == null:
		pool = _find_pool()
	if pool:
		_pool_z = pool.z_index
		if pool.z_index <= cat.z_index:
			pool.z_index = cat.z_index + 1  # the sunk feet go under the surface
	_cine = CineZoom.new()
	_cine.name = "CineZoom"
	add_child(_cine)
	_cine.target = cat
	_cine.target_offset = focus_offset
	_take_camera()
	_fade_hud(true)


func _find_pool() -> GooPool:
	var best: GooPool = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("goo_pool"):
		var gp := p as GooPool
		if gp == null:
			continue
		var lx := cat.global_position.x - gp.global_position.x
		var dx := maxf(maxf(-lx, lx - gp.width), 0.0)
		var d := dx + absf(cat.global_position.y - gp.global_position.y)
		if d < best_d and d < 64.0:
			best = gp
			best_d = d
	return best


## Lift the camera's limits, keeping the view exactly where it is (no jump),
## then ease its offset only as far as the close-up needs.
func _take_camera() -> void:
	_cam = get_viewport().get_camera_2d()
	if _cam == null:
		return
	_cam_saved = {
		"zoom": _cam.zoom, "offset": _cam.offset,
		"limits": [_cam.limit_left, _cam.limit_top, _cam.limit_right, _cam.limit_bottom],
		"smoothing": _cam.position_smoothing_enabled, "limit_smoothed": _cam.limit_smoothed,
	}
	for c in _cam.get_children():
		if c is ScreenShake:
			c.set_process(false)  # the CineZoom shakes the close-up instead
			_shakers.append(c)
	var seen := _cam.get_screen_center_position()
	_cam.position_smoothing_enabled = false
	_cam.limit_left = -10000000
	_cam.limit_top = -10000000
	_cam.limit_right = 10000000
	_cam.limit_bottom = 10000000
	# Measure, do not assume: whatever order the camera applies limits and
	# offset in, this keeps the first frame identical.
	_cam.force_update_scroll()
	_cam.offset += seen - _cam.get_screen_center_position()
	_cam.force_update_scroll()
	_cam_saved["hold"] = _cam.offset
	# Pan only as far as the close-up needs: the magnified view at zoom_max
	# must fit inside the game frame with the cat at its centre. Usually
	# that is nothing at all, and the room never slides.
	var vp := get_viewport().get_visible_rect().size
	var half := vp * 0.5 / zoom_max
	var at := cat.get_global_transform_with_canvas() * focus_offset
	var shift := (at - at.clamp(half, vp - half)) / _cam.zoom
	if zoom_mode == ZoomMode.CAMERA:
		shift = (at - vp * 0.5) / _cam.zoom  # camera zoom scales about the view centre
	if shift.length() > 0.5:
		create_tween().tween_property(_cam, "offset", (_cam.offset + shift).round(), T_STUCK + 0.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _give_camera_back() -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var lim: Array = _cam_saved["limits"]
	_cam.limit_left = lim[0]
	_cam.limit_top = lim[1]
	_cam.limit_right = lim[2]
	_cam.limit_bottom = lim[3]
	_cam.offset = _cam_saved["offset"]
	_cam.zoom = _cam_saved["zoom"]
	_cam.position_smoothing_enabled = _cam_saved["smoothing"]
	_cam.limit_smoothed = _cam_saved["limit_smoothed"]
	for s in _shakers:
		if is_instance_valid(s):
			s.set_process(true)
	_shakers.clear()


func _fade_hud(out: bool) -> void:
	if out:
		_hud.clear()
		var layers: Array = get_tree().get_nodes_in_group("hud")
		var scene := get_tree().current_scene
		if scene:
			layers.append_array(scene.find_children("Hud", "CanvasLayer", true, false))
		for l in layers:
			if l is CanvasItem:
				_hud.append(l)
			for c in l.get_children():
				if c is CanvasItem and not _hud.has(c):
					_hud.append(c)
	for item in _hud:
		if is_instance_valid(item):
			create_tween().tween_property(item, "modulate:a", 0.0 if out else 1.0, 0.4)


func _start_hum() -> AudioStreamPlayer:
	if hum_stream == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = hum_stream
	p.pitch_scale = hum_pitch
	p.volume_db = -40.0
	add_child(p)
	p.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p, "volume_db", hum_volume_db, T_VEINS + T_EYES).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(p, "pitch_scale", hum_pitch * 1.35, T_VEINS + T_EYES).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return p


func _burst_light() -> void:
	var l := PointLight2D.new()
	l.texture = preload("res://assets/fx/light_soft.png")
	l.color = FXPalette.NANO_BLUE.lerp(FXPalette.NANO_GREEN, 0.5)
	l.energy = 3.0
	l.texture_scale = 1.6
	l.position = focus_offset
	cat.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "energy", 0.0, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


func _release() -> Signal:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_cine, "zoom", 1.0, T_RELEASE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if zoom_mode == ZoomMode.CAMERA and _cam:
		tw.tween_property(_cam, "zoom", _cam_saved["zoom"], T_RELEASE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_cine, "bars", 0.0, T_RELEASE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_cine, "vignette", 0.0, T_RELEASE)
	if _cam and _cam_saved.has("hold"):
		tw.tween_property(_cam, "offset", _cam_saved["hold"], T_RELEASE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade_hud(false)
	tw.chain().tween_callback(_teardown)
	return tw.finished


func _teardown() -> void:
	_give_camera_back()
	if is_instance_valid(_cine):
		_cine.queue_free()
	_cine = null
	if pool:
		pool.z_index = _pool_z
	_struggle = 0.0
	_sink = 0.0
	_anim = ""
	_sprite.position = _sprite_pos
	_sprite.speed_scale = 1.0
	if cat.has_method("set_forced_anim"):
		cat.call("set_forced_anim", "")
	_sprite.play()
	if _paused_physics:
		cat.set_physics_process(true)
	if cat.has_method("set_can_move"):
		cat.call("set_can_move", true)
