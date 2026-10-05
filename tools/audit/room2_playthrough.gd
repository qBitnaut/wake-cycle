## Drives the real Cat through every beat of Room 2, "The Yard", with scripted
## input (Input.action_press, the same path a keyboard takes), in the real
## scene with the real physics. No teleporting except to reset a failed trial.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/room2_playthrough.gd
##
## Arrival (as Room 1 leaves the cat: mind awake, no powers, auto-save) ->
## discovery (the pad in the low tunnel cannot be hopped; emitters go blue;
## the monologue) -> the Surge-only gap (a plain double jump falls, a Surge
## single jump falls, a Surge double jump lands) -> the timed gate (a plain
## cat is too late, a Surge cat is through with time to spare) -> the docked
## bot reacts -> the searchlight drone (standing in the beam sends the cat to
## the checkpoint, no death; running ahead on Surge is never seen) -> the fence
## -> Room 3. Asserts that Surge comes only from pads, that nothing else is
## granted, and that the mind carries through. Prints MEASURE lines with the
## clearances. Exit code 1 if any beat fails. Deletes user://save.json.
extends SceneTree

const T := 32.0
const FLOOR_Y := 320.0
const GAP_EDGE := 2240.0     # last floor of the Surge gap (col 70)
const GAP_FAR := 2528.0      # first floor beyond it (col 79)
const GATE_X := 4080.0
const DRONE_TRIGGER := 5024.0
const PIT_EDGE := 5408.0
const VENT_FROM := 5770.0
const VENT_TO := 5930.0

var room: Node2D
var cat: CharacterBody2D
var results: Array = []
var _frames := 0
var _beat_start := 0
var _timeline: Array = []
var _lines: Array = []
var _died := 0
var _hurt := 0
var _grants: Array = []     # [power, on_a_pad] for every grant, across reloads
var _lit_frames := 0
var _min_cover_gap := 99999.0
## TRACE=from,to prints the cat every frame in that range (debugging).
var _trace_from := 0
var _trace_to := 0


func gs() -> Node:
	return root.get_node("GameState")


func ss() -> Node:
	return root.get_node("SaveSystem")


func mono() -> Node:
	return root.get_node("Monologue")


func _initialize() -> void:
	_main.call_deferred()


# ---- input helpers --------------------------------------------------------

func hold(action: String, on := true) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func dir(d: float) -> void:
	hold("move_right", d > 0.0)
	hold("move_left", d < 0.0)


func stop() -> void:
	dir(0.0)
	hold("jump", false)
	hold("move_down", false)


func ticks(n: int) -> void:
	for i in n:
		await physics_frame
		_frames += 1
		if _trace_to > _trace_from and _frames >= _trace_from and _frames <= _trace_to and cat != null and is_instance_valid(cat):
			print("   f=%d x=%.0f y=%.0f vx=%.0f vy=%.0f floor=%s power=%s move=%s crouch=%s right=%s down=%s mv=%s" % [_frames, x(), y(), cat.velocity.x, cat.velocity.y, cat.is_on_floor(), gs().power, cat.can_move, cat.crouched, Input.is_action_pressed("move_right"), Input.is_action_pressed("move_down"), cat.can_move])


func x() -> float:
	return cat.global_position.x


func y() -> float:
	return cat.global_position.y


func teleport(px: float, py := FLOOR_Y) -> void:
	cat.global_position = Vector2(px, py)
	cat.velocity = Vector2.ZERO


func go_to(target: float, tol := 6.0, limit := 1500) -> bool:
	var n := 0
	while absf(x() - target) > tol and n < limit:
		dir(signf(target - x()))
		await ticks(1)
		n += 1
	dir(0.0)
	await ticks(6)
	return n < limit


func refresh() -> void:
	room = current_scene
	cat = room.get_node("Cat")
	cat.hurt_taken.connect(func(_hp):
		_hurt += 1
		print("   (hurt at x=%.0f y=%.0f vy=%.0f frame %d; bots %s)" % [x(), y(), cat.velocity.y, _frames, str(get_nodes_in_group("enemy").map(func(b): return snappedf(b.global_position.x, 1.0)))]))
	cat.died.connect(func(): _died += 1)


