## Drives the real Cat through every beat of Room 3, "The Stacks", with scripted
## input (Input.action_press, the same path a keyboard takes), in the real scene
## with the real physics.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/room3_playthrough.gd
##
## Two phases. LAB: a throwaway copy of the room; every Spring wall (the shed, the two chained
## ledges, both pits of the underfloor corridor, the vent tower's pillar, the exit tower and the
## exit pit) is searched exhaustively over takeoff positions and double-jump timings, with plain,
## Surge and Spring (pads made inert so the trial power is the only one): this proves where a
## power is REQUIRED (no trial succeeds without it) and finds a robust set of parameters for
## each hop. PLAY: a fresh room, one continuous run from the arrival to the exit with those
## parameters: the Spring wall, the chain up the ledges inside one 10 s charge; the underfloor
## corridor (an electric strip, two ceiling crawlers, a moving platform over a pit, a hopper,
## three falling platforms over a pit, the pits' Spring pads, the lift); the conduit (the
## shockwave unlocks there and only there), the crates, the patrol bot, the shock switch and
## shutter; the light well's girder ladder; the roof (the cracked wall and its crawlspace, the
## turret the shockwave stuns, the barrel chain that opens the sealed door, the vent tower with
## its Spring pillar, steam, falling platform, flame vent, the golden bone and the memory
## fragment, the skywalk drop); the roof's patrol bot; the mirror bot and its plate (also walked
## back and forth: recoverable); the exit tower, the falling platforms over the exit pit, the
## exit to the world map. Asserts that only Spring is ever granted (never Phase or Impact; Surge
## is not used here), only from pads. Prints MEASURE lines with the clearances. Exit code 1 if
## any check fails. Deletes user://save.json (use XDG_DATA_HOME to keep your own).
##
## Developing a beat: START=<beat> skips ahead (teleports there with the state that beat needs):
## corridor, conduit, shockwave, roof, vent, bay, tower.
extends SceneTree

const HumanSweep := preload("res://tools/audit/human_sweep.gd")
const G := 1408.0       ## yard floor y (row 44)
const R1 := 1216.0      ## shed roof (row 38)
const R2 := 1024.0      ## floating ledge, the pit floors (row 32)
const R3 := 832.0       ## long roof, the corridor floor (row 26)
const R4 := 640.0       ## the gallery floor (row 20)
const R5 := 448.0       ## the roof, the bay deck (row 14)
const R6 := 256.0       ## the tower tops, the exit roof (row 8)
const BAY_Y := 576.0    ## the loader bot's track (row 18)
const DECK_Y := 128.0   ## the crane deck (row 4: girders)
const WALL1 := 1088.0   ## face of the shed (col 34)
const STRIP_X0 := 1888.0
const STRIP_X1 := 1984.0
const PIT1_L := 2720.0
const PIT1_FACE := 2976.0
const PIT2_L := 3264.0
const PIT2_FACE := 3520.0
const LIFT_X := 3776.0
const CONDUIT_X := 3536.0
const CRATES_E := 3296.0
const SWITCH_X := 2512.0
const GATE_X := 2416.0
const PUMP_X := 2432.0
const BARREL_X := 2976.0
const DOOR_X := 3088.0
const VENT_PAD_X := 3184.0
const BAY_L := 3840.0
const BAY_GATE_X := 4656.0
const TOWER3_FACE := 4864.0
const XPIT_L := 5024.0
const XPIT_FACE := 5280.0

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
		var near := []
		for g in ["enemy", "kit_projectile", "kit_hazard"]:
			for b in get_nodes_in_group(g):
				if b.global_position.distance_to(cat.global_position) < 140.0:
					near.append("%s %s" % [b.name, str(b.global_position.round())])
		print("   (hurt at x=%.0f y=%.0f frame %d; near %s)" % [x(), y(), _frames, str(near)]))
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



## Floor `ahead` px in front of the feet (within 70 px below)?
func floor_ahead(d: float, ahead := 22.0) -> bool:
	return ray(cat.global_position + Vector2(d * ahead, -2), cat.global_position + Vector2(d * ahead, 70))


func threatening(b: Node) -> bool:
	if b.get("life") != null:
		return int(b.get("life")) == 0
	if b.get("state") != null:
		return int(b.get("state")) == 0
	return true


## A reactive runner: hold a direction, hop walls, walkers, bolts and (gaps) the edges of pits
## with a single jump. Returns whether `target` was reached.
func run_to(target: float, d := 1.0, limit := 1800, gaps := false) -> bool:
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
			var threat := false
			for b in get_nodes_in_group("enemy"):
				var dd: Vector2 = b.global_position - cat.global_position
				if dd.x * d > 40.0 and dd.x * d < 92.0 and absf(dd.y) < 30.0 and threatening(b):
					threat = true
			for p in get_nodes_in_group("kit_projectile"):
				var dp: Vector2 = p.global_position - cat.global_position
				if dp.x * d > 0.0 and dp.x * d < 80.0 and absf(dp.y) < 40.0:
					threat = true
			var edge := gaps and not floor_ahead(d)
			if wall or threat or edge:
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


## Wait (standing still) until `cond`, hopping over anything that rolls or walks at the cat.
func wait_until(cond: Callable, limit := 1500, evade := false) -> bool:
	var n := 0
	while not cond.call() and n < limit and not cat.dead and current_scene == room:
		if evade and cat.is_on_floor():
			for b in get_nodes_in_group("enemy"):
				var dd: Vector2 = b.global_position - cat.global_position
				if absf(dd.x) < 62.0 and absf(dd.y) < 26.0 and threatening(b):
					hold("jump", true)
					await ticks(18)
					hold("jump", false)
					break
		await ticks(1)
		n += 1
	return cond.call()


## A timed hazard (KitHazard) at the start of its idle phase: the longest safe window.
func idle_start(h: Node) -> bool:
	return int(h.get("phase")) == 0 and float(h.get("phase_time")) < 0.25


func lift_at_bottom(lift: Node) -> bool:
	return lift.global_position.y >= R3 - 6.0


func lift_at_top(lift: Node) -> bool:
	return lift.global_position.y <= R4 + 6.0


func coll(path: String) -> bool:
	return gs().is_collected("/root/Room3/" + path)


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
	# HOPS=<file>: the hop parameters of an earlier lab run (development: skips the search).
	var cache := OS.get_environment("HOPS")
	if cache != "" and FileAccess.file_exists(cache):
		_hops = JSON.parse_string(FileAccess.get_file_as_string(cache))
		return
	_start_room()
	await ticks(4)
	refresh()
	cat.death_y = 1e9
	var host: Object = self   # a SceneTree standalone, a Node when full_game.gd runs this as a routine
	var tree: SceneTree = host if host is SceneTree else (host as Node).get_tree()
	var bare = HumanSweep.new(tree, room, cat)   # no bot, drone or hazard moves or hurts in the lab
	await bare.prepare()
	await _lab()
	room.queue_free()
	await ticks(4)
	if cache != "":
		var f := FileAccess.open(cache, FileAccess.WRITE)
		f.store_string(JSON.stringify(_hops))


