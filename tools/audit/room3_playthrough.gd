## Drives the real Cat through every beat of Room 3, "The Stacks", with scripted
## input (Input.action_press, the same path a keyboard takes), in the real scene
## with the real physics.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/room3_playthrough.gd
##
## Two phases. LAB: a throwaway copy of the room; every hop (the Spring wall, the
## two chained ledges, the tower, the Surge gap...) is searched exhaustively over
## takeoff positions and double-jump timings, with plain, Surge and Spring
## (pads made inert so the trial power is the only one): this proves where a
## power is REQUIRED (no trial succeeds without it) and finds a robust set of
## parameters for each hop. PLAY: a fresh room, one continuous run from the
## arrival to the exit with those parameters: the Spring wall, the chain up the
## ledges inside one 10 s charge, the conduit (the shockwave unlocks there and
## only there), the crates, the patrol bot, the shock switch and shutter, the
## mirror bot and its plate (also walked back and forth: recoverable), the Spring
## tower, the Surge pad, the ten-tile gap, the exit to Room 4. Asserts that
## only Spring and Surge are ever granted (never Phase or Impact), only from
## pads. Prints MEASURE lines with the clearances. Exit code 1 if any check
## fails. Deletes user://save.json (use --user-data-dir to keep your own).
extends SceneTree

const G := 1152.0       ## yard floor y (row 36)
const S1 := 960.0       ## shed roof (row 30)
const S2 := 768.0       ## floating ledge (row 24)
const S3 := 576.0       ## long roof (row 18)
const S4 := 384.0       ## tower tops (row 12)
const BAY_Y := 704.0    ## bay floor (row 22)
const PIT_Y := 704.0    ## the pit floor under the gap (row 22)
const GROOF := 192.0    ## gallery roof (row 6)
const WALL1 := 1088.0   ## face of the shed (col 34)
const LEDGE_L := 1440.0
const LEDGE_R := 1632.0
const LONG_L := 1728.0  ## face of the long roof (col 54)
const CONDUIT_X := 2224.0
const CRATES_X := 2464.0
const SWITCH_X := 3088.0
const GATE_X := 3184.0
const BAY_L := 3264.0
const BAY_GATE_X := 4080.0
const TOWER_L := 4416.0
const TAKEOFF := 4672.0 # right edge of the tower top
const LAND_L := 4992.0

var room: Node2D
var cat: CharacterBody2D
var results: Array = []
var _frames := 0
var _beat_start := 0
var _timeline: Array = []
var _lines: Array = []
var _died := 0
var _hurt := 0
var _grants: Array = []     # [power, on_a_pad] for every grant, across the play
var _min_y := 0.0
var _retries := 0
var _hops := {}             # name -> {jump_x, dj} chosen in the lab


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


func x() -> float:
	return cat.global_position.x


func y() -> float:
	return cat.global_position.y


func teleport(px: float, py: float) -> void:
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


func ray(from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to, 1)
	return not cat.get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func refresh() -> void:
	room = current_scene
	cat = room.get_node("Cat")
	cat.hurt_taken.connect(func(_hp):
		_hurt += 1
		print("   (hurt at x=%.0f y=%.0f frame %d)" % [x(), y(), _frames]))
	cat.died.connect(func(): _died += 1)


func note(name: String, ok: bool, detail := "") -> void:
	results.append([name, ok, detail])
	print("%s  %-66s %s" % ["PASS" if ok else "FAIL", name, detail])


func measure(label: String, detail: String) -> void:
	print("MEASURE  %-44s %s" % [label, detail])


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


func lines_of(id: String) -> Array:
	return _lines.filter(func(l): return l[0] == id).map(func(l): return l[1])


func wait_lines(id: String, count: int, limit := 1500) -> bool:
	var n := 0
	while lines_of(id).size() < count and n < limit:
		await ticks(1)
		n += 1
	return lines_of(id).size() >= count


func on_pad() -> bool:
	if current_scene == null:
		return false
	for pad in current_scene.find_children("*", "PowerPad", true, false):
		for b in (pad as Area2D).get_overlapping_bodies():
			if b is CharacterBody2D:
				return true
	return false


func pads_inert(on: bool) -> void:
	for pad in room.find_children("*", "PowerPad", true, false):
		pad.set("_cd", 1e9 if on else 0.0)