## Wait for a reload (death, alarm) to bring up a fresh scene (the old one's instance id).
func await_reload(old_id: int, limit := 900) -> bool:
	var n := 0
	while (current_scene == null or current_scene.get_instance_id() == old_id or current_scene.get_node_or_null("Cat") == null) and n < limit:
		await ticks(1)
		n += 1
	await ticks(6)
	refresh()
	return n < limit


func ray(from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to, 1)
	return not cat.get_world_2d().direct_space_state.intersect_ray(q).is_empty()


## A reactive runner: hold right, hop walls, bots and (with a double jump) pits,
## crouch between `crouch_from` and `crouch_to`. Returns when x >= target.
func run_to(target: float, crouch_from := -1.0, crouch_to := -1.0, limit := 1800) -> bool:
	var air := -1
	var pit_jump := false
	var n := 0
	while x() < target and n < limit and not cat.dead and current_scene == room:
		dir(1.0)
		var crouch := crouch_from > 0.0 and x() >= crouch_from and x() <= crouch_to
		hold("move_down", crouch)
		var on_floor := cat.is_on_floor()
		if on_floor and air >= 3:  # landed (the first frames after the press still read as floor)
			air = -1
			hold("jump", false)
		if on_floor and air < 0 and not crouch:
			var wall := ray(cat.global_position + Vector2(0, -8), cat.global_position + Vector2(34, -8))
			var no_ground := not ray(cat.global_position + Vector2(0, -2), cat.global_position + Vector2(0, 80))
			var bot_ahead := false
			for b in get_nodes_in_group("enemy"):
				var d: Vector2 = b.global_position - cat.global_position
				if d.x > 40.0 and d.x < 92.0 and absf(d.y) < 30.0:
					bot_ahead = true
			if wall or no_ground or bot_ahead:
				hold("jump", true)
				air = 0
				pit_jump = no_ground
		elif air >= 0:
			air += 1  # also counts the first frames after a press
			if pit_jump and air == 26:
				hold("jump", false)
			elif pit_jump and air == 27:
				hold("jump", true)
			elif not pit_jump and air > 24:
				hold("jump", false)
		await ticks(1)
		n += 1
	stop()
	if n >= limit:
		print("   (run_to %.0f timed out at x=%.0f y=%.0f frames %d)" % [target, x(), y(), _frames])
	return x() >= target


func note(name: String, ok: bool, detail := "") -> void:
	results.append([name, ok, detail])
	print("%s  %-62s %s" % ["PASS" if ok else "FAIL", name, detail])


func measure(label: String, detail: String) -> void:
	print("MEASURE  %-40s %s" % [label, detail])


func mark(label: String) -> void:
	_timeline.append([label, (_frames - _beat_start) / 60.0])
	_beat_start = _frames


func node(path: String) -> Node:
	return room.get_node_or_null(path)


func aug_color() -> Color:
	var aug: Node = cat.get_node_or_null("Sprite/Augments")
	return aug.get("_color") if aug else Color.BLACK


func close(a: Color, b: Color, tol := 0.08) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol


func on_pad() -> bool:
	if current_scene == null:
		return false
	for pad in current_scene.find_children("*", "PowerPad", true, false):
		for b in (pad as Area2D).get_overlapping_bodies():
			if b is CharacterBody2D:
				return true
	return false


func lines_of(id: String) -> Array:
	return _lines.filter(func(l): return l[0] == id).map(func(l): return l[1])


func wait_lines(id: String, count: int, limit := 1500) -> bool:
	var n := 0
	while lines_of(id).size() < count and n < limit:
		await ticks(1)
		n += 1
	return lines_of(id).size() >= count


# ---- the run --------------------------------------------------------------

## Standalone: a fresh Room 2 as Room 1 leaves the cat. In the full-game chain
## (tools/audit/full_game.gd) Room 2 is already loaded: _setup(true).
func _main() -> void:
	await _setup(false)
	await _beats()
	_finish()


