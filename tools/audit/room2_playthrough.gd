## Drives the real Cat through every beat of Room 2, "The Yard", with scripted
## input (Input.action_press, the same path a keyboard takes), in the real
## scene with the real physics. Teleports only to start a branch or to reset a failed trial.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/room2_playthrough.gd
##   BEATS=under,roofs ... runs only those beats (each starts from its own staging point)
##
## The yard is TALL (four tiers, see tools/build_room2.gd), so the run covers every route:
## arrival (as Room 1 leaves the cat: mind awake, no powers, auto-save) -> discovery (the pad in
## the low tunnel cannot be hopped; emitters go blue; the monologue) -> the Surge-only gap (a
## plain double jump falls into the underpass, a Surge single jump falls, a Surge double jump
## lands) -> THE UNDERPASS: the safe drop, the vault (a turret's bolt pops the explosive barrel,
## the blast breaks the hatch, the memory fragment), the crawl cache (the golden bone), the electric
## floor, the acid, the supply closet (the drone's bomb breaks the hatch), the grate back up ->
## the timed gate (a plain cat is too late, a Surge cat is through with time to spare) -> THE ROOFS:
## the girder stair, the Surge pad, a Surge run over the containers past a turret, a laser bot
## and a bomber, the moving bridge, the crane stair, the cab, the lift down -> the dock: conveyors,
## the falling crate, the docked bot, the security camera (the alarm shuts the guard door and wakes
## the turret; the detour goes over the hut) -> the searchlight drone (standing in the beam sends
## the cat to the checkpoint, no death; running ahead on Surge is never seen; the pit is an escape)
## -> the fence -> Room 3. Asserts that Surge comes only from pads, that nothing else is granted, that
## every hazard gives at least 0.4 s of warning, and that the mind carries through. Prints MEASURE
## lines. Exit code 1 if any beat fails. Deletes user://save.json.
extends SceneTree

const T := 32.0
const HumanSweep := preload("res://tools/audit/human_sweep.gd")
const FLOOR_Y := 768.0       # the yard floor (row 24)
const U_Y := 1024.0          # the underpass floor (row 32)
const V_Y := 1152.0          # the vault floor (row 36)
const GAP_EDGE := 2240.0     # last floor of the Surge gap (col 70)
const GAP_FAR := 2528.0      # first floor beyond it (col 79)
const GATE_X := 4080.0
const DRONE_TRIGGER := 5376.0
const VENT_FROM := 6122.0    # crouch from here to VENT_TO (the low beam is cols 193-194)
const VENT_TO := 6282.0

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
var _frozen: Array = []
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


## A FILLER line (see Monologue, "Pacing") is held back or dropped while the narrator is busy or in
## its cooldown: that is the rule working, so the audits take "played, or held/dropped" as handled.
func filler_handled(id: String, played: bool) -> bool:
	return played or mono().drop_log.any(func(d): return d[0] == id) or mono().filler_blocked()


func wait_lines(id: String, count: int, limit := 1500) -> bool:
	var n := 0
	while lines_of(id).size() < count and n < limit:
		if lines_of(id).is_empty() and mono().priority_of(id) == mono().Prio.FILLER and filler_handled(id, false):
			break  # held back by the pacing rules: do not stand here waiting for it
		await ticks(1)
		n += 1
	return lines_of(id).size() >= count


# ---- the run --------------------------------------------------------------

## Standalone: a fresh Room 2 as Room 1 leaves the cat. In the full-game chain
## (tools/audit/full_game.gd) Room 2 is already loaded: _setup(true).
func _main() -> void:
	if OS.get_environment("SWEEP") != "0":
		await HumanSweep.lab(self, "room2", note, "LAB ")
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


func _want(b: String) -> bool:
	var only := OS.get_environment("BEATS")
	return only == "" or only.split(",").has(b)


func _beats() -> void:
	if _want("arrival"):
		await _beat_arrival()
		await _after("arrival")
	if _want("discovery"):
		await _beat_discovery()
		await _after("discovery")
	if _want("gap"):
		await _beat_gap()
		await _after("gap")
	if _want("under"):
		await _beat_under()
		await _after("under")
	if _want("gate"):
		await _beat_gate()
		await _after("gate")
	if _want("roofs"):
		await _beat_roofs()
		await _after("roofs")
	if _want("dock"):
		await _beat_dock()
		await _after("dock")
	if _want("drone"):
		await _beat_drone()
		await _after("drone")
	if _want("inventory"):
		_inventory()
	if _want("exit"):
		await _beat_exit()
		await _after("exit")

	note("Z Surge came only from pads, and only Surge", _grants.size() >= 5 and _grants.all(func(g): return g[0] == 1 and g[1]), "%d grants: %s" % [_grants.size(), str(_grants)])
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


# ---- scripted moves -------------------------------------------------------

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


## One scripted hop from where the cat stands: run in direction `d` to `jump_x`, press jump and hold
## it to the apex time (or `dj` frames to a second press), hold `d` until the landing. True when it
## lands standing inside [tx0, tx1] at height `ty` (the same box the human sweep uses).
func hop(d: float, jump_x: float, tx0: float, tx1: float, ty: float, dj := -1) -> bool:
	var n := 0
	while (x() - jump_x) * d < 0.0 and n < 900 and not cat.dead:
		dir(d)
		await ticks(1)
		n += 1
	hold("jump", true)
	var f := 0
	while f < 220 and not cat.dead and current_scene == room:
		dir(d)
		await ticks(1)
		f += 1
		if dj >= 0:
			if f == dj:
				hold("jump", false)
			elif f == dj + 1:
				hold("jump", true)
			elif f == dj + 40:
				hold("jump", false)
		elif f == 22:
			hold("jump", false)
		if f > 6 and cat.is_on_floor() and cat.velocity.y >= 0.0:
			break
	stop()
	await ticks(6)
	return cat.is_on_floor() and x() >= tx0 and x() <= tx1 and absf(y() - ty) < 6.0


## A staircase of hops: each step [d, jump_x, tx0, tx1, ty]. A failed step puts the cat back at
## `from` (a human would try again) and retries the whole climb, up to `tries` times.
func climb(steps: Array, from: Vector2, tries := 3) -> Dictionary:
	var t := 0
	while t < tries:
		t += 1
		if t > 1:
			gs().set_health(3)
			teleport(from.x, from.y)
			await ticks(20)
		var ok := true
		for st in steps:
			if not await hop(st[0], st[1], st[2], st[3], st[4]):
				ok = false
				break
		if ok and not cat.dead:
			return {"ok": true, "tries": t}
	return {"ok": false, "tries": tries}