## A reactive runner: hold a direction, hop walls (and bots) with a single jump.
func run_to(target: float, d := 1.0, limit := 1800) -> bool:
	var air := -1
	var n := 0
	while (x() - target) * d < 0.0 and n < limit and not cat.dead and current_scene == room:
		dir(d)
		var on_floor := cat.is_on_floor()
		if on_floor and air >= 3:
			air = -1
			hold("jump", false)
			await ticks(1)  # release before the next press: a release and a press in one frame is no new press
			n += 1
			continue
		if on_floor and air < 0:
			var wall := ray(cat.global_position + Vector2(0, -8), cat.global_position + Vector2(34 * d, -8))
			var bot_ahead := false
			for b in get_nodes_in_group("enemy"):
				var dd: Vector2 = b.global_position - cat.global_position
				if dd.x * d > 40.0 and dd.x * d < 92.0 and absf(dd.y) < 30.0:
					bot_ahead = true
			if wall or bot_ahead:
				hold("jump", true)
				air = 0
		elif air >= 0:
			air += 1
			if air > 24:
				hold("jump", false)
		await ticks(1)
		n += 1
	stop()
	return (x() - target) * d >= 0.0


# ---- hops: run to a takeoff x, jump, double jump `dj` frames later ------------

## `dj` < 0: a single jump. With tp the cat is put at (sx, sy) with `power` first.
## Tracks the lowest y reached in _min_y (the highest rise).
func attempt(sx: float, sy: float, d: float, jump_x: float, dj: int, power: int, tp := true) -> void:
	if tp:
		teleport(sx, sy)
		if power == 0:
			gs().clear_power()
		else:
			gs().grant_power(power, 10.0)
		stop()
		await ticks(4)
	_min_y = y()
	var n := 0
	while (x() - jump_x) * d < 0.0 and n < 900:
		dir(d)
		await ticks(1)
		n += 1
	hold("jump", true)
	var f := 0
	var done := dj < 0
	var y0 := y()
	while f < 220:
		dir(d)
		await ticks(1)
		f += 1
		_min_y = minf(_min_y, y())
		if not done and f == dj:
			hold("jump", false)
		elif not done and f == dj + 1:
			hold("jump", true)
			done = true
		elif f == dj + 40:
			hold("jump", false)
		if f > 6 and cat.is_on_floor() and cat.velocity.y >= 0.0:
			break
		if y() > y0 + 700.0:
			break
	stop()
	await ticks(3)


func landed(tx0: float, tx1: float, ty: float) -> bool:
	return cat.is_on_floor() and x() >= tx0 and x() <= tx1 and absf(y() - ty) < 3.0


## Exhaustive search of one hop. Returns {hits, total, best (jump_x, dj of the
## most surrounded success), rise (the highest rise over all trials, px)}.
func search(name: String, sx: float, sy: float, d: float, jumps: Array, djs: Array, power: int, tx0: float, tx1: float, ty: float) -> Dictionary:
	var grid := []
	var hits := 0
	var rise := 0.0
	for j in jumps:
		var row := []
		for dj in djs:
			await attempt(sx, sy, d, j, dj, power)
			var ok := landed(tx0, tx1, ty)
			row.append(ok)
			hits += 1 if ok else 0
			rise = maxf(rise, sy - _min_y)
		grid.append(row)
	var best := {}
	var best_score := -1
	for a in jumps.size():
		for b in djs.size():
			if not grid[a][b]:
				continue
			var score := 0
			for da in [-1, 0, 1]:
				for db in [-1, 0, 1]:
					var aa: int = a + da
					var bb: int = b + db
					if aa >= 0 and aa < jumps.size() and bb >= 0 and bb < djs.size() and grid[aa][bb]:
						score += 1
			if score > best_score:
				best_score = score
				best = {"jump_x": jumps[a], "dj": djs[b], "score": score}
	var total := jumps.size() * djs.size()
	print("   hop %-38s %-6s %2d / %2d landed, highest rise %.0f px%s" % [name, ["plain", "Surge", "Spring"][power], hits, total, rise, ("  best " + str(best)) if hits > 0 else ""])
	return {"hits": hits, "total": total, "best": best, "rise": rise}


func jump_list(edge: float, offsets: Array) -> Array:
	var out := []
	for o in offsets:
		out.append(edge + o)
	return out


# ---- the run --------------------------------------------------------------

func _start_room() -> void:
	ss().delete_save()
	gs().new_game()
	mono().reset()
	# As Room 2 leaves the cat: the mind awake, no powers, no shockwave, through a RoomExit.
	gs().awaken_mind()
	ss().session_scene = ""
	ss().session_checkpoint = ""
	RoomTransition.arriving = true
	room = load("res://scenes/levels/room3.tscn").instantiate()
	root.add_child(room)
	current_scene = room


## Standalone: the lab (where each power is required), then a fresh Room 3 as Room 2
## leaves the cat. In the full-game chain (tools/audit/full_game.gd) Room 3 is already
## loaded and the lab is skipped: _setup(true).
func _main() -> void:
	await _setup(false)
	await _beats()
	_finish()


