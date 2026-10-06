class_name TransformSequence
extends Node
## The hero moment: the goo takes the cat and gives it back changed. It
## does not grant a power: it wakes a mind. About 18 s, with a slow
## cinematic zoom onto the cat throughout.
##
##   phase_started      beat                                                  s
##   goo_rises          a  caught: the cat churns, strains and cries; its feet
##                         sink; the pool grips and dark tendrils climb      1.4
##                      b  glossy black goo creeps up the cat while it
##                         fights, weaker and weaker, until it freezes       4.0
##   veins_reach_eyes   c  glowing veins crawl up through the goo to the eyes,
##                         shedding sparks; the eyes ignite and hold         3.0
##   absorb             d  an energy pulse (rings, flash, shake), then the
##                         goo soaks into the cat                            1.9
##   looks_normal       e  a still beat: just the tabby again                1.0
##   augments_appear    f  the implants arrive one by one, each with a flash:
##                         ear, spine plates from the neck back, tail band,
##                         eye ring; then the cat stands with them           4.2
##                         the awakened mind: a soft glow at the head and a
##                         glint in the eye as the camera eases in;
##                         `mind_awakened`                                   1.5
##                      g  the zoom eases out, control returns, `finished`   1.1
##
##     var seq := TransformSequence.play(cat)       # starts at once
##     seq.finished.connect(_on_transform_finished)
##
## Same API as the Room 1 stub: play() adds the node next to the cat and
## returns it; phase_started(phase) fires with the names above; `finished`
## comes last, after control is handed back, and the node then frees
## itself. Extra signals for audio, camera and story hooks: goo_rising (a),
## veins (c), absorbed (end of d), augments_revealed (end of the reveal),
## mind_awakened (end of the mind beat, just before the zoom eases out).
##
## The cat: input is locked with Cat.set_can_move(false) and its animation
## held with Cat.set_forced_anim(); the sequence re-asserts its pose and
## sprite offset every frame after the level runs, so it owns the cat until
## `finished`. (A cat without those methods has its physics paused instead.)
## The goo, pixel veins and augments are overlay sprites (CatNanotech,
## CatAugments); the HD glow (smooth veins, sparks, eye flare, pulse,
## augment flashes, the mind glow) is NanoHD at native resolution over the
## CineZoom close-up. The cat's own sprite, material and fx_tint are
## untouched, and the pool stays colourless: the colour is all on the cat.
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
signal mind_awakened

enum ZoomMode { MAGNIFIER, CAMERA }

const GOO_RISES := &"goo_rises"
const VEINS_REACH_EYES := &"veins_reach_eyes"
const ABSORB := &"absorb"
const LOOKS_NORMAL := &"looks_normal"
const AUGMENTS_APPEAR := &"augments_appear"

const T_STUCK := 1.4
const T_RISE := 4.0
const T_VEINS := 2.4
const T_EYES := 0.6
const T_PULSE := 0.3
const T_ABSORB := 1.6
const T_STILL := 1.0
const T_REVEAL := 3.6
const T_STAND := 0.6
const T_MIND := 1.5
const T_RELEASE := 1.1
## The cat's height above its feet, px (centres the close-up on what shows).
const CAT_HEIGHT := 30.0
## Struggle: [animation, speed, lift px] beats, each STRUGGLE_BEAT s long.
const STRUGGLE := [["walk", 2.2, 0.0], ["jump", 1.0, -2.0], ["walk", 2.2, 0.0], ["meow", 1.4, 0.0], ["jump", 1.0, -1.0], ["walk", 2.0, 0.0]]
const STRUGGLE_BEAT := 0.42

