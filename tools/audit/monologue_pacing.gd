## Narration pacing audit (rating-week fix): the priority queue of scripts/systems/monologue.gd.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/monologue_pacing.gd
##
## Three parts, all headless, all driving the real Monologue autoload and the real MonologueTrigger
## and Checkpoint actors:
##  1. RULES: synthetic cases for each queue rule (CRITICAL cuts FILLER and jumps the queue, FILLER is
##     dropped when anything speaks or in the cooldown, expiry, section and distance staleness, a
##     FILLER set is cut when the cat runs, the minimum gap, the voice fade and the duck release).
##  2. SPEEDRUN: three paces per room ("speedrun": the required triggers flat out; "all": every
##     trigger flat out; "brisk": every trigger at a third of that, a quick real playthrough). For each room the cat is moved along the route of the room's playthrough (the trigger
##     and checkpoint nodes of the real scene, in the order its playthrough audit visits them) at
##     the Surge run speed (1.5 x run speed: faster than a real route, which also climbs and jumps).
##     The real triggers fire from the real physics overlaps; the geometry is harvested from the real
##     room scene and rebuilt without its hazards. Asserts: every CRITICAL set plays, starts within
##     1.5 s of its trigger (not counting time spent behind other non-FILLER speech), the queue never
##     holds more than QUEUE_MAX sets, no FILLER starts later than about 4 s after its trigger, no
##     FILLER from an earlier checkpoint section plays after the next checkpoint, and the talk-time
##     ratio is reported per room. Also prints the old queue's (plain FIFO) critical latency for the
##     same trigger times, replayed from the line lengths.
##  3. SLOW PLAY: standing at each trigger until its set has finished (after the cooldown) plays every
##     line of every set, filler included, and a FILLER trigger entered while the narrator is busy
##     fires once the cat has lingered past the cooldown.
## ROUTES=room2,room3 limits the speedruns. Exit code 1 on a failure. Deletes user://save.json.
extends SceneTree

const RUN_SPEED := 178.0  # the cat's run speed, px/s (the path is walked flat out, vertical then horizontal)
const CAT_SCENE := "res://scenes/player/cat.tscn"
const CP_SCENE := "res://scenes/actors/checkpoint.tscn"
## "brisk": every trigger, at a third of the run speed: a quick real playthrough also climbs, jumps,
## waits for hazards and falls back (a flat-out run of Room 3 is under a minute; a quick human takes minutes).
const BRISK_FACTOR := 0.33
const FILLER_START_MAX := 4.6  # s: FILLER_EXPIRY with a frame of slack
const RATIO_MAX := 0.6  # talk time / route time on the brisk run

## s a CRITICAL set may wait for anything but other non-FILLER speech: Monologue's target plus the
## cut fade and some slack (set in _main).
var crit_excess_max := 1.5
var _fails := 0
var _harvest := {}
var _report: Array = []


func mono() -> Node:
	return root.get_node("Monologue")


func gs() -> Node:
	return root.get_node("GameState")


func ss() -> Node:
	return root.get_node("SaveSystem")