func _setup(chained: bool) -> void:
	if not chained:
		if OS.get_environment("SWEEP") != "0":
			await HumanSweep.lab(self, "room3", note, "LAB ")
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
	var start := OS.get_environment("START")
	await _beat_arrival(start)
	await _after("arrival")
	await _beat_spring_discovery(start)
	await _after("spring_discovery")
	await _beat_spring_use(start)
	await _after("spring_use")
	await _beat_corridor(start)
	await _after("corridor")
	await _beat_conduit(start)
	await _after("conduit")
	await _beat_shockwave(start)
	await _after("shockwave")
	await _beat_undercroft(start)
	await _after("undercroft")
	await _beat_roof(start)
	await _after("roof")
	await _beat_vent(start)
	await _after("vent")
	await _beat_bay(start)
	await _after("mirror")
	await _beat_tower(start)
	await _after("combine")
	var violations: int = int(room.get("power_violations")) + _prior_violations
	var unlocks: Array = _prior_unlocks + room.get("shock_unlocks")
	await _beat_exit()
	await _after("exit")

	note("Z only Spring was ever granted, each from a pad, never Phase or Impact", _grants.size() >= 10 and _grants.all(func(g): return g[0] == 2 and g[1]), "%d grants: %s" % [_grants.size(), str(_grants)])
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
	var h1 := await _lab_hop("H1 ground -> shed roof (6 tiles)", 980.0, G, 1.0, jump_list(WALL1, near), djs, 1100.0, 1700.0, R1, 2)
	_hops["H1"] = h1[2]
	var h2 := await _lab_hop("H2 shed roof -> floating ledge", 1312.0, R1, 1.0, jump_list(1440.0, [-11.0, -23.0, -35.0, -51.0, -71.0, -101.0]), djs, 1450.0, 1625.0, R2, 2)
	_hops["H2"] = h2[2]
	var h3 := await _lab_hop("H3 ledge -> long roof", 1500.0, R2, 1.0, jump_list(1696.0, [-11.0, -23.0, -35.0, -51.0, -71.0]), djs, 1735.0, 2100.0, R3, 2)
	_hops["H3"] = h3[2]
	var p1 := await _lab_hop("P1 out of the first pit (6 tiles)", 2800.0, R2, 1.0, jump_list(PIT1_FACE, near), djs, 2984.0, 3240.0, R3, 2)
	_hops["P1"] = p1[2]
	var p2 := await _lab_hop("P2 out of the second pit (6 tiles)", 3360.0, R2, 1.0, jump_list(PIT2_FACE, near), djs, 3528.0, 3700.0, R3, 2)
	_hops["P2"] = p2[2]
	var hv := await _lab_hop("V the vent tower's pillar (6 tiles)", 3120.0, R5, 1.0, jump_list(3200.0, near), [-1], 3208.0, 3350.0, R6, 2)
	_hops["V"] = hv[2]
	var hx := await _lab_hop("X the exit tower (6 tiles)", 4800.0, R5, 1.0, jump_list(TOWER3_FACE, near), djs, 4872.0, 5000.0, R6, 2)
	_hops["X"] = hx[2]
	var hp := await _lab_hop("XP out of the exit pit (6 tiles)", 5160.0, R5, 1.0, jump_list(XPIT_FACE, near), djs, 5288.0, 5500.0, R6, 2)
	_hops["XP"] = hp[2]
	var u1 := await _lab_hop("U1 undercroft: west pit -> pillar (6 tiles)", 4296.0, 1216.0, 1.0, jump_list(4352.0, near), djs, 4360.0, 4470.0, R2, 2)
	_hops["U1"] = u1[2]
	var u2 := await _lab_hop("U2 undercroft: east pit -> pillar (6 tiles)", 4536.0, 1216.0, -1.0, jump_list(4480.0, [11.0, 21.0, 35.0, 59.0, 101.0]), djs, 4362.0, 4472.0, R2, 2)
	_hops["U2"] = u2[2]
	var u3 := await _lab_hop("U3 undercroft: pillar -> far landing (6 up, 2 across)", 4400.0, R2, 1.0, jump_list(4480.0, [-28.0, -20.0, -12.0, -4.0, 4.0]), djs, 4544.0, 4600.0, R3, 2)
	_hops["U3"] = u3[2]
	var u4 := await _lab_hop("U4 undercroft: pillar -> corridor (6 up, 2 across)", 4440.0, R2, -1.0, jump_list(4352.0, [4.0, 12.0, 20.0, 28.0, 36.0]), djs, 4150.0, 4278.0, R3, 2)
	_hops["U4"] = u4[2]
	measure("wall 1 (6 tiles = 192 px)", "plain best rise %.0f px (%.0f px short), Spring %.0f px (%.0f px spare)" % [h1[0], 192.0 - h1[0], h1[1], h1[1] - 192.0])
	measure("the pits and towers (6 tiles = 192 px)", "plain best rise %.0f px, Spring %.0f px" % [p1[0], p1[1]])
	# The skips that must not exist.
	var skip1 := await _lab_hop("S1 shed -> long roof direct (12 tiles)", 1650.0, R1, 1.0, jump_list(1728.0, near), djs, 1735.0, 2100.0, R3, -1)
	var skip2 := await _lab_hop("S2 long roof -> the roof past the conduit (12 tiles)", 2040.0, R3, 1.0, jump_list(2112.0, near), djs, 2112.0, 3000.0, R5, -1)
	note("LAB no skips: the 12-tile climbs are out of every power's reach (the shed to the long roof, the long roof to the roof)", skip1[0] == 0 and skip2[0] == 0, "hits %d / %d" % [skip1[0], skip2[0]])
	# Every pit has its Spring pad inside it (so a fall is never a trap), at the foot of the far wall.
	var pads_ok := true
	var where := []
	for d in [["PadSpringPit1", PIT1_L, PIT1_FACE], ["PadSpringPit2", PIT2_L, PIT2_FACE], ["PadSpringExit", XPIT_L + 32.0, XPIT_FACE]]:
		var pad := node(d[0]) as Node2D
		var inside: bool = pad != null and pad.global_position.x > d[1] and pad.global_position.x < d[2] and absf(pad.global_position.x - (d[2] - 16.0)) < 2.0 and int(pad.get("power")) == 2
		pads_ok = pads_ok and inside
		where.append("%s %s" % [d[0], str(pad.global_position.round()) if pad else "missing"])
	note("LAB each pit has a Spring pad at the foot of its far wall, inside the pit", pads_ok, "; ".join(where))
	pads_inert(false)
	gs().clear_power()
	var tiles := node("Tiles") as TileMapLayer
	var open_cells := 0
	for col in [75]:
		for r in range(14, 17):  # solid from the roof (row 14) down to the shutter opening (row 17)
			if tiles.get_cell_source_id(Vector2i(col, r)) == -1:
				open_cells += 1
	for r in range(6, 11):  # the bay gate's ceiling (row 6) down to its opening (row 11)
		if tiles.get_cell_source_id(Vector2i(145, r)) == -1:
			open_cells += 1
	note("LAB both shutters have a solid ceiling over the opening, so neither can be hopped", open_cells == 0, "%d open cells" % open_cells)


