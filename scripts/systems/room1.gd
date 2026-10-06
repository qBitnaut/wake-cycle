class_name Room1
extends Level
## Warehouse Room 1, the opening level. Plain movement only (run, jump, double
## jump, crouch, stomping bots): no pads, no shockwave, no dash, no ground
## pound. The goo's gift at the end is intelligence, not a power.
##
## Beats: INTRO (asleep in the nook, fade from black, the title, the stretch)
## -> PLAY (the platforming challenge) -> TRANSFORM (the cat steps into the
## dark pool and cannot get out; TransformSequence.play owns it) -> FREE
## (the mind awakened, the pool inert, the wrecked nanofluid crate to read, walk out
## through the loading door).
##
## Hooks for the transformation effect: `nanotech_absorbed_started` (also on
## GameState), TransformSequence.play(cat) and its `finished`, then
## GameState.awaken_mind() (intelligence; no power).
##
## Web debug hooks for tools/audit/web_room1.mjs: window.__wake is published
## every physics frame; window.wakeTeleport(x, y) moves the cat; ?start=room2 /
## room3 / room4 / home (and test, the test room; map, the world map) jumps straight to that room (see
## _web_start_override).

signal nanotech_absorbed_started
signal transform_finished
signal intro_finished

enum Beat { INTRO, PLAY, STRUGGLE, TRANSFORM, FREE }

## The intro plays once per run (a respawn or a Continue skips it).
static var intro_done := false

## The cat is caught once it is this far in, and standing on the pool floor.
@export var pool_trigger_x := 4480.0
const POOL_FRAMING_DROP := 64

var beat := Beat.PLAY
var power_violations := 0
var pool: GooPool

var _hud: CanvasLayer
var _title: TitleOverlay
var _t := 0.0
var _sleep_anim := ""
var _sprite_home := Vector2.ZERO
var _inert := false
var _intro_t := 0.0
var _js_callbacks: Array = []
var _zones: Array = []


func _ready() -> void:
	super()
	_hud = get_node_or_null("Hud") as CanvasLayer
	pool = get_node_or_null("GooPool") as GooPool
	_sprite_home = cat.sprite.position
	for z in find_children("*", "PuddleZone", true, false):
		_zones.append(z)
	# Roof leaks ring the puddle they fall into.
	for d in find_children("*", "DripFX", true, false):
		if d.has_meta("puddle_path"):
			var z := d.get_node_or_null(d.get_meta("puddle_path")) as PuddleZone
			if z:
				(d as DripFX).puddle = z.puddle
	GameState.power_changed.connect(func(p: int, _d: float):
		if p != NanoPalette.Power.NONE and beat != Beat.FREE:
			power_violations += 1)
	GameState.shockwave_unlock_changed.connect(func(on: bool):
		if on:
			power_violations += 1)
	# Audit tools pass `-- --skip-intro` to start awake.
	if OS.get_cmdline_user_args().has("--skip-intro"):
		intro_done = true
	if GameState.intelligence:
		# A revisit (back from the world map, or a respawn after the pool): the
		# mind is already awake, so no intro, no second transformation and no
		# new_game() (it would wipe the run and the map progress).
		intro_done = true
		_start_awake()
	elif _checkpoint_id == "" and not intro_done:
		# A fresh game: nothing unlocked, nothing carried over.
		GameState.new_game()
		Monologue.reset()
		SaveSystem.session_snapshot = GameState.snapshot()
		_start_intro()
	if OS.has_feature("web"):
		_setup_web()
		_web_start_override()


# ---- revisit ----------------------------------------------------------------

var _revisit := false


## Awake from the first frame: the FREE beat, the pool already inert (drained,
## dark) and the pool trigger off (_physics_process only springs it in PLAY).
func _start_awake() -> void:
	_revisit = true
	beat = Beat.FREE
	_inert = true
	if pool:
		pool.depth = 28.0
		pool.position.y += 8.0
	if _hud:
		_hud.visible = true


# ---- intro ----------------------------------------------------------------