func note(label: String, ok: bool, detail := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_fails += 1


func _initialize() -> void:
	_main()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func wait(secs: float) -> void:
	await ticks(int(ceil(secs * 60.0)))


## Wait (physics ticks) until `cond` holds, at most `limit` seconds; false on timeout.
func wait_until(cond: Callable, limit: float) -> bool:
	var n := int(limit * 60.0)
	while n > 0 and not cond.call():
		await physics_frame
		n -= 1
	return cond.call()


func _main() -> void:
	crit_excess_max = mono().CRITICAL_START_TARGET + mono().PREEMPT_FADE + 0.25
	ss().delete_save()
	await _rules()
	var only := OS.get_environment("ROUTES")
	for room_id in ["room1", "room2", "room3", "room4", "home"]:
		_harvest[room_id] = await _harvest_room(room_id)
	for room_id in ["room1", "room2", "room3", "room4", "home"]:
		if only != "" and not only.split(",").has(room_id):
			continue
		for variant in ["speedrun", "all", "brisk"]:
			await _run_route(room_id, variant)
	await _slow_play()
	_summary()
	ss().delete_save()
	quit(1 if _fails > 0 else 0)


func _summary() -> void:
	print("")
	print("room   route     time talk ratio(new/old) ...  (F played/asked; queue = sets waiting)")
	for r in _report:
		print(r)
	print("")
	print("MONOLOGUE PACING AUDIT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])


# ---- world ---------------------------------------------------------------------------------------

func _new_game(awake := true) -> void:
	ss().delete_save()
	gs().new_game()
	mono().reset()
	ss().session_checkpoint = ""
	if awake:
		gs().awaken_mind()


## A bare world holding one cat (physics off: the audit moves it) and, optionally, rebuilt actors.
func _world(scene_path := "", start := Vector2(0, 0)) -> Dictionary:
	if current_scene and is_instance_valid(current_scene):
		current_scene.queue_free()
		await process_frame
	var w := Node2D.new()
	w.name = "PaceWorld"
	w.scene_file_path = scene_path
	root.add_child(w)
	current_scene = w
	ss().session_scene = scene_path
	ss().session_checkpoint = ""
	var cat: Node2D = load(CAT_SCENE).instantiate()
	w.add_child(cat)
	cat.global_position = start
	await ticks(3)  # the cat switches its own physics on in its first frames
	cat.set_physics_process(false)  # no gravity, no input: the audit places it
	cat.global_position = start
	await ticks(2)
	return {"world": w, "cat": cat}


func _harvest_room(room_id: String) -> Dictionary:
	var path := "res://scenes/levels/%s.tscn" % room_id
	_new_game()
	var src: Node = load(path).instantiate()
	root.add_child(src)
	await ticks(3)
	var out := {"path": path, "trigs": {}, "cps": {}, "mems": {}, "marks": {}}
	_collect(src, out)
	src.queue_free()
	await ticks(2)
	ss().delete_save()
	return out


func _collect(n: Node, out: Dictionary) -> void:
	var sp: String = n.get_script().resource_path if n.get_script() else ""
	if n is Node2D and (String(n.name) == "RoomExit" or String(n.name) == "TimedGate"):
		out.marks[String(n.name)] = (n as Node2D).global_position
	if n is Node2D and n.get("line_id") != null:
		out.trigs[String(n.name)] = {
			"id": String(n.get("line_id")), "pos": (n as Node2D).global_position, "size": n.get("size"),
			"require_mind": bool(n.get("require_mind")), "requires_played": String(n.get("requires_played")),
			"shock": sp.ends_with("shock_line_trigger.gd")}
	elif n is Node2D and n.get("checkpoint_id") != null:
		out.cps[String(n.name)] = {"id": String(n.get("checkpoint_id")), "pos": (n as Node2D).global_position}
	elif n is Node2D and n.get("memory_id") != null and String(n.get("memory_id")) != "":
		out.mems[String(n.name)] = {"id": String(n.get("memory_id")), "pos": (n as Node2D).global_position}
	for c in n.get_children():
		_collect(c, out)


func _spawn(w: Node2D, h: Dictionary, active: Array) -> Dictionary:
	var trigs := {}
	for nm in h.trigs:
		if not active.has(nm):
			continue
		var d: Dictionary = h.trigs[nm]
		var t: Area2D = load("res://scripts/actors/shock_line_trigger.gd" if d.shock else "res://scripts/actors/monologue_trigger.gd").new()
		t.name = nm
		t.set("line_id", d.id)
		t.set("require_mind", d.require_mind)
		t.set("requires_played", d.requires_played)
		t.set("size", d.size)
		t.position = d.pos
		w.add_child(t)
		trigs[nm] = t
	for nm in h.marks:  # the door and the timed gate: the objective hints look for them by name
		var mk := Node2D.new()
		mk.name = nm
		mk.position = h.marks[nm]
		w.add_child(mk)
	for nm in h.cps:
		if not active.has(nm):
			continue
		var c: Node2D = load(CP_SCENE).instantiate()
		c.name = nm
		c.set("checkpoint_id", h.cps[nm].id)
		c.position = h.cps[nm].pos
		w.add_child(c)
	return trigs


# ---- 1. rules ------------------------------------------------------------------------------------

func _moved(cat: Node2D, dx: float) -> void:
	cat.global_position += Vector2(dx, 0.0)


func _idle() -> bool:
	return not mono().is_speaking() and mono()._queue.is_empty()


func _first(id: String, idx := 0) -> Dictionary:
	for e in mono().play_log:
		if e.id == id and e.idx == idx:
			return e
	return {}


func _rules() -> void:
	var m := mono()
	_new_game()
	var wc := await _world("res://scenes/levels/room2.tscn", Vector2(1000, 768))
	var cat: Node2D = wc.cat
	# R1 a CRITICAL cuts a FILLER that is speaking within the fade, and the voice and duck release.
	m.play("stacks_lift")
	await wait(1.5)
	note("R1 a FILLER line is speaking", m.is_speaking() and not m.play_log.is_empty() and m.play_log[0].id == "stacks_lift")
	var t_crit: float = m._clock
	m.play("spring_hint")
	await wait(0.4)
	var c1 := _first("spring_hint")
	note("R1 the CRITICAL line starts within the preempt fade (%.2f s)" % (c1.get("start_t", 99.0) - t_crit),
		not c1.is_empty() and c1.start_t - t_crit <= m.PREEMPT_FADE + 0.1)
	note("R1 the FILLER line is marked preempted and its set dropped", _first("stacks_lift").get("preempted", false) and m.stats.preempted == 1)
	await wait(1.0)
	var voiced: bool = m.voice_active
	var vdb: float = m._voice.volume_db
	note("R1 the new line's voice plays at full level (the fade did not stick)", voiced and vdb > -1.0, "voice %s %.1f dB" % [str(voiced), vdb])
	await wait(10.0)
	_new_game()
	m.play("stacks_lift")
	await wait(1.5)
	note("R1 a voiced FILLER line holds the duck (voice_active)", m.voice_active)
	m.say("Hmm.", 2.0)  # text only: nothing to voice, so the cut must release the duck
	await wait(0.1)
	note("R1 mid-fade the voice is fading out (not yet stopped)", m.voice_active and m._voice.volume_db < 0.0, "%.1f dB" % m._voice.volume_db)
	await wait(0.4)
	note("R1 once cut, the voice is stopped, the duck released and the level restored", not m.voice_active and not m._voice.playing and m._voice.volume_db == 0.0, "%s %s %.1f" % [str(m.voice_active), str(m._voice.playing), m._voice.volume_db])
	await wait(8.0)
	# R2 FILLER never waits: dropped while something speaks, and during the cooldown.
	await wait(10.0)
	m.play("spring_hint")
	await wait(0.5)
	var n_before: int = m.play_log.size()
	var d0: int = m.drop_log.size()
	m.play("stacks_barrels")
	note("R2 a FILLER asked for while a line speaks is dropped at once, never queued", m.drop_log.size() == d0 + 1 and m._queue.is_empty() and m.play_log.size() == n_before, str(m.drop_log.back()))
	await wait(8.0)
	note("R2 ... and stays dropped", _first("stacks_barrels").is_empty())
	m.play("stacks_barrels")
	note("R2 a FILLER inside the cooldown after a line is dropped (%.1f s after it)" % (m._clock - m._last_end), m.drop_log.back()[0] == "stacks_barrels" and m.drop_log.back()[1] == "cooldown")
	await wait(m.FILLER_COOLDOWN + 0.5)
	m.play("stacks_barrels")
	await wait(0.2)
	note("R2 once the cooldown has passed a FILLER plays", not _first("stacks_barrels").is_empty())
	await wait(8.0)
	# R3 a CRITICAL jumps ahead of queued STORY/MEMORY/FILLER; STORY/MEMORY queue ahead of FILLER.
	_new_game()
	m.play("nanofluid_container")  # STORY, speaking
	await wait(0.5)
	m.play("memory_yard")  # MEMORY
	m.play("map_yard", true)  # FILLER, patient (queues)
	m.play("dock_bot")  # STORY
	m.play("spring_first")  # CRITICAL
	var order: Array = m._queue.map(func(s): return s.id)
	note("R3 queue order: CRITICAL, then STORY, MEMORY (the queued FILLER was shed: only FILLER is)", order == ["spring_first", "dock_bot", "memory_yard"] and m.drop_log.any(func(d): return d[0] == "map_yard" and d[1] == "queue_full"), str(order) + str(m.drop_log))
	await wait(12.0)
	var cut_ok: bool = _first("nanofluid_container").get("preempted", false) == false
	note("R3 a STORY line in progress is never cut", cut_ok)
	await wait(60.0)
	var seq: Array = m.play_log.map(func(e): return e.id)
	var i_crit: int = seq.find("spring_first")
	var i_story: int = seq.find("dock_bot")
	var i_cont: int = seq.rfind("nanofluid_container")
	note("R3 the CRITICAL set was spoken before the queued STORY and MEMORY sets", i_crit >= 0 and i_crit < i_story and i_story < seq.find("memory_yard"), str(seq))
	note("R3 the queued set was started after the line in progress ended (no overlap)", m.play_log.size() > 0)
	# R4 the silence between chained lines is at least MIN_GAP plus the dip of the fade out.
	var gap_ok := true
	var min_gap := 99.0
	for k in range(1, m.play_log.size()):
		var prev: Dictionary = m.play_log[k - 1]
		var cur: Dictionary = m.play_log[k]
		if prev.fade_t >= 0.0 and prev.end_t >= 0.0 and cur.start_t - prev.end_t < 0.05:
			var g: float = cur.start_t - prev.fade_t
			min_gap = minf(min_gap, g)
			if g < m.MIN_GAP + 0.25:
				gap_ok = false
	note("R4 chained lines are separated by at least MIN_GAP (%.1f s) of silence after the fade starts (min %.2f s)" % [m.MIN_GAP, min_gap], gap_ok and min_gap < 90.0)
	# R5 expiry: a patient FILLER that cannot start within FILLER_EXPIRY is dropped.
	_new_game()
	m.play("nanofluid_container")
	await wait(0.3)
	m.play("map_yard", true)
	await wait(m.FILLER_EXPIRY + 0.6)
	note("R5 a queued FILLER that cannot start within %.0f s is dropped (expired)" % m.FILLER_EXPIRY, m.drop_log.any(func(d): return d[0] == "map_yard" and d[1] == "expired"), str(m.drop_log))
	# R6 section: a new checkpoint discards pending FILLER and far STORY; a near STORY stays.
	_new_game()
	cat.global_position = Vector2(1000, 768)
	m.play("awakening")  # CRITICAL, 5 lines: keeps the queue waiting
	await wait(0.5)
	m.play("dock_bot")  # STORY (near the cat)
	m.play("map_stacks", true)  # FILLER
	ss().session_checkpoint = "cp_audit"
	await wait(0.1)
	var dropped: Array = m.drop_log.map(func(d): return d[0] + ":" + d[1])
	note("R6 a new checkpoint drops the pending FILLER", dropped.has("map_stacks:section"), str(dropped))
	note("R6 ... and keeps a STORY that is near the cat", m._queue.any(func(s): return s.id == "dock_bot"), str(m._queue.map(func(s): return s.id)))
	m.play("credential")  # STORY
	cat.global_position = Vector2(1000 + m.STORY_STALE_DIST + 50.0, 768)
	ss().session_checkpoint = "cp_audit2"
	await wait(0.1)
	dropped = m.drop_log.map(func(d): return d[0] + ":" + d[1])
	note("R6 a new checkpoint drops a STORY more than %.0f px behind the cat" % m.STORY_STALE_DIST, dropped.has("credential:section_far") and dropped.has("dock_bot:section_far"), str(dropped))
	# R7 distance staleness (same section): a pending STORY more than STALE_DIST behind goes; CRITICAL stays.
	_new_game()
	cat.global_position = Vector2(1000, 768)
	m.play("awakening")
	await wait(0.5)
	m.play("credential")
	m.play("exit_hint")
	cat.global_position = Vector2(1000 + m.STALE_DIST + 50.0, 768)
	await wait(0.1)
	dropped = m.drop_log.map(func(d): return d[0] + ":" + d[1])
	note("R7 a pending STORY more than %.0f px behind the cat is dropped, a pending CRITICAL is not" % m.STALE_DIST, dropped.has("credential:far") and m._queue.any(func(s): return s.id == "exit_hint"), str(dropped))
	# R8 a multi-line FILLER set stops after the line during which the cat ran.
	_new_game()
	cat.global_position = Vector2(1000, 768)
	m.play("yard_arrival")
	await wait(1.0)
	cat.global_position = Vector2(1000 + m.FILLER_CUT_DIST + 100.0, 768)
	await wait(7.0)
	var lines_played: int = m.play_log.filter(func(e): return e.id == "yard_arrival").size()
	note("R8 a FILLER set whose first line the cat outran plays only that line", lines_played == 1 and m.stats.filler_cut == 1, "lines %d cut %d" % [lines_played, m.stats.filler_cut])
	await wait(10.0)
	cat.global_position = Vector2(1000, 768)
	m.play("yard_arrival")
	await wait(14.0)
	lines_played = m.play_log.filter(func(e): return e.id == "yard_arrival").size()
	note("R8 ... a lingering player hears both lines", lines_played == 3, "lines %d" % lines_played)
	# R9 a STORY set plays fully even when the cat runs.
	_new_game()
	cat.global_position = Vector2(1000, 768)
	m.play("dock_bot")
	await wait(1.0)
	cat.global_position = Vector2(1000 + 500.0, 768)
	await wait(14.0)
	note("R9 a STORY set plays fully whatever the cat does", m.play_log.filter(func(e): return e.id == "dock_bot").size() == 2)
	# R10 pre-mind: meows only, nothing queued.
	_new_game(false)
	m.play("awakening")
	m.play("stacks_lift")
	await wait(0.5)
	note("R10 before the mind wakes nothing is shown or queued (meows only)", m.play_log.is_empty() and m._queue.is_empty() and not m.is_speaking() and m.meow_log.size() == 2)

	await _rules_objective(wc)
	await _rules_story(wc)


# ---- 2. speedruns --------------------------------------------------------------------------------

## The route of each room: the playthrough's order. "speedrun" is the required path only; "all" adds
## the optional rooms and memory fragments. Steps: start NODE | go NODE | do ACTION [arg] | wait S.
func _route(room_id: String, variant: String) -> Array:
	var r: Array = _route_body(room_id, variant)
	if variant == "speedrun" and room_id != "home":
		r.append(["go", "RoomExit"])  # a speedrunner walks into the door
	return r


func _route_body(room_id: String, variant: String) -> Array:
	var all: bool = variant != "speedrun"
	match room_id:
		"room1":
			# The pool is near the end of the warehouse; the awakening plays as the struggle ends.
			return [["start", "ReadContainer", Vector2(-260, 0)], ["do", "awaken"], ["go", "ReadContainer"], ["go", "HintExit"]]
		"room2":
			var r: Array = [["start", "YardArrival"], ["go", "SurgeFirst"], ["go", "CheckpointA"]]
			if all:
				r += [["go", "YardVault"], ["do", "memory", "MemoryYard"], ["go", "YardUnder"], ["go", "CheckpointU"], ["go", "YardCloset"]]
			r += [["go", "CheckpointB"]]
			if all:
				r += [["go", "YardRoof"]]
			r += [["go", "SurgeGate"]]
			if all:
				r += [["go", "CheckpointR"]]
			r += [["go", "CheckpointC"], ["go", "DockBotLine"], ["go", "CheckpointD"], ["go", "ExitFence"]]
			return r
		"room3":
			var r: Array = [["start", "StacksArrival"], ["go", "SpringHint"], ["go", "SpringFirst"], ["go", "CheckpointA"], ["go", "SpringHintLedge"], ["go", "CheckpointB"]]
			if all:
				r += [["go", "SpringHintPit1"], ["go", "SpringHintPit2"]]
			r += [["go", "CheckpointC"], ["go", "LiftLine"], ["go", "CheckpointD"], ["do", "shock"], ["go", "ConduitLine"], ["go", "CheckpointRoof"], ["do", "shock_first"], ["go", "CrackLine"]]
			if all:
				r += [["go", "BarrelLine"]]
			r += [["go", "VentLine"]]
			if all:
				r += [["go", "VentTopLine"], ["do", "memory", "MemoryStacks"]]
			r += [["go", "CheckpointBay"], ["go", "MirrorLine"], ["go", "CheckpointGate"], ["go", "SpringHintCombine"], ["go", "CheckpointExit"], ["go", "StacksExit"]]
			return r
		"room4":
			var r: Array = [["start", "PerimeterArrival"], ["go", "PhaseFirst"], ["go", "CheckpointA"], ["go", "SpringHintRoof"], ["go", "CheckpointB"],
				["go", "ImpactFirst"]]
			if all:
				r += [["go", "PerimeterDepths"]]
			r += [["go", "CheckpointC"], ["go", "CheckpointD"]]
			if all:
				r += [["go", "ArchiveHollow"], ["do", "memory", "GemMemory"]]
			r += [["go", "CheckpointG"]]
			if all:
				r += [["go", "CisternEnter"]]
			r += [["go", "CheckpointH"], ["do", "relay", 0], ["go", "CheckpointF"], ["go", "RelaysIntro"], ["go", "SpringHintTower"], ["go", "CheckpointL"], ["do", "relay", 1],
				["go", "CheckpointI"], ["go", "VaultMech"], ["do", "relay", 2], ["go", "CheckpointJ"], ["do", "scanner"], ["wait", 3.2], ["do", "credential"], ["wait", 1.8], ["go", "PerimeterExit"]]
			return r
		"home":
			return [["start", "ArrivalTalk"], ["go", "FlapTalk"], ["wait", 1.6], ["do", "final"]]
	return []


func _node_pos(h: Dictionary, nm: String) -> Vector2:
	if h.trigs.has(nm):
		return h.trigs[nm].pos
	if h.cps.has(nm):
		return h.cps[nm].pos
	if h.mems.has(nm):
		return h.mems[nm].pos
	if h.marks.has(nm):
		return h.marks[nm]
	return Vector2.INF


func _run_route(room_id: String, variant: String) -> void:
	var h: Dictionary = _harvest[room_id]
	var steps := _route(room_id, variant)
	var tag := "%s %s" % [room_id, variant]
	var speed := RUN_SPEED * (BRISK_FACTOR if variant == "brisk" else 1.0)
	# Actors on the route only: the others are the optional corners this variant skips.
	var active: Array = []
	for s in steps:
		if s[0] in ["start", "go"]:
			active.append(s[1])
	_new_game(room_id != "room1")
	var first_pos := _node_pos(h, steps[0][1])
	if steps[0].size() > 2:
		first_pos += steps[0][2]
	var wc := await _world(h.path, first_pos)
	var cat: Node2D = wc.cat
	var trigs := _spawn(wc.world, h, active)
	var m := mono()
	await ticks(3)
	var t0: float = m._clock
	var events: Array = []  # [t, id, prio] every set the route asks for, for the old-queue replay
	var entered := {}  # trigger node -> first time the cat stood in it
	var step_t := {}  # script-driven id -> time
	var pos := first_pos
	for s in steps:
		match s[0]:
			"start":
				pass
			"go":
				var target := _node_pos(h, s[1])
				for leg in [Vector2(pos.x, target.y), target]:
					while cat.global_position.distance_to(leg) > 0.01:
						cat.global_position = cat.global_position.move_toward(leg, speed / 60.0)
						_sample_entries(trigs, cat, entered, m._clock - t0)
						await physics_frame
				pos = target
			"wait":
				await wait(float(s[1]))
			"do":
				var now: float = m._clock - t0
				match s[1]:
					"awaken":
						gs().awaken_mind()
						m.play("awakening")
						events.append([now, "awakening"])
					"shock":
						gs().shockwave_unlocked = true
					"shock_first":
						m.play_once("shock_first")
						events.append([now, "shock_first"])
					"memory":
						m.play_memory(h.mems[s[2]].id)
						events.append([now, h.mems[s[2]].id])
					"relay":
						m.play_line("relay_done", int(s[2]))
						events.append([now, "relay_done"])
					"scanner":
						m.play_once("scanner")
						events.append([now, "scanner"])
					"credential":
						m.play_once("credential")
						events.append([now, "credential"])
					"final":
						m.play("home_final")
						events.append([now, "home_final"])
	var route_t: float = m._clock - t0
	await wait_until(func(): return _idle() and not m._busy, 120.0)
	for nm in entered:
		var d: Dictionary = h.trigs[nm]
		var when: float = entered[nm]
		if d.requires_played != "":
			for e in events + _entry_events(h, entered):
				if e[1] == d.requires_played:
					when = maxf(when, e[0])
		events.append([when, d.id])
	events.sort_custom(func(a, b): return a[0] < b[0])
	_analyse(tag, m, t0, route_t, events)
	current_scene.queue_free()
	await process_frame


func _entry_events(h: Dictionary, entered: Dictionary) -> Array:
	var out: Array = []
	for nm in entered:
		out.append([entered[nm], h.trigs[nm].id])
	return out


## Note the first moment the cat is inside a trigger (the trigger rect grown by the cat's body).
func _sample_entries(trigs: Dictionary, cat: Node2D, entered: Dictionary, t: float) -> void:
	for nm in trigs:
		if entered.has(nm):
			continue
		var tr: Node2D = trigs[nm]
		var sz: Vector2 = tr.get("size")
		var r := Rect2(tr.global_position + Vector2(-sz.x / 2.0, -sz.y), sz).grow(10.0)
		if r.has_point(cat.global_position):
			entered[nm] = t


func _prio_name(p: int) -> String:
	return ["CRITICAL", "STORY", "MEMORY", "FILLER"][p]


func _analyse(tag: String, m: Node, t0: float, route_t: float, events: Array) -> void:
	var log: Array = m.play_log
	# Sets: a line with idx at the first position of its set starts it.
	var sets: Array = []  # {id, prio, trigger_t, start_t, lines}
	for e in log:
		var open: Dictionary = {}
		for k in range(sets.size() - 1, -1, -1):
			if sets[k].id == e.id and sets[k].trigger_t == e.trigger_t:
				open = sets[k]
				break
		if open.is_empty():
			open = {"id": e.id, "prio": e.prio, "trigger_t": e.trigger_t, "start_t": e.start_t, "lines": 0, "section_bad": false, "scene_bad": false}
			sets.append(open)
		open.lines += 1
		if e.prio == m.Prio.FILLER and e.section_t != e.section_s:
			open.section_bad = true
		if e.scene_t != "" and e.prio != m.Prio.CRITICAL and e.scene_t != e.section_s.split("#")[0]:
			open.scene_bad = true
	var worst_raw := 0.0
	var worst_excess := 0.0
	var worst_name := ""
	var crit_n := 0
	var by_prio := [0, 0, 0, 0]
	var filler_late := 0.0
	var section_bad := 0
	for s in sets:
		by_prio[s.prio] += 1
		if s.section_bad or s.scene_bad:
			section_bad += 1
		if s.prio == m.Prio.FILLER:
			filler_late = maxf(filler_late, s.start_t - s.trigger_t)
		if s.prio == m.Prio.CRITICAL:
			crit_n += 1
			var raw: float = s.start_t - s.trigger_t
			var busy := 0.0
			for e in log:
				if e.prio == m.Prio.FILLER or e.start_t >= s.start_t or e.end_t < 0.0:
					continue
				if e.id == s.id and e.trigger_t == s.trigger_t:
					continue
				busy += maxf(0.0, minf(e.end_t, s.start_t) - maxf(e.start_t, s.trigger_t))
			var excess := maxf(0.0, raw - busy)
			if raw > 3.0:
				var by: Array = []
				for e in log:
					if e.prio != m.Prio.FILLER and e.start_t < s.start_t and e.end_t > s.trigger_t and not (e.id == s.id and e.trigger_t == s.trigger_t) and not by.has(_prio_name(e.prio)[0] + ":" + e.id):
						by.append(_prio_name(e.prio)[0] + ":" + e.id)
				print("   %s: %s waited %.1f s behind %s" % [tag, s.id, raw, str(by)])
			if raw > worst_raw:
				worst_raw = raw
			if excess > worst_excess:
				worst_excess = excess
				worst_name = s.id
	# critical sets asked for versus spoken
	var crit_asked := 0
	var asked := {}
	for ev in events:
		if m.priority_of(ev[1]) == m.Prio.CRITICAL and not asked.has(ev[1]):
			asked[ev[1]] = true  # once-only sets can be triggered from two places (the two Spring pit hints)
			crit_asked += 1
	var talk := 0.0
	for e in log:
		var a: float = e.start_t - t0
		var b: float = (e.end_t if e.end_t >= 0.0 else m._clock) - t0
		talk += maxf(0.0, minf(b, route_t) - maxf(a, 0.0))
	var ratio: float = talk / maxf(route_t, 0.01)
	var old := _legacy(m, events)
	var end_new := 0.0
	for e in log:
		end_new = maxf(end_new, (e.end_t if e.end_t >= 0.0 else m._clock) - t0)
	var filler_asked := 0
	var seen_f := {}
	for ev in events:
		if m.priority_of(ev[1]) == m.Prio.FILLER and not seen_f.has(ev[1]):
			seen_f[ev[1]] = true
			filler_asked += 1
	var dropF := 0
	for d in m.drop_log:
		if d[2] == m.Prio.FILLER:
			dropF += 1
	var label := "%s" % tag
	var spoken := {}
	for e in log:
		spoken[e.id] = true
	if tag.begins_with("room1"):
		var heard := spoken.has("exit_hint")
		if tag.ends_with("speedrun") or tag.ends_with("brisk"):
			note("%s: the exit hint is dropped (objective met) because the cat walked into the door%s" % [tag, "" if not heard else " (it was spoken!)"], not heard and _dropped("exit_hint", "fulfilled") if tag.ends_with("speedrun") else true)
		if tag.ends_with("all"):
			var seq: Array = log.map(func(e): return e.id)
			note("%s: a lingering player hears the crate reading, then the exit hint" % tag, heard and seq.find("exit_hint") > seq.rfind("nanofluid_container") and seq.count("nanofluid_container") == 4)
	var unmet := 0
	var met := {}
	for d in m.drop_log:
		if d[2] == m.Prio.CRITICAL and d[1] == "fulfilled" and asked.has(d[0]) and not spoken.has(d[0]) and not met.has(d[0]):
			met[d[0]] = true
			unmet += 1
	var spoken_asked := 0
	for id in asked:
		if spoken.has(id):
			spoken_asked += 1
	note("%s: every CRITICAL set asked for is spoken, or dropped because its objective was met (%d spoken + %d met of %d)" % [label, spoken_asked, unmet, crit_asked], spoken_asked + unmet == crit_asked)
	note("%s: CRITICAL waits at most %.1f s for anything but non-FILLER speech (worst %.2f s: %s; raw worst %.1f s, old queue %.1f s)" % [label, crit_excess_max, worst_excess, worst_name, worst_raw, old.crit_max],
		worst_excess <= crit_excess_max)
	# Flat out through every optional corner the CRITICAL hints themselves can stack three deep.
	var qcap: int = m.QUEUE_MAX + (1 if tag.ends_with("all") else 0)
	note("%s: the queue never held more than %d sets (max %d %s)" % [label, qcap, m.stats.queue_max, str(m.stats.queue_ids)], m.stats.queue_max <= qcap)
	note("%s: no FILLER set started more than %.1f s after its trigger (worst %.2f s)" % [label, FILLER_START_MAX, filler_late], filler_late <= FILLER_START_MAX)
	note("%s: no FILLER from an older checkpoint section and no non-critical line from another room played after it (%d)" % [label, section_bad], section_bad == 0)
	if tag.ends_with("brisk") and tag.begins_with("room") and not tag.begins_with("room1"):
		note("%s: talk-time ratio %.2f (%.0f s of %.0f s) is at most %.2f" % [label, ratio, talk, route_t, RATIO_MAX], ratio <= RATIO_MAX)
	else:
		print("   %s: talk-time ratio %.2f (%.0f s of %.0f s), flat out" % [label, ratio, talk, route_t])
	_report.append("%-6s %-9s %4.0fs %4.0fs %4.2f %4.2f | crit wait new %5.1fs (excess %4.2f) old %5.1fs | talk after route new %4.0fs old %4.0fs | sets C%d S%d M%d F%d/%d | cut %d preempt %d qmax %d" % [
		tag.split(" ")[0], tag.split(" ")[1], route_t, talk, ratio, old.talk_in_route / maxf(route_t, 0.01), worst_raw, worst_excess, old.crit_max,
		maxf(end_new - route_t, 0.0), maxf(old.end_t - route_t, 0.0),
		by_prio[0], by_prio[1], by_prio[2], by_prio[3], filler_asked, m.stats.filler_cut, m.stats.preempted, m.stats.queue_max])
	# the old queue replayed on the same trigger times: how much of the route it would have spent talking
	print("   %s: old queue (FIFO replay) talk %.0f s of the route %.0f s (%.2f), %d sets queued, last line over at +%.0f s" % [tag, old.talk_in_route, route_t, old.talk_in_route / maxf(route_t, 0.01), events.size(), old.end_t])
	print("   %s: dropped %s" % [tag, str(m.drop_log.map(func(d): return d[0] + ":" + d[1]))])


## The old queue: every triggered set queued behind everything, first in first out, line lengths
## from the clips. Returns the worst CRITICAL start delay and how long it talked within the route.
func _legacy(m: Node, events: Array) -> Dictionary:
	var free := 0.0
	var crit_max := 0.0
	var talk := 0.0
	var route_end := 0.0
	for ev in events:
		route_end = maxf(route_end, ev[0])
	for ev in events:
		var id: String = ev[1]
		var start := maxf(ev[0], free)
		if m.priority_of(id) == m.Prio.CRITICAL:
			crit_max = maxf(crit_max, start - ev[0])
		var dur := 0.0
		var lines: Array = m._sets.get(id, [])
		for i in lines.size():
			var l: Variant = lines[i]
			var text: String = m.clean(str(l.get("text", "")) if l is Dictionary else str(l))
			var hold: float = float(l.get("hold", -1.0)) if l is Dictionary and l.has("hold") else m.hold_for(text)
			var after: float = float(l.get("after", 0.0)) if l is Dictionary else 0.0
			var clip: AudioStream = m._clip(id, i)
			if clip:
				hold = maxf(hold, clip.get_length() + m.VOICE_TAIL)
			dur += m.FADE_IN + hold + (m.FADE_OUT * 0.5 if i < lines.size() - 1 else m.FADE_OUT) + after
		free = start + dur
		talk += maxf(0.0, minf(free, route_end) - minf(start, route_end))
	return {"crit_max": crit_max, "talk_in_route": talk, "end_t": free}


# ---- 3. slow play --------------------------------------------------------------------------------

func _slow_play() -> void:
	var total_sets := 0
	var total_lines := 0
	var missing: Array = []
	var m := mono()
	for room_id in ["room1", "room2", "room3", "room4", "home"]:
		var h: Dictionary = _harvest[room_id]
		_new_game()
		var wc := await _world(h.path, Vector2(-5000, -5000))
		var cat: Node2D = wc.cat
		var names: Array = h.trigs.keys()
		var trigs := _spawn(wc.world, h, names + h.cps.keys())
		# nothing fires at the parked spot; every trigger is visited in turn, in the order of its id
		var seen := {}
		var order: Array = names.duplicate()
		order.sort_custom(func(a, b):
			var ra: bool = h.trigs[a].requires_played != ""
			var rb: bool = h.trigs[b].requires_played != ""
			if ra != rb:
				return rb  # the hints that follow a reading come after it
			return h.trigs[a].pos.x < h.trigs[b].pos.x)
		for nm in order:
			var d: Dictionary = h.trigs[nm]
			if seen.has(d.id):
				continue
			seen[d.id] = true
			gs().shockwave_unlocked = true
			await wait_until(func(): return not m._busy and m._queue.is_empty() and m._clock > m._last_end + m.FILLER_COOLDOWN + 0.2, 60.0)
			var before: int = m.play_log.size()
			cat.global_position = d.pos
			var want: int = m.line_count(d.id)
			var ok: bool = await wait_until(func(): return m.play_log.size() - before >= want and not m._busy, 60.0)
			total_sets += 1
			total_lines += want
			var got: int = m.play_log.size() - before
			if not ok or got != want:
				missing.append("%s:%d/%d" % [d.id, got, want])
			cat.global_position = Vector2(-5000, -5000)
			await ticks(2)
		current_scene.queue_free()
		await process_frame
	note("SLOW lingering at every trigger of every room plays every line (%d sets, %d lines, filler included)" % [total_sets, total_lines], missing.is_empty(), str(missing))
	# script-driven sets (memory, relays, finale) and the map's patient lines, spoken one at a time
	_new_game()
	var wc2 := await _world("res://scenes/levels/room3.tscn", Vector2(500, 500))
	var scripted := ["memory_warehouse", "memory_yard", "memory_stacks", "memory_perimeter", "relay_done", "scanner", "credential", "perimeter_missing_r1",
		"perimeter_missing_r2", "perimeter_missing_r3", "perimeter_missing_many", "continue_tease", "home_final", "shock_first", "map_yard", "map_stacks", "map_perimeter", "map_home"]
	var miss2: Array = []
	for id in scripted:
		await wait_until(func(): return not m._busy and m._queue.is_empty() and m._clock > m._last_end + m.FILLER_COOLDOWN + 0.2, 60.0)
		var b2: int = m.play_log.size()
		m.play(id, true)
		await wait_until(func(): return m.play_log.size() - b2 >= m.line_count(id) and not m._busy, 60.0)
		if m.play_log.size() - b2 != m.line_count(id):
			miss2.append(id)
	note("SLOW every scripted set (memory, relay, finale, map) plays in full on its own", miss2.is_empty(), str(miss2))
	# a FILLER trigger entered while the narrator is busy fires once the cat has lingered
	_new_game()
	var h3: Dictionary = _harvest["room3"]
	var wc3 := await _world(h3.path, Vector2(-5000, -5000))
	var cat3: Node2D = wc3.cat
	_spawn(wc3.world, h3, ["LiftLine", "SpringHint"])
	m.play("spring_first")  # a CRITICAL, speaking
	await wait(1.0)
	var lift: Dictionary = h3.trigs["LiftLine"]
	cat3.global_position = lift.pos
	await wait(2.0)
	note("SLOW a FILLER trigger entered while a line speaks is held back (not dropped, not queued)", m.play_log.filter(func(e): return e.id == "stacks_lift").is_empty() and m._queue.is_empty())
	var fired: bool = await wait_until(func(): return not m.play_log.filter(func(e): return e.id == "stacks_lift").is_empty(), 40.0)
	var lift_e := _first("stacks_lift")
	note("SLOW ... and fires after the cooldown if the cat is still there (%.1f s after the other line)" % (lift_e.get("start_t", 0.0) - m._last_end if fired else -1.0), fired)
	await wait_until(func(): return not m._busy, 30.0)
	cat3.global_position = Vector2(-5000, -5000)
	current_scene.queue_free()
	await process_frame
	# the same trigger run past: dropped and counted
	_new_game()
	var wc4 := await _world(h3.path, Vector2(-5000, -5000))
	_spawn(wc4.world, h3, ["LiftLine", "SpringHint"])
	m.play("spring_first")
	await wait(1.0)
	wc4.cat.global_position = lift.pos
	await wait(0.3)
	wc4.cat.global_position = Vector2(-5000, -5000)
	await wait(0.3)
	note("SLOW a FILLER trigger the cat only ran through while a line spoke is counted as dropped, never spoken later", m.drop_log.any(func(d): return d[0] == "stacks_lift" and d[1] == "blocked"), str(m.drop_log))
	await wait_until(func(): return not m._busy, 30.0)
	current_scene.queue_free()
	await process_frame


# ---- rules 1-3: objective expiry, the exit hint's order, carried story ----------------------------

func _dropped(id: String, why: String) -> bool:
	return mono().drop_log.any(func(d): return d[0] == id and d[1] == why)


func _played(id: String) -> int:
	return mono().play_log.filter(func(e): return e.id == id).size()


func _rules_objective(wc: Dictionary) -> void:
	var m := mono()
	var cat: Node2D = wc.cat
	var w: Node2D = wc.world
	var door := Node2D.new()
	door.name = "RoomExit"
	door.position = Vector2(1400, 768)
	w.add_child(door)
	var gate := Node2D.new()
	gate.name = "TimedGate"
	gate.position = Vector2(1500, 768)
	w.add_child(gate)
	# O1 a Spring hint is not queued once the cat holds a Spring charge ...
	_new_game()
	cat.global_position = Vector2(1000, 768)
	gs().grant_power(2, 8.0)
	m.play("spring_hint")
	await wait(0.3)
	note("O1 a Spring hint is dropped, not queued, when the cat already has a Spring charge", _dropped("spring_hint", "fulfilled") and _played("spring_hint") == 0 and m._queue.is_empty())
	# ... or while it speaks (cut with the fade) ...
	_new_game()
	cat.global_position = Vector2(1000, 768)
	m.play("spring_hint")
	await wait(1.0)
	gs().grant_power(2, 8.0)
	await wait(0.5)
	note("O1 ... and cut, faded out, if the cat takes the Spring pad while it speaks", _first("spring_hint").get("preempted", false) and not m.voice_active and not m.is_speaking(), str(_first("spring_hint")))
	# ... or once it is above the wall (queued behind a CRITICAL).
	_new_game()
	cat.global_position = Vector2(1000, 768)
	m.play("awakening")
	await wait(0.5)
	m.play("spring_hint_ledge")
	cat.global_position = Vector2(1000, 768 - SPRING_UP)
	await wait(0.2)
	note("O1 a queued Spring hint is dropped once the cat is above the wall", _dropped("spring_hint_ledge", "fulfilled") and m._queue.is_empty())
	# O2 surge_gate: dropped once past the gate
	_new_game()
	cat.global_position = Vector2(1000, 768)
	m.play("awakening")
	await wait(0.5)
	m.play("surge_gate")
	cat.global_position = Vector2(1600, 768)
	await wait(0.2)
	note("O2 surge_gate is dropped once the cat is past the gate", _dropped("surge_gate", "fulfilled"))
	# O3 exit lines: dropped near the door, and when the room is left; kept while the cat lingers
	_new_game()
	cat.global_position = Vector2(1000, 768)
	m.play("awakening")
	await wait(0.5)
	m.play("exit_fence")
	cat.global_position = Vector2(1250, 768)
	await wait(0.2)
	note("O3 exit_fence is dropped once the cat is within the exit distance of the door", _dropped("exit_fence", "fulfilled"))
	_new_game()
	cat.global_position = Vector2(1300, 768)
	m.play("stacks_exit")
	await wait(1.0)
	note("O3 an exit line triggered close to the door still plays while the cat lingers there", _played("stacks_exit") == 1)
	# O4 relays
	_new_game()
	gs().mark_collected("r4_relay1")
	m.play("perimeter_missing_r1")
	m.play("relays_intro")
	m.play("perimeter_missing_many")
	note("O4 a missing-relay hint is dropped once that relay is lit, relays_intro once any is", _dropped("perimeter_missing_r1", "fulfilled") and _dropped("relays_intro", "fulfilled") and not _dropped("perimeter_missing_many", "fulfilled"))
	await wait(0.3)
	m.play("perimeter_missing_r2")
	await wait(0.5)
	note("O4 ... while a hint for a relay still dark plays", _played("perimeter_missing_r2") == 1 or m.is_speaking())
	await wait(8.0)
	# O5 power first-use lines: kept the first time, dropped once the power was taken twice
	_new_game()
	gs().grant_power(1, 5.0)
	m.play("surge_first")
	await wait(0.5)
	note("O5 surge_first plays after the first pad", _played("surge_first") == 1)
	await wait(10.0)
	gs().grant_power(1, 5.0)
	m.reset()
	gs().grant_power(1, 5.0)
	gs().grant_power(1, 5.0)
	m.play("surge_first")
	note("O5 ... and is dropped when the pad has been taken twice", _dropped("surge_first", "fulfilled") and _played("surge_first") == 0)
	gs().clear_power()
	door.queue_free()
	gate.queue_free()


const SPRING_UP := 200.0


func _rules_story(wc: Dictionary) -> void:
	var m := mono()
	var cat: Node2D = wc.cat
	var w: Node2D = wc.world
	# S1 the crate reading comes before the exit hint, whatever order they are asked in
	_new_game()
	cat.global_position = Vector2(1000, 768)
	m.play("awakening")
	await wait(0.5)
	m.play("nanofluid_container")
	m.play("exit_hint")
	var order: Array = m._queue.map(func(q): return q.id)
	note("S1 the exit hint is queued behind the crate reading (not ahead of it)", order == ["nanofluid_container", "exit_hint"], str(order))
	await wait(70.0)
	var seq: Array = m.play_log.map(func(e): return e.id)
	var last_crate: int = seq.rfind("nanofluid_container")
	note("S1 all four crate lines are spoken before the exit hint", _played("nanofluid_container") == 4 and seq.find("exit_hint") > last_crate, str(seq))
	# S2 stale STORY is carried to the map: a room change drops it, the list keeps it
	_new_game()
	cat.global_position = Vector2(1000, 768)
	m.play("awakening")
	await wait(0.5)
	m.play("dock_bot")
	m.play("relay_done")
	m.play("credential")
	var other := Node2D.new()
	other.scene_file_path = "res://scenes/ui/world_map.tscn"
	root.add_child(other)
	current_scene = other
	await wait(0.2)
	note("S2 STORY sets dropped by leaving the room are carried (relay_done is not)", gs().pending_story == ["dock_bot", "credential"] and not _played("dock_bot") > 0, str(gs().pending_story))
	m.reset()
	gs().pending_story = ["dock_bot", "credential", "mirror_bot"]
	ss().session_snapshot = gs().snapshot()
	var n: int = m.play_pending_story()
	await wait(0.3)
	note("S2 the map plays at most %d carried sets per visit and keeps the rest" % m.STORY_PER_MAP, n == 2 and gs().pending_story == ["mirror_bot"], str(gs().pending_story))
	note("S2 the carried queue is in the session snapshot, and restores", ss().session_snapshot.get("pending_story", []) == ["mirror_bot"])
	var snap: Dictionary = gs().snapshot()
	gs().pending_story = []
	gs().restore(snap)
	note("S2 ... through GameState.snapshot / restore", gs().pending_story == ["mirror_bot"])
	ss().save_checkpoint("cp_audit", "res://scenes/levels/room2.tscn")
	gs().pending_story = []
	ss().persist_pending()
	note("S2 and on disk, like the pending memory (written, cleared by new_game)", ss().read_save().get("pending_story", ["x"]) == [])
	gs().pending_story = ["mirror_bot"]
	ss().persist_pending()
	note("S2 ... the save holds the waiting set", ss().read_save().get("pending_story", []) == ["mirror_bot"])
	gs().new_game()
	note("S2 a new game clears it", gs().pending_story.is_empty())
	await wait(40.0)
	other.queue_free()
	current_scene = w
	ss().delete_save()