## Runs the plain, Surge and Spring searches for one hop. `needs` is the power (0..2) that
## must be the only one that works, or -1 for a hop nothing may manage.
## Returns [plain rise, Spring rise, best params, hits of the needed power, total].
func _lab_hop(name: String, sx: float, sy: float, d: float, jumps: Array, djs: Array, tx0: float, tx1: float, ty: float, needs: int, ignore := []) -> Array:
	var r := []
	for p in [0, 1, 2]:
		r.append(await search(name, sx, sy, d, jumps, djs, p, tx0, tx1, ty))
	if needs < 0:
		return [r[0]["hits"] + r[1]["hits"] + r[2]["hits"], 0.0, {}, 0, r[0]["total"]]
	var others := [0, 1, 2].filter(func(p): return p != needs and not ignore.has(p))
	var none_else: bool = others.all(func(p): return r[p]["hits"] == 0)
	note("LAB %s: needs %s, impossible without it" % [name, ["plain", "Surge", "Spring"][needs]], r[needs]["hits"] > 0 and none_else, "hits plain %d / Surge %d / Spring %d of %d" % [r[0]["hits"], r[1]["hits"], r[2]["hits"], r[0]["total"]])
	return [r[0]["rise"], r[2]["rise"], r[needs]["best"], r[needs]["hits"], r[needs]["total"]]


# ---- PLAY ------------------------------------------------------------------

func _hop(name: String, tx0: float, tx1: float, ty: float, d := 1.0) -> bool:
	var p: Dictionary = _hops[name]
	await attempt(0.0, 0.0, d, p["jump_x"], p["dj"], 0, false)
	var ok := landed(tx0, tx1, ty)
	print("   hop %s: %s at x=%.0f y=%.0f (jump_x %.0f, dj %d, power left %.1f s)" % [name, "landed" if ok else "MISSED", x(), y(), p["jump_x"], p["dj"], gs().power_time])
	return ok


const ORDER := ["arrival", "spring_discovery", "spring_use", "corridor", "conduit", "shockwave", "undercroft", "roof", "vent", "bay", "tower"]


func _skipped(start: String, beat: String) -> bool:
	return start != "" and ORDER.find(start) > ORDER.find(beat)


## Development (START=<beat>): put the cat where that beat starts, with what it would carry.
func _jump_to(start: String, beat: String, px: float, py: float, _mind := true, shock := false, cp := "") -> void:
	if start == beat:
		teleport(px, py)
		if shock:
			gs().unlock_shockwave()
		if cp != "":
			ss().session_checkpoint = cp
		await ticks(20)


func _beat_arrival(start: String) -> void:
	if _skipped(start, "arrival"):
		return
	note("A arrives in the yard, on the floor, control at once", absf(x() - 112.0) < 8.0 and cat.is_on_floor() and cat.can_move and absf(y() - G) < 3.0, "x=%.0f y=%.0f" % [x(), y()])
	note("A the mind carried over from Room 2, no power, no shockwave", gs().intelligence and gs().power == 0 and not gs().shockwave_unlocked)
	var save: Dictionary = ss().read_save()
	note("A auto-saved on arrival with the mind and no shockwave", save.get("scene", "") == "res://scenes/levels/room3.tscn" and save.get("abilities", {}).get("mind", false) and not save.get("abilities", {}).get("shockwave", true), str(save.get("abilities", {})))
	note("A the augments show without the reveal, HUD shown", cat.get_node_or_null("Sprite/Augments") != null and cat.get_node("Sprite/Augments").get("shown") and (node("Hud") as CanvasLayer).visible)
	var rain := node("RainNear")
	var far := node("RainFar")
	note("A real RainFX, lighter than Room 2, following the camera in both axes", rain != null and far != null and rain.get("density") < 38.0 and far.get("density") < 45.0 and rain.get_node("Drops").emitting and absf(rain.global_position.x - cat.camera.get_screen_center_position().x) < 2.0 and absf(rain.global_position.y - (cat.camera.get_screen_center_position().y - 190.0)) < 2.0, "density %.0f / %.0f (Room 2: 38 / 45)" % [rain.get("density") if rain else -1.0, far.get("density") if far else -1.0])
	note("A skyline backdrop, the suburbs fade layer, lamps on poles", node("Exterior") != null and node("Suburbs") != null and room.find_children("*", "WarningLight", true, false).size() >= 15)
	note("A the room is tall: the tier camera, 48 rows, 172 columns", room.get("camera_follow") == 1 and room.get("limits") == Rect2i(0, 0, 172 * 32, 48 * 32), str(room.get("limits")))
	await wait_lines("stacks_arrival", 2)
	note("A arrival monologue, two lines", lines_of("stacks_arrival") == ["The rain's easing up.", "From up here I can see the whole district... and not one person. Just machines, working."], str(lines_of("stacks_arrival")))
	# The shockwave must not exist yet: double-jumping at the crates breaks nothing.
	var crates: int = room.call("crates_left")
	var sx := x()
	teleport(CRATES_E + 44.0, R4)
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


func _beat_spring_discovery(start: String) -> void:
	if _skipped(start, "spring_discovery"):
		return
	var pad := node("PadSpring1") as Area2D
	note("B1 the Spring pad is at the foot of the wall", pad != null and absf(pad.global_position.x - (WALL1 - 16.0)) < 2.0, "pad x=%.0f, wall face x=%.0f" % [pad.global_position.x if pad else -1.0, WALL1])
	var p: Dictionary = _hops["H1"]
	var power0: int = gs().power
	# Real run: walk up (over the pad), jump, double jump, onto the shed roof.
	await attempt(0.0, 0.0, 1.0, p["jump_x"], p["dj"], 0, false)
	note("B1 the pad grants Spring (a pad, nothing else); the emitters go green", power0 == 0 and _grants.size() == 1 and _grants[0] == [2, true] and close(aug_color(), Color(0.2, 1.0, 0.5), 0.1), "grants %s, emitter %s" % [str(_grants), str(aug_color())])
	note("B1 with Spring the double jump climbs the 6-tile wall onto the shed roof", landed(1100.0, 1700.0, R1), "x=%.0f y=%.0f" % [x(), y()])
	var charge_left: float = gs().power_time   # read before the (queued) monologue is waited out
	await wait_lines("spring_first", 2)
	note("B1 the hint at the foot of the wall played on the way to the pad", lines_of("spring_hint") == ["Too high to jump... that green pad hums like a spring."], str(lines_of("spring_hint")))
	note("B1 the monologue fires on the first use", lines_of("spring_first") == ["Up! Higher than any cat should go.", "Green this time. Each pad wakes a different part of me."], str(lines_of("spring_first")))
	note("B1 the power is timed (10 s)", absf(gs().power_duration - 10.0) < 0.01 and charge_left > 5.0, "%.1f s left after the climb" % charge_left)
	mark("B1 discovery")


func _beat_spring_use(start: String) -> void:
	if _skipped(start, "spring_use"):
		return
	# Walk over checkpoint A (col 36) and the second pad (col 41), then chain the two ledges inside one charge.
	await go_to(1168.0, 8.0)
	await ticks(6)
	note("B2 checkpoint A saves on the shed roof", ss().session_checkpoint == "cp_a", str(ss().session_checkpoint))
	var grants0 := _grants.size()
	await go_to(1328.0, 8.0)
	await ticks(6)
	note("B2 the second Spring pad refreshes the charge to 10 s", _grants.size() == grants0 + 1 and gs().power == 2 and gs().power_time > 9.5, "%.1f s" % gs().power_time)
	var t0 := _frames
	var ok2 := await _hop("H2", 1450.0, 1625.0, R2)
	var ok3: bool = ok2 and await _hop("H3", 1735.0, 2100.0, R3)
	var secs := (_frames - t0) / 60.0
	var left: float = gs().power_time
	if not ok2 or not ok3:
		_retries += 1
		teleport(1750.0, R3)
		await ticks(10)
	note("B2 the chain: shed roof -> floating ledge -> long roof in one charge", ok2 and ok3, "%.1f s of the 10 s, %.1f s of Spring left" % [secs, left])
	measure("chain of two Spring jumps", "%.1f s from the pad; %.1f s of the charge to spare" % [secs, left])
	mark("B2 chain")
	await run_to(1860.0)
	await ticks(10)
	note("B2 checkpoint B saves on the long roof", ss().session_checkpoint == "cp_b", str(ss().session_checkpoint))
	gs().clear_power()