## Leave empty to use the nearest GooPool under the cat.
@export var pool: GooPool
## MAGNIFIER: CineZoom, smooth and crisp at any zoom (the default).
## CAMERA: the Camera2D's own zoom at the internal resolution; fractional
## steps there give uneven pixels that shimmer. Kept for comparison.
@export var zoom_mode := ZoomMode.MAGNIFIER
## The dolly-in while the cat is caught: it ends centred and close enough
## to watch the goo creep.
@export_range(1.0, 5.0, 0.05) var zoom_caught := 2.4
## Close-up magnification once the veins have reached the eyes (the slow
## creep from zoom_caught gets there).
@export_range(1.0, 6.0, 0.05) var zoom_max := 4.0
## The extra push-in for the awakened mind.
@export_range(1.0, 6.0, 0.05) var zoom_mind := 4.6
## Where the view centres on the cat, relative to its origin (feet), px.
@export var focus_offset := Vector2(0, -16)
@export var letterbox := true
## Low hum under the veins (a loop, played pitched down).
@export var hum_stream: AudioStream = preload("res://assets/audio/sfx/goo_bubble.ogg")
@export var hum_pitch := 0.8
@export_range(-60.0, 0.0, 0.5) var hum_volume_db := -11.0
## The feet sink until they are this deep in the goo (never below the
## pool's bottom), px. A cat already wading deeper does not sink at all.
@export var sink_to_px := 8.0
## Most the sprite may sink, px.
@export var sink_px := 4.0

var cat: Cat
var phase: StringName = &""
var running := false