## The lab: where each power is required, and the hop parameters the route uses
## (its own Room 3, discarded afterwards). The full-game chain runs it first.
func _run_lab() -> void:
	_start_room()
	await ticks(4)
	refresh()
	cat.death_y = 1e9
	await _lab()
	room.queue_free()
	await ticks(4)


func _setup(chained: bool) -> void:
	if not chained:
		mono().line_started.connect(func(id: String, text: String): _lines.append([id, text]))
		await _run_lab()
		_start_room()
		_lines.clear()
	else:
		room = current_scene
		_lines = mono().history.duplicate()  # the arrival lines began before this routine took over
		mono().line_started.connect(func(id: String, text: String): _lines.append([id, text]))
	await ticks(4)
	refresh()
	gs().power_changed.connect(func(p: int, _d: float):
		if p != 0:
			_grants.append([p, on_pad()]))
	_beat_start = _frames


## Ticks to wait after a room exit loads the next room before checking it. The
## full-game chain sets it small, so the next routine meets the room as its own
## standalone run does (patrols and drones in the same phase).
var exit_settle := 100
## Hook counts of a room instance the chain reloaded (a Continue): carried into the Z checks.
var _prior_unlocks: Array = []
var _prior_violations := 0


## Full-game chain hook: called as beat_hook.call(self, "<beat>") after each beat
## (tools/audit/full_game.gd uses it for the continue-from-save checks).
var beat_hook := Callable()


func _after(beat_name: String) -> void:
	if beat_hook.is_valid():
		await beat_hook.call(self, beat_name)


func _beats() -> void:
	await _beat_arrival()
	await _after("arrival")
	await _beat_spring_discovery()
	await _after("spring_discovery")
	await _beat_spring_use()
	await _after("spring_use")
	await _beat_conduit()
	await _after("conduit")
	await _beat_shockwave()
	await _after("shockwave")
	await _beat_mirror()
	await _after("mirror")
	await _beat_combine()
	await _after("combine")
	var violations: int = int(room.get("power_violations")) + _prior_violations
	var unlocks: Array = _prior_unlocks + room.get("shock_unlocks")
	await _beat_exit()
	await _after("exit")

	note("Z only Spring and Surge were ever granted, each from a pad, never Phase or Impact", _grants.size() >= 4 and _grants.all(func(g): return (g[0] == 1 or g[0] == 2) and g[1]), "%d grants: %s" % [_grants.size(), str(_grants)])
	note("Z Room3 audit hooks agree: no power violation", violations == 0, "violations %d" % violations)
	note("Z the shockwave unlocked exactly once, at the conduit", unlocks.size() == 1 and unlocks[0][2], str(unlocks))
	note("Z no deaths in the scripted run", _died == 0, "died %d, hurt %d, hop retries %d" % [_died, _hurt, _retries])


func _finish() -> void:
	var ok_all := true
	for r in results:
		ok_all = ok_all and r[1]
	print("== timeline (s, scripted run):")
	var total := 0.0
	for e in _timeline:
		total += e[1]
		print("   %-16s %6.1f" % [e[0], e[1]])
	print("   %-16s %6.1f" % ["TOTAL", total])
	print("== %d checks, %s, hurt %d, died %d" % [results.size(), "ALL PASS" if ok_all else "FAILURES", _hurt, _died])
	ss().delete_save()
	quit(0 if ok_all else 1)


# ---- LAB: where each power is required, and the hop parameters ----------------