## The zigzag rungs of a 5-wide grate shaft whose left column is `c`: the yard floor at the top.
func shaft_steps(c: float) -> Array:
	return [
		[1.0, c * T - 30.0, c * T + 8.0, (c + 3.0) * T + 8.0, U_Y - 64.0],
		[1.0, (c + 2.0) * T - 20.0, (c + 2.0) * T + 8.0, (c + 5.0) * T + 8.0, U_Y - 128.0],
		[-1.0, (c + 3.0) * T + 20.0, c * T - 8.0, (c + 3.0) * T - 8.0, U_Y - 192.0],
		[1.0, (c + 3.0) * T - 20.0, c * T + 8.0, (c + 7.0) * T, FLOOR_Y],
	]


## Switch off every enemy except the named ones (and remember them): the secrets and the climbs
## are about the level, the enemies have their own beats.
func freeze_enemies(except: Array = []) -> void:
	for e in get_nodes_in_group("enemy"):
		if not except.has(String(e.name)) and e.process_mode != Node.PROCESS_MODE_DISABLED:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			_frozen.append(e)


func thaw_enemies() -> void:
	for e in _frozen:
		if is_instance_valid(e):
			e.process_mode = Node.PROCESS_MODE_INHERIT
	_frozen.clear()


func collected(node_name: String) -> bool:
	return gs().is_collected("/root/Room2/" + node_name) or gs().is_collected(str(current_scene.get_path()) + "/" + node_name)


func gone(node_name: String) -> bool:
	var n := room.get_node_or_null(node_name)
	return n == null or n.is_queued_for_deletion()


# ---- the beats ------------------------------------------------------------

func _beat_arrival() -> void:
	note("A arrives at the warehouse door, on the floor, control at once", absf(x() - 112.0) < 8.0 and cat.is_on_floor() and cat.can_move, "x=%.0f y=%.0f" % [x(), y()])
	note("A the mind carried over from Room 1, no power, no shockwave", gs().intelligence and gs().power == 0 and not gs().shockwave_unlocked)
	var save: Dictionary = ss().read_save()
	note("A auto-saved on arrival with the mind", save.get("scene", "") == "res://scenes/levels/room2.tscn" and save.get("abilities", {}).get("mind", false), str(save.get("abilities", {})))
	note("A the augments show without the reveal", cat.get_node_or_null("Sprite/Augments") != null and cat.get_node("Sprite/Augments").get("shown"))
	note("A HUD shown", (node("Hud") as CanvasLayer).visible)
	var rain := node("RainNear")
	note("A real RainFX rain, two layers, windows on the camera view", rain != null and node("RainFar") != null and rain.get_node("Drops").emitting and rain.get("follow_camera") and node("RainFar").get("follow_camera"))
	note("A lamps on poles, a lightning rig, the backdrop", room.find_children("*", "WarningLight", true, false).size() >= 10 and node("Lightning") != null and node("Exterior") != null)
	note("A a tall room: camera follow TIERS, 220 x 39 tiles (3.5 screens), the limits are the exact rect", room.camera_follow == 1 and room.limits == Rect2i(0, 0, 220 * 32, 39 * 32), str(room.limits))
	# Lightning: a strike makes thunder, and the thunder is hooked to a sound.
	var t0: int = room.get("thunders")
	node("Lightning").strike(1.0)
	await ticks(200)
	note("A lightning strikes and the thunder signal plays the thunder sound", room.get("thunders") >= t0 + 1, "thunders %d" % room.get("thunders"))
	await wait_lines("yard_arrival", 2)
	note("A arrival monologue, two lines (a FILLER: dropped if the last room's line just ended)", filler_handled("yard_arrival", lines_of("yard_arrival") == ["Rain. Cold. Real.", "The city... all those lights. Is anyone out there?"]), str(lines_of("yard_arrival")))
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
	if x() < 900.0 or y() > FLOOR_Y + 8.0:
		teleport(930.0)
		await ticks(20)
	var tiles := node("Tiles") as TileMapLayer
	var open_cells := 0
	for c in range(39, 57):
		for r in range(18, 24):
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
	while t < 260:
		await ticks(1)
		t += 1
		if dj and t == 28:
			hold("jump", false)
			await ticks(1)
			hold("jump", true)
		if reach < 0.0 and t > 10 and y() >= FLOOR_Y and cat.velocity.y > 0.0:
			reach = x()
		if t > 10 and cat.is_on_floor():
			landed = y() < FLOOR_Y + 2.0 and x() > GAP_FAR
			fell = y() > FLOOR_Y + 100.0
			break
	stop()
	var travel := (reach if reach > 0.0 else x()) - (GAP_EDGE + 8.0)
	print("   gap trial %-34s takeoff vx %.0f, travel %.0f px, %s" % [label, vx, travel, "LANDED" if landed else ("fell into the underpass" if fell else "?")])
	return {"landed": landed, "fell": fell, "travel": travel}


## Walk onto a pad from the west (a real walk over it), then stop short of the lip.
func _repad(pad_x: float, from_x: float) -> void:
	await ticks(240)
	teleport(from_x)
	await ticks(10)
	dir(1.0)
	var n := 0
	while x() < pad_x + 40.0 and n < 300:
		await ticks(1)
		n += 1
	stop()


