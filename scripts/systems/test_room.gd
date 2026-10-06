extends Level
## Test room with debug hotkeys (not part of the input map):
## F1 toggle shockwave, F2-F5 grant Surge/Spring/Phase/Impact, F6 clear power.


## Web debug hooks, used by tools/audit/web_playthrough.mjs. Query string:
## index.html?x=3600&shock=1&power=3&keys=brass teleports the cat on load.
## At run time the page also gets window.wakeTeleport(x, y), wakePower(p),
## wakeShock(on) and wakeKey(color).
var _js_callbacks: Array = []


func _ready() -> void:
	super()
	if not OS.has_feature("web"):
		return
	var q := func(key: String) -> String:
		return str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('%s') || ''" % key))
	if q.call("x") != "":
		cat.global_position = Vector2(float(q.call("x")), 300.0)
	if q.call("shock") == "1":
		GameState.shockwave_unlocked = true
	if q.call("keys") != "":
		GameState.add_key(q.call("keys"))
	if q.call("power") != "":
		GameState.grant_power(int(q.call("power")), 10.0)
	var win := JavaScriptBridge.get_interface("window")
	_expose(win, "wakeTeleport", func(a): cat.global_position = Vector2(float(a[0]), float(a[1])); cat.velocity = Vector2.ZERO)
	_expose(win, "wakePower", func(a): GameState.grant_power(int(a[0]), 10.0))
	_expose(win, "wakeShock", func(a): GameState.shockwave_unlocked = bool(a[0]))
	_expose(win, "wakeKey", func(a): GameState.add_key(str(a[0])))


func _expose(win: JavaScriptObject, fn_name: String, fn: Callable) -> void:
	var cb := JavaScriptBridge.create_callback(fn)
	_js_callbacks.append(cb)  # keep a reference or the callback is freed
	win[fn_name] = cb


## Web builds publish state to window.__wake every physics frame, so Playwright
## can drive the run by physics frame (f) instead of wall-clock time.
func _physics_process(delta: float) -> void:
	super(delta)
	if not OS.has_feature("web"):
		return
	var bot := get_node_or_null("Bot")
	var crate := get_node_or_null("PushCrate")
	var d := {
		"f": Engine.get_physics_frames(),
		"x": cat.global_position.x, "y": cat.global_position.y,
		"vx": cat.velocity.x, "vy": cat.velocity.y, "floor": cat.is_on_floor(),
		"hp": GameState.health, "score": GameState.score, "keys": GameState.keys,
		"letters": GameState.letters, "power": GameState.power,
		"shock": GameState.shockwave_unlocked, "dead": cat.dead,
		"crouch": cat.crouched, "save": SaveSystem.has_save(),
		"cp": SaveSystem.session_checkpoint,
		"bot": [bot.global_position.x, bot.global_position.y, bot.stomps, int(bot.state)] if bot else null,
		"crate": [crate.global_position.x, crate.global_position.y] if crate else null,
		"plate": _flag("PlateA", "active"), "fenceA": _flag("FenceA", "active"),
		"fenceT": _flag("FenceTimed", "active"), "fenceB": _flag("FenceB", "active"),
		"fenceD": _flag("FenceDash", "active"), "switch": _flag("SwitchA", "active"),
		"door": get_node_or_null("DoorBrass") != null,
		"crates": get_tree().get_nodes_in_group("breakable").size(),
	}
	d["loops"] = LoopSfx.census_cached(get_tree())
	d["audio"] = AudioDirector.web_state()
	JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))


func _flag(node_name: String, prop: String) -> Variant:
	var n := get_node_or_null(node_name)
	return n.get(prop) if n else null


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_F1:
			GameState.shockwave_unlocked = not GameState.shockwave_unlocked
		KEY_F2:
			GameState.grant_power(NanoPalette.Power.SURGE, 10.0)
		KEY_F3:
			GameState.grant_power(NanoPalette.Power.SPRING, 10.0)
		KEY_F4:
			GameState.grant_power(NanoPalette.Power.PHASE, 10.0)
		KEY_F5:
			GameState.grant_power(NanoPalette.Power.IMPACT, 10.0)
		KEY_F6:
			GameState.clear_power()