## The underfloor corridor: a strip of electric floor, two crawlers on the underside of the girders
## above, a moving platform over a pit, a hopper, falling platforms over a pit, the lift.
func _beat_corridor(start: String) -> void:
	if _skipped(start, "corridor"):
		return
	await _jump_to(start, "corridor", 1860.0, R3, true, false, "cp_b")
	var hp0: int = gs().health
	# --- the electric strip on the long roof ---
	var strip := node("StripFloor")
	var t_warn := 0.0
	var n := 0
	while not idle_start(strip) and n < 900:
		t_warn = maxf(t_warn, float(strip.get("last_warn")))
		await ticks(1)
		n += 1
	var ok := await run_to(STRIP_X1 + 40.0)
	note("C1 the electric strip on the long roof warns (>= 0.4 s) and is crossed in its idle phase, unhurt", ok and gs().health == hp0 and float(strip.get("last_warn")) >= 0.4, "warn %.2f s, hp %d" % [float(strip.get("last_warn")), gs().health])
	# --- into the corridor, under the crawlers ---
	await run_to(2150.0)
	await wait_lines("stacks_lift", 0)
	var crawlers: Array = room.find_children("Crawler*", "", true, false)
	note("C2 two crawlers hang on the underside of the girders above the corridor", crawlers.size() == 2 and crawlers.all(func(c): return absf(c.global_position.y - 704.0) < 3.0), "%d crawlers, y %s" % [crawlers.size(), str(crawlers.map(func(c): return c.global_position.y))])
	var hp1: int = gs().health
	ok = await run_to(PIT1_L - 40.0, 1.0, 1800, true)
	var dropped: bool = crawlers.any(func(c): return is_instance_valid(c) and int(c.get("mode")) >= 2)
	var tell: float = 0.0
	for c in crawlers:
		tell = maxf(tell, float(c.get("last_telegraph")))
	await wait_until(func(): return not crawlers.any(func(c): return is_instance_valid(c) and int(c.get("mode")) == 3 and absf(c.global_position.x - x()) < 140.0), 600, true)
	note("C2 a crawler drops from the ceiling after a telegraph (>= 0.4 s) and the cat gets by unhurt", ok and dropped and tell >= 0.4 and gs().health == hp1, "dropped %s, tell %.2f s, hp %d -> %d, x=%.0f" % [dropped, tell, hp1, gs().health, x()])
	# --- pit 1: the moving platform ---
	var mv := node("MoverPit1")
	var left_x := PIT1_L + 48.0
	var travel: float = mv.get("travel")
	await wait_until(func(): return mv.global_position.x < left_x + 12.0 and mv.global_position.x > left_x - 4.0, 900, true)
	var t_board := _frames
	dir(1.0)
	n = 0
	while x() < PIT1_L + 40.0 and n < 120:
		await ticks(1)
		n += 1
	stop()
	var rode_from := x()
	var on_platform := cat.is_on_floor() and absf(y() - R3) < 4.0 and x() > PIT1_L
	await wait_until(func(): return mv.global_position.x > left_x + travel - 12.0, 900)
	var rode_to := x()
	note("C3 the moving platform carries the cat across the 8-tile pit", on_platform and rode_to - rode_from > travel - 40.0 and absf(y() - R3) < 4.0, "boarded at x=%.0f, now x=%.0f y=%.0f (travel %.0f)" % [rode_from, rode_to, y(), travel])
	ok = await run_to(PIT1_FACE + 40.0)
	note("C3 ...and steps off on the far side", ok and cat.is_on_floor() and absf(y() - R3) < 4.0 and gs().health == hp1, "x=%.0f hp %d" % [x(), gs().health])
	measure("moving platform", "%.1f s from boarding to the far side" % ((_frames - t_board) / 60.0))
	# Fell in? The pit has its own Spring pad: put the cat on the pit floor and climb out. The
	# corridor's dropped crawlers may have rolled into the pit by now (it depends on the pace of the
	# run); this test is about the pad, so clear any that did.
	for k in room.get_children():
		if String(k.name).begins_with("Crawler") and k is Node2D and k.global_position.y > R3 + 64.0:
			k.queue_free()
	teleport(PIT1_L + 80.0, R2)
	await ticks(30)
	var g0 := _grants.size()
	var ok_p1 := await _hop("P1", PIT1_FACE + 8.0, 3240.0, R3)
	note("C3 a cat in the pit climbs out with the pit's own Spring pad (6 tiles)", ok_p1 and _grants.size() == g0 + 1 and _grants[-1] == [2, true], "grants %s, x=%.0f y=%.0f" % [str(_grants.slice(g0)), x(), y()])
	gs().clear_power()
	# --- the hopper ---
	var hopper := node("Hopper1")
	var hp2: int = gs().health
	ok = await run_to(3250.0, 1.0, 1800, true)
	var hopper_hops: int = int(hopper.get("hops"))
	note("C4 the hopper squats (>= 0.4 s warning), hops at the cat and is outrun or jumped", ok and gs().health >= hp2 - 1 and float(hopper.get("last_telegraph")) >= 0.4, "hops %d, tell %.2f s, hp %d -> %d, x=%.0f" % [hopper_hops, float(hopper.get("last_telegraph")), hp2, gs().health, x()])
	# --- pit 2: three falling platforms ---
	var fps: Array = room.find_children("FallPit2*", "", true, false)
	var hp3: int = gs().health
	ok = await run_to(PIT2_FACE + 40.0, 1.0, 1500, true)
	note("C5 three falling platforms carry the cat over the second pit in a run", ok and cat.is_on_floor() and absf(y() - R3) < 4.0 and gs().health == hp3, "x=%.0f y=%.0f hp %d" % [x(), y(), gs().health])
	# A cat that stands on one: it shakes (the warning), falls, and the pit's pad is the way out.
	await wait_until(func(): return fps.all(func(f): return f.get("state") == "ride"), 900)
	teleport(3392.0, R3 - 2.0)
	var t_stand := _frames
	var fell := false
	n = 0
	while n < 400 and not fell:
		await ticks(1)
		n += 1
		fell = y() > R3 + 40.0
	var fp_mid = fps[1] if fps.size() > 1 else null
	var warn: float = float(fp_mid.get("last_warn")) if fp_mid else 0.0
	note("C5 a platform stood on shakes for >= 0.4 s (0.9 here) before it drops", fell and warn >= 0.4 and (_frames - t_stand) / 60.0 >= 0.8, "fell after %.2f s, warn %.2f s" % [(_frames - t_stand) / 60.0, warn])
	await ticks(60)
	var g1 := _grants.size()
	var ok_p2 := await _hop("P2", PIT2_FACE + 8.0, 3700.0, R3)
	note("C5 ...and the second pit's Spring pad lifts the cat out (6 tiles)", ok_p2 and _grants.size() == g1 + 1 and _grants[-1] == [2, true], "x=%.0f y=%.0f" % [x(), y()])
	gs().clear_power()
	# --- the lift ---
	await run_to(3660.0)
	note("C6 checkpoint C saves east of the second pit", ss().session_checkpoint == "cp_c", str(ss().session_checkpoint))
	var lift := node("LiftC")
	await wait_lines("stacks_lift", 1, 600)
	note("C6 the lift hint plays at the foot of the shaft", lines_of("stacks_lift") == ["A lift. Slow, but it knows the way up."], str(lines_of("stacks_lift")))
	await go_to(3712.0, 6.0)
	await wait_until(func(): return lift_at_bottom(lift), 1200)
	var t_lift := _frames
	dir(1.0)
	n = 0
	while x() < LIFT_X - 8.0 and n < 120:
		await ticks(1)
		n += 1
	stop()
	var on_lift := absf(x() - LIFT_X) < 30.0
	var wait_ok := await wait_until(func(): return lift_at_top(lift), 900)
	note("C6 the lift carries the cat 6 tiles up through the gallery floor", on_lift and wait_ok and absf(y() - R4) < 8.0, "x=%.0f y=%.0f, %.1f s" % [x(), y(), (_frames - t_lift) / 60.0])
	dir(-1.0)
	n = 0
	while x() > LIFT_X - 64.0 and n < 120:
		await ticks(1)
		n += 1
	stop()
	await ticks(10)
	note("C6 and steps off west onto the gallery floor", cat.is_on_floor() and absf(y() - R4) < 4.0 and x() < LIFT_X - 32.0, "x=%.0f y=%.0f" % [x(), y()])
	note("C no damage in the whole corridor but what the hopper cost", gs().health >= hp0 - 1, "hp %d -> %d" % [hp0, gs().health])
	mark("C corridor")