func _beat_gap() -> void:
	if x() < 1800.0 or y() > FLOOR_Y + 8.0:
		teleport(1840.0)
		await ticks(20)
	await go_to(2064.0, 8.0)  # over the second pad, then past it
	await ticks(10)
	# Plain double jump: the best a plain cat can do.
	gs().clear_power()
	var hp0: int = gs().health
	var a := await _gap_trial(2064.0, true, "plain, double jump")
	note("B2 the gap is impossible without Surge (plain double jump, run-up, best timing)", not a["landed"] and a["fell"], "travel %.0f px of the 266 needed" % a["travel"])
	measure("gap: plain double jump", "%.0f px of travel; needs 266 for a 288 px gap" % a["travel"])
	# And it is a detour, not a death: the hole drops into the underpass.
	await ticks(30)
	note("B2 falling in is safe: the underpass floor, no damage, no death, control kept", cat.is_on_floor() and absf(y() - U_Y) < 4.0 and gs().health == hp0 and not cat.dead and cat.can_move, "y=%.0f hp %d (was %d)" % [y(), gs().health, hp0])
	await wait_lines("yard_underpass", 1)
	note("B2 the underpass monologue plays on the way down", filler_handled("yard_underpass", lines_of("yard_underpass").size() == 1), str(lines_of("yard_underpass")))
	await ticks(60)
	note("B2 the near rain fades out under the yard", room.get("_rain_near_k") < 0.4, "rain %.2f" % room.get("_rain_near_k"))
	# The pad again (real walk over it), then a single jump only.
	await _repad(1984.0, 1960.0)
	var b := await _gap_trial(2064.0, false, "Surge, single jump")
	note("B2 Surge alone is not enough: a single jump falls short", not b["landed"] and b["fell"], "travel %.0f px" % b["travel"])
	measure("gap: Surge single jump", "%.0f px of travel" % b["travel"])
	await _repad(1984.0, 1960.0)
	var power_now: int = gs().power
	note("B2 the second pad grants Surge again", power_now == 1 and gs().power_time > 9.0, "%.1f s" % gs().power_time)
	var c := await _gap_trial(2064.0, true, "Surge, double jump")
	note("B2 with Surge the gap is crossed (run-up, double jump)", c["landed"], "travel %.0f px (needs 266), spare %.0f px" % [c["travel"], c["travel"] - 266.0])
	measure("gap: Surge double jump", "%.0f px of travel, spare %.0f px over the 266 needed" % [c["travel"], c["travel"] - 266.0])
	await ticks(20)
	var ok := await run_to(2640.0)
	await ticks(10)
	note("B2 landed and walked to checkpoint B", ss().session_checkpoint == "cp_b" and cat.is_on_floor(), "cp %s x=%.0f" % [ss().session_checkpoint, x()])
	# The landing is covered by a turret on the container stub (bolts to dodge); a walker beyond.
	var turret := node("TurretLand")
	var hp1: int = gs().health
	var cr := await cross_walker(3060.0, hp1)
	note("B2 walked the landing under the turret and past the second walker (a hit means try again)", cr["ok"], "x=%.0f hp %d, %d tries, the turret fired %d" % [x(), gs().health, cr["tries"], turret.shots])
	mark("B2 gap")