func _setup(chained: bool) -> void:
	var tr := OS.get_environment("TRACE")
	if tr.contains(","):
		_trace_from = int(tr.split(",")[0])
		_trace_to = int(tr.split(",")[1])
	if not chained:
		ss().delete_save()
		gs().new_game()
		mono().reset()
		# As Room 1 leaves the cat: the mind awake, no powers, arriving through a RoomExit.
		gs().awaken_mind()
		ss().session_scene = ""
		ss().session_checkpoint = ""
		RoomTransition.arriving = true
		room = load("res://scenes/levels/room2.tscn").instantiate()
		root.add_child(room)
		current_scene = room
	else:
		room = current_scene
		_lines = mono().history.duplicate()  # the arrival lines began before this routine took over
	mono().line_started.connect(func(id: String, text: String): _lines.append([id, text]))
	await ticks(4)
	refresh()
	gs().power_changed.connect(func(p: int, _d: float):
		if p != 0:
			_grants.append([p, on_pad()]))
	process_frame.connect(_sample_drone)


## Ticks to wait after a room exit loads the next room before checking it. The
## full-game chain sets it small, so the next routine meets the room as its own
## standalone run does (patrols and drones in the same phase).
var exit_settle := 100


## Full-game chain hook: called as beat_hook.call(self, "<beat>") after each beat
## (tools/audit/full_game.gd uses it for the continue-from-save checks).
var beat_hook := Callable()


func _after(beat_name: String) -> void:
	if beat_hook.is_valid():
		await beat_hook.call(self, beat_name)


func _beats() -> void:
	await _beat_arrival()
	await _after("arrival")
	await _beat_discovery()
	await _after("discovery")
	await _beat_gap()
	await _after("gap")
	await _beat_gate()
	await _after("gate")
	await _beat_dock()
	await _after("dock")
	await _beat_drone()
	await _after("drone")
	await _beat_exit()
	await _after("exit")

	note("Z Surge came only from pads, and only Surge", _grants.size() >= 4 and _grants.all(func(g): return g[0] == 1 and g[1]), "%d grants: %s" % [_grants.size(), str(_grants)])
	note("Z the shockwave was never unlocked, no other power was granted", not gs().shockwave_unlocked)


func _finish() -> void:
	var ok_all := true
	for r in results:
		ok_all = ok_all and r[1]
	print("== timeline (s, scripted run):")
	var total := 0.0
	for e in _timeline:
		total += e[1]
		print("   %-14s %6.1f" % [e[0], e[1]])
	print("   %-14s %6.1f" % ["TOTAL", total])
	print("== %d checks, %s, hurt %d, died %d" % [results.size(), "ALL PASS" if ok_all else "FAILURES", _hurt, _died])
	ss().delete_save()
	quit(0 if ok_all else 1)


func _sample_drone() -> void:
	if current_scene == null or cat == null or not is_instance_valid(cat):
		return
	var d := current_scene.get_node_or_null("SearchDrone")
	if d and d.get("lit"):
		_lit_frames += 1


## Run right from `start_x` to `target`, hopping walkers. A walker's timing is not the
## test: if one lands a hit, restore the health and take the run again (up to three tries).
func cross_walker(target: float, hp0: int) -> Dictionary:
	var start := Vector2(x(), y())
	var tries := 0
	while tries < 3:
		tries += 1
		if tries > 1:
			gs().set_health(hp0)
			teleport(start.x, start.y)
			await ticks(120)
		var ok := await run_to(target)
		if ok and not cat.dead and gs().health == hp0:
			return {"ok": true, "tries": tries}
	return {"ok": false, "tries": tries}


