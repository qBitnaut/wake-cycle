class_name Room1
extends Level
## Warehouse Room 1, the opening level. Plain movement only (run, jump, double
## jump, crouch, stomping bots): no pads, no shockwave, no dash, no ground
## pound. The only power in the room is the goo gift at the end.
##
## Beats: INTRO (asleep in the nook, fade from black, the title, the stretch)
## -> PLAY (the platforming challenge) -> STRUGGLE (the cat steps into the
## dark pool and cannot get out) -> TRANSFORM (TransformSequence.play) -> FREE
## (shockwave unlocked, the pool inert, walk out through the loading door).
##
## Hooks for the transformation effect: `nanotech_absorbed_started` (also on
## GameState), TransformSequence.play(cat) and its `finished`, then
## GameState.unlock_shockwave().
##
## Web debug hooks for tools/audit/web_room1.mjs: window.__wake is published
## every physics frame; window.wakeTeleport(x, y) moves the cat.

signal nanotech_absorbed_started
signal transform_finished
signal intro_finished

enum Beat { INTRO, PLAY, STRUGGLE, TRANSFORM, FREE }

## The intro plays once per run (a respawn or a Continue skips it).
static var intro_done := false

## The cat is caught once it is this far in, and standing on the pool floor.
@export var pool_trigger_x := 4480.0
@export var struggle_time := 1.6

var beat := Beat.PLAY
var power_violations := 0
var pool: GooPool

var _hud: CanvasLayer
var _title: TitleOverlay
var _t := 0.0
var _sleep_anim := ""
var _struggle_t := 0.0
var _sprite_home := Vector2.ZERO
var _inert := false
var _intro_t := 0.0
var _js_callbacks: Array = []


func _ready() -> void:
	super()
	_hud = get_node_or_null("Hud") as CanvasLayer
	pool = get_node_or_null("GooPool") as GooPool
	_sprite_home = cat.sprite.position
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
		if on and beat != Beat.FREE and beat != Beat.TRANSFORM:
			power_violations += 1)
	# Audit tools pass `-- --skip-intro` to start awake.
	if OS.get_cmdline_user_args().has("--skip-intro"):
		intro_done = true
	if _checkpoint_id == "" and not intro_done:
		# A fresh game: nothing unlocked, nothing carried over.
		GameState.new_game()
		SaveSystem.session_snapshot = GameState.snapshot()
		_start_intro()
	if OS.has_feature("web"):
		_setup_web()


# ---- intro ----------------------------------------------------------------

func _start_intro() -> void:
	intro_done = true
	beat = Beat.INTRO
	cat.set_can_move(false)
	_set_sleep("sleep1")
	if _hud:
		_hud.visible = false
	# The camera drifts in from the room towards the sleeping cat.
	cat.camera.offset = Vector2(400, -25)
	var tw := create_tween()
	tw.tween_property(cat.camera, "offset", Vector2(176, -25), 6.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): cat.camera.offset = Vector2(0, -25))
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
	elif beat == Beat.STRUGGLE or beat == Beat.TRANSFORM:
		_squirm(delta)
	_pool_glow()


func _physics_process(delta: float) -> void:
	super(delta)
	if beat == Beat.PLAY and not cat.dead and cat.is_on_floor() and cat.global_position.x >= pool_trigger_x:
		_start_absorb()
	if OS.has_feature("web"):
		_publish()


## The pool reads as darker water from afar; the circuit glow only wakes up
## as the cat comes close.
func _pool_glow() -> void:
	if pool == null or _inert:
		return
	var d := maxf(pool.global_position.x - cat.global_position.x, 0.0)
	var near := 1.0 - clampf((d - 40.0) / 300.0, 0.0, 1.0)
	near *= near
	pool.trace_energy = lerpf(0.12, 1.2, near)
	pool.light_energy = lerpf(0.12, 1.6, near)