func _start_intro() -> void:
	intro_done = true
	beat = Beat.INTRO
	cat.set_can_move(false)
	_set_sleep("sleep1")
	if _hud:
		_hud.visible = false
	# The camera drifts in from the room towards the sleeping cat.
	# (The camera limit applies before the offset, so the pan is just the offset easing to 0.)
	if camera_rig != null and camera_rig.managed:
		# The tall room's driver owns the camera offset: the drift is its look_offset.
		camera_rig.look_offset = Vector2(150, 0)
		create_tween().tween_property(camera_rig, "look_offset", Vector2.ZERO, 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		cat.camera.offset = Vector2(150, -25)
		create_tween().tween_property(cat.camera, "offset", Vector2(0, -25), 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_title = (load("res://scenes/fx/title_overlay.tscn") as PackedScene).instantiate()
	add_child(_title)
	_title.finished.connect(_wake)


func _set_sleep(anim: String) -> void:
	if anim != _sleep_anim:
		_sleep_anim = anim
		cat.set_forced_anim(anim)


## The wake-up: the stretch plays, then control is granted.
func _wake() -> void:
	if beat != Beat.INTRO:
		return
	beat = Beat.PLAY  # blocks a second call; the cat is still locked for the stretch
	cat.set_forced_anim("stretch")
	await get_tree().create_timer(1.3).timeout
	cat.set_forced_anim("")
	cat.set_can_move(true)
	if _hud:
		_hud.visible = true
	intro_finished.emit()


# ---- the pool -------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if beat == Beat.INTRO:
		_intro_t += delta
		_set_sleep("sleep1" if int(_t / 1.2) % 2 == 0 else "sleep2")
		var pressed := Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("move_right")
		if _intro_t > 3.2 and pressed and _title:
			_title.skip()


func _physics_process(delta: float) -> void:
	super(delta)
	_ease_pool_framing()
	if beat == Beat.PLAY and not cat.dead and cat.is_on_floor() and cat.global_position.x >= pool_trigger_x \
			and (pool == null or absf(cat.global_position.y - pool.global_position.y) < 64.0):  # the tall room has other floors above it
		_start_absorb()
	if OS.has_feature("web"):
		_publish()


## Walking up to the pool the camera floor eases down by 64 px (the underfloor
## tiles), lifting the cat from the very bottom of the frame towards its middle.
## The close-up that follows must pan its focus to the cat; starting nearer the
## middle makes that pan about half as long, instead of one hard drop.
func _ease_pool_framing() -> void:
	if camera_tiers() or (beat != Beat.PLAY and not _revisit) or cat.dead:
		return  # the tall room's camera driver frames the basement floor itself
	var k := smoothstep(pool_trigger_x - 420.0, pool_trigger_x - 60.0, cat.global_position.x)
	var want := limits.end.y + int(roundf(POOL_FRAMING_DROP * k))
	cat.camera.limit_bottom = want


func _start_absorb() -> void:
	beat = Beat.TRANSFORM
	cat.set_can_move(false)
	cat.velocity.x = 0.0
	GameState.nanotech_absorbed_started.emit()
	nanotech_absorbed_started.emit()
	# The sequence owns the cat from here: its own caught beat, the creep, the
	# veins, the augments and the awakened mind.
	_seq = TransformSequence.play(cat, pool)
	_seq.mind_awakened.connect(_on_mind_awakened)
	_seq.finished.connect(_end_transform)


var _seq: TransformSequence


## The goo's gift: intelligence, no powers. The cat's thoughts come up as subtitles
## (they keep playing after control returns; see data/monologue.json "awakening").
func _on_mind_awakened() -> void:
	GameState.awaken_mind()
	Monologue.play("awakening")


func _end_transform() -> void:
	beat = Beat.FREE
	cat.sprite.position = _sprite_home
	cat.set_forced_anim("")
	cat.set_can_move(true)
	_go_inert()
	transform_finished.emit()


## The pool drains away and stops glowing.
func _go_inert() -> void:
	_inert = true
	if pool == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(pool, "depth", 28.0, 3.0)
	tw.tween_property(pool, "position:y", pool.position.y + 8.0, 3.0)


# ---- web debug --------------------------------------------------------------

func _setup_web() -> void:
	var win := JavaScriptBridge.get_interface("window")
	var cb := JavaScriptBridge.create_callback(func(a):
		cat.global_position = Vector2(float(a[0]), float(a[1]))
		cat.velocity = Vector2.ZERO)
	_js_callbacks.append(cb)
	win["wakeTeleport"] = cb


## Web audit deep links: index.html?start=room2 / room3 / room4 / home skips ahead
## (and ?start=kit, the actor kit lab, in debug builds only)
## and arrives the way the previous room's exit would leave the cat (mind awake, no
## powers, auto-save); room4 and home also have the shockwave, which the Room 3
## conduit grants.
const WEB_STARTS := {
	"room2": "res://scenes/levels/room2.tscn",
	"room3": "res://scenes/levels/room3.tscn",
	"room4": "res://scenes/levels/room4.tscn",
	"home": "res://scenes/levels/home.tscn",
	"test": "res://scenes/levels/test_room.tscn",  # tools/audit/web_playthrough.mjs: a bare game, no mind
}


## The deep link applies to the page load only: a later Room 1 (the return
## after the credits) is the real start.
static var _web_start_used := false


func _web_start_override() -> void:
	if _web_start_used:
		return
	_web_start_used = true
	var start := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('start') || ''"))
	if start == "map":
		# ?start=map&completed=<id>[&letters=n]: the world map as an exit opens it.
		WorldMap.web_deep_link()
		return
	if start == "kit" and OS.is_debug_build():
		# ?start=kit: the actor kit test gallery (debug builds only).
		intro_done = true
		GameState.new_game()
		GameState.awaken_mind()
		Monologue.reset()
		SaveSystem.session_scene = ""
		SaveSystem.session_checkpoint = ""
		get_tree().change_scene_to_file.call_deferred("res://scenes/lab/kit_lab.tscn")
		return
	if not WEB_STARTS.has(start):
		return
	intro_done = true
	GameState.new_game()
	if start != "test":
		GameState.awaken_mind()
	if start == "room4" or start == "home":
		GameState.unlock_shockwave()
	Monologue.reset()
	SaveSystem.session_scene = ""
	SaveSystem.session_checkpoint = ""
	RoomTransition.arriving = start != "test"
	get_tree().change_scene_to_file.call_deferred(WEB_STARTS[start])


func _flag(node_name: String, prop: String) -> Variant:
	var n := get_node_or_null(node_name)
	return n.get(prop) if n else null


func _rect_arr(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


## Named actors the route audits wait on: name -> [x, y, phase/mode, dangerous, open].
const WATCH := ["Drone1", "Camera1", "ShutterMezz", "FreightLift", "FallA", "RideA", "RideB", "SpikesG", "Electric1", "Electric2",
	"Crusher1", "SpikesMachine", "PlateOffice", "ShutterOffice", "Steam1", "Steam2", "Steam3", "BotDeck", "BotMezz", "BotMachine"]


func _watch() -> Dictionary:
	var out := {}
	for n in WATCH:
		var a := get_node_or_null(n)
		if a == null:
			continue
		var e := [a.global_position.x, a.global_position.y, 0, false, true]
		if a.has_method("is_dangerous"):
			e[3] = a.is_dangerous()
		if a.has_method("is_warning"):
			e[3] = e[3] or a.is_warning()
		var ph = a.get("phase")
		if ph == null:
			ph = a.get("state")
		if ph == null:
			ph = a.get("mode")
		e[2] = ph if ph is int else (str(ph) if ph != null else 0)
		var op = a.get("open")
		if op == null:
			op = a.get("active")
		if op != null:
			e[4] = op
		out[n] = e
	return out


func _publish() -> void:
	var ripples := 0
	for z in _zones:
		ripples = maxi(ripples, z.puddle._ripples.size())
	var d := {
		"f": Engine.get_physics_frames(),
		"x": cat.global_position.x, "y": cat.global_position.y,
		"vx": cat.velocity.x, "vy": cat.velocity.y, "floor": cat.is_on_floor(),
		"hp": GameState.health, "score": GameState.score, "keys": GameState.keys,
		"letters": GameState.letters, "power": GameState.power,
		"shock": GameState.shockwave_unlocked, "mind": GameState.intelligence, "dead": cat.dead,
		"crouch": cat.crouched, "save": SaveSystem.has_save(),
		"cp": SaveSystem.session_checkpoint, "scene": get_tree().current_scene.scene_file_path,
		"can_move": cat.can_move, "beat": int(beat), "violations": power_violations,
		"anim": cat.sprite.animation, "hud": _hud.visible if _hud else false,
		"title": _title != null and is_instance_valid(_title) and _title.visible,
		"ripples": ripples, "inert": _inert, "pool_y": pool.position.y if pool else 0.0,
		"sw": cat.anim_switches, "mono": Monologue.history.size(),
		"monoLast": Monologue.history.back() if Monologue.history.size() else null,
		"monoIds": Monologue.history.map(func(l): return l[0]),
		"container": Monologue.has_played("nanofluid_container"), "hint": Monologue.has_played("exit_hint"),
		"cam": [cat.camera.get_screen_center_position().x, cat.camera.get_screen_center_position().y],
		"cz": CineZoom.current().zoom if CineZoom.current() else 1.0, "cineActive": CineZoom.current() != null,
		"overlaid": CineZoom.current() != null and CineZoom.current().is_overlaid(Monologue),
		"speaking": Monologue.is_speaking(), "pushT": cat._push_t,
		"win": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"subWin": _rect_arr(Monologue.plate_window_rect()), "catWin": _rect_arr(Monologue.cat_window_rect()),
		"subRect": _rect_arr(Monologue.plate_rect()), "catRect": _rect_arr(Monologue.cat_screen_rect()),
		"subAlpha": Monologue._root.modulate.a if Monologue._root else 0.0,
		"glintA": fposmod(_flag("LetterA", "_t") if get_node_or_null("LetterA") else -1.0, 2.6),
		"glintC": fposmod(_flag("LetterC", "_t") if get_node_or_null("LetterC") else -1.0, 2.6),
		"glintT": fposmod(_flag("LetterT", "_t") if get_node_or_null("LetterT") else -1.0, 2.6),
		"door": get_node_or_null("DoorOffice") != null, "n": _watch(), "lmask": GameState.letter_mask,
		"got": GameState.collected.map(func(c): return String(c).get_file()),
	}
	d["loops"] = LoopSfx.census_cached(get_tree())
	d["audio"] = AudioDirector.web_state()
	JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))