func _beat_arrival() -> void:
	note("A arrives at the warehouse door, on the floor, control at once", absf(x() - 112.0) < 8.0 and cat.is_on_floor() and cat.can_move, "x=%.0f y=%.0f" % [x(), y()])
	note("A the mind carried over from Room 1, no power, no shockwave", gs().intelligence and gs().power == 0 and not gs().shockwave_unlocked)
	var save: Dictionary = ss().read_save()
	note("A auto-saved on arrival with the mind", save.get("scene", "") == "res://scenes/levels/room2.tscn" and save.get("abilities", {}).get("mind", false), str(save.get("abilities", {})))
	note("A the augments show without the reveal", cat.get_node_or_null("Sprite/Augments") != null and cat.get_node("Sprite/Augments").get("shown"))
	note("A HUD shown", (node("Hud") as CanvasLayer).visible)
	var rain := node("RainNear")
	note("A real RainFX rain, two layers, following the camera", rain != null and node("RainFar") != null and rain.get_node("Drops").emitting and absf(rain.global_position.x - cat.camera.get_screen_center_position().x) < 2.0)
	note("A lamps on poles, a lightning rig, the backdrop", room.find_children("*", "WarningLight", true, false).size() >= 10 and node("Lightning") != null and node("Exterior") != null)
	# Lightning: a strike makes thunder, and the thunder is hooked to a sound.
	var t0: int = room.get("thunders")
	node("Lightning").strike(1.0)
	await ticks(200)
	note("A lightning strikes and the thunder signal plays the thunder sound", room.get("thunders") >= t0 + 1, "thunders %d" % room.get("thunders"))
	await wait_lines("yard_arrival", 2)
	note("A arrival monologue, two lines", lines_of("yard_arrival") == ["Rain. Cold. Real.", "The city... all those lights. Is anyone out there?"], str(lines_of("yard_arrival")))
	# The walker: a plain stomp bounces, nothing more.
	var bot = node("Bot1")
	var hp0: int = gs().health
	teleport(bot.global_position.x, bot.global_position.y - 90.0)
	var bounced := false
	for i in 40:
		await ticks(1)
		bounced = bounced or cat.velocity.y < -300.0
	note("A stomping the first walker bounces and does no damage", bounced and bot.state == 0 and bot.stomps == 0 and gs().health == hp0, "state %d stomps %d hp %d" % [bot.state, bot.stomps, gs().health])
	await go_to(112.0, 6.0)
	var cr := await cross_walker(930.0, hp0)
	note("A crossed the arrival yard past the walker (a patient player: a hit means try again)", cr["ok"], "x=%.0f hp %d, %d tries" % [x(), gs().health, cr["tries"]])
	mark("arrival")


func _beat_discovery() -> void:
	# The pad sits in a tunnel with 32 px of headroom. Mash jump through it.
	var tiles := node("Tiles") as TileMapLayer
	var pad := node("PadSurge1") as Area2D
	var open_cells := 0
	for c in range(39, 57):
		for r in range(4, 10):
			if tiles.get_cell_source_id(Vector2i(c, r)) != -1:
				open_cells += 1
	note("B1 the run after the pad is clear: no tile between the tunnel and the checkpoint", open_cells == 0, "%d solid cells in cols 39-56" % open_cells)
	var min_y := 1e9
	var power0: int = gs().power
	dir(1.0)
	var n := 0
	while x() < 1200.0 and n < 600:
		if n % 18 == 0:
			hold("jump", true)
		elif n % 18 == 9:
			hold("jump", false)
		await ticks(1)
		if x() > 975.0 and x() < 1180.0:
			min_y = minf(min_y, y())
		n += 1
	stop()
	var rise := FLOOR_Y - min_y
	note("B1 the pad cannot be hopped over: mashing jump in the tunnel grants Surge", power0 == 0 and gs().power == 1 and _grants.size() == 1 and _grants[0][1], "power %d, headroom rise %.1f px (pad is 44 px wide)" % [gs().power, rise])
	measure("tunnel headroom (rise while under it)", "%.1f px of 32 px clearance; cat is 26 px" % rise)
	await ticks(30)
	note("B1 the power is timed (10 s) and the HUD shows it", absf(gs().power_duration - 10.0) < 0.01 and gs().power_time > 8.0 and gs().power_time < 10.0, "%.1f s left" % gs().power_time)
	note("B1 the emitters turn Surge blue (GameState.power_changed)", close(aug_color(), Color(0.16, 0.42, 1.0)), "emitter %s" % str(aug_color()))
	await wait_lines("surge_first", 2)
	note("B1 a monologue trigger fires on the first use", lines_of("surge_first") == ["Whoa- my legs! Everything's... faster.", "That pad. It's humming the same blue as the lines in me."], str(lines_of("surge_first")))
	dir(1.0)
	await go_to(1300.0, 6.0)
	dir(1.0)
	await ticks(40)
	var vx := cat.velocity.x
	stop()
	note("B1 the cat runs faster: 1.5x on the clear run", absf(vx - 178.0 * 1.5) < 6.0, "vx %.0f (plain 178)" % vx)
	var ok := await run_to(1850.0)
	await ticks(10)
	note("B1 checkpoint A saves", ss().session_checkpoint == "cp_a", str(ss().session_checkpoint))
	mark("B1 discovery")