func _lab() -> void:
	pads_inert(true)
	var djs := [-1]
	for k in range(6, 52, 3):
		djs.append(k)
	var near := [-11.0, -21.0, -35.0, -59.0, -101.0]   # takeoff x relative to a wall face (cat half width 11)
	var h1 := await _lab_hop("H1 ground -> shed roof (6 tiles)", 980.0, G, 1.0, jump_list(WALL1, near), djs, 1100.0, 1700.0, S1, 2)
	_hops["H1"] = h1[2]
	var h2 := await _lab_hop("H2 shed roof -> floating ledge", 1312.0, S1, 1.0, jump_list(LEDGE_L, [-11.0, -23.0, -35.0, -51.0, -71.0, -101.0]), djs, 1450.0, 1625.0, S2, 2)
	_hops["H2"] = h2[2]
	var h3 := await _lab_hop("H3 ledge -> long roof", 1500.0, S2, 1.0, jump_list(LEDGE_R, [-11.0, -23.0, -35.0, -51.0, -71.0]), djs, 1735.0, 2100.0, S3, 2)
	_hops["H3"] = h3[2]
	var h4 := await _lab_hop("H4 roof -> tower top (6 tiles)", 4250.0, S3, 1.0, jump_list(TOWER_L, near), djs, 4430.0, 4660.0, S4, 2)
	_hops["H4"] = h4[2]
	var h5 := await _lab_hop("H5 ten-tile gap", 4528.0, S4, 1.0, jump_list(TAKEOFF, [-8.0, -4.0, 0.0, 4.0, 8.0]), djs, 4995.0, 5400.0, S4, 1)
	_hops["H5"] = h5[2]
	measure("wall 1 (6 tiles = 192 px)", "plain best rise %.0f px (%.0f px short), Spring %.0f px (%.0f px spare)" % [h1[0], 192.0 - h1[0], h1[1], h1[1] - 192.0])
	measure("tower (6 tiles = 192 px)", "plain best rise %.0f px, Spring %.0f px" % [h4[0], h4[1]])
	measure("ten-tile gap (320 px, needs 298)", "Surge lands %d of %d trials; plain and Spring none" % [h5[3], h5[4]])
	# The skips that must not exist.
	var skip1 := await _lab_hop("S1 shed -> long roof direct (12 tiles)", 1650.0, S1, 1.0, jump_list(LONG_L, near), djs, 1735.0, 2100.0, S3, -1)
	var skip2 := await _lab_hop("S2 long roof -> gallery roof (12 tiles)", 1950.0, S3, 1.0, jump_list(2112.0, near), djs, 2130.0, 2900.0, GROOF, -1)
	var skip3 := await _lab_hop("S3 pit floor -> far tower (10 tiles)", 4850.0, PIT_Y, 1.0, jump_list(LAND_L, near), djs, 5000.0, 5200.0, S4, -1)
	note("LAB no skips: the 12-tile climbs are out of every power's reach, so is the far tower from the pit", skip1[0] == 0 and skip2[0] == 0 and skip3[0] == 0, "hits %d / %d / %d" % [skip1[0], skip2[0], skip3[0]])
	# The pit has stairs back up on the near side: climbing them needs no power.
	gs().clear_power()
	teleport(4850.0, PIT_Y)
	await ticks(20)
	var ok_run := await run_to(4620.0, -1.0)
	await ticks(20)
	note("LAB the pit is no trap: its stairs lead from the floor back to the tower top, no power", ok_run and cat.is_on_floor() and absf(y() - S4) < 3.0 and gs().power == 0, "x=%.0f y=%.0f" % [x(), y()])
	var tiles := node("Tiles") as TileMapLayer
	var open_cells := 0
	for col in [99, 127]:
		for r in range(6, 15):  # solid from the gallery roof (row 6) down to the opening (row 15)
			if tiles.get_cell_source_id(Vector2i(col, r)) == -1:
				open_cells += 1
	note("LAB both shutters have a solid ceiling over the opening, so neither can be hopped", open_cells == 0, "%d open cells" % open_cells)


## Runs the plain, Surge and Spring searches for one hop. `needs` is the power (0..2) that
## must be the only one that works, or -1 for a hop nothing may manage.
## Returns [plain rise, Spring rise, best params, hits of the needed power, total].
func _lab_hop(name: String, sx: float, sy: float, d: float, jumps: Array, djs: Array, tx0: float, tx1: float, ty: float, needs: int) -> Array:
	var r := []
	for p in [0, 1, 2]:
		r.append(await search(name, sx, sy, d, jumps, djs, p, tx0, tx1, ty))
	if needs < 0:
		return [r[0]["hits"] + r[1]["hits"] + r[2]["hits"], 0.0, {}, 0, r[0]["total"]]
	var others := [0, 1, 2].filter(func(p): return p != needs)
	var none_else: bool = others.all(func(p): return r[p]["hits"] == 0)
	note("LAB %s: needs %s, impossible without it" % [name, ["plain", "Surge", "Spring"][needs]], r[needs]["hits"] > 0 and none_else, "hits plain %d / Surge %d / Spring %d of %d" % [r[0]["hits"], r[1]["hits"], r[2]["hits"], r[0]["total"]])
	return [r[0]["rise"], r[2]["rise"], r[needs]["best"], r[needs]["hits"], r[needs]["total"]]


# ---- PLAY ------------------------------------------------------------------

func _hop(name: String, tx0: float, tx1: float, ty: float) -> bool:
	var p: Dictionary = _hops[name]
	await attempt(0.0, 0.0, 1.0, p["jump_x"], p["dj"], 0, false)
	var ok := landed(tx0, tx1, ty)
	print("   hop %s: %s at x=%.0f y=%.0f (jump_x %.0f, dj %d, power left %.1f s)" % [name, "landed" if ok else "MISSED", x(), y(), p["jump_x"], p["dj"], gs().power_time])
	return ok