func _beat_conduit(start: String) -> void:
	if _skipped(start, "conduit"):
		return
	await _jump_to(start, "conduit", 3700.0, R4, true, false, "cp_c")
	note("D the shockwave is still locked on the way to the conduit", not gs().shockwave_unlocked)
	var hp_before: int = gs().health
	var conduit := node("Conduit")
	var flashed := false
	var held := false
	var flare := 0.0
	dir(-1.0)
	var n := 0
	while x() > CONDUIT_X - 80.0 and n < 900:
		await ticks(1)
		n += 1
		if conduit.get("has_fired"):
			held = held or not cat.can_move
			if conduit.get_children().any(func(c): return c is CanvasLayer):
				flashed = true
			var aug := cat.get_node_or_null("Sprite/Augments")
			flare = maxf(flare, aug.get("_flare") if aug else 0.0)
	stop()
	note("D checkpoint D saves at the head of the gallery", ss().session_checkpoint == "cp_d", str(ss().session_checkpoint))
	note("D walking over the sparking conduit is unavoidable and unlocks the shockwave", conduit.get("has_fired") and gs().shockwave_unlocked, "x=%.0f" % x())
	note("D ...with the augments flaring, a screen flash and the cat held a moment", flashed and held and flare > 0.5, "flash %s held %s flare %.2f" % [flashed, held, flare])
	note("D ...harmless: no damage, control returns", gs().health == hp_before and cat.can_move, "hp %d -> %d" % [hp_before, gs().health])
	var unlocks: Array = room.get("shock_unlocks")
	note("D the unlock happened at the conduit (audit hook)", unlocks.size() == 1 and unlocks[0][2] and absf(unlocks[0][0] - CONDUIT_X) < 60.0, str(unlocks))
	await wait_lines("conduit", 2)
	note("D the conduit monologue (ShockLineTrigger) plays after it", lines_of("conduit") == ["Ow- no. Not pain. The machines in me... drank it.", "Something new. When I jump twice, the air itself pushes out."], str(lines_of("conduit")))
	var save: Dictionary = ss().read_save()
	note("D the auto-save from checkpoint C still says shockwave locked (it unlocks only here)", not save.get("abilities", {}).get("shockwave", true), str(save.get("abilities", {})))
	mark("D conduit")


func _double_jump_burst() -> void:
	hold("jump", true)
	await ticks(8)
	hold("jump", false)
	await ticks(1)
	hold("jump", true)
	await ticks(6)
	hold("jump", false)


func _beat_shockwave(start: String) -> void:
	if _skipped(start, "shockwave"):
		return
	await _jump_to(start, "shockwave", 3480.0, R4, true, true, "cp_d")
	# --- the crates ---
	await go_to(CRATES_E + 44.0, 6.0)
	var n := 0
	while room.call("crates_left") > 0 and n < 5:
		await _double_jump_burst()
		await ticks(40)
		dir(-1.0)
		await ticks(25)
		stop()
		await ticks(5)
		n += 1
	note("E1 a double jump (the shockwave) breaks the crate stack", room.call("crates_left") == 0, "%d bursts" % n)
	await wait_lines("shock_first", 1)
	note("E1 the monologue after the first crate break", lines_of("shock_first") == ["Okay. That's... a lot of power for a house cat."], str(lines_of("shock_first")))
	# --- the patrol bot ---
	await run_to(3070.0, -1.0)
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
	var ok := await run_to(SWITCH_X + 60.0, -1.0)
	var secs := (_frames - t0) / 60.0
	note("E2 ...and the cat passes it unhurt", ok and gs().health == hp0 and not cat.dead, "%.1f s of the %.1f s stun, hp %d" % [secs, bot.get("stun_time"), gs().health])
	# --- the switch and the shutter ---
	var shutter := node("GalleryShutter")
	var sw := node("ShockSwitch")
	await go_to(GATE_X + 30.0, 6.0)
	dir(-1.0)
	await ticks(60)
	stop()
	note("E3 the shutter is shut: the cat cannot pass it", not shutter.get("open") and x() > GATE_X + 8.0 and not sw.get("active"), "x=%.0f" % x())
	await go_to(SWITCH_X + 40.0, 6.0)
	n = 0
	while not sw.get("active") and n < 4:
		await _double_jump_burst()
		await ticks(30)
		n += 1
	note("E3 a double jump near the switch flips it and the shutter rolls up", sw.get("active") and shutter.get("open"), "%d bursts" % n)
	var t1 := _frames
	ok = await run_to(GATE_X - 30.0, -1.0)
	var t_pass := (_frames - t1) / 60.0
	note("E3 the cat gets through the shutter inside the 6 s window", ok and sw.get("active"), "%.1f s after the burst, %.1f s of 6 left" % [t_pass, sw.get("_left")])
	mark("E shockwave")