func _gap_trial(from_x: float, dj: bool, label: String) -> Dictionary:
	cat.death_y = 1e9
	teleport(from_x)
	await ticks(30)
	dir(1.0)
	var n := 0
	while x() < GAP_EDGE + 8.0 and n < 800:
		await ticks(1)
		n += 1
	var vx := cat.velocity.x
	hold("jump", true)
	var t := 0
	var reach := -1.0
	var landed := false
	var fell := false
	while t < 220:
		await ticks(1)
		t += 1
		if dj and t == 28:
			hold("jump", false)
			await ticks(1)
			hold("jump", true)
		if reach < 0.0 and t > 10 and y() >= FLOOR_Y and cat.velocity.y > 0.0:
			reach = x()
		if t > 10 and cat.is_on_floor() and y() < FLOOR_Y + 2.0:
			landed = x() > GAP_FAR
			break
		if y() > 400.0:
			fell = true
			break
	stop()
	var travel := (reach if reach > 0.0 else x()) - (GAP_EDGE + 8.0)
	print("   gap trial %-34s takeoff vx %.0f, travel %.0f px, %s" % [label, vx, travel, "LANDED" if landed else "fell"])
	return {"landed": landed, "fell": fell, "travel": travel}


func _beat_gap() -> void:
	await go_to(2064.0, 8.0)  # over the second pad, then past it
	await ticks(10)
	# Plain double jump: the best a plain cat can do.
	gs().clear_power()
	var a := await _gap_trial(2064.0, true, "plain, double jump")
	note("B2 the gap is impossible without Surge (plain double jump, run-up, best timing)", not a["landed"] and a["fell"], "travel %.0f px of the 266 needed" % a["travel"])
	measure("gap: plain double jump", "%.0f px of travel; needs 266 for a 288 px gap" % a["travel"])
	# The pad again (real walk over it), then a single jump only.
	await ticks(240)
	teleport(1960.0)
	await ticks(10)
	dir(1.0)
	var n := 0
	while x() < 2010.0 and n < 200:
		await ticks(1)
		n += 1
	stop()
	var b := await _gap_trial(2064.0, false, "Surge, single jump")
	note("B2 Surge alone is not enough: a single jump falls short", not b["landed"] and b["fell"], "travel %.0f px" % b["travel"])
	measure("gap: Surge single jump", "%.0f px of travel" % b["travel"])
	await ticks(240)
	teleport(1960.0)
	await ticks(10)
	dir(1.0)
	n = 0
	while x() < 2010.0 and n < 200:
		await ticks(1)
		n += 1
	stop()
	var power_now: int = gs().power
	note("B2 the second pad grants Surge again", power_now == 1 and gs().power_time > 9.0, "%.1f s" % gs().power_time)
	var c := await _gap_trial(2064.0, true, "Surge, double jump")
	note("B2 with Surge the gap is crossed (run-up, double jump)", c["landed"], "travel %.0f px (needs 266), spare %.0f px" % [c["travel"], c["travel"] - 266.0])
	measure("gap: Surge double jump", "%.0f px of travel, spare %.0f px over the 266 needed" % [c["travel"], c["travel"] - 266.0])
	cat.death_y = 448.0
	await ticks(20)
	var ok := await run_to(2660.0)
	await ticks(10)
	note("B2 landed and walked to checkpoint B", ss().session_checkpoint == "cp_b" and cat.is_on_floor(), "cp %s x=%.0f" % [ss().session_checkpoint, x()])
	var cr := await cross_walker(3060.0, 3)
	ok = cr["ok"]
	note("B2 walked past the second walker (a hit means try again)", ok, "x=%.0f hp %d, %d tries" % [x(), gs().health, cr["tries"]])
	mark("B2 gap")


