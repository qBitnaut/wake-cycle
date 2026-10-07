class_name Home
extends Level
## Home, the ending: the morning after the storm. A short, gentle walk with no
## challenge, from the end of the road through a sunny, rain-washed street to
## the cat's own house, in through the cat flap, and to its spot in the
## sunbeam, where it curls up and sleeps. The game opened with the cat waking
## curled up in the dark; it closes with it falling asleep in the light.
##
## Beats: STREET (walk, home_arrival) -> FLAP (home_flap on the steps; the
## cat pushes through the flap and the facade dissolves like a dollhouse
## front) -> INSIDE (walk to the sunbeam) -> SETTLE (input locks: the cat
## circles, sits, lies down, sleeps; the augments dim to a slow breathing
## glow; a slow CineZoom ease-in) -> ASLEEP (home_final) -> OUTRO (fade to
## warm white, then the credits scene: title card, credits, return to Room 1).
##
## Walking into things is the whole interface: the flap and the spot are
## Area2D triggers. Scene built by tools/build_home.gd.
##
## Web debug hooks (tools/audit/web_home.mjs): window.__wake every physics
## frame, window.wakeTeleport(x, y).

signal entered_house
signal settled
signal outro_started

enum Beat { STREET, FLAP, INSIDE, SETTLE, ASLEEP, OUTRO }

const CREDITS := "res://scenes/ui/credits.tscn"
const FLAP_SOUND := "wing_flap"
## The cat strolls here: the walk animation, not the run.
const WALK_SPEED := 104.0
## Warm white of the final fade (sunlight, not a hospital).
const WARM_WHITE := Color(1.0, 0.96, 0.86)
## The interior's light-mask bit: the sun does not reach in; the window does.
const MASK_INTERIOR := 8

## The middle of the cushion (world x) and how far up its top sits.
@export var spot_x := 3500.0
@export var spot_rise := 3.0
## Framed on the cat (1.5x its 1x art): close enough that it reads as it did,
## loose enough that the window stays in the shot.
@export var final_zoom := 2.9
@export var zoom_time := 12.0
## How long the arrival fades up from black (out of the dark, into the sun).
@export var arrival_fade := 2.4

var beat := Beat.STREET
var music: AudioStreamPlayer
var cine: CineZoom
var facade_amount := 1.0
var settle_step := ""        ## audit hook: the step of the settle sequence

var _facade_mat: ShaderMaterial
var _base: Sprite2D
var _flap: Sprite2D
var _flap_x := 0.0
var _aug: CatAugments
var _breathe := 0.0
var _sleeping := false
var _sprite_home := Vector2.ZERO
var _fade: CanvasLayer
var _fade_rect: ColorRect
var _js_callbacks: Array = []


func _ready() -> void:
	# Out of the night: a slower fade up than a room change, and the save is ours.
	var arriving := RoomTransition.arriving
	RoomTransition.arriving = false
	super()
	if arriving:
		SaveSystem.save_checkpoint("", scene_file_path)
		RoomTransition.fade_in(self, arrival_fade)
	if not GameState.intelligence:
		# Started here directly (tests, ?start=home): the cat as the game leaves it.
		GameState.awaken_mind()
		GameState.unlock_shockwave()
	_aug = CatAugments.attach(cat, true)
	cat.run_speed = WALK_SPEED
	_sprite_home = cat.sprite.position
	var facade := get_node_or_null("Facade") as Node2D
	if facade:
		for s in facade.find_children("*", "Sprite2D", true, false):
			if (s as Sprite2D).material is ShaderMaterial:
				_facade_mat = (s as Sprite2D).material
				break
	_flap = get_node_or_null("Facade/Flap") as Sprite2D
	# The dark base under the floor that hides the street once the wall has gone.
	_base = get_node_or_null("Base") as Sprite2D
	# The cushion's front rim draws over the cat: hidden while the wall stands.
	var rim := get_node_or_null("CushionFront") as CanvasItem
	if rim:
		rim.visible = false
	var ft := get_node_or_null("FlapTrigger") as Area2D
	if ft:
		_flap_x = ft.global_position.x
		ft.body_entered.connect(func(b: Node):
			if b is Cat and beat == Beat.STREET:
				_enter_house())
	var st := get_node_or_null("SpotTrigger") as Area2D
	if st:
		st.body_entered.connect(func(b: Node):
			if b is Cat and beat == Beat.INSIDE:
				_settle())
	# Day puddles: they reach up to the sky and the houses, and ring when
	# drops land in them.
	var glints := get_node_or_null("Glints") as WetGlints
	for z in find_children("*", "PuddleZone", true, false):
		var pu := (z as PuddleZone).puddle
		pu.water_tint = Color(0.50, 0.68, 0.90)
		pu.reflectivity = 0.82
		pu.reflect_scale = 4.0
		pu.highlight = Color(1.0, 0.95, 0.82)
		if glints:
			glints.puddles.append(pu)
	# The window's beam lights the room and its dust, never the facade outside.
	var beam_light := get_node_or_null("Sunbeam/Light") as Light2D
	if beam_light:
		beam_light.range_item_cull_mask = MASK_INTERIOR | LightingRig.MASK_MOTES
	if OS.has_feature("web") and OS.is_debug_build():
		_setup_web()