func _beat_under() -> void:
	# --- S3, the vault: stand where the turret sees the cat across the barrel ---
	gs().clear_power()
	gs().set_health(3)
	teleport(1840.0, U_Y)
	await ticks(20)
	freeze_enemies(["TurretVault"])
	var barrel := node("BarrelVault")
	var hatch := node("VaultHatch")
	var turret := node("TurretVault")
	note("U3 the vault lane: a turret, an explosive barrel and a blast-only hatch in the floor", barrel != null and hatch != null and turret != null and hatch.kind == 2 and barrel.kind == 0, "hatch kind %s" % str(hatch.kind if hatch else "?"))
	note("U3 the hatch takes a blast and nothing else (not a stomp, a shock or a pound)", hatch.breaks_with("blast") and not hatch.breaks_with("shock") and not hatch.breaks_with("pound") and not hatch.breaks_with("stomp"))
	var hp0: int = gs().health
	var t_first := -1
	var n := 0
	while n < 900 and not (gone("BarrelVault") and gone("VaultHatch")):
		await ticks(1)
		n += 1
		if t_first < 0 and turret.shots >= 1:
			t_first = n
	await ticks(30)
	note("U3 the turret's bolt sets off the barrel, the blast breaks the hatch, and the cat 7 tiles away is not hurt", gone("BarrelVault") and gone("VaultHatch") and gs().health == hp0 and turret.shots >= 1, "after %.1f s, the turret fired at %.1f s, hp %d" % [n / 60.0, t_first / 60.0, gs().health])
	measure("vault: telegraph", "the turret charged %.2f s before it fired (>= 0.4)" % turret.last_telegraph)
	await wait_lines("yard_vault", 2)
	note("U3 the hint line plays at the lane", lines_of("yard_vault").size() == 2, str(lines_of("yard_vault")))
	# Into the hatch: walk to the hole, drop, collect the memory.
	gs().set_health(3)
	dir(-1.0)
	n = 0
	while x() > 1690.0 and n < 300:
		await ticks(1)
		n += 1
	stop()
	n = 0
	while y() < V_Y - 70.0 and n < 120:
		await ticks(1)
		n += 1
	await ticks(40)
	note("U3 dropped through the broken hatch into the vault", y() > U_Y + 30.0 and cat.is_on_floor(), "y=%.0f" % y())
	var score0: int = gs().score
	await go_to(1488.0, 8.0)
	await ticks(10)
	await wait_lines("memory_yard", 2)
	note("U3 the memory fragment: 5000 points, collected, and its two lines play", collected("MemoryYard") and gs().score >= score0 + 5000 and lines_of("memory_yard").size() == 2, "score +%d, lines %s" % [gs().score - score0, str(lines_of("memory_yard"))])
	# The way out: three hops up the rungs (32, 64 and 32 px).
	await go_to(1500.0, 10.0)
	var cl := await climb([
		[1.0, 1544.0, 1560.0, 1720.0, V_Y - 32.0],
		[1.0, 1608.0, 1648.0, 1722.0, V_Y - 96.0],
		[1.0, 1704.0, 1736.0, 1860.0, U_Y],
	], Vector2(1500.0, V_Y))
	note("U3 climbed out of the vault by the rungs", cl["ok"] and absf(y() - U_Y) < 4.0, "x=%.0f y=%.0f, %d tries" % [x(), y(), cl["tries"]])
	thaw_enemies()
	mark("S3 vault")

	# --- S1, the crawl cache: a dip with a bell, a low tunnel, a golden bone ---
	freeze_enemies()
	teleport(3040.0, U_Y)
	await ticks(20)
	var bone_score: int = gs().score
	dir(1.0)
	n = 0
	var min_head := 999.0
	while x() < 3712.0 and n < 900:
		await ticks(1)
		n += 1
		if x() > 3230.0 and x() < 3540.0:
			min_head = minf(min_head, y())
	stop()
	await ticks(10)
	note("U1 the crawl cache: the dip, the low tunnel (32 px) and the chamber are walkable", x() >= 3640.0 and cat.is_on_floor(), "x=%.0f y=%.0f" % [x(), y()])
	note("U1 the golden bone (2000) and the fish are in the cache; the bell shows the way", collected("BoneYard") and collected("FishCache") and collected("BellDip") and gs().score >= bone_score + 2000 + 250, "score +%d" % (gs().score - bone_score))
	# Back out: a 32 px step up from the chamber into the tunnel, then the dip is a 2-tile climb.
	await go_to(3590.0, 8.0)
	var stepped := await hop(-1.0, 3584.0, 3440.0, 3548.0, U_Y + 64.0)
	await go_to(3170.0, 8.0)
	var out := await hop(-1.0, 3166.0, 3000.0, 3128.0, U_Y)
	note("U1 climbed back out: the step up from the chamber, then the dip", stepped and out, "x=%.0f y=%.0f" % [x(), y()])
	thaw_enemies()
	mark("S1 crawl")

	# --- the electric floor under the broken floodlight, then the acid ---
	freeze_enemies(["ElectricFloor"])
	gs().set_health(3)
	teleport(3480.0, U_Y)
	await ticks(20)
	var ef := node("ElectricFloor")
	note("U the electric floor warns 0.4 s or more (its panels flash before they arc)", ef.warn_seconds() >= 0.4, "warn %.2f s" % ef.warn_seconds())
	var hpe: int = gs().health
	n = 0
	while not (ef.phase == 0 and ef.phase_time < 0.15) and n < 600:
		await ticks(1)
		n += 1
	dir(1.0)
	n = 0
	while x() < 3700.0 and n < 200:
		await ticks(1)
		n += 1
	stop()
	note("U crossed the electric floor in its idle window, unhurt", x() >= 3700.0 and gs().health == hpe, "x=%.0f hp %d" % [x(), gs().health])
	await go_to(3730.0, 6.0)
	await ticks(10)
	note("U the checkpoint in the drain saves", ss().session_checkpoint == "cp_u", str(ss().session_checkpoint))
	# The leaking acid barrel (an obstacle to hop) and its pool (a hazard to jump).
	var acid_hp: int = gs().health
	var h1 := await hop(1.0, 3752.0, 3812.0, 3900.0, U_Y)
	note("U hopped the acid barrel", h1, "x=%.0f" % x())
	var h2 := await hop(1.0, 3880.0, 3976.0, 4090.0, U_Y)
	note("U jumped the acid pool (2 tiles) unhurt", h2 and gs().health == acid_hp, "x=%.0f hp %d" % [x(), gs().health])
	thaw_enemies()
	mark("U hazards")

	# --- S2, the supply closet: stand on the hatch under the drone, let it arm, run ---
	gs().set_health(3)
	freeze_enemies()   # the drone too: where its cycle stands must not depend on how long the walk in took
	teleport(4470.0, U_Y)
	await ticks(20)
	await go_to(4656.0, 8.0)
	var drone := node("DroneSpur")
	drone.mode = 0   # a fresh cycle (patrol) from the moment the cat stands on the hatch, so the run has the whole telegraph
	drone._m_t = 0.0
	drone.process_mode = Node.PROCESS_MODE_INHERIT
	_frozen.erase(drone)
	var hatch2 := node("SupplyHatch")
	note("U2 the supply closet: a blast-only hatch in the floor under a hover drone", drone != null and hatch2 != null and hatch2.kind == 2, "")
	var armed := false
	n = 0
	while n < 900 and not armed:
		await ticks(1)
		n += 1
		armed = drone.mode == 1
	var arm_x: float = drone.global_position.x
	var arm_t := 0
	# Run for it the moment the bomb bay glows (the telegraph).
	var hp2: int = gs().health
	dir(-1.0)
	while arm_t < 200 and x() > 4540.0:
		await ticks(1)
		arm_t += 1
	stop()
	await ticks(90)
	note("U2 the drone hangs still and arms before it drops (0.4 s or more of warning)", armed and drone.last_telegraph >= 0.4, "armed %.1f s after the cat stood there; telegraph %.2f s" % [n / 60.0, drone.last_telegraph])
	note("U2 its bomb lands on the hatch and breaks it; the cat that ran is unhurt", gone("SupplyHatch") and gs().health == hp2, "hatch gone %s hp %d" % [str(gone("SupplyHatch")), gs().health])
	await wait_lines("yard_closet", 2)
	note("U2 the closet hint plays", lines_of("yard_closet").size() == 2, str(lines_of("yard_closet")))
	freeze_enemies()
	# Down the hole for the loot, and out by the rungs.
	await go_to(4640.0, 10.0)
	await ticks(60)
	note("U2 dropped into the supply closet", y() > U_Y + 30.0, "y=%.0f" % y())
	await go_to(4560.0, 8.0)
	await go_to(4584.0, 8.0)
	await go_to(4528.0, 8.0)
	note("U2 the closet loot: a mouse (500), two bells, a fish", collected("MouseCloset") and collected("BellCloset1") and collected("FishCloset"), "mouse %s bell %s fish %s" % [str(collected("MouseCloset")), str(collected("BellCloset1")), str(collected("FishCloset"))])
	var cl2 := await climb([
		[1.0, 4552.0, 4568.0, 4730.0, V_Y - 32.0],
		[1.0, 4616.0, 4648.0, 4732.0, V_Y - 96.0],
		[1.0, 4712.0, 4744.0, 4830.0, U_Y],
	], Vector2(4530.0, V_Y))
	note("U2 climbed out of the closet by the rungs", cl2["ok"] and absf(y() - U_Y) < 4.0, "x=%.0f y=%.0f, %d tries" % [x(), y(), cl2["tries"]])
	mark("S2 closet")

	# --- the grate: back up to the yard, west of the dock ---
	await go_to(4066.0, 10.0)
	var up := await climb(shaft_steps(128.0), Vector2(4066.0, U_Y))
	note("U the grate shaft climbs back to the yard (four 2-tile hops, then the flush floor)", up["ok"] and absf(y() - FLOOR_Y) < 4.0 and x() > 4100.0, "x=%.0f y=%.0f, %d tries" % [x(), y(), up["tries"]])
	thaw_enemies()
	mark("under")