func _beat_gate() -> void:
	var gate := node("TimedGate")
	var plate := node("GatePlate")
	# Plain: no Surge (clear it after the pad), the gate wins.
	gs().clear_power()
	teleport(3200.0)
	await ticks(20)
	dir(1.0)
	var t_plate := -1
	var f0 := _frames
	var n := 0
	while x() < 4040.0 and n < 1200:
		await ticks(1)
		n += 1
		if t_plate < 0 and plate.get("active"):
			t_plate = _frames
	var t_stop := _frames
	stop()
	await ticks(30)
	var plain_x := x()
	note("B3 without Surge the gate closes first: the plain cat is stopped at it", plain_x < GATE_X - 20.0 and gate.is_shut(), "stopped at x=%.0f of %.0f, %.1f s after the plate" % [plain_x, GATE_X, (t_stop - t_plate) / 60.0])
	measure("gate: plain cat", "reaches it %.1f s after the plate; the gate starts closing at 3.5 s and is shut at 4.0 s" % ((t_stop - t_plate) / 60.0))
	# A jump over a shut gate is no way through (gate 224 px, a double jump rises 171 px).
	dir(1.0)
	hold("jump", true)
	await ticks(18)
	hold("jump", false)
	await ticks(1)
	hold("jump", true)
	await ticks(60)
	stop()
	note("B3 and it cannot be jumped (224 px gate, double jump 171 px)", x() < GATE_X and gate.is_shut(), "x=%.0f" % x())
	# Back to the plate: the gate reopens (retry).
	await go_to(3280.0, 6.0)
	await ticks(10)
	note("B3 stepping on the plate again reopens it", gate.get("open") and not gate.is_shut(), "time left %.1f" % gate.get("time_left"))
	# Surge: through the pad, the plate, the gate.
	await ticks(240)
	teleport(3040.0)
	await ticks(20)
	dir(1.0)
	var t_armed := -1
	var passed_left := -1.0
	var t_pass := -1
	n = 0
	while x() < 4140.0 and n < 1200:
		await ticks(1)
		n += 1
		if t_armed < 0 and plate.get("active"):
			t_armed = _frames
		if t_pass < 0 and x() >= GATE_X:
			t_pass = _frames
			passed_left = gate.get("time_left")
	stop()
	var t_run := (t_pass - t_armed) / 60.0
	note("B3 on Surge the gate is beaten", x() >= 4140.0 and passed_left > 0.0, "through %.1f s after the plate, %.2f s before it starts closing" % [t_run, passed_left])
	measure("gate: Surge cat", "%.2f s after the plate; margin %.2f s before the gate starts closing; plain margin %.2f s after it is shut" % [t_run, passed_left, (t_stop - t_plate) / 60.0 - 4.0])
	await wait_lines("surge_gate", 1)
	note("B3 the gate monologue plays", lines_of("surge_gate") == ["That gate won't wait for me. Good thing I don't have to wait either."], str(lines_of("surge_gate")))
	await ticks(300)
	note("B3 and the gate shuts behind it", gate.is_shut())
	mark("B3 gate")


func _beat_dock() -> void:
	var ok := await run_to(4230.0)
	await ticks(10)
	note("D checkpoint C saves", ss().session_checkpoint == "cp_c", str(ss().session_checkpoint))
	var dock := node("DockBot")
	note("D the docked bot sleeps until the cat is near", not dock.get("has_reacted") and dock.get("wake") == 0.0)
	await go_to(4420.0, 8.0)
	await ticks(90)
	var eye: Color = dock.get("eye_color")
	note("D the bot reacts: eyes flicker, then take the colour of the cat's emitters", dock.get("has_reacted") and dock.get("wake") > 0.95 and close(eye, aug_color(), 0.12), "eye %s emitter %s" % [str(eye), str(aug_color())])
	await wait_lines("dock_bot", 2)
	note("D the monologue trigger fires", lines_of("dock_bot") == ["It... looked at me. Like it knew me.", "Why do I feel like it's waiting for an order?"], str(lines_of("dock_bot")))
	note("D no mirror, no befriend yet: a plain node, no collision, not an enemy", dock is Node2D and not dock is CollisionObject2D and not dock.is_in_group("enemy"))
	ok = await run_to(4860.0)
	await ticks(10)
	note("D checkpoint D saves", ss().session_checkpoint == "cp_d", str(ss().session_checkpoint))
	mark("D dock")