func _process(delta: float) -> void:
	if _sleeping:
		# Breathing: a slow 1 px rise and fall of the back, feet planted.
		_breathe += delta
		var s := 1.0 + 0.035 * (0.5 + 0.5 * sin(TAU * _breathe / 4.4))
		cat.sprite.scale = Vector2(1.0, s)
		cat.sprite.position.y = _sprite_home.y * s - spot_rise


func _physics_process(delta: float) -> void:
	super(delta)
	if OS.has_feature("web") and OS.is_debug_build():
		_publish()


# ---- the cat flap -------------------------------------------------------------

func _enter_house() -> void:
	beat = Beat.FLAP
	cat.set_can_move(false)
	cat.velocity.x = 0.0
	cat.facing = 1
	cat.sprite.flip_h = false
	cat.set_forced_anim("crawl")
	cat.sprite.speed_scale = 0.8
	var tw := create_tween()
	tw.tween_property(cat, "global_position:x", _flap_x + 8.0, 0.45)
	tw.parallel().tween_property(cat.sprite, "modulate:a", 0.0, 0.4).set_delay(0.12)
	get_tree().create_timer(0.14).timeout.connect(_swing_flap)
	await tw.finished
	# Through: the wall opens like a dollhouse front.
	_open_house()
	await get_tree().create_timer(0.75).timeout
	cat.global_position.x = _flap_x + 26.0
	cat.velocity = Vector2.ZERO
	_light_inside(cat.sprite)
	var tw2 := create_tween()
	tw2.tween_property(cat.sprite, "modulate:a", 1.0, 0.35)
	await tw2.finished
	cat.set_forced_anim("")
	cat.set_can_move(true)
	beat = Beat.INSIDE
	entered_house.emit()
	# Indoors the street goes quiet: the birds and drips through the walls.
	var amb := get_node_or_null("Ambience")
	if amb:
		for p in amb.get_children():
			if p is AudioStreamPlayer:
				create_tween().tween_property(p, "volume_db", (p as AudioStreamPlayer).volume_db - 9.0, 2.0)


func _swing_flap() -> void:
	Sfx.play(self, FLAP_SOUND)
	if _flap == null:
		return
	create_tween().tween_method(_flap_swing, 0.0, 2.4, 2.4)


## The flap swings in on its hinge and settles: seen face on, it foreshortens.
func _flap_swing(t: float) -> void:
	var a := 1.25 * exp(-1.7 * t) * cos(7.5 * t)
	_flap.scale.y = maxf(cos(a), 0.08)
	var d := 1.0 - 0.35 * absf(sin(a))
	_flap.modulate = Color(d, d, d)