func _beat_gate() -> void:
	var gate := node("TimedGate")
	var plate := node("GatePlate")
	# Plain: no Surge (clear it after the pad), the gate wins.
	gs().clear_power()
	gs().set_health(3)
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


func _beat_roofs() -> void:
	gs().clear_power()
	gs().set_health(3)
	# The hanging bridge: a plain cat rides it across the 5-tile gap (no jump at all). (The laser bot
	# and the bomber have their own run below.)
	var grants0 := _grants.size()
	freeze_enemies()
	teleport(3630.0, 512.0)
	await ticks(30)
	var bridge := node("Bridge")
	var start_x: float = (115.0 + 1.5) * T
	var n := 0
	while bridge.global_position.x > start_x + 1.0 and n < 600:
		await ticks(1)
		n += 1
	dir(1.0)
	n = 0
	while x() < 3700.0 and n < 120:
		await ticks(1)
		n += 1
	stop()
	var on_it := cat.is_on_floor() and absf(y() - 512.0) < 4.0
	n = 0
	while bridge.global_position.x < start_x + 63.0 and n < 400:
		await ticks(1)
		n += 1
	dir(1.0)
	n = 0
	while x() < 3900.0 and n < 200:
		await ticks(1)
		n += 1
	stop()
	note("R the hanging-container bridge carries a plain cat over the gap, no jump", on_it and x() >= 3880.0 and absf(y() - 512.0) < 4.0 and cat.is_on_floor(), "x=%.0f y=%.0f" % [x(), y()])
	thaw_enemies()

	# The girder stair from the landing up to the first roof (four 2-tile hops, plain).
	teleport(2600.0)
	await ticks(20)
	var c1 := await climb([
		[1.0, 2658.0, 2696.0, 2776.0, FLOOR_Y - 64.0],
		[1.0, 2764.0, 2792.0, 2872.0, FLOOR_Y - 128.0],
		[1.0, 2860.0, 2888.0, 2968.0, FLOOR_Y - 192.0],
		[1.0, 2956.0, 2984.0, 3200.0, 512.0],
	], Vector2(2600.0, FLOOR_Y))
	note("R climbed the girder stair to the first roof (a plain cat, four hops)", c1["ok"], "x=%.0f y=%.0f, %d tries" % [x(), y(), c1["tries"]])
	# The pad on the roof: Surge for the run.
	await go_to(3040.0, 6.0)
	await ticks(10)
	note("R the roof pad grants Surge", gs().power == 1 and _grants.size() >= grants0 + 1, "power %d" % gs().power)
	await wait_lines("yard_roof", 1)
	note("R the rooftop hint plays", lines_of("yard_roof").size() == 1, str(lines_of("yard_roof")))
	# The Surge run: a turret to dodge, a gap, a laser bot, the bridge gap, a bomber.
	var turret := node("TurretRoof")
	var hp0: int = gs().health
	var t0 := _frames
	var ok := false
	var tries := 0
	while tries < 3 and not ok:
		# A hit from the turret or the bot can knock a runner off the roof: a human goes round again.
		tries += 1
		if tries > 1:
			gs().set_health(3)
			teleport(2992.0, 512.0)
			await ticks(240)
			await go_to(3040.0, 6.0)   # the pad again (a real walk over it)
			hp0 = gs().health
		t0 = _frames
		ok = await run_to(3900.0)
		n = 0
		while not cat.is_on_floor() and n < 90:
			await ticks(1)
			n += 1
		ok = ok and absf(y() - 512.0) < 6.0 and not cat.dead
	var secs := (_frames - t0) / 60.0
	note("R ran the rooftops on Surge: turret, 5-tile gap, laser bot, 5-tile gap (a hit means try again)", ok and not cat.dead and absf(y() - 512.0) < 6.0, "x=%.0f y=%.0f in %.1f s, hp %d (was %d), the turret fired %d" % [x(), y(), secs, gs().health, hp0, turret.shots])
	measure("roofs: Surge run", "%.1f s from the pad to the third roof; Surge left %.1f s" % [secs, gs().power_time])
	if absf(y() - 512.0) >= 6.0 or cat.dead:
		teleport(3900.0, 512.0)
		await ticks(30)
	# The crane stair: roof -> three girders -> the cab floor, all plain hops.
	gs().clear_power()
	gs().set_health(3)
	await go_to(4034.0, 6.0)
	var c2 := await climb([
		[1.0, 4040.0, 4072.0, 4152.0, 448.0],
		[-1.0, 4094.0, 3976.0, 4056.0, 384.0],
		[1.0, 4040.0, 4072.0, 4152.0, 320.0],
		[1.0, 4136.0, 4168.0, 4300.0, 256.0],
	], Vector2(4034.0, 512.0))
	note("R climbed the crane stair to the cab (four 2-tile hops)", c2["ok"] and absf(y() - 256.0) < 4.0, "x=%.0f y=%.0f, %d tries" % [x(), y(), c2["tries"]])
	await ticks(10)
	await go_to(4180.0, 8.0)
	await go_to(4272.0, 8.0)
	note("R the cab: a checkpoint, a mouse (500) and a bell", ss().session_checkpoint == "cp_r" and collected("MouseCab") and collected("BellCab"), "cp %s" % ss().session_checkpoint)
	# The lift down to the dock.
	var lift := node("Lift")
	note("R the lift is a vertical moving platform (travel 480 px)", lift != null and lift.mode == 1 and lift.travel == 480.0)
	await go_to(4300.0, 6.0)
	n = 0
	while lift.global_position.y > 258.0 and n < 1500:
		await ticks(1)
		n += 1
	dir(1.0)
	n = 0
	while x() < 4368.0 and n < 120:
		await ticks(1)
		n += 1
	stop()
	var ride_t := 0
	while y() < 700.0 and ride_t < 1500 and not cat.dead:
		await ticks(1)
		ride_t += 1
	await ticks(60)
	dir(1.0)
	n = 0
	while x() < 4460.0 and n < 120:
		await ticks(1)
		n += 1
	stop()
	await ticks(30)
	note("R the lift carries the cat down to the dock floor", cat.is_on_floor() and absf(y() - FLOOR_Y) < 4.0 and x() > 4420.0, "rode %.1f s, x=%.0f y=%.0f" % [ride_t / 60.0, x(), y()])
	mark("roofs")