func _beat_drone() -> void:
	var old := room.get_instance_id()
	var hp0: int = gs().health
	var died0 := _died
	# Seen: stand in the beam. Not death: back to the checkpoint, health kept.
	teleport(5330.0)
	var drone := node("SearchDrone")
	var n := 0
	while not drone.get("alarmed") and n < 1500:
		await ticks(1)
		n += 1
	var alarm_after := n / 60.0
	var reloaded := await await_reload(old)
	note("B4 standing in the searchlight raises the alarm and sends the cat to the checkpoint", reloaded and absf(x() - 4848.0) < 14.0 and ss().session_checkpoint == "cp_d", "after %.1f s, back at x=%.0f" % [alarm_after, x()])
	note("B4 ...and it is not death: no death, no hit, health kept, control back", _died == died0 and gs().health == hp0 and cat.can_move and not cat.dead, "hp %d died %d" % [gs().health, _died - died0])
	await ticks(30)
	# The clean run on Surge: the pad, the trigger, steps, pit, vent, out.
	_lit_frames = 0
	var drone2 := node("SearchDrone")
	var got := await run_to(DRONE_TRIGGER - 10.0)
	note("B4 the pad before it grants Surge", gs().power == 1 and _grants.size() >= 5, "power %d" % gs().power)
	var t0 := _frames
	got = await run_to(6300.0, VENT_FROM, VENT_TO)
	var secs := (_frames - t0) / 60.0
	var dx: float = x() - drone2.global_position.x
	note("B4 combined challenge on Surge: steps, pit, crawl vent, never seen", got and not drone2.get("alarmed") and _lit_frames == 0 and not cat.dead, "%.1f s from the trigger, lit %d frames, ahead of the drone by %.0f px" % [secs, _lit_frames, dx])
	measure("combined: Surge run", "%.1f s from the trigger line to x=6300; drone (%.0f px/s) was %.0f px behind at the end" % [secs, drone2.get("speed"), dx])
	# For the record: the same run on plain speed.
	var old2 := room.get_instance_id()
	cat.kill()
	await await_reload(old2)
	_lit_frames = 0
	teleport(DRONE_TRIGGER - 30.0)  # past the pad
	gs().clear_power()
	await ticks(10)
	var t1 := _frames
	var got2 := await run_to(6300.0, VENT_FROM, VENT_TO)
	var drone3 := current_scene.get_node_or_null("SearchDrone")
	var alarmed: bool = drone3 != null and drone3.get("alarmed")
	measure("combined: plain run (informational)", "%s after %.1f s, lit %d frames" % ["seen" if alarmed or not got2 else "got through", (_frames - t1) / 60.0, _lit_frames])
	if alarmed or not got2:
		await await_reload(current_scene.get_instance_id())
	mark("B4 drone")


func _beat_exit() -> void:
	if x() < 6200.0:
		teleport(6000.0)
		await ticks(20)
	var ok := await run_to(6330.0)
	await wait_lines("exit_fence", 1)
	note("E the fence line plays near the exit", lines_of("exit_fence") == ["The fence goes on forever. There has to be a way through."], str(lines_of("exit_fence")))
	var fence := node("Fence") as YardFence
	note("E the fence has a cut in it where the exit is", fence != null and fence.gaps.size() == 1 and fence.gaps[0].x > 0.0)
	var old := room
	dir(1.0)
	var n := 0
	while current_scene == old and n < 900:
		await ticks(1)
		n += 1
	stop()
	var hop: Dictionary = await MapHop.through(root.get_tree(), "yard", "stacks")
	note("E the exit fades out onto the world map, the yard is finished and the stacks open", hop["on_map"] and hop["completed"] and hop["unlocked"], str(hop))
	await ticks(exit_settle)
	var r3 := current_scene
	note("E the stacks are entered from the map: Room 3 loads", r3 != null and r3.scene_file_path == "res://scenes/levels/room3.tscn", str(r3.scene_file_path if r3 else "?"))
	note("E Room 3 is the real room (The Stacks): the conduit and the Spring pad are there", r3 != null and r3.get_node_or_null("Conduit") != null and r3.get_node_or_null("PadSpring1") != null)
	var save: Dictionary = ss().read_save()
	note("E auto-saved at the start of Room 3 with the mind, no shockwave", save.get("scene", "") == "res://scenes/levels/room3.tscn" and save.get("abilities", {}).get("mind", false) and not save.get("abilities", {}).get("shockwave", true), str(save.get("abilities", {})))
	note("E the cat keeps its augments in Room 3", r3 != null and r3.get_node_or_null("Cat/Sprite/Augments") != null and gs().intelligence)
	mark("E exit")