func _beat_arrival() -> void:
	note("A arrives in the yard, on the floor, control at once", absf(x() - 112.0) < 8.0 and cat.is_on_floor() and cat.can_move and absf(y() - G) < 3.0, "x=%.0f y=%.0f" % [x(), y()])
	note("A the mind carried over from Room 2, no power, no shockwave", gs().intelligence and gs().power == 0 and not gs().shockwave_unlocked)
	var save: Dictionary = ss().read_save()
	note("A auto-saved on arrival with the mind and no shockwave", save.get("scene", "") == "res://scenes/levels/room3.tscn" and save.get("abilities", {}).get("mind", false) and not save.get("abilities", {}).get("shockwave", true), str(save.get("abilities", {})))
	note("A the augments show without the reveal, HUD shown", cat.get_node_or_null("Sprite/Augments") != null and cat.get_node("Sprite/Augments").get("shown") and (node("Hud") as CanvasLayer).visible)
	var rain := node("RainNear")
	var far := node("RainFar")
	note("A real RainFX, lighter than Room 2, following the camera in both axes", rain != null and far != null and rain.get("density") < 38.0 and far.get("density") < 45.0 and rain.get_node("Drops").emitting and absf(rain.global_position.x - cat.camera.get_screen_center_position().x) < 2.0 and absf(rain.global_position.y - (cat.camera.get_screen_center_position().y - 190.0)) < 2.0, "density %.0f / %.0f (Room 2: 38 / 45)" % [rain.get("density") if rain else -1.0, far.get("density") if far else -1.0])
	note("A skyline backdrop, the suburbs fade layer, lamps on poles", node("Exterior") != null and node("Suburbs") != null and room.find_children("*", "WarningLight", true, false).size() >= 15)
	await wait_lines("stacks_arrival", 2)
	note("A arrival monologue, two lines", lines_of("stacks_arrival") == ["The rain's easing up.", "From up here I can see the whole district... and not one person. Just machines, working."], str(lines_of("stacks_arrival")))
	# The shockwave must not exist yet: double-jumping at the crates breaks nothing.
	var crates: int = room.call("crates_left")
	var sx := x()
	teleport(CRATES_X - 40.0, S3)
	await ticks(10)
	for k in 3:
		hold("jump", true)
		await ticks(8)
		hold("jump", false)
		await ticks(1)
		hold("jump", true)
		await ticks(30)
		hold("jump", false)
		await ticks(50)
	note("A before the conduit the crates cannot be broken, double jumps and all", room.call("crates_left") == crates and crates == 6 and not gs().shockwave_unlocked and not cat.pounding, "%d of %d crates, shockwave %s" % [room.call("crates_left"), crates, gs().shockwave_unlocked])
	mono().reset()
	_lines.clear()
	teleport(sx, G)
	await ticks(10)
	# The walker: a plain stomp bounces, nothing more.
	var bot = node("Bot1")
	var hp0: int = gs().health
	teleport(bot.global_position.x, bot.global_position.y - 90.0)
	var bounced := false
	for i in 40:
		await ticks(1)
		bounced = bounced or cat.velocity.y < -300.0
	note("A stomping the first walker bounces and does no damage", bounced and bot.state == 0 and bot.stomps == 0 and gs().health == hp0, "bounced %s state %d stomps %d hp %d bot (%.0f,%.0f) cat (%.0f,%.0f)" % [bounced, bot.state, bot.stomps, gs().health, bot.global_position.x, bot.global_position.y, x(), y()])
	teleport(112.0, G)
	await ticks(10)
	var ok := await run_to(980.0)
	note("A crossed the arrival yard past the walker and the crates", ok and not cat.dead and gs().health == hp0, "x=%.0f hp %d" % [x(), gs().health])
	mark("arrival")


func _beat_spring_discovery() -> void:
	var pad := node("PadSpring1") as Area2D
	note("B1 the Spring pad is at the foot of the wall", pad != null and absf(pad.global_position.x - (WALL1 - 16.0)) < 2.0, "pad x=%.0f, wall face x=%.0f" % [pad.global_position.x if pad else -1.0, WALL1])
	var p: Dictionary = _hops["H1"]
	var power0: int = gs().power
	# Real run: walk up (over the pad), jump, double jump, onto the shed roof.
	await attempt(0.0, 0.0, 1.0, p["jump_x"], p["dj"], 0, false)
	note("B1 the pad grants Spring (a pad, nothing else); the emitters go green", power0 == 0 and _grants.size() == 1 and _grants[0] == [2, true] and close(aug_color(), Color(0.2, 1.0, 0.5), 0.1), "grants %s, emitter %s" % [str(_grants), str(aug_color())])
	note("B1 with Spring the double jump climbs the 6-tile wall onto the shed roof", landed(1100.0, 1700.0, S1), "x=%.0f y=%.0f" % [x(), y()])
	await wait_lines("spring_first", 2)
	note("B1 the monologue fires on the first use", lines_of("spring_first") == ["Up! Higher than any cat should go.", "Green this time. Each pad wakes a different part of me."], str(lines_of("spring_first")))
	note("B1 the power is timed (10 s)", absf(gs().power_duration - 10.0) < 0.01 and gs().power_time > 5.0, "%.1f s left" % gs().power_time)
	mark("B1 discovery")