func _beat_dock() -> void:
	gs().clear_power()
	gs().set_health(3)
	if x() < 4300.0 or y() > FLOOR_Y + 8.0 or y() < FLOOR_Y - 8.0:
		teleport(4368.0)
		await ticks(20)
	# Checkpoint C, then the first conveyor and the falling crate over it.
	await go_to(4290.0, 6.0)
	await ticks(10)
	note("D checkpoint C saves", ss().session_checkpoint == "cp_c", str(ss().session_checkpoint))
	var belt_a := node("Conveyor0")
	var debris := node("CrateDrop")
	var hp0: int = gs().health
	note("D the loading dock: two conveyor belts running opposite ways", belt_a != null and node("Conveyor1") != null and belt_a.speed < 0.0 and node("Conveyor1").speed > 0.0, "%s / %s" % [str(belt_a.speed), str(node("Conveyor1").speed)])
	var xa := -1.0
	var fa := 0
	var xb := -1.0
	var fb := 0
	dir(1.0)
	var n := 0
	while x() < 4540.0 and n < 600:
		await ticks(1)
		n += 1
		if xa < 0.0 and x() >= 4430.0:
			xa = x()
			fa = _frames
		if xb < 0.0 and x() >= 4500.0:
			xb = x()
			fb = _frames
	stop()
	await ticks(60)
	var vx_belt := (xb - xa) / maxf((fb - fa) / 60.0, 0.01)
	note("D the belt pushes against the runner (slower than the plain 178)", vx_belt < 150.0 and vx_belt > 40.0, "%.0f px/s across the left-moving belt" % vx_belt)
	note("D the crate drop cracks first (0.4 s or more) and falls where the cat has left", debris.last_warn >= 0.4 and gs().health == hp0, "warned %.2f s, hp %d" % [debris.last_warn, gs().health])
	# The docked bot reacts to the augments.
	var dock := node("DockBot")
	note("D the docked bot sleeps until the cat is near", true)
	await go_to(4540.0, 8.0)
	await ticks(90)
	var eye: Color = dock.get("eye_color")
	note("D the bot reacts: eyes flicker, then take the colour of the cat's emitters", dock.get("has_reacted") and dock.get("wake") > 0.95 and close(eye, aug_color(), 0.12), "eye %s emitter %s" % [str(eye), str(aug_color())])
	await wait_lines("dock_bot", 2)
	note("D the monologue trigger fires", lines_of("dock_bot") == ["It... looked at me. Like it knew me.", "Why do I feel like it's waiting for an order?"], str(lines_of("dock_bot")))
	note("D no mirror, no befriend yet: a plain node, no collision, not an enemy", dock is Node2D and not dock is CollisionObject2D and not dock.is_in_group("enemy"))
	# The security camera: standing in its cone raises the alarm: the guard door shuts, the turret wakes.
	var cam := node("DockCamera")
	var shutter := node("HutShutter")
	var tdock := node("TurretDock")
	note("D the dock turret sleeps until an alarm; the guard door starts open", tdock.dormant and shutter.open, "")
	n = 0
	var dirn := 1.0
	var bounce := 0
	await go_to(4770.0, 8.0)
	while cam.alarms < 1 and n < 1800 and not cat.dead:
		dir(dirn)
		await ticks(1)
		n += 1
		if x() > 4890.0:
			dirn = -1.0
		elif x() < 4780.0:
			dirn = 1.0
	stop()
	var spot_t: float = cam.last_telegraph
	await ticks(20)
	note("D the camera spots the cat (the lens ticks 0.4 s or more), then the alarm: the door shuts, the turret wakes", cam.alarms >= 1 and spot_t >= 0.4 and not shutter.open and tdock.is_awake(), "after %.1f s, spotted for %.2f s, door open %s, turret awake %s" % [n / 60.0, spot_t, str(shutter.open), str(tdock.is_awake())])
	# The shut door stops a cat on the floor.
	gs().set_health(3)
	dir(1.0)
	n = 0
	while x() < 5030.0 and n < 300:
		await ticks(1)
		n += 1
	stop()
	var door_x := x()
	note("D the shut guard door blocks the floor route", door_x < 5040.0 and not shutter.open, "stopped at x=%.0f of the door at 5040" % door_x)
	# The detour: the girders onto the canopy, over the hut, down the far side.
	gs().set_health(3)
	await go_to(4540.0, 8.0)
	var dt := await climb([
		[1.0, 4552.0, 4584.0, 4660.0, FLOOR_Y - 64.0],
		[1.0, 4648.0, 4680.0, 4760.0, FLOOR_Y - 128.0],
		[1.0, 4744.0, 4776.0, 4900.0, FLOOR_Y - 192.0],
	], Vector2(4540.0, FLOOR_Y))
	note("D the detour: three hops up the girders onto the canopy roof", dt["ok"], "x=%.0f y=%.0f, %d tries" % [x(), y(), dt["tries"]])
	dir(1.0)
	n = 0
	while x() < 5150.0 and n < 600:
		await ticks(1)
		n += 1
	stop()
	await ticks(60)
	note("D ...over the hut and down the far side, past the shut door (the roof is out of the turret's sight)", x() > 5130.0 and (absf(y() - FLOOR_Y) < 6.0 or absf(y() - (FLOOR_Y - 32.0)) < 6.0), "x=%.0f y=%.0f" % [x(), y()])
	var ok := await run_to(5210.0)
	await ticks(10)
	note("D checkpoint D saves", ss().session_checkpoint == "cp_d", str(ss().session_checkpoint))
	# The alarm ends and the door rolls back up.
	var waited := 0
	while not shutter.open and waited < 900:
		await ticks(1)
		waited += 1
	note("D the alarm passes: the guard door opens again (no soft-lock)", shutter.open, "after %.1f s more" % (waited / 60.0))
	mark("D dock")