## The undercroft (optional, under the bay): ride the lift down, break the cracked wall at the foot of
## its shaft, cross the corridor (crawlers, an electric strip), the shaft with the pillar and its pads,
## the loot on the far landing, and back.
func _beat_undercroft(start: String) -> void:
	if _skipped(start, "undercroft"):
		return
	await _jump_to(start, "undercroft", 3700.0, R4, true, true, "cp_d")
	teleport(3700.0, R4)   # back through the gallery (the shutter closes behind: only the walk is skipped)
	await ticks(20)
	var lift := node("LiftC")
	var hp0: int = gs().health
	await wait_until(func(): return lift_at_top(lift), 900)
	dir(1.0)
	var n := 0
	while x() < LIFT_X - 8.0 and n < 120:
		await ticks(1)
		n += 1
	stop()
	await wait_until(func(): return lift_at_bottom(lift), 900)
	note("U1 the lift carries the cat down to the foot of its shaft", absf(y() - R3) < 8.0, "y=%.0f" % y())
	var wall := node("CrackedWall2")
	await go_to(3712.0, 6.0)
	await wait_until(func(): return lift_at_top(lift), 900)
	await go_to(3780.0, 6.0)
	n = 0
	while is_instance_valid(wall) and not wall.is_queued_for_deletion() and n < 4:
		await _double_jump_burst()
		await ticks(40)
		n += 1
	note("U1 the shockwave breaks the cracked wall at the foot of the lift shaft", not is_instance_valid(wall) or wall.is_queued_for_deletion(), "%d bursts" % n)
	var ok := await run_to(3900.0)
	note("U2 behind it a corridor under the bay: a checkpoint", ok and ss().session_checkpoint == "cp_under", str(ss().session_checkpoint))
	# --- crawlers on the ceiling and an electric strip: stun the crawlers with the shockwave, cross the strip idle ---
	var strip := node("StripUnder")
	var crawlers: Array = room.find_children("UnderCrawler*", "", true, false)
	ok = await run_to(3990.0)
	var hp1: int = gs().health
	await wait_until(func(): return idle_start(strip), 600, true)
	ok = await run_to(4180.0, 1.0, 900)
	await wait_until(func(): return not crawlers.any(func(c): return is_instance_valid(c) and int(c.get("mode")) == 3 and absf(c.global_position.x - x()) < 140.0), 600, true)
	note("U2 the strip and the crawlers are got past without a scratch", ok and gs().health >= hp1 - 1, "x=%.0f hp %d -> %d" % [x(), hp1, gs().health])
	ok = await run_to(4270.0, 1.0, 900)
	var g0 := _grants.size()   # (a landing at the pillar's far edge can already touch its east pad)
	# --- the shaft: a plain jump across the 2-tile gap, down onto the pillar ---
	hold("jump", true)
	dir(1.0)
	await ticks(6)
	hold("jump", false)
	var air_n := 0
	while air_n < 120 and (air_n < 8 or not cat.is_on_floor()):
		await ticks(1)
		air_n += 1
	stop()
	await ticks(20)
	note("U3 a plain jump over the shaft's edge lands on the pillar 6 tiles down", cat.is_on_floor() and absf(y() - R2) < 4.0 and x() > 4352.0 and x() <= 4482.0, "x=%.0f y=%.0f" % [x(), y()])
	# --- Spring pads: east, to the far landing ---
	await go_to(4400.0, 8.0)
	var ok3 := await _hop("U3", 4544.0, 4600.0, R3)
	note("U3 the pillar's east pad lifts the cat onto the far landing (6 up, 2 across)", ok3 and _grants.size() >= g0 + 1 and _grants[-1] == [2, true], "x=%.0f y=%.0f" % [x(), y()])
	gs().clear_power()
	# --- the loot, the turret ---
	var turret := node("TurretUnder")
	n = 0
	while n < 600 and not turret.is_stunned():
		stop()
		if absf(turret.global_position.x - x()) < 62.0 and cat.is_on_floor():
			await _double_jump_burst()
			await ticks(2)
		elif x() < turret.global_position.x - 80.0:
			dir(1.0)
			await ticks(1)
		else:
			await ticks(1)
		n += 1
	note("U4 the turret guarding the far landing is stunned by the shockwave", turret.is_stunned(), "x=%.0f hp %d" % [x(), gs().health])
	await go_to(4560.0, 6.0)
	await ticks(10)
	note("U4 on the far landing: two toy mice and a bell", coll("GemMouseUnder2") and coll("GemBellUnder"), "mouse2 %s bell %s" % [coll("GemMouseUnder2"), coll("GemBellUnder")])
	# --- back: the turret has woken again (stunned for 3.5 s): the shockwave once more, then a plain hop
	# down onto the pillar, the west pad, the corridor ---
	n = 0
	while n < 300 and not turret.is_stunned():
		stop()
		if absf(turret.global_position.x - x()) < 62.0 and cat.is_on_floor():
			await _double_jump_burst()
			await ticks(2)
		else:
			await ticks(1)
		n += 1
	await run_to(4500.0, -1.0, 900, true)
	await ticks(60)
	var on_pillar := cat.is_on_floor() and absf(y() - R2) < 4.0 and x() > 4352.0 and x() < 4480.0
	note("U5 back across: the cat steps off the landing onto the pillar (6 tiles down)", on_pillar or (cat.is_on_floor() and absf(y() - 1216.0) < 4.0), "x=%.0f y=%.0f" % [x(), y()])
	if not on_pillar:
		var g1 := _grants.size()
		var ok_u2 := await _hop("U2", 4362.0, 4472.0, R2, -1.0)
		note("U5 ...and a cat that fell into the east pit climbs out with its pad", ok_u2 and _grants.size() == g1 + 1, "x=%.0f y=%.0f" % [x(), y()])
		gs().clear_power()
	await go_to(4420.0, 8.0)
	gs().clear_power()
	await ticks(4)
	var g2 := _grants.size()
	var ok4 := await _hop("U4", 4150.0, 4278.0, R3, -1.0)
	if not ok4:   # a crawler ball that rolled off the corridor's edge may have hit the cat on the pillar (a hit clears the power): once more
		_retries += 1
		teleport(4420.0, R2)
		await ticks(200)
		gs().clear_power()
		ok4 = await _hop("U4", 4150.0, 4278.0, R3, -1.0)
	note("U5 the pillar's west pad lifts the cat back to the corridor (6 up, 2 across)", ok4 and _grants.size() >= g2 + 1 and _grants[-1] == [2, true], "x=%.0f y=%.0f" % [x(), y()])
	gs().clear_power()
	# A cat that fell into the west pit climbs out too.
	teleport(4300.0, 1216.0)
	await ticks(40)
	var g3 := _grants.size()
	var ok_u1 := await _hop("U1", 4360.0, 4470.0, R2)
	if not ok_u1:
		_retries += 1
		teleport(4300.0, 1216.0)
		await ticks(200)
		gs().clear_power()
		ok_u1 = await _hop("U1", 4360.0, 4470.0, R2)
	note("U5 a cat in the west pit climbs out onto the pillar with its pad (6 tiles)", ok_u1 and _grants.size() >= g3 + 1, "x=%.0f y=%.0f" % [x(), y()])
	gs().clear_power()
	teleport(3700.0, R3)   # the cat walks back to the lift and rides up
	await ticks(30)
	note("U no damage in the undercroft but what the strip, the crawlers and the turret cost", gs().health >= hp0 - 2, "hp %d -> %d" % [hp0, gs().health])
	teleport(2330.0, R4)   # ...and on to the light well, for the roof
	await ticks(20)
	mark("U undercroft")