func _beat_spring_use() -> void:
	# Walk over checkpoint A (col 36) and the second pad (col 41), then chain the two ledges inside one charge.
	await go_to(1168.0, 8.0)
	await ticks(6)
	note("B2 checkpoint A saves on the shed roof", ss().session_checkpoint == "cp_a", str(ss().session_checkpoint))
	var grants0 := _grants.size()
	await go_to(1328.0, 8.0)
	await ticks(6)
	note("B2 the second Spring pad refreshes the charge to 10 s", _grants.size() == grants0 + 1 and gs().power == 2 and gs().power_time > 9.5, "%.1f s" % gs().power_time)
	var t0 := _frames
	var ok2 := await _hop("H2", 1450.0, 1625.0, S2)
	var ok3: bool = ok2 and await _hop("H3", 1735.0, 2100.0, S3)
	var secs := (_frames - t0) / 60.0
	var left: float = gs().power_time
	if not ok2 or not ok3:
		_retries += 1
		teleport(1750.0, S3)
		await ticks(10)
	note("B2 the chain: shed roof -> floating ledge -> long roof in one charge", ok2 and ok3, "%.1f s of the 10 s, %.1f s of Spring left" % [secs, left])
	measure("chain of two Spring jumps", "%.1f s from the pad; %.1f s of the charge to spare" % [secs, left])
	mark("B2 chain")
	await run_to(1900.0)
	await ticks(10)
	note("B2 checkpoint B saves on the long roof", ss().session_checkpoint == "cp_b", str(ss().session_checkpoint))
	gs().clear_power()


func _beat_conduit() -> void:
	note("C the shockwave is still locked on the way to the conduit", not gs().shockwave_unlocked)
	var conduit := node("Conduit")
	var flashed := false
	var held := false
	var flare := 0.0
	dir(1.0)
	var n := 0
	while x() < CONDUIT_X + 80.0 and n < 900:
		await ticks(1)
		n += 1
		if conduit.get("has_fired"):
			held = held or not cat.can_move
			if conduit.get_children().any(func(c): return c is CanvasLayer):
				flashed = true
			var aug := cat.get_node_or_null("Sprite/Augments")
			flare = maxf(flare, aug.get("_flare") if aug else 0.0)
	stop()
	note("C walking over the sparking conduit is unavoidable and unlocks the shockwave", conduit.get("has_fired") and gs().shockwave_unlocked, "x=%.0f" % x())
	note("C ...with the augments flaring, a screen flash and the cat held a moment", flashed and held and flare > 0.5, "flash %s held %s flare %.2f" % [flashed, held, flare])
	note("C ...harmless: no damage, control returns", gs().health == 3 and cat.can_move, "hp %d" % gs().health)
	var unlocks: Array = room.get("shock_unlocks")
	note("C the unlock happened at the conduit (audit hook)", unlocks.size() == 1 and unlocks[0][2] and absf(unlocks[0][0] - CONDUIT_X) < 60.0, str(unlocks))
	await wait_lines("conduit", 2)
	note("C the conduit monologue (ShockLineTrigger) plays after it", lines_of("conduit") == ["Ow- no. Not pain. The machines in me... drank it.", "Something new. When I jump twice, the air itself pushes out."], str(lines_of("conduit")))
	var save: Dictionary = ss().read_save()
	note("C the auto-save from checkpoint B still says shockwave locked (it unlocks only here)", not save.get("abilities", {}).get("shockwave", true), str(save.get("abilities", {})))
	mark("C conduit")


func _double_jump_burst() -> void:
	hold("jump", true)
	await ticks(8)
	hold("jump", false)
	await ticks(1)
	hold("jump", true)
	await ticks(6)
	hold("jump", false)