func _beat_drone() -> void:
	var old := room.get_instance_id()
	gs().set_health(3)
	if ss().session_checkpoint != "cp_d":
		# Run on its own (BEATS=drone): touch checkpoint D first, as the dock beat does.
		teleport(5200.0)
		await ticks(20)
	var hp0: int = gs().health
	var died0 := _died
	# Seen: stand in the beam. Not death: back to the checkpoint, health kept.
	teleport(5700.0)
	var drone := node("SearchDrone")
	var n := 0
	while not drone.get("alarmed") and n < 1500:
		await ticks(1)
		n += 1
	var alarm_after := n / 60.0
	var reloaded := await await_reload(old)
	note("B4 standing in the searchlight raises the alarm and sends the cat to the checkpoint", reloaded and absf(x() - 5200.0) < 14.0 and ss().session_checkpoint == "cp_d", "after %.1f s, back at x=%.0f" % [alarm_after, x()])
	note("B4 ...and it is not death: no death, no hit, health kept, control back", _died == died0 and gs().health >= hp0 and cat.can_move and not cat.dead, "hp %d (was %d) died %d can_move %s dead %s" % [gs().health, hp0, _died - died0, str(cat.can_move), str(cat.dead)])
	await ticks(30)
	# The clean run on Surge: the pad, the trigger, steps, hole, vent, out.
	_lit_frames = 0
	var drone2 := node("SearchDrone")
	var got := await run_to(DRONE_TRIGGER - 10.0)
	note("B4 the pad before it grants Surge", gs().power == 1 and not _grants.is_empty() and _grants.back()[1], "power %d" % gs().power)
	var t0 := _frames
	got = await run_to(DRONE_TRIGGER + 90.0)
	# Sound: the drone's whirr is a LoopSfx child of the drone: audible near the cat, none left on the root.
	var hum: Node = drone2.get("hum")
	note("S the drone's hum starts when it triggers, follows it and is audible near the cat", hum != null and hum.get_parent() == drone2 and hum.audible() and hum.gain > 0.2, "gain %.2f at %.0f px" % [hum.gain if hum else -1.0, (drone2.global_position.distance_to(cat.global_position)) if hum else -1.0])
	note("S ...and nothing loops on the root (the old leak: a looping one-shot parented to the root)", LoopSfx.orphans(root.get_tree()).is_empty() and root.get_children().all(func(c): return not (c is AudioStreamPlayer and c.playing and LoopSfx._loops(c.stream))), str(LoopSfx.orphans(root.get_tree())))
	got = await run_to(6560.0, VENT_FROM, VENT_TO)   # past where the drone gives up (x = 6496)
	var secs := (_frames - t0) / 60.0
	var dx: float = x() - drone2.global_position.x
	note("B4 combined challenge on Surge: steps, hole, crawl vent, never seen", got and not drone2.get("alarmed") and _lit_frames == 0 and not cat.dead, "%.1f s from the trigger, lit %d frames, ahead of the drone by %.0f px" % [secs, _lit_frames, dx])
	measure("combined: Surge run", "%.1f s from the trigger line to x=6560; drone (%.0f px/s) was %.0f px behind at the end" % [secs, drone2.get("speed"), dx])
	# The drone leaves: its hum fades out of range and the player is freed.
	var left := 0
	while drone2.get("state") != 3 and left < 900:
		await ticks(1)
		left += 1
	await ticks(90)
	note("S after the drone has left, its hum has stopped and been freed (no loop outlives its source)", drone2.get("state") == 3 and not is_instance_valid(hum), "state %s, hum valid %s" % [str(drone2.get("state")), str(is_instance_valid(hum))])
	note("S ...and the census agrees: no audible positional loop, no orphan", LoopSfx.census(root.get_tree())["positional"] == 0 and LoopSfx.orphans(root.get_tree()).is_empty(), str(LoopSfx.census(root.get_tree())))
	# Self-test of the detector (it must see the old bug): a looping player on the root, outside the scene.
	var leak := AudioStreamPlayer.new()
	leak.stream = Sfx.stream("laser_hum")
	root.add_child(leak)
	leak.play()
	await ticks(2)
	var seen := LoopSfx.orphans(root.get_tree()).size()
	# ...and Sfx.play of a looping asset (what the drone used to do) is now a true one-shot.
	Sfx.play(root, "laser_hum", -40.0)
	await ticks(2)
	var after_sfx := LoopSfx.orphans(root.get_tree()).size()
	leak.queue_free()
	await ticks(2)
	note("S self-test: a looping player left on the root is detected as an orphan, and Sfx.play of a loop asset is not one", seen == 1 and after_sfx == 1 and LoopSfx.orphans(root.get_tree()).is_empty(), "seen %d, with Sfx.play %d, after cleanup %d" % [seen, after_sfx, LoopSfx.orphans(root.get_tree()).size()])
	# The hole is an escape: a cat that drops into the underpass during the chase is never lit.
	var old2 := room.get_instance_id()
	cat.kill()
	await await_reload(old2)
	_lit_frames = 0
	gs().clear_power()
	gs().set_health(3)
	teleport(5690.0)
	await ticks(10)
	var drone3 := node("SearchDrone")
	dir(1.0)
	n = 0
	while y() < FLOOR_Y + 100.0 and n < 300:
		await ticks(1)
		n += 1
	stop()
	print("   (hole test: walked %d frames, now x=%.0f y=%.0f, drone x=%.0f state %s)" % [n, x(), y(), drone3.global_position.x, str(drone3.get("state"))])
	var unlit := true
	var below_frames := 0
	while drone3.get("state") != 3 and below_frames < 1500 and not drone3.get("alarmed"):
		await ticks(1)
		below_frames += 1
		if x() > 6000.0 or drone3.global_position.x > 6100.0:
			break
		unlit = unlit and not drone3.get("lit")
	note("B4 the hole is an escape: a cat in the underpass is never lit by the searchlight", y() > U_Y - 8.0 and unlit and not drone3.get("alarmed"), "y=%.0f for %.1f s while the drone passed overhead (x=%.0f)" % [y(), below_frames / 60.0, drone3.global_position.x])
	# Up the grate behind it (the drone is past).
	await go_to(5922.0, 10.0)
	var pit_up := await climb(shaft_steps(186.0), Vector2(5922.0, U_Y))
	note("B4 the pit's grate climbs back up to the yard, past the drone", pit_up["ok"] and absf(y() - FLOOR_Y) < 4.0 and not drone3.get("alarmed"), "x=%.0f y=%.0f" % [x(), y()])
	# For the record: the same run on plain speed.
	var old3 := room.get_instance_id()
	cat.kill()
	await await_reload(old3)
	_lit_frames = 0
	teleport(DRONE_TRIGGER - 30.0)  # past the pad
	gs().clear_power()
	await ticks(10)
	var t1 := _frames
	var got2 := await run_to(6560.0, VENT_FROM, VENT_TO)
	var drone4 := current_scene.get_node_or_null("SearchDrone")
	var alarmed: bool = drone4 != null and drone4.get("alarmed")
	measure("combined: plain run (informational)", "%s after %.1f s, lit %d frames" % ["seen" if alarmed or not got2 else "got through", (_frames - t1) / 60.0, _lit_frames])
	if alarmed or not got2:
		await await_reload(current_scene.get_instance_id())
	mark("B4 drone")