## The light well's girder ladder (plain jumps, 2 tiles a step), then the roof: the pump house and
## its cracked wall, the turret, the barrel chain.
func _beat_roof(start: String) -> void:
	if _skipped(start, "roof"):
		return
	await _jump_to(start, "roof", 2330.0, R4, true, true, "cp_d")
	# --- the light well ---
	await go_to(2176.0, 6.0)
	hold("jump", true)
	await ticks(30)
	hold("jump", false)
	await ticks(20)
	var on_g1 := cat.is_on_floor() and absf(y() - 580.0) < 8.0
	note("F1 a plain jump from the gallery floor lands on the first girder of the light well (2 tiles)", on_g1, "x=%.0f y=%.0f" % [x(), y()])
	dir(1.0)
	hold("jump", true)
	await ticks(12)
	hold("jump", false)
	await ticks(30)
	stop()
	await ticks(20)
	var on_g2 := cat.is_on_floor() and absf(y() - 516.0) < 8.0
	note("F1 ...a second jump to the next girder (2 tiles, one-way: through it and onto it)", on_g2, "x=%.0f y=%.0f" % [x(), y()])
	await go_to(2250.0, 6.0)
	hold("jump", true)
	dir(1.0)
	await ticks(14)
	hold("jump", false)
	await ticks(40)
	stop()
	note("F1 ...and a third onto the roof: the ladder is plain movement, no power", cat.is_on_floor() and absf(y() - R5) < 6.0 and x() > 2272.0 and gs().power == 0, "x=%.0f y=%.0f" % [x(), y()])
	await run_to(2360.0)
	note("F1 checkpoint on the roof", ss().session_checkpoint == "cp_roof", str(ss().session_checkpoint))
	# --- the cracked wall of the pump house ---
	await wait_lines("stacks_crack", 1, 1200)
	note("F2 the hint at the pump house plays", lines_of("stacks_crack") == ["Cracks in that wall. My shockwave might finish it."], str(lines_of("stacks_crack")))
	var wall := node("CrackedWall1")
	await go_to(2386.0, 4.0)
	var n := 0
	while is_instance_valid(wall) and not wall.is_queued_for_deletion() and n < 4:
		await _double_jump_burst()
		await ticks(40)
		n += 1
	note("F2 the shockwave breaks the cracked wall and opens the crawlspace", not is_instance_valid(wall) or wall.is_queued_for_deletion(), "%d bursts" % n)
	hold("move_down", true)
	await go_to(2540.0, 6.0)
	hold("move_down", false)
	await ticks(10)
	note("F2 inside: a fish, a bell and a toy mouse", coll("FishCloset") and coll("GemBellCloset") and coll("GemMouseCloset"), "fish %s bell %s mouse %s" % [coll("FishCloset"), coll("GemBellCloset"), coll("GemMouseCloset")])
	await go_to(2400.0, 8.0)
	# --- the turret ---
	var turret := node("Turret1")
	var hp0: int = gs().health
	hold("jump", true)   # up the pump house (2 tiles)
	dir(1.0)
	await ticks(24)
	hold("jump", false)
	await ticks(20)
	var ok := await run_to(turret.global_position.x - 50.0)   # along its top
	n = 0
	while n < 600 and not turret.is_stunned():
		stop()
		if absf(turret.global_position.x - x()) < 62.0 and cat.is_on_floor():
			await _double_jump_burst()
			await ticks(2)
		else:
			await ticks(1)
		n += 1
	note("F3 the turret by the pump house is stunned by the shockwave", turret.is_stunned(), "turret x=%.0f cat x=%.0f hp %d -> %d" % [turret.global_position.x, x(), hp0, gs().health])
	note("F3 ...and the cat is unhurt by it", gs().health == hp0, "hp %d" % gs().health)
	ok = await run_to(2700.0)
	note("F3 the cat passes the turret", ok and not cat.dead, "x=%.0f hp %d" % [x(), gs().health])
	# --- the laser bot between the turret and the barrels: stunned by the shockwave too ---
	var rb := node("RoofBot")
	var hp1: int = gs().health
	n = 0
	while n < 900 and not rb.is_stunned():
		stop()
		if absf(rb.global_position.x - x()) < 58.0 and cat.is_on_floor():
			await _double_jump_burst()
			await ticks(2)
		elif absf(rb.global_position.x - x()) > 100.0 and rb.global_position.x > x():
			dir(1.0)
			await ticks(1)
		else:
			await ticks(1)
		n += 1
	note("F4 the laser patrol bot is stunned by the shockwave (it aims for >= 0.4 s first)", rb.is_stunned() and gs().health >= hp1 - 1, "bot x=%.0f cat x=%.0f hp %d -> %d, aim %.2f s" % [rb.global_position.x, x(), hp1, gs().health, float(rb.get("last_telegraph"))])
	ok = await run_to(2900.0)
	note("F4 ...and the cat passes it", ok and not cat.dead, "x=%.0f hp %d" % [x(), gs().health])
	mark("F roof west")


func _beat_vent(start: String) -> void:
	if _skipped(start, "vent"):
		return
	await _jump_to(start, "vent", 2880.0, R5, true, true, "cp_roof")
	# --- the barrel chain and the sealed door ---
	await wait_lines("stacks_barrels", 1, 600)
	note("G1 the hint at the sealed hatch plays", lines_of("stacks_barrels") == ["A sealed hatch, and a row of barrels. They look... touchy."], str(lines_of("stacks_barrels")))
	var door := node("BlastDoor")
	var barrels: Array = room.find_children("Barrel9*", "", true, false)
	note("G1 three explosive barrels stand in front of a blast-only wall", barrels.size() == 3 and door != null and int(door.get("kind")) == 2, "%d barrels" % barrels.size())
	await go_to(2906.0, 6.0)
	var hp0: int = gs().health
	var t_burst := _frames
	await _double_jump_burst()
	var armed: bool = barrels.any(func(b): return is_instance_valid(b) and b.get("armed"))
	note("G1 a double jump near the first barrel sets it off (a lit fuse)", armed, "barrel x=%.0f cat x=%.0f" % [barrels[0].global_position.x, x()])
	await run_to(2872.0, -1.0)   # 104 px from the first barrel (its blast reaches 84); not back into the laser bot's lane
	var fuse: float = float(barrels[0].get("fuse")) if is_instance_valid(barrels[0]) else 1.0
	var door_gone := await wait_until(func(): return not is_instance_valid(door) or door.is_queued_for_deletion(), 600)
	note("G1 the chain reaction blows the door open (a blast-only wall), and the cat, warned by the fuse, is unhurt", door_gone and gs().health == hp0, "fuse %.1f s, hp %d -> %d, %.1f s after the burst" % [fuse, hp0, gs().health, (_frames - t_burst) / 60.0])
	await ticks(60)
	# --- the vent tower: Spring up the pillar ---
	await wait_lines("spring_hint_tower", 0)
	var ok := await run_to(DOOR_X + 20.0)
	await ticks(10)
	var g0 := _grants.size()
	await wait_until(func(): return true, 2)
	ok = await _hop("V", 3208.0, 3350.0, R6)
	note("G2 the pad inside the tower lifts the cat onto the pillar (6 tiles, Spring)", ok and _grants.size() == g0 + 1 and _grants[-1] == [2, true], "grants %s x=%.0f y=%.0f" % [str(_grants.slice(g0)), x(), y()])
	# --- the steam vent on the pillar top ---
	var vent := node("VentSteam1")
	var hp1: int = gs().health
	if x() < 3262.0:
		await go_to(3250.0, 6.0)
		await wait_until(func(): return idle_start(vent), 600)
		await go_to(3328.0, 6.0)
	else:
		await go_to(3328.0, 6.0)
	note("G2 the steam vent warns (>= 0.4 s) and is crossed in its idle phase, unhurt", gs().health == hp1 and float(vent.get("last_warn")) >= 0.4, "warn %.2f s, hp %d" % [float(vent.get("last_warn")), gs().health])
	# --- the falling platform and the crane deck (plain jumps: the charge is let run out) ---
	gs().clear_power()
	hold("jump", true)
	await ticks(30)
	hold("jump", false)
	await ticks(10)
	var y_fp := y()
	var on_fp := absf(y_fp - 192.0) < 10.0
	hold("jump", true)
	await ticks(30)
	hold("jump", false)
	await ticks(20)
	note("G3 straight up: the falling platform, then the crane deck (two plain jumps of 2 tiles)", on_fp and cat.is_on_floor() and absf(y() - (DECK_Y + 4.0)) < 8.0, "on platform %s (y=%.0f), now x=%.0f y=%.0f" % [on_fp, y_fp, x(), y()])
	await wait_lines("stacks_vent_top", 1, 600)
	# --- the flame vent, the bone and the memory fragment ---
	var flame := node("VentFlame1")
	var hp2: int = gs().health
	await wait_until(func(): return idle_start(flame), 900)
	var ok2 := await run_to(3170.0, -1.0)
	note("G4 the flame vent warns (>= 0.4 s) and is crossed in its idle phase, unhurt", ok2 and gs().health == hp2 and float(flame.get("last_warn")) >= 0.4, "warn %.2f s, hp %d" % [float(flame.get("last_warn")), gs().health])
	await go_to(3120.0, 6.0)
	await ticks(10)
	note("G4 the golden fish bone and the memory fragment are on the crane deck", coll("GemBoneStacks") and coll("MemoryStacks"), "bone %s memory %s" % [coll("GemBoneStacks"), coll("MemoryStacks")])
	await wait_until(func(): return not mono().memory_active, 1800)
	note("G4 the memory plays (memory_stacks), then the music returns", mono().history.any(func(l): return String(l[0]) == "memory_stacks"), str(mono().history.map(func(l): return l[0]).slice(-3)))
	# Back across the flame, along the skywalk and off the end: a ten-tile drop onto the roof.
	await wait_until(func(): return idle_start(flame), 900)
	ok2 = await run_to(3600.0)
	dir(1.0)
	var n := 0
	while not (cat.is_on_floor() and y() > 400.0) and n < 400:
		await ticks(1)
		n += 1
	stop()
	note("G5 off the end of the skywalk the cat drops ten tiles onto the roof and walks away unhurt", cat.is_on_floor() and absf(y() - R5) < 6.0 and gs().health == hp2, "x=%.0f y=%.0f hp %d" % [x(), y(), gs().health])
	mark("G vent tower")