func _beat_shockwave() -> void:
	# --- the crates ---
	await go_to(CRATES_X - 40.0, 6.0)
	var n := 0
	while room.call("crates_left") > 0 and n < 5:
		await _double_jump_burst()
		await ticks(40)
		dir(1.0)
		await ticks(25)
		stop()
		await ticks(5)
		n += 1
	note("E1 a double jump (the shockwave) breaks the crate stack", room.call("crates_left") == 0, "%d bursts" % n)
	await wait_lines("shock_first", 1)
	note("E1 the monologue after the first crate break", lines_of("shock_first") == ["Okay. That's... a lot of power for a house cat."], str(lines_of("shock_first")))
	# --- the patrol bot ---
	await run_to(2640.0)
	var bot := node("StackBot")
	var hp0: int = gs().health
	n = 0
	while n < 900 and bot.state != 1:
		stop()
		if absf(bot.global_position.x - x()) < 70.0 and cat.is_on_floor():
			await _double_jump_burst()
			await ticks(2)
		else:
			await ticks(1)
		n += 1
	note("E2 the patrol bot in the corridor is stunned by the shockwave", bot.state == 1, "bot x=%.0f cat x=%.0f" % [bot.global_position.x, x()])
	var t0 := _frames
	var ok := await run_to(3050.0)
	var secs := (_frames - t0) / 60.0
	note("E2 ...and the cat passes it unhurt", ok and gs().health == hp0 and not cat.dead, "%.1f s of the %.1f s stun, hp %d" % [secs, bot.get("stun_time"), gs().health])
	# --- the switch and the shutter ---
	var shutter := node("GalleryShutter")
	var sw := node("ShockSwitch")
	await go_to(GATE_X - 30.0, 6.0)
	dir(1.0)
	await ticks(60)
	stop()
	note("E3 the shutter is shut: the cat cannot pass it", not shutter.get("open") and x() < GATE_X - 8.0 and not sw.get("active"), "x=%.0f" % x())
	await go_to(SWITCH_X - 40.0, 6.0)
	n = 0
	while not sw.get("active") and n < 4:
		await _double_jump_burst()
		await ticks(30)
		n += 1
	note("E3 a double jump near the switch flips it and the shutter rolls up", sw.get("active") and shutter.get("open"), "%d bursts" % n)
	var t1 := _frames
	ok = await run_to(GATE_X + 30.0)
	var t_pass := (_frames - t1) / 60.0
	note("E3 the cat gets through the shutter inside the 6 s window", ok and sw.get("active"), "%.1f s after the burst, %.1f s of 6 left" % [t_pass, sw.get("_left")])
	mark("E shockwave")


func _beat_mirror() -> void:
	var bot := node("MirrorBot")
	var plate := node("BayPlate")
	var shutter := node("BayShutter")
	note("F the loader bot is dormant before the cat arrives", not bot.get("awake") and absf(bot.get("velocity").x) < 1.0)
	await go_to(BAY_L - 64.0, 6.0)
	await ticks(10)
	note("F ...and stays dormant outside its wake range", not bot.get("awake") and absf(bot.get("velocity").x) < 1.0, "cat x=%.0f, bot x=%.0f" % [x(), bot.global_position.x])
	gs().intelligence = false
	await go_to(BAY_L - 20.0, 6.0)
	await ticks(30)
	note("F ...and a cat whose mind is not awake does not wake it (only the augmented one)", not bot.get("awake"))
	gs().intelligence = true
	var x0: float = bot.global_position.x
	dir(1.0)
	var n := 0
	while not bot.get("awake") and n < 200:
		await ticks(1)
		n += 1
	stop()
	var cx_wake := x()
	note("F checkpoint at the bay mouth saves", ss().session_checkpoint == "cp_bay", str(ss().session_checkpoint))
	note("F the bot wakes as the augmented cat steps onto the catwalk", bot.get("awake"), "cat x=%.0f, bot x=%.0f" % [cx_wake, bot.global_position.x])
	# Mirror: the bot moves when the cat moves, the same way, the same amount.
	var bx0: float = bot.global_position.x
	var cx0 := x()
	await run_to(cx0 + 200.0)
	await ticks(30)
	var dbx: float = bot.global_position.x - bx0
	var dcx := x() - cx0
	await wait_lines("mirror_bot", 2)
	note("F the mirror monologue plays (a trigger at the catwalk)", lines_of("mirror_bot") == ["It's copying me. Every step.", "It thinks I'm in charge. Maybe the goo made me something they recognise."], str(lines_of("mirror_bot")))
	note("F the bot mirrors the cat's steps: same direction, same distance", absf(dbx - dcx) < 0.1 * dcx and dbx > 150.0, "cat moved %.0f px, bot %.0f px" % [dcx, dbx])
	note("F ...on its own track under the catwalk, off the cat's path", absf(bot.global_position.y - BAY_Y) < 3.0 and not plate.get("active"), "bot y=%.0f (bay floor %.0f)" % [bot.global_position.y, BAY_Y])
	# Walk back: it follows left. It never leaves the bay and the shutter stays shut.
	await run_to(cx_wake, -1.0)
	await ticks(30)
	note("F walking back brings it back (nothing is lost)", bot.global_position.x < bx0 + 40.0 and not plate.get("active") and not shutter.get("open"), "bot x=%.0f (start %.0f)" % [bot.global_position.x, x0])
	# The extreme: all the way back to the shut shutter. The bot is back near the start of its track; still solvable.
	await run_to(GATE_X - 12.0, -1.0)
	await ticks(30)
	note("F walking all the way back to the shutter leaves the bot on its track, off the plate", bot.get("global_position").x < x0 + 40.0 and absf(bot.global_position.y - BAY_Y) < 3.0 and not plate.get("active"), "bot x=%.0f, cat x=%.0f" % [bot.global_position.x, x()])
	# The solve: walk right until it is pinned on the plate.
	var t0 := _frames
	n = 0
	dir(1.0)
	while not plate.get("active") and n < 1500:
		await ticks(1)
		n += 1
	var cat_at := x()
	stop()
	note("F the bot ends on the pressure plate at the end of its track and the plate holds", plate.get("active"), "cat x=%.0f, bot x=%.0f, %.1f s" % [cat_at, bot.global_position.x, (_frames - t0) / 60.0])
	await ticks(40)
	note("F the way opens: the shutter at the end of the catwalk rolls up", shutter.get("open") and cat_at < BAY_GATE_X - 40.0, "shutter open %s, cat is %.0f px before it" % [shutter.get("open"), BAY_GATE_X - cat_at])
	# The plate holds while the cat keeps walking (the bot is pinned against the end of its track).
	var ok := await run_to(BAY_GATE_X + 90.0)
	note("F the cat walks on through and the plate keeps holding", ok and plate.get("active") and shutter.get("open"), "x=%.0f bot x=%.0f" % [x(), bot.global_position.x])
	measure("mirror puzzle", "the bot's track is %.0f px from its start to the plate; a cat from the wake point walks %.0f px" % [bot.global_position.x - x0, cat_at - cx_wake])
	mark("F mirror")