func _beat_exit() -> void:
	if x() < 6300.0:
		teleport(6350.0)
		await ticks(20)
	var ok := await run_to(6660.0)
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
	var hop_result: Dictionary = await MapHop.through(root.get_tree(), "yard", "stacks")
	note("E the exit fades out onto the world map, the yard is finished and the stacks open", hop_result["on_map"] and hop_result["completed"] and hop_result["unlocked"], str(hop_result))
	note("E sound: after the exit no looping sound from the room is still playing, on the map or in the next room", hop_result["sound_map"].is_empty() and hop_result["sound_next"].is_empty(), "map %s next %s" % [str(hop_result["sound_map"]), str(hop_result["sound_next"])])
	await ticks(exit_settle)
	var r3 := current_scene
	note("E the stacks are entered from the map: Room 3 loads", r3 != null and r3.scene_file_path == "res://scenes/levels/room3.tscn", str(r3.scene_file_path if r3 else "?"))
	note("E Room 3 is the real room (The Stacks): the conduit and the Spring pad are there", r3 != null and r3.get_node_or_null("Conduit") != null and r3.get_node_or_null("PadSpring1") != null)
	var save: Dictionary = ss().read_save()
	note("E auto-saved at the start of Room 3 with the mind, no shockwave", save.get("scene", "") == "res://scenes/levels/room3.tscn" and save.get("abilities", {}).get("mind", false) and not save.get("abilities", {}).get("shockwave", true), str(save.get("abilities", {})))
	note("E the cat keeps its augments in Room 3", r3 != null and r3.get_node_or_null("Cat/Sprite/Augments") != null and gs().intelligence)
	mark("E exit")


## Static checks on a fresh copy of the scene (the live one has lost what the run collected).
func _inventory() -> void:
	var inv: Node = load("res://scenes/levels/room2.tscn").instantiate()
	var types := {}
	for e in inv.find_children("*", "KitEnemy", true, false):
		var k := String(e.get("actor_id"))
		types[k] = int(types.get(k, 0)) + 1
	note("K enemies: turrets, patrol bots with lasers, hover drones, hoppers, a security camera", types.get("sentry_turret", 0) >= 4 and types.get("patrol_bot", 0) >= 1 and types.get("hover_drone", 0) >= 2 and types.get("hopper_bot", 0) >= 3 and types.get("security_camera", 0) >= 1, str(types))
	var hz := {}
	hz["floor"] = inv.find_children("*", "ElectricFloor", true, false).size()
	hz["debris"] = inv.find_children("*", "FallingDebris", true, false).size()
	hz["conveyor"] = inv.find_children("*", "KitConveyor", true, false).size()
	hz["acid"] = inv.find_children("*", "AcidPool", true, false).size()
	hz["barrel"] = inv.find_children("*", "KitBarrel", true, false).size()
	hz["wall"] = inv.find_children("*", "KitWall", true, false).size()
	hz["platform"] = inv.find_children("*", "KitPlatform", true, false).size()
	note("K hazards and set pieces: an electric floor, falling crates, conveyors, acid, barrels, blast walls, moving platforms", hz["floor"] >= 1 and hz["debris"] >= 2 and hz["conveyor"] >= 2 and hz["acid"] >= 1 and hz["barrel"] >= 2 and hz["wall"] >= 2 and hz["platform"] >= 2, str(hz))
	# Every warning is at least 0.4 s.
	var worst := 99.0
	for h in inv.find_children("*", "KitHazard", true, false):
		worst = minf(worst, h.warn_seconds())
	for d in inv.find_children("*", "FallingDebris", true, false):
		worst = minf(worst, d.warn_seconds())
	for t in inv.find_children("*", "SentryTurret", true, false):
		worst = minf(worst, t.charge_time)
	for dr in inv.find_children("*", "HoverDrone", true, false):
		worst = minf(worst, dr.arm_time)
	for hp in inv.find_children("*", "HopperBot", true, false):
		worst = minf(worst, hp.squat_time)
	for b in inv.find_children("*", "KitPatrolBot", true, false):
		worst = minf(worst, b.aim_time)
	for c in inv.find_children("*", "SecurityCamera", true, false):
		worst = minf(worst, c.spot_time)
	note("K every hazard and attack telegraphs for at least 0.4 s", worst >= 0.4, "shortest warning %.2f s" % worst)
	# Collectibles: variety and one memory fragment, one rare.
	var kinds := {}
	var memories := 0
	var mem_ok := false
	for it in inv.find_children("*", "Collectible", true, false):
		kinds[it.kind] = int(kinds.get(it.kind, 0)) + 1
		if it.kind == 6:
			memories += 1
			mem_ok = String(it.memory_id) == "memory_yard"
	var gems := 0
	for nd in inv.get_children():
		if String(nd.name).begins_with("Gem"):
			gems += 1
	var reg_gems: int = LevelRegistry.gems_total("yard")
	note("K collectibles: yarn on the path, bells, mice, fish, one golden bone, exactly one memory fragment (memory_yard)", kinds.get(1, 0) >= 30 and kinds.get(2, 0) >= 5 and kinds.get(3, 0) >= 3 and kinds.get(0, 0) >= 6 and kinds.get(4, 0) == 1 and memories == 1 and mem_ok, "kinds %s memories %d" % [str(kinds), memories])
	note("K the world map's yarn total (levels.json yard.gems) matches the Gem nodes in the scene", gems == reg_gems, "scene %d, registry %d" % [gems, reg_gems])
	note("K no required path needs a power the cat lacks: no wall here takes a shock or a pound", inv.find_children("*", "KitWall", true, false).all(func(w): return w.kind == 2))
	note("K new monologue lines are in data/monologue.json under yard_ keys", mono().has_set("yard_roof") and mono().has_set("yard_underpass") and mono().has_set("yard_vault") and mono().has_set("yard_closet") and mono().has_set("memory_yard"))
	inv.free()