func _beat_bay(start: String) -> void:
	if _skipped(start, "bay"):
		return
	await _jump_to(start, "bay", 3640.0, R5, true, true, "cp_roof")
	var ok := await run_to(BAY_L - 64.0)
	var n := 0
	var bot := node("MirrorBot")
	var plate := node("BayPlate")
	var shutter := node("BayShutter")
	note("F the loader bot is dormant before the cat arrives", not bot.get("awake") and absf(bot.get("velocity").x) < 1.0)
	n = 0
	await ticks(10)
	note("F ...and stays dormant outside its wake range", not bot.get("awake") and absf(bot.get("velocity").x) < 1.0, "cat x=%.0f, bot x=%.0f" % [x(), bot.global_position.x])
	gs().intelligence = false
	await go_to(BAY_L - 20.0, 6.0)
	await ticks(30)
	note("F ...and a cat whose mind is not awake does not wake it (only the augmented one)", not bot.get("awake"))
	gs().intelligence = true
	var x0: float = bot.global_position.x
	dir(1.0)
	n = 0
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
	# The extreme: all the way back out of the bay. The bot is back near the start of its track; still solvable.
	await run_to(BAY_L - 20.0, -1.0)
	await ticks(30)
	note("F walking all the way back out of the bay leaves the bot on its track, off the plate", bot.get("global_position").x < x0 + 40.0 and absf(bot.global_position.y - BAY_Y) < 3.0 and not plate.get("active"), "bot x=%.0f, cat x=%.0f" % [bot.global_position.x, x()])
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
	ok = await run_to(BAY_GATE_X + 90.0)
	note("F the cat walks on through and the plate keeps holding", ok and plate.get("active") and shutter.get("open"), "x=%.0f bot x=%.0f" % [x(), bot.global_position.x])
	measure("mirror puzzle", "the bot's track is %.0f px from its start to the plate; a cat from the wake point walks %.0f px" % [bot.global_position.x - x0, cat_at - cx_wake])
	mark("F mirror")


func _beat_tower(start: String) -> void:
	if _skipped(start, "tower"):
		return
	await _jump_to(start, "tower", 4700.0, R5, true, true, "cp_bay")
	await run_to(4780.0)
	await ticks(10)
	note("I checkpoint at the gate saves", ss().session_checkpoint == "cp_gate", str(ss().session_checkpoint))
	await wait_lines("spring_hint_combine", 1, 300)
	var grants0 := _grants.size()
	var ok := await _hop("X", 4872.0, 5000.0, R6)
	note("I Spring (the foot-of-tower pad) climbs the exit tower: the 6-tile wall", ok and _grants.size() >= grants0 + 1 and _grants[grants0] == [2, true], "grants %s" % str(_grants.slice(grants0)))
	gs().clear_power()
	# --- the exit pit: two falling platforms ---
	var hp0: int = gs().health
	await go_to(5010.0, 6.0)
	ok = await run_to(XPIT_FACE + 60.0, 1.0, 1500, true)
	await ticks(30)
	note("I two falling platforms carry the cat over the exit pit", ok and cat.is_on_floor() and absf(y() - R6) < 4.0 and gs().health == hp0, "x=%.0f y=%.0f hp %d" % [x(), y(), gs().health])
	# A cat that falls in: the pit's pad is the way out.
	teleport(5150.0, R5 - 2.0)
	await ticks(60)
	var g1 := _grants.size()
	var ok2 := await _hop("XP", XPIT_FACE + 8.0, 5500.0, R6)
	note("I a cat in the exit pit climbs out with the pit's own Spring pad (6 tiles)", ok2 and _grants.size() == g1 + 1 and _grants[-1] == [2, true], "x=%.0f y=%.0f" % [x(), y()])
	gs().clear_power()
	await go_to(5336.0, 6.0)
	await ticks(10)
	note("I checkpoint at the exit saves", ss().session_checkpoint == "cp_exit", str(ss().session_checkpoint))
	await run_to(5360.0)
	await wait_lines("stacks_exit", 2)
	note("I the exit monologue (suburbs, home) plays", lines_of("stacks_exit") == ["There, past the fences. Trees. Rooftops. Little lights in windows.", "Home is that way. I can almost smell it."], str(lines_of("stacks_exit")))
	mark("I tower and exit")


func _beat_exit() -> void:
	var old := room
	dir(1.0)
	var n := 0
	while current_scene == old and n < 900:
		await ticks(1)
		n += 1
	stop()
	var hop: Dictionary = await MapHop.through(root.get_tree(), "stacks", "perimeter")
	note("J the exit fades out onto the world map, the stacks are finished and the perimeter opens", hop["on_map"] and hop["completed"] and hop["unlocked"], str(hop))
	note("J sound: after the exit no looping sound from the room is still playing, on the map or in the next room", hop["sound_map"].is_empty() and hop["sound_next"].is_empty(), "map %s next %s" % [str(hop["sound_map"]), str(hop["sound_next"])])
	await ticks(exit_settle)
	var next := current_scene
	note("J the perimeter is entered from the map: Room 4 loads", next != null and next.scene_file_path == "res://scenes/levels/room4.tscn", str(next.scene_file_path if next else "?"))
	var save: Dictionary = ss().read_save()
	note("J auto-saved in Room 4 with the mind and the shockwave", save.get("scene", "") == "res://scenes/levels/room4.tscn" and save.get("abilities", {}).get("mind", false) and save.get("abilities", {}).get("shockwave", false), str(save.get("abilities", {})))
	mark("J exit")