var _sprite: AnimatedSprite2D
var _nano: CatNanotech
var _aug: CatAugments
var _hd: NanoHD
var _cine: CineZoom
var _cam: Camera2D
var _cam_saved := {}
var _shakers: Array[Node] = []
var _hud: Array[CanvasItem] = []
var _vein_light: PointLight2D
var _pool_z := 0
var _sprite_pos := Vector2.ZERO
var _struggle := 0.0
var _struggling := false
var _beat := -1
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

	# (a) Caught: the cat fights; its feet sink; the goo takes hold.
	_enter(GOO_RISES)
	goo_rising.emit()
	var cin := create_tween().set_parallel(true)  # letterbox, vignette
	var t_creep := T_RISE + T_VEINS + T_EYES
	var zt: Object = _cam if zoom_mode == ZoomMode.CAMERA and _cam else _cine
	var z0: Vector2 = _cam.zoom if zt == _cam else Vector2.ONE
	var zoom_in := create_tween()
	if zt == _cam:
		zoom_in.tween_property(_cam, "zoom", z0 * zoom_caught, T_STUCK).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		zoom_in.tween_property(_cam, "zoom", z0 * zoom_max, t_creep).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		zoom_in.tween_property(_cine, "zoom", zoom_caught, T_STUCK).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		zoom_in.tween_property(_cine, "zoom", zoom_max, t_creep).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if letterbox:
		cin.tween_property(_cine, "bars", 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	cin.tween_property(_cine, "vignette", 0.22, 2.5)  # a light frame; the close-up must read
	_struggling = true
	_struggle = 1.0
	if pool:
		pool.grip(cat.global_position.x, 1.0, cat.z_index)
	create_tween().tween_property(self, "_sink", _sink_amount(), T_STUCK + T_RISE * 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	create_tween().tween_property(_nano, "goo_level", 0.1, T_STUCK).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _wait(T_STUCK)

	# (b) The goo creeps up the cat while it fights, weaker and weaker.
	create_tween().tween_property(_nano, "goo_level", 1.0, T_RISE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	create_tween().tween_property(self, "_struggle", 0.0, T_RISE * 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _wait(T_RISE * 0.5)
	if pool:
		pool.grip(cat.global_position.x, 0.3, cat.z_index)  # tendrils sink into the coat
	await _wait(T_RISE * 0.3)
	_struggling = false
	_set_anim("idle", 1.0, true)
	await _wait(T_RISE * 0.2)
	_hd.front = -1.0

	# (c) Veins crawl up to the eyes; the eyes ignite and hold; a hum swells.
	_enter(VEINS_REACH_EYES)
	veins.emit()
	_nano.vein_energy = 0.45  # the pixel traces sit in the goo under the HD glow
	create_tween().tween_method(_set_veins, 0.0, 1.0, T_VEINS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	create_tween().tween_property(_vein_light, "energy", 0.75, T_VEINS)
	var hum := _start_hum()
	await _wait(T_VEINS + T_EYES)

	# (d) The energy pulse, then the goo soaks in.
	_enter(ABSORB)
	var pulse := create_tween().set_parallel(true)
	pulse.tween_property(_nano, "flash", 2.2, 0.06)
	pulse.tween_property(_hd, "flash", 1.6, 0.06)
	pulse.chain().tween_property(_nano, "flash", 0.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	pulse.parallel().tween_property(_hd, "flash", 0.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_hd.pulse(1.0)
	_cine.shake(0.75, 0.5)
	if zoom_mode == ZoomMode.MAGNIFIER:
		var punch := create_tween()
		punch.tween_property(_cine, "zoom", zoom_max * 1.06, 0.07)
		punch.tween_property(_cine, "zoom", zoom_max, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_burst_light()
	if pool:
		pool.surge(1.0)
		pool.release()
	if hum:
		var hf := create_tween()
		hf.tween_property(hum, "volume_db", -60.0, 0.35)
		hf.tween_callback(hum.queue_free)
	Sfx.play(self, "absorb_pulse")
	await _wait(T_PULSE)
	var ab := create_tween().set_parallel(true)
	ab.tween_property(_nano, "absorb", 1.0, T_ABSORB).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ab.tween_property(_hd, "vein_fade", 0.0, T_ABSORB * 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	ab.tween_property(_hd, "eye", 0.0, T_ABSORB * 0.6)
	ab.tween_property(_vein_light, "energy", 0.0, T_ABSORB * 0.7)
	ab.tween_property(self, "_sink", 0.0, T_ABSORB * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _wait(T_ABSORB * 0.8)
	var last := create_tween().set_parallel(true)  # one last faint flicker
	last.tween_property(_nano, "flash", 0.6, 0.07)
	last.tween_property(_hd, "vein_fade", 0.35, 0.07)
	last.chain().tween_property(_nano, "flash", 0.0, 0.25)
	last.parallel().tween_property(_hd, "vein_fade", 0.0, 0.25)
	await _wait(T_ABSORB * 0.2)
	absorbed.emit()

	# (e) A beat of stillness: just the tabby again.
	_enter(LOOKS_NORMAL)
	_nano.clear()
	_nano.vein_energy = 1.15
	_hd.vein_progress = 0.0
	_set_anim("idle")
	await _wait(T_STILL)

	# (f) The augments arrive one by one, then the cat stands with them.
	_enter(AUGMENTS_APPEAR)
	_aug.piece_revealed.connect(_on_piece)
	_aug.reveal(T_REVEAL)
	await _wait(T_REVEAL + T_STAND)
	_aug.piece_revealed.disconnect(_on_piece)
	Sfx.play(self, "augment_reveal")
	augments_revealed.emit()

	# The awakened mind: a soft glow at the head, a glint in the eye.
	var mz := create_tween().set_parallel(true)
	if zoom_mode == ZoomMode.MAGNIFIER:
		mz.tween_property(_cine, "zoom", zoom_mind, T_MIND).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	mz.tween_property(_hd, "mind", 1.0, T_MIND * 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	mz.chain().tween_property(_hd, "mind", 0.3, T_MIND * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	Sfx.play(self, "checkpoint", -10.0, 0.8)
	await _wait(T_MIND * 0.3)
	_hd.mind_pulse()
	await _wait(T_MIND * 0.7)
	mind_awakened.emit()

	# (g) Ease back out to gameplay, hand the cat back, then `finished`.
	await _release()
	running = false
	finished.emit()
	queue_free()


func _enter(p: StringName) -> void:
	phase = p
	phase_started.emit(p)


func _set_veins(v: float) -> void:
	_nano.vein_progress = v
	_hd.vein_progress = v
	_hd.eye = smoothstep(0.86, 1.0, v)


func _on_piece(_kind: String, local: Vector2) -> void:
	_hd.pop(local, _aug.idle_color.lerp(Color.WHITE, 0.3))
	Sfx.play(self, "augment_click")


func _process(delta: float) -> void:
	if not running or _sprite == null:
		return
	_t += delta
	var lift := 0.0
	if _struggling:
		lift = _struggle_beat()
	var jx := roundf(sin(_t * 41.0) * 1.5 * _struggle)
	_sprite.position = _sprite_pos + Vector2(jx, roundf(_sink + lift))
	_hold_pose(delta)
	if _hd and _nano.goo_level > 0.0 and _nano.vein_progress <= 0.0:
		_hd.front = _nano.goo_level


## Steps through the struggle beats while it lasts; returns the strain lift.
func _struggle_beat() -> float:
	var b := int(_t / STRUGGLE_BEAT)
	var beat: Array = STRUGGLE[b % STRUGGLE.size()]
	if b != _beat:
		_beat = b
		_set_anim(beat[0], float(beat[1]) * lerpf(0.4, 1.0, _struggle), beat[0] == "jump")
		if beat[0] == "walk" and _struggle > 0.5 and b % 4 == 0:
			_sprite.flip_h = not _sprite.flip_h  # tries the other way
	var u := fmod(_t, STRUGGLE_BEAT) / STRUGGLE_BEAT
	return float(beat[2]) * _struggle * sin(u * PI)


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
	_beat = -1
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
	_cine.target_offset = _visible_focus()
	_hd = NanoHD.new()
	_hd.name = "NanoHD"
	_hd.cine = _cine
	_hd.sprite = _sprite
	if pool and pool.z_index > cat.z_index:
		_hd.clip_world_y = pool.global_position.y - 1.0
	add_child(_hd)
	_vein_light = PointLight2D.new()
	_vein_light.texture = preload("res://assets/fx/light_soft.png")
	_vein_light.color = FXPalette.NANO_BLUE.lerp(FXPalette.NANO_GREEN, 0.4)
	_vein_light.energy = 0.0
	_vein_light.texture_scale = 0.55  # the glow stays on and around the cat
	_vein_light.position = _visible_focus()
	cat.add_child(_vein_light)
	_take_camera()
	_fade_hud(true)


## How far to sink: down to sink_to_px under the surface, not past the
## pool's bottom, at most sink_px.
func _sink_amount() -> float:
	if pool == null:
		return sink_px
	var feet := cat.global_position.y
	var surface := pool.global_position.y
	var room := surface + pool.depth - 1.0 - feet
	return clampf(minf(sink_to_px - (feet - surface), room), 0.0, sink_px)


## focus_offset, moved up to the middle of what shows above the goo when
## the cat stands deep in it.
func _visible_focus() -> Vector2:
	if pool == null:
		return focus_offset
	var feet := cat.global_position.y
	var shown := minf(feet, pool.global_position.y + 2.0)
	var mid := (feet - CAT_HEIGHT + shown) * 0.5 - feet
	return Vector2(focus_offset.x, minf(focus_offset.y, mid))


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
	# Pan only as far as the close-up needs: the magnified view at its
	# closest must fit inside the game frame with the cat at its centre.
	# Usually that is nothing at all, and the room never slides.
	var vp := get_viewport().get_visible_rect().size
	var half := vp * 0.5 / maxf(zoom_max, zoom_mind)
	var at := cat.get_global_transform_with_canvas() * _cine.target_offset
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
	p.stream = hum_stream.duplicate()
	p.stream.set("loop", true)
	p.bus = &"SFX"
	p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	Sfx.play(self, "vein_rise")
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
	tw.tween_property(_hd, "mind", 0.0, T_RELEASE * 0.8)
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
	if is_instance_valid(_vein_light):
		_vein_light.queue_free()
	if pool:
		pool.z_index = _pool_z
	_struggle = 0.0
	_struggling = false
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
