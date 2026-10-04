extends Level
## Test room with debug hotkeys (not part of the input map):
## F1 toggle shockwave, F2-F5 grant Surge/Spring/Phase/Impact, F6 clear power.


var _tele := 0.0


## Web debug: index.html?x=1650&shock=1&power=3&keys=red teleports the cat for test runs.
func _ready() -> void:
	super()
	if not OS.has_feature("web"):
		return
	var q := func(key: String) -> String:
		return str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('%s') || ''" % key))
	if q.call("x") != "":
		cat.global_position = Vector2(float(q.call("x")), 216.0)
	if q.call("shock") == "1":
		GameState.shockwave_unlocked = true
	if q.call("keys") != "":
		GameState.add_key(q.call("keys"))
	if q.call("power") != "":
		GameState.grant_power(int(q.call("power")), 10.0)


## Web builds publish state to window.__wake so Playwright can drive the run.
func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	_tele -= delta
	if _tele > 0.0:
		return
	_tele = 0.05
	var bot := get_node_or_null("Bot")
	var d := {
		"x": cat.global_position.x, "y": cat.global_position.y,
		"vx": cat.velocity.x, "vy": cat.velocity.y, "floor": cat.is_on_floor(),
		"hp": GameState.health, "score": GameState.score, "keys": GameState.keys,
		"letters": GameState.letters, "power": GameState.power,
		"shock": GameState.shockwave_unlocked, "dead": cat.dead,
		"crouch": cat.crouched, "save": SaveSystem.has_save(),
		"cp": SaveSystem.session_checkpoint,
		"bot": [bot.global_position.x, bot.global_position.y, bot.stomps, int(bot.state)] if bot else null,
	}
	JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))


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