func _start_absorb() -> void:
	beat = Beat.STRUGGLE
	cat.set_can_move(false)
	cat.velocity.x = 0.0
	GameState.nanotech_absorbed_started.emit()
	nanotech_absorbed_started.emit()
	if pool:
		pool.surge(1.0)
	_struggle_t = 0.0
	await get_tree().create_timer(struggle_time).timeout
	_begin_transform()


## Feet stuck: the cat strains (jump frame), meows and shakes in place.
func _squirm(delta: float) -> void:
	_struggle_t += delta
	var calm := beat == Beat.TRANSFORM and _transform_phase_calm()
	var amp := 0.0 if calm else (1.5 if beat == Beat.STRUGGLE else 1.0)
	cat.sprite.position = _sprite_home + Vector2(roundf(sin(_struggle_t * 41.0) * amp), roundf(sin(_struggle_t * 27.0) * amp * 0.7))
	if calm:
		cat.set_forced_anim("sit")
		return
	var seq := ["meow", "idle", "jump", "idle"]
	cat.set_forced_anim(seq[int(_struggle_t / 0.45) % seq.size()])
	if pool and int(_struggle_t * 6.0) != int((_struggle_t - delta) * 6.0):
		pool.surge(0.35)


var _seq: TransformSequence


func _transform_phase_calm() -> bool:
	return _seq != null and (_seq.phase == TransformSequence.LOOKS_NORMAL or _seq.phase == TransformSequence.AUGMENTS_APPEAR)


func _begin_transform() -> void:
	beat = Beat.TRANSFORM
	_seq = TransformSequence.play(cat)
	_seq.finished.connect(_end_transform)


func _end_transform() -> void:
	GameState.unlock_shockwave()  # the goo's gift
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
	pool.bubbles = false
	pool._bubbles.emitting = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(pool, "depth", 3.0, 3.0)
	tw.tween_property(pool, "position:y", pool.position.y + 11.0, 3.0)
	tw.tween_property(pool, "trace_energy", 0.0, 2.0)
	tw.tween_property(pool, "light_energy", 0.0, 2.0)


# ---- web debug --------------------------------------------------------------

func _setup_web() -> void:
	var win := JavaScriptBridge.get_interface("window")
	var cb := JavaScriptBridge.create_callback(func(a):
		cat.global_position = Vector2(float(a[0]), float(a[1]))
		cat.velocity = Vector2.ZERO)
	_js_callbacks.append(cb)
	win["wakeTeleport"] = cb


func _flag(node_name: String, prop: String) -> Variant:
	var n := get_node_or_null(node_name)
	return n.get(prop) if n else null


func _publish() -> void:
	var bot := get_node_or_null("Bot") as PatrolBot
	var crate := get_node_or_null("PushCrate")
	var steam := []
	for n in ["Steam1", "Steam2", "Steam3"]:
		var s := get_node_or_null(n) as SteamHazard
		steam.append(s.is_dangerous() if s else false)
	var d := {
		"f": Engine.get_physics_frames(),
		"x": cat.global_position.x, "y": cat.global_position.y,
		"vx": cat.velocity.x, "vy": cat.velocity.y, "floor": cat.is_on_floor(),
		"hp": GameState.health, "score": GameState.score, "keys": GameState.keys,
		"letters": GameState.letters, "power": GameState.power,
		"shock": GameState.shockwave_unlocked, "dead": cat.dead,
		"crouch": cat.crouched, "save": SaveSystem.has_save(),
		"cp": SaveSystem.session_checkpoint, "scene": get_tree().current_scene.scene_file_path,
		"can_move": cat.can_move, "beat": int(beat), "violations": power_violations,
		"bot": [bot.global_position.x, bot.global_position.y, bot.stomps, int(bot.state)] if bot else null,
		"crate": [crate.global_position.x, crate.global_position.y] if crate else null,
		"plate": _flag("PlateA", "active"), "shutter": _flag("Shutter", "open"),
		"fenceT": _flag("FenceTimed", "active"), "steam": steam,
		"door": get_node_or_null("DoorBrass") != null,
	}
	JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))