func _open_house() -> void:
	if _facade_mat:
		var tw := create_tween()
		tw.tween_method(_set_facade, 1.0, 0.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_facade(v: float) -> void:
	facade_amount = v
	_facade_mat.set_shader_parameter("amount", v)
	var facade := get_node_or_null("Facade") as Node2D
	if facade:
		facade.visible = v > 0.0
	var rim := get_node_or_null("CushionFront") as CanvasItem
	if rim:
		rim.visible = v <= 0.0
	if _base:
		_base.modulate.a = smoothstep(1.0, 0.35, v)
		_base.visible = v < 1.0


## Inside, the cat is lit like the room (the window, not the sun).
func _light_inside(spr: CanvasItem) -> void:
	spr.light_mask = MASK_INTERIOR
	for c in spr.find_children("*", "CanvasItem", true, false):
		(c as CanvasItem).light_mask = MASK_INTERIOR


# ---- the spot -------------------------------------------------------------------

func _settle() -> void:
	beat = Beat.SETTLE
	cat.set_can_move(false)
	cat.velocity.x = 0.0
	_start_music()
	_start_zoom()
	# Onto the cushion: a few steps to its middle.
	settle_step = "step_in"
	cat.sprite.flip_h = spot_x < cat.global_position.x
	cat.facing = -1 if cat.sprite.flip_h else 1
	cat.set_forced_anim("walk")
	var d := absf(spot_x - cat.global_position.x)
	var tw := create_tween()
	tw.tween_property(cat, "global_position:x", spot_x, maxf(d / 70.0, 0.25))
	tw.parallel().tween_property(cat.sprite, "position:y", _sprite_home.y - spot_rise, 0.3)
	await tw.finished
	# Cats turn about before they lie down.
	settle_step = "circle"
	for k in 2:
		cat.sprite.flip_h = not cat.sprite.flip_h
		var dir := -1.0 if cat.sprite.flip_h else 1.0
		var t2 := create_tween()
		t2.tween_property(cat, "global_position:x", spot_x + dir * 4.0, 0.42)
		await t2.finished
	cat.sprite.flip_h = false
	create_tween().tween_property(cat, "global_position:x", spot_x, 0.2)
	# Turn to face the room, then down.
	settle_step = "sit"
	cat.set_forced_anim("sit")
	_aug.set_sleeping(true, 6.0)
	await get_tree().create_timer(1.7).timeout
	settle_step = "lie_down"
	cat.set_forced_anim("lie_down")
	await get_tree().create_timer(1.6).timeout
	settle_step = "sleep"
	cat.set_forced_anim("sleep1")
	_sleeping = true
	beat = Beat.ASLEEP
	settled.emit()
	await get_tree().create_timer(1.6).timeout
	Monologue.set_finished.connect(_on_line_set, CONNECT_ONE_SHOT)
	Monologue.play("home_final")


func _start_zoom() -> void:
	cine = CineZoom.new()
	cine.name = "CineZoom"
	add_child(cine)
	cine.target = cat
	# Frame the room above the cat (the window, the wall), not the street below,
	# with the sleeping cat low and left, clear of the subtitle.
	cine.target_offset = Vector2(14, -40)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(cine, "zoom", final_zoom, zoom_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cine, "bars", 0.45, zoom_time * 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(cine, "vignette", 0.25, zoom_time)


func _start_music() -> void:
	music = AudioDirector.play_music("home", 5.0)


func _on_line_set(id: String) -> void:
	if id != "home_final":
		Monologue.set_finished.connect(_on_line_set, CONNECT_ONE_SHOT)
		return
	_outro()


# ---- the outro --------------------------------------------------------------------

func _outro() -> void:
	beat = Beat.OUTRO
	outro_started.emit()
	await get_tree().create_timer(2.6).timeout
	_fade = CanvasLayer.new()
	_fade.name = "WarmFade"
	_fade.layer = 120
	_fade_rect = ColorRect.new()
	_fade_rect.color = WARM_WHITE
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.add_child(_fade_rect)
	add_child(_fade)
	if cine and cine.has_fx():
		cine.attach_overlay(_fade)   # over the whole window, letterbox and all
	var amb := get_node_or_null("Ambience")
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 1.0, 4.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if amb:
		for p in amb.get_children():
			if p is AudioStreamPlayer:
				tw.parallel().tween_property(p, "volume_db", -60.0, 4.5)
	await tw.finished
	# All white now: end the close-up cleanly (the overlay goes back to the
	# game frame, where the white still covers everything), then leave.
	if cine:
		cine.detach_overlay(_fade)
		cine.zoom = 1.0
		cine.bars = 0.0
	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file(CREDITS)


# ---- web debug ---------------------------------------------------------------------

func _setup_web() -> void:
	var win := JavaScriptBridge.get_interface("window")
	var cb := JavaScriptBridge.create_callback(func(a):
		cat.global_position = Vector2(float(a[0]), float(a[1]))
		cat.velocity = Vector2.ZERO)
	_js_callbacks.append(cb)
	win["wakeTeleport"] = cb


func _publish() -> void:
	var glints := get_node_or_null("Glints") as WetGlints
	var birds := get_node_or_null("Birds") as Birds
	var d := {
		"f": Engine.get_physics_frames(), "fps": Engine.get_frames_per_second(),
		"x": cat.global_position.x, "y": cat.global_position.y,
		"vx": cat.velocity.x, "floor": cat.is_on_floor(),
		"scene": scene_file_path, "beat": int(beat), "step": settle_step,
		"can_move": cat.can_move, "anim": cat.sprite.animation, "flip": cat.sprite.flip_h,
		"mind": GameState.intelligence, "shock": GameState.shockwave_unlocked, "power": GameState.power,
		"save": SaveSystem.has_save(), "facade": facade_amount,
		"aug": _aug.shown if _aug else false, "augE": _aug.emitter_energy() if _aug else 0.0,
		"asleep": _aug.is_sleeping() if _aug else false,
		"mono": Monologue.history.size(), "monoIds": Monologue.history.map(func(l): return l[0]),
		"monoLast": Monologue.history.back()[1] if Monologue.history.size() else "",
		"speaking": Monologue.is_speaking(),
		"cz": cine.zoom if cine else 1.0, "fade": _fade_rect.modulate.a if _fade_rect else 0.0,
		"glints": glints.glints_spawned if glints else 0, "drops": glints.drops_landed if glints else 0,
		"birdsFlown": birds.flown if birds else 0,
		"music": AudioDirector.music_db(),
		"cam": [cat.camera.get_screen_center_position().x, cat.camera.get_screen_center_position().y],
	}
	d["loops"] = LoopSfx.census_cached(get_tree())
	d["audio"] = AudioDirector.web_state()
	JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))