func _beat_combine() -> void:
	await run_to(4240.0)
	await ticks(10)
	note("G checkpoint C saves", ss().session_checkpoint == "cp_c", str(ss().session_checkpoint))
	var grants0 := _grants.size()
	var ok := await _hop("H4", 4430.0, 4660.0, S4)
	note("G Spring (the foot-of-tower pad) climbs the tower: the 6-tile wall", ok and _grants.size() >= grants0 + 1 and _grants[grants0] == [2, true], "grants %s" % str(_grants.slice(grants0)))
	await go_to(4528.0, 6.0)
	await ticks(40)
	note("G the Surge pad on top replaces Spring: the two powers in sequence", gs().power == 1 and _grants.size() == grants0 + 2 and _grants[-1] == [1, true] and close(aug_color(), Color(0.16, 0.42, 1.0), 0.1), "power %d, grants %s, emitter %s" % [gs().power, str(_grants.slice(grants0)), str(aug_color())])
	var t0 := _frames
	ok = await _hop("H5", 4995.0, 5400.0, S4)
	note("G Surge's double jump crosses the ten-tile gap onto the exit roof", ok, "%.1f s from the pad" % ((_frames - t0) / 60.0))
	await ticks(10)
	await go_to(5056.0, 6.0)
	await ticks(10)
	note("G checkpoint D saves on the exit roof", ss().session_checkpoint == "cp_d", str(ss().session_checkpoint))
	await run_to(5150.0)
	await wait_lines("stacks_exit", 2)
	note("G the exit monologue (suburbs, home) plays", lines_of("stacks_exit") == ["There, past the fences. Trees. Rooftops. Little lights in windows.", "Home is that way. I can almost smell it."], str(lines_of("stacks_exit")))
	mark("G combine")


func _beat_exit() -> void:
	var old := room
	dir(1.0)
	var n := 0
	while current_scene == old and n < 900:
		await ticks(1)
		n += 1
	stop()
	await ticks(exit_settle)
	var next := current_scene
	note("H the exit leads to Room 4", next != null and next.scene_file_path == "res://scenes/levels/room4.tscn", str(next.scene_file_path if next else "?"))
	var save: Dictionary = ss().read_save()
	note("H auto-saved in Room 4 with the mind and the shockwave", save.get("scene", "") == "res://scenes/levels/room4.tscn" and save.get("abilities", {}).get("mind", false) and save.get("abilities", {}).get("shockwave", false), str(save.get("abilities", {})))
	mark("H exit")
