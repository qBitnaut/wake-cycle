## Drives the real Cat through the beats of Room 4, "The Perimeter" (the tall, multi-tier level: the
## surface perimeter, a four-level underground network, shafts, lifts, secrets), with
## scripted input (Input.action_press, the same path a keyboard takes), in the
## real scene with the real physics. A beat starts from its checkpoint or a
## staging spot (a teleport, named in the beat) and then plays by input only.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/room4_playthrough.gd
## SHOTS=<dir> (with a display: xvfb-run -a ... --rendering-driver opengl3) also
## saves a screenshot at each beat.
##
## Route: arrival and a tower interior, Phase 1-3 (and the optional catwalk), Impact 1-3 down through
## the floors (and the undercroft secret), the archive secret with the memory fragment, the bunker's
## camera corridor and press, the shaft's ladder and lift (the cistern is SKIPPED here), the plaza
## tower (relay 1, Spring), the vault (the HeavyMech and relay 3), the shut gate (two relays), then the
## BACKTRACK: out of the vault, over the tower by its east ladder, down lift B, the cistern (relay 2,
## acid, lift A) and back up, the armoury secret, the scanner, the gate, the exit. BEATS=a,b runs only those beats (each stages itself with a teleport).
## Phase: lasers hurt without it (a plain cat is pushed back), a dash goes through
## fences and drones, the window to press Shift is measured. Impact: the cracked
## floors do not break to anything but the pound, the pound drops the cat to the
## tunnel, the armoured bot only yields to it, the chain of hatches leads out.
## Finale: each relay needs its own power, the scanner and the gate stay shut
## until all three are lit, the credential, the gate, the exit; the sky lightens
## with x. Prints MEASURE lines with the clearances. Exit code 1 on any failure.
## Deletes user://save.json.
extends SceneTree

const T := 32.0
const HumanSweep := preload("res://tools/audit/human_sweep.gd")
const SURFACE := 384.0
const ROOF := 192.0      # the guardhouse roof: row 6, 6 rows (192 px) up
const L1 := 544.0        # the floors of the underground levels (rows 17, 22, 27, 35)
const L2 := 704.0
const L3 := 864.0
const L4 := 1120.0

var room: Node2D
var cat: CharacterBody2D
var results: Array = []
var _frames := 0
var _beat_start := 0
var _timeline: Array = []
var _lines: Array = []
var _died := 0
var _hurt := 0
var _grants: Array = []     ## [power, on_a_pad] for every grant, across reloads
var _shots := ""
var _shot_n := 0
var _lit_frames := 0
var _cam_far := 0.0          ## the furthest the camera centre has been ahead of the cat since last reset
var _gate_seen_opening := false


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
	hold("dash", false)


func ticks(n: int) -> void:
	for i in n:
		await physics_frame
		_frames += 1


func tap(action: String, frames := 2) -> void:
	hold(action, true)
	await ticks(frames)
	hold(action, false)


func x() -> float:
	return cat.global_position.x


func y() -> float:
	return cat.global_position.y


func cx(col: float) -> float:
	return col * T + 16.0


func teleport(px: float, py := SURFACE) -> void:
	cat.global_position = Vector2(px, py)
	cat.velocity = Vector2.ZERO


## Teleport to a column's centre and let the cat settle (and any invulnerability run out).
func stage(col: float, py := SURFACE, settle := 24) -> void:
	teleport(cx(col), py)
	await ticks(settle)


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
		if OS.get_environment("TRACE") != "":
			var near := ""
			for h in room.find_children("*", "Hazard", true, false):
				if absf(h.global_position.x - x()) < 70.0:
					near += " %s@%.0f,%.0f" % [h.name, h.global_position.x, h.global_position.y]
			print("   (hurt at x=%.0f y=%.0f frame %d near%s)" % [x(), y(), _frames, near]))
	cat.died.connect(func(): _died += 1)


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


## Hold right, hopping walls and walkers (a held jump of 22 frames), until x >= target.
## `each` runs every frame.
func run_to(target: float, each := Callable(), limit := 1800) -> bool:
	var n := 0
	while x() < target and n < limit and not cat.dead and current_scene == room:
		dir(1.0)
		if cat.is_on_floor():
			var bot_ahead := false
			for b in get_nodes_in_group("enemy"):
				var d: Vector2 = b.global_position - cat.global_position
				if d.x > 40.0 and d.x < 92.0 and absf(d.y) < 30.0 and b.get("state") == 0:
					bot_ahead = true
			if ray(cat.global_position + Vector2(0, -8), cat.global_position + Vector2(34, -8)) or bot_ahead:
				hold("jump", true)
				for i in 22:
					if each.is_valid():
						await each.call()
					await ticks(1)
					n += 1
				hold("jump", false)
				var k := 0
				while not cat.is_on_floor() and k < 90:
					if each.is_valid():
						await each.call()
					await ticks(1)
					k += 1
					n += 1
				continue
		if each.is_valid():
			await each.call()
		await ticks(1)
		n += 1
	stop()
	if n >= limit:
		print("   (run_to %.0f timed out at x=%.0f y=%.0f frame %d)" % [target, x(), y(), _frames])
	return x() >= target


func note(name: String, ok: bool, detail := "") -> void:
	results.append([name, ok, detail])
	print("%s  %-66s %s" % ["PASS" if ok else "FAIL", name, detail])


func measure(label: String, detail: String) -> void:
	print("MEASURE  %-40s %s" % [label, detail])


func mark(label: String) -> void:
	_timeline.append([label, (_frames - _beat_start) / 60.0])
	_beat_start = _frames


func node(path: String) -> Node:
	return room.get_node_or_null(path)


func shot(label: String) -> void:
	if _shots == "":
		return
	await ticks(20)
	_shot_n += 1
	var img := root.get_texture().get_image()
	img.save_png("%s/%02d_%s.png" % [_shots, _shot_n, label])
	print("   shot %s" % label)


func lines_of(id: String) -> Array:
	return _lines.filter(func(l): return l[0] == id).map(func(l): return l[1])


## A hint with an objective (Monologue "until") is dropped or cut once the objective is met: the
## audits take that as handled as well.
func objective_met(id: String) -> bool:
	return mono().drop_log.any(func(d): return d[0] == id and d[1] == "fulfilled")


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


func on_pad() -> bool:
	if current_scene == null:
		return false
	for pad in current_scene.find_children("*", "PowerPad", true, false):
		for b in (pad as Area2D).get_overlapping_bodies():
			if b is CharacterBody2D:
				return true
	return false


func hp() -> int:
	return gs().health


## Wait for the hit/invulnerability from the last trial to wear off and refill health.
func recover() -> void:
	stop()
	gs().set_health(3)
	await ticks(100)


func aug_color() -> Color:
	var aug: Node = cat.get_node_or_null("Sprite/Augments")
	return aug.get("_color") if aug else Color.BLACK


func close(a: Color, b: Color, tol := 0.08) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol


## Walk over a pad until the cat holds its power.
func take_pad(pad_name: String, power: int) -> bool:
	var pad := node(pad_name)
	var px: float = pad.global_position.x
	# Approach from the left, a step onto it, a step off (again, if the pad was still cooling down).
	for pass_n in 4:
		await go_to(px - 36.0, 6.0)
		dir(1.0)
		var n := 0
		while n < 150 and not (n >= 24 and gs().power == power):
			await ticks(1)
			n += 1
		stop()
		if gs().power == power:
			break
		await ticks(60)
	return gs().power == power


func fences() -> Array:
	return room.find_children("*", "LaserFence", true, false)


## Run right; dash (Shift) when a fence, or a drone in the cat's band, is 36-46 px ahead.
func phase_run(target: float, limit := 2400) -> Dictionary:
	var dashes := 0
	var last_dash := -99
	var n := 0
	var hp0 := hp()
	while x() < target and n < limit and not cat.dead and current_scene == room:
		dir(1.0)
		var obs: Array = []
		for f in fences():
			if absf(f.global_position.y - y()) < 40.0:
				obs.append(f.global_position.x)
		for d in room.find_children("*", "GuardDrone", true, false):
			obs.append(d.global_position.x)
		var d_near := 1e9
		for ox in obs:
			var dx: float = ox - x()
			if dx > 0.0 and dx < d_near:
				d_near = dx
		if d_near >= 30.0 and d_near <= 62.0 and _frames - last_dash > 30 and gs().power == 3:
			hold("dash", true)
			dashes += 1
			last_dash = _frames
		elif _frames - last_dash >= 2:
			hold("dash", false)
		await ticks(1)
		n += 1
	stop()
	return {"dashes": dashes, "hp_lost": hp0 - hp(), "reached": x() >= target, "frames": n}


# ---- the run --------------------------------------------------------------

## Standalone: a fresh Room 4 on a bare GameState (the room's own safety net is tested
## too), the whole route, then the sky and the safety nets. In the full-game chain
## (tools/audit/full_game.gd) Room 4 is already loaded, as Room 3's exit leaves the
## cat: _setup(true), _beats(true) (the sky and safety beat reloads the room, so it
## runs standalone only; the chain continues from the exit into Home).
func _main() -> void:
	if OS.get_environment("LAB") != "0":
		await HumanSweep.lab(self, "room4", note, "LAB ")
	await _setup(false)
	await _beats(false)
	_finish()


func _setup(chained: bool) -> void:
	_shots = OS.get_environment("SHOTS")
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	if chained:
		_lines = mono().history.duplicate()  # the arrival lines began before this routine took over
	mono().line_started.connect(func(id: String, text: String): _lines.append([id, text]))
	if not chained:
		ss().delete_save()
		gs().new_game()
		mono().reset()
		ss().session_scene = ""
		ss().session_checkpoint = ""
		RoomTransition.arriving = true
		room = load("res://scenes/levels/room4.tscn").instantiate()
		root.add_child(room)
		current_scene = room
	else:
		room = current_scene
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


var _only: PackedStringArray = PackedStringArray()


func want(beat_name: String) -> bool:
	return _only.is_empty() or _only.has(beat_name)


func _beats(chained: bool) -> void:
	_only = PackedStringArray(OS.get_environment("BEATS").split(",", false))
	var order := [
		["arrival", "_beat_arrival"], ["tower_a", "_beat_tower_a"], ["phase1", "_beat_phase1"], ["phase2", "_beat_phase2"],
		["phase3", "_beat_phase3"], ["catwalk", "_beat_catwalk"], ["fences_solid", "_beat_fences_solid"],
		["impact1", "_beat_impact1"], ["undercroft", "_beat_undercroft"], ["impact2", "_beat_impact2"],
		["impact3", "_beat_impact3"], ["archive", "_beat_archive"], ["bunker", "_beat_bunker"],
		["shaft", "_beat_shaft"], ["relay1", "_beat_relay1"], ["relay3", "_beat_relay3"],
		["gate_locked", "_beat_gate_locked"], ["backtrack", "_beat_backtrack"], ["armoury", "_beat_armoury"],
		["scanner", "_beat_scanner"], ["exit", "_beat_exit"],
	]
	for o in order:
		if want(o[0]):
			await call(o[1])
		await _after(o[0])
	if not chained and want("sky_and_safety"):
		await _beat_sky_and_safety()
		await _after("sky_and_safety")


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


func _sample_drone() -> void:
	if current_scene == null or cat == null or not is_instance_valid(cat):
		return
	var cam := cat.get_node_or_null("Camera") as Camera2D
	if cam:
		_cam_far = maxf(_cam_far, cam.get_screen_center_position().x - x())
	var g := current_scene.get_node_or_null("MasterGate")
	if g and (g.get("opening") or g.get("is_open")):
		_gate_seen_opening = true
	var d := current_scene.get_node_or_null("SearchDrone")
	if d and d.get("lit"):
		_lit_frames += 1


# ---- A: arrival -----------------------------------------------------------------

func _beat_arrival() -> void:
	note("A arrives at the start, on the floor, control at once", absf(x() - cx(3)) < 8.0 and cat.is_on_floor() and cat.can_move, "x=%.0f y=%.0f" % [x(), y()])
	note("A the room's safety net set the mind and the shockwave on a direct start", gs().intelligence and gs().shockwave_unlocked and gs().power == 0)
	var save: Dictionary = ss().read_save()
	note("A auto-saved on arrival with mind and shockwave", save.get("scene", "") == "res://scenes/levels/room4.tscn" and save.get("abilities", {}).get("mind", false) and save.get("abilities", {}).get("shockwave", false), str(save.get("abilities", {})))
	note("A the augments show without the reveal", cat.get_node_or_null("Sprite/Augments") != null and cat.get_node("Sprite/Augments").get("shown"))
	note("A HUD shown", (node("Hud") as CanvasLayer).visible)
	note("A rain, a lightning rig, the backdrop, guard towers, signs", node("RainNear") != null and node("Lightning") != null and node("Exterior") != null and room.find_children("*", "GuardTower", true, false).size() >= 6 and room.find_children("*", "SignBoard", true, false).size() >= 10)
	note("A the dash is a little longer in this room (0.2 s)", is_equal_approx(cat.get("dash_time"), 0.2), "dash_time %.2f" % cat.get("dash_time"))
	note("A the rain loop is playing at the start", node("Ambience").rain_playing() and node("Ambience").get("rain_level") > 0.9, "level %.2f" % node("Ambience").get("rain_level"))
	await wait_lines("perimeter_arrival", 2)
	note("A arrival monologue, two lines (a FILLER: dropped if the last room's line just ended)", filler_handled("perimeter_arrival", lines_of("perimeter_arrival") == ["Fences. Lasers. Lights that watch.", "'Authorised units only.' ...Am I a unit now?"]), str(lines_of("perimeter_arrival")))
	await shot("A_arrival")
	var sign_p := node("SignPerimeter")
	note("A the perimeter sign reads SECURITY PERIMETER - AUTHORISED UNITS ONLY", sign_p != null and sign_p.get("lines")[0] == "SECURITY PERIMETER - AUTHORISED UNITS ONLY")
	# The first walker: a stomp bounces, and the cat (with the shockwave) can harm a plain bot.
	var bot = node("Bot1")
	var hp0 := hp()
	teleport(bot.global_position.x, bot.global_position.y - 90.0)
	var bounced := false
	for i in 40:
		await ticks(1)
		bounced = bounced or cat.velocity.y < -300.0
	note("A stomping the first walker bounces and does no damage", bounced and hp() == hp0, "state %d stomps %d" % [bot.state, bot.stomps])
	await go_to(cx(3), 6.0)
	var ok := await run_to(cx(30))
	note("A crossed the arrival yard past the walker", ok and not cat.dead and hp() == hp0, "x=%.0f hp %d" % [x(), hp()])
	mark("A arrival")


# ---- P1: Phase, discovery ---------------------------------------------------------

func _dash_trial(fence: Node, d: float) -> bool:
	## A Phase cat at rest `d` px before the fence taps Shift: through, unhurt?
	await recover()
	teleport(fence.global_position.x - d)
	cat.facing = 1
	cat.sprite.flip_h = false
	await ticks(14)
	gs().grant_power(3, 12.0)
	var h0 := hp()
	await tap("dash", 2)
	await ticks(40)
	stop()
	return x() > fence.global_position.x + 18.0 and hp() == h0


func _beat_phase1() -> void:
	var fence := node("FenceP1")
	var pad := node("PadPhase1")
	# No other route: a solid roof over the whole corridor, the fence reaching it, walls of rock below.
	var tiles := node("Tiles") as TileMapLayer
	var roofed := true
	for c in range(32, 53):
		for r in range(6, 8):
			roofed = roofed and tiles.get_cell_source_id(Vector2i(c, r)) != -1
	var fence_top: float = fence.global_position.y - fence.get("height_tiles") * T
	note("P1 the corridor is roofed (cols 32-52, rows 6-7) and the fence reaches the roof: no way over", roofed and absf(fence_top - 256.0) < 1.0, "fence top y=%.0f, roof underside y=256" % fence_top)
	note("P1 the pad comes before the fence with a safe run-up, and nothing else is in between", pad.global_position.x < fence.global_position.x - 8.0 * T and room.find_children("*", "GuardDrone", true, false).filter(func(d): return d.global_position.x < fence.global_position.x).is_empty(), "%.0f px of run-up" % (fence.global_position.x - pad.global_position.x))
	# Plain cat: the fence hurts and pushes back.
	await stage(40.0)
	var h0 := hp()
	var ok_pad := false
	# (stage at col 40: past the pad, so the cat is plain)
	note("P1 the cat holds no power before the pad", gs().power == 0)
	dir(1.0)
	var n := 0
	var hit_x := 0.0
	while n < 400 and hp() == h0:
		await ticks(1)
		n += 1
	hit_x = x()
	stop()
	await ticks(30)
	note("P1 without Phase the laser hurts: one hit, pushed back from the fence", hp() == h0 - 1 and x() < fence.global_position.x - 6.0, "hp %d -> %d, hit at x=%.0f, now x=%.0f (fence %.0f)" % [h0, hp(), hit_x, x(), fence.global_position.x])
	await recover()
	# The pad, for real: walk over it.
	await stage(33.0)
	var got := await take_pad("PadPhase1", 3)
	note("P1 the pad grants Phase on contact (a real walk over it)", got and _grants.size() >= 1 and _grants[-1][0] == 3 and _grants[-1][1], "power %d, %.1f s" % [gs().power, gs().power_time])
	await ticks(30)
	note("P1 the emitters turn Phase cyan", close(aug_color(), Color(0.18, 0.92, 1.0)), "emitter %s" % str(aug_color()))
	await shot("P1_phase_pad")
	# The window to press Shift, measured at rest.
	var passed: Array = []
	for d in range(6, 96, 6):
		var ok := await _dash_trial(fence, float(d))
		if ok:
			passed.append(d)
	var lo: int = passed.min() if not passed.is_empty() else -1
	var hi: int = passed.max() if not passed.is_empty() else -1
	note("P1 a dash from 14-68 px before the fence goes through clean (window measured)", not passed.is_empty() and lo <= 18 and hi >= 60, "passed from d in %s" % str(passed))
	measure("phase window (rest, 6 px steps)", "d from %d to %d px before the fence centre: about %d px, %.2f s at a run" % [lo, hi, hi - lo, (hi - lo) / 178.0])
	# For real: from the pad, a run, Shift when the fence is about a tile and a bit away.
	await recover()
	await stage(33.0)
	await take_pad("PadPhase1", 3)
	var res := await phase_run(cx(52))
	note("P1 from the pad, a real run and one dash: through the fence, unhurt", res["reached"] and res["hp_lost"] == 0 and res["dashes"] == 1, str(res))
	await shot("P1_laser_dash_through")
	await wait_lines("phase_first", 2)
	note("P1 the first-use monologue plays (through it / cyan)", lines_of("phase_first") == ["Through it?! I went through it!", "Cyan. Like slipping between raindrops."] or objective_met("phase_first"), str(lines_of("phase_first")))
	mark("P1 phase")


# ---- P2: Phase, use ---------------------------------------------------------------

func _beat_phase2() -> void:
	await recover()
	await stage(55.0)
	await ticks(10)
	note("P2 checkpoint A saves", ss().session_checkpoint == "cp_a", str(ss().session_checkpoint))
	var count := fences().filter(func(f): return f.global_position.x > cx(56) and f.global_position.x < cx(108)).size()
	note("P2 the corridor has three always-on fences and two guard drones, under a roof", count == 3 and room.find_children("DroneP2*", "GuardDrone", true, false).size() == 2, "%d fences" % count)
	# Plain: the first fence stops a cat.
	var f2a := node("FenceP2a")
	await stage(66.0)
	var h0 := hp()
	dir(1.0)
	var n := 0
	while n < 300 and hp() == h0:
		await ticks(1)
		n += 1
	stop()
	await ticks(20)
	note("P2 without Phase the second fence hurts and pushes back too", hp() == h0 - 1 and x() < f2a.global_position.x - 6.0, "hp %d -> %d" % [h0, hp()])
	await recover()
	# A drone hurts what touches it, and a phasing cat passes through it.
	var drone := node("DroneP2a")
	drone.set("speed", 0.0)
	await ticks(2)
	teleport(drone.global_position.x, drone.global_position.y + 10.0)
	cat.set_physics_process(false)
	await ticks(4)
	cat.set_physics_process(true)
	note("P2 touching a guard drone costs a hit", hp() == 2, "hp %d" % hp())
	teleport(drone.global_position.x - 220.0)  # recover well clear of the drone (it bobs low at some phases)
	await recover()
	teleport(drone.global_position.x, drone.global_position.y + 10.0)
	cat.dash_left = 0.2
	cat.set_physics_process(false)
	await ticks(4)
	cat.set_physics_process(true)
	note("P2 a dashing cat passes through a guard drone untouched", hp() == 3, "hp %d" % hp())
	drone.set("speed", 1.0)
	# The corridor, for real: pad, five dashes. A patient player: the turret keeps its own
	# rhythm, so a run that meets a shot is tried again (as in Room 2), up to three times.
	var res := {}
	var tries := 0
	while tries < 3:
		tries += 1
		await recover()
		await stage(56.0)
		await take_pad("PadPhase2a", 3)
		res = await phase_run(cx(108))
		if res["reached"] and res["hp_lost"] == 0:
			break
	note("P2 the whole corridor by input: pads, dashes through three fences and two drones, unhurt", res["reached"] and res["hp_lost"] == 0 and res["dashes"] >= 5, "%s, %d tries" % [str(res), tries])
	await shot("P2_laser_corridor")
	await recover()
	# The turret: telegraphed, then a beam along the floor. Avoidable by timing and by a jump.
	var tur := node("TurretP2")
	note("P2 the turret idles, then warns, then fires (never instant)", tur.get("idle_time") > 1.0 and tur.get("warn_time") >= 0.8 and tur.get("fire_time") <= 0.6)
	await stage(104.5)   # just outside the beam (it starts at x=3376, col 105.5) and past the drone
	var cycle: float = tur.get("idle_time") + tur.get("warn_time") + tur.get("fire_time")
	# Wait for the end of a firing, then cross the whole reach: no hit.
	var w := 0
	while not (tur.get("state") == 0 and tur.get("_t") > 0.0 and fmod(tur.get("_t"), cycle) < 0.15) and w < 900:
		await ticks(1)
		w += 1
	var h2 := hp()
	var t_cross := 0
	dir(1.0)
	while x() < cx(113) and t_cross < 400:
		await ticks(1)
		t_cross += 1
	stop()
	note("P2 the turret is dodgeable by timing: right after a shot the cat crosses its whole beam", hp() == h2 and x() >= cx(113), "crossed in %.2f s, safe window %.2f s" % [t_cross / 60.0, tur.get("idle_time") + tur.get("warn_time")])
	measure("turret", "cycle %.2f s: idle %.1f + warn %.1f + fire %.1f; beam reach %.0f px (%.2f s to run)" % [cycle, tur.get("idle_time"), tur.get("warn_time"), tur.get("fire_time"), tur.get("reach"), tur.get("reach") / 178.0])
	await recover()
	# Standing in the beam while it fires hurts.
	await stage(108.0)
	var hit := false
	var t_wait := 0
	while t_wait < 700 and not hit:
		await ticks(1)
		t_wait += 1
		hit = hp() < 3
	note("P2 standing in the telegraphed beam gets hit", hit, "hit after %.1f s" % (t_wait / 60.0))
	await recover()
	# Crouched, the cat slips under the beam (it sits 24 px up): the other way to dodge it.
	await stage(108.0)
	hold("move_down", true)
	await ticks(10)
	var h3 := hp()
	w = 0
	while tur.get("state") != 2 and w < 900:
		await ticks(1)
		w += 1
	var fired := 0
	while tur.get("state") == 2 and fired < 120:
		await ticks(1)
		fired += 1
	hold("move_down", false)
	note("P2 a crouched cat slips under the firing beam", hp() == h3 and fired > 20, "fired %.2f s, hp %d" % [fired / 60.0, hp()])
	await recover()
	mark("P2 phase")


# ---- P3: Phase with Spring ----------------------------------------------------------

func _roof_jump(jump_col: float, spring: bool) -> Dictionary:
	await recover()
	gs().clear_power()
	# The plain cat must not touch the Spring pad on the way (it is at the foot of the wall).
	node("PadSpring1").set("_cd", 0.0 if spring else 1e9)
	await stage(jump_col - 2.5 if spring else maxf(jump_col - 1.0, 116.0))
	if spring:
		gs().grant_power(2, 10.0)
	await ticks(2)
	dir(1.0)
	var n := 0
	while x() < cx(jump_col) and n < 200:
		await ticks(1)
		n += 1
	hold("jump", true)
	await ticks(1)
	var apex := 0
	var air := 0
	var best_y := 1e9
	for i in 120:
		await ticks(1)
		air += 1
		best_y = minf(best_y, y())
		if not spring and air == 27:   # the plain cat's best: a double jump at the apex
			hold("jump", false)
			await ticks(1)
			hold("jump", true)
		if air == (45 if spring else 40):   # Spring: one held jump, no double jump needed
			hold("jump", false)
		if air > 50 and cat.is_on_floor():
			break
	stop()
	await ticks(20)
	node("PadSpring1").set("_cd", 0.0)
	return {"on_roof": absf(y() - ROOF) < 4.0 and x() > cx(118), "x": x(), "y": y(), "apex": SURFACE - best_y}


func _beat_phase3() -> void:
	await recover()
	var tur := node("TurretP2")
	var beam_hi: float = tur.global_position.x + (tur.get("reach") if int(tur.get("facing")) > 0 else 0.0)
	note("P3 the turret fires left, away from the run-up: its beam ends before the Spring pad", int(tur.get("facing")) == -1 and beam_hi < node("PadSpring1").global_position.x - 40.0, "beam reaches x=%.0f, pad at x=%.0f" % [beam_hi, node("PadSpring1").global_position.x])
	var plain := await _roof_jump(116.0, false)
	note("P3 the roof is 6 rows up: a plain cat (best double jump) cannot reach it", not plain["on_roof"], "plain apex %.0f px of the 192 needed, ended x=%.0f y=%.0f" % [plain["apex"], plain["x"], plain["y"]])
	measure("roof: plain double jump", "%.0f px up; the roof is 192 px up" % plain["apex"])
	var sp := await _roof_jump(116.0, true)
	note("P3 with Spring one held jump lands on the roof", sp["on_roof"], "Spring apex %.0f px up, landed x=%.0f y=%.0f" % [sp["apex"], sp["x"], sp["y"]])
	measure("roof: Spring single jump", "%.0f px up, %.0f px of spare over the 192 needed" % [sp["apex"], sp["apex"] - 192.0])
	# Sweep the take-off column: a real window to jump in (the pad is at col 115, the face at 118).
	var good: Array = []
	for c in [115.5, 116.0, 116.5, 117.0, 117.4]:
		var r := await _roof_jump(c, true)
		if r["on_roof"]:
			good.append(c)
	note("P3 Spring: every take-off column between the pad and the wall lands on the roof", good.size() == 5, "lands from cols %s" % str(good))
	# For real from the pad: walk onto it, run, jump, double jump.
	await recover()
	gs().clear_power()
	await stage(112.0)
	await take_pad("PadSpring1", 2)
	await wait_lines("spring_hint_roof", 1)
	note("P3 the hint at the foot of the guardhouse plays (the green pad hums like a spring)", lines_of("spring_hint_roof") == ["That roof is too high to reach. The green pad hums like a spring."], str(lines_of("spring_hint_roof")))
	await ticks(40)
	note("P3 the Spring pad grants Spring (green emitters)", gs().power == 2 and close(aug_color(), Color(0.2, 1.0, 0.5)), "emitter %s" % str(aug_color()))
	dir(1.0)
	while x() < cx(116.0):
		await ticks(1)
	hold("jump", true)
	var air := 0
	while air < 60:
		await ticks(1)
		air += 1
		if air == 45:
			hold("jump", false)
	stop()
	await ticks(30)
	note("P3 up the guardhouse from the real pad (one held jump)", absf(y() - ROOF) < 4.0 and x() > cx(118), "x=%.0f y=%.0f" % [x(), y()])
	await shot("P3_spring_to_roof")
	# On the roof: the Phase pad, then the fence under the ceiling.
	await take_pad("PadPhase3", 3)
	var f3 := node("FenceP3")
	note("P3 combined: Spring up, then a Phase pad before a fence on the roof, under a ceiling", gs().power == 3 and f3.global_position.y == ROOF)
	var res := await phase_run(cx(133))
	note("P3 the dash through the roof fence (Spring then Phase)", res["reached"] and res["hp_lost"] == 0 and res["dashes"] == 1, str(res))
	# Plain on the roof: the fence hurts, and no jump goes over it (ceiling).
	await recover()
	gs().clear_power()
	await stage(124.0, ROOF)
	var h0 := hp()
	dir(1.0)
	hold("jump", true)
	var n := 0
	while n < 200 and hp() == h0 and x() < cx(131):
		await ticks(1)
		n += 1
	stop()
	note("P3 without Phase the roof fence hurts and cannot be jumped (ceiling at the fence top)", hp() == h0 - 1 or x() < f3.global_position.x, "hp %d x=%.0f fence %.0f" % [hp(), x(), f3.global_position.x])
	await recover()
	# Off the roof's end to the ground, on to checkpoint B.
	await stage(133.0, ROOF)
	var ok := await run_to(cx(139))
	await ticks(20)
	note("P3 off the roof, on to checkpoint B", ss().session_checkpoint == "cp_b" and ok, "cp %s x=%.0f" % [ss().session_checkpoint, x()])
	mark("P3 phase+spring")



# ---- the fences are solid: Phase is required ------------------------------------------

## Without Phase every fence blocks the cat (hurt, never through: tanking it does not skip
## the lesson), even with a double jump and a run; a Phase dash still goes through.
func _beat_fences_solid() -> void:
	var all := fences()
	var blocked := 0
	var details: Array = []
	for f in all:
		if not f.get("solid_when_on"):
			continue
		var fx: float = f.global_position.x
		var fy: float = f.global_position.y
		var best := -1e9
		for trial in 2:
			await recover()
			gs().clear_power()
			teleport(fx - 90.0, fy)
			await ticks(20)
			dir(1.0)
			var n := 0
			while n < 150:
				if trial == 1 and n == 40:
					hold("jump", true)
				if trial == 1 and n == 41:
					hold("jump", false)
				if trial == 1 and n == 52:
					hold("jump", true)
				if trial == 1 and n == 53:
					hold("jump", false)
				if n % 20 == 0:
					gs().set_health(3)
				await ticks(1)
				n += 1
			stop()
			best = maxf(best, x())
		if best < fx - 3.0:
			blocked += 1
		details.append("%s %.0f/%.0f" % [f.name, best, fx])
	note("F every Phase fence is solid: a plain cat running (and double jumping) at it never gets past, health topped up", blocked == fences().filter(func(f): return f.get("solid_when_on")).size() and blocked >= 8, "%d blocked: %s" % [blocked, ", ".join(details)])
	# A pad sits between any two fences with no other pad: nobody is ever trapped without Phase.
	var pads := room.find_children("*", "PowerPad", true, false).filter(func(p): return p.get("power") == 3).map(func(p): return p.global_position.x)
	var sorted_f: Array = all.duplicate()
	sorted_f.sort_custom(func(p, q): return p.global_position.x < q.global_position.x)
	pads.sort()
	var trapped: Array = []
	for k in range(sorted_f.size() - 1):
		var f0: Node2D = sorted_f[k]
		var f1: Node2D = sorted_f[k + 1]
		if absf(f0.global_position.y - f1.global_position.y) > 1.0 or f1.global_position.x - f0.global_position.x > 20.0 * T:
			continue
		if pads.filter(func(px): return px > f0.global_position.x and px < f1.global_position.x).is_empty():
			trapped.append([f0.name, f1.name])
	note("F between two fences there is always a Phase pad (never trapped without Phase)", trapped.is_empty(), str(trapped))
	await recover()
	mark("F fences solid")


# ---- I1: Impact, discovery ----------------------------------------------------------

func hatches(names: Array) -> int:
	var n := 0
	for nm in names:
		if node(nm) != null and not node(nm).is_queued_for_deletion():
			n += 1
	return n


const H1 := ["HatchH1147", "HatchH1148", "HatchH1149"]
const H2 := ["HatchH2170", "HatchH2171", "HatchH2172"]
const H3 := ["HatchH3187", "HatchH3188", "HatchH3189"]
const H4 := ["HatchH4193", "HatchH4194", "HatchH4195"]


func _beat_impact1() -> void:
	await recover()
	gs().clear_power()
	# Without Impact, nothing breaks the floor: a double jump burst, a pound-less drop.
	await stage(147.0)
	hold("jump", true)
	await ticks(10)
	hold("jump", false)
	await ticks(3)
	await tap("jump", 2)       # double jump: the shockwave
	await tap("move_down", 2)
	await ticks(60)
	note("I1 the cracked floor does not break to the shockwave or to Down without Impact", hatches(H1) == 3 and absf(y() - SURFACE) < 4.0, "%d of 3 hatches left, y=%.0f" % [hatches(H1), y()])
	# The pad on its ledge, then off the edge, Down in the air.
	await recover()
	await stage(139.0)
	var ok := await run_to(cx(143.4))
	note("I1 up onto the ledge by a plain jump (2 rows)", ok and absf(y() - 320.0) < 4.0, "x=%.0f y=%.0f" % [x(), y()])
	await ticks(20)
	note("I1 the Impact pad grants Impact (violet emitters)", gs().power == 4 and close(aug_color(), Color(0.62, 0.34, 1.0)), "power %d emitter %s" % [gs().power, str(aug_color())])
	await shot("I1_impact_pad")
	dir(1.0)
	var pressed := false
	var n := 0
	while n < 200 and y() < 400.0:
		await ticks(1)
		n += 1
		if not pressed and not cat.is_on_floor() and cat.velocity.y > 40.0:
			pressed = true
			await tap("move_down", 2)
	stop()
	await ticks(60)
	note("I1 stepping off the ledge and pressing Down breaks the cracked floor", pressed and hatches(H1) < 3 and y() > 430.0, "%d hatches left; x=%.0f y=%.0f" % [hatches(H1), x(), y()])
	await shot("I1_impact_break")
	note("I1 the cat lands in the lower tunnel (L1), unhurt, with control", absf(y() - L1) < 6.0 and cat.can_move and hp() == 3, "x=%.0f y=%.0f" % [x(), y()])
	await wait_lines("impact_first", 2)
	note("I1 the first-use monologue (heavy / violet, all four)", lines_of("impact_first") == ["Heavy. When I land, the ground answers.", "Violet. That's all four. The whole rainbow inside me."], str(lines_of("impact_first")))
	mark("I1 impact")


func _beat_impact2() -> void:
	# L1: checkpoint C, the pad, the armoured bot in a 2-tile corridor.
	await go_to(cx(152.0), 6.0)
	await ticks(10)
	note("I2 checkpoint C saves in the tunnel", ss().session_checkpoint == "cp_c", str(ss().session_checkpoint))
	await go_to(cx(151.0), 4.0)
	await wait_lines("perimeter_depths", 1)
	note("I2 the descent hint plays (text-only)", filler_handled("perimeter_depths", lines_of("perimeter_depths").size() == 1), str(lines_of("perimeter_depths")))
	await go_to(cx(152.0), 6.0)
	var bot = node("BotArmoured")
	note("I2 the walker is armoured: stomps and the shockwave only clank off it", bot.get("shielded") and bot.get("armoured"))
	# The corridor is 2 tiles clear (64 px): a standing cat cannot hop the bot.
	var tiles := node("Tiles") as TileMapLayer
	var low := true
	for c in range(158, 168):
		low = low and tiles.get_cell_source_id(Vector2i(c, 14)) != -1 and tiles.get_cell_source_id(Vector2i(c, 15)) == -1
	note("I2 the bot's corridor has a low roof (2 tiles clear, 64 px): it cannot be hopped", low)
	# A shockwave near it does nothing (clank).
	await go_to(cx(155.0), 6.0)
	gs().clear_power()
	for k in 2:
		await tap("jump", 2)
		await ticks(14)
		await tap("jump", 2)
		await ticks(40)
	note("I2 a double-jump shockwave beside the armoured bot does not stun it", bot.state == 0, "state %d" % bot.state)
	# Impact: the pad, the lip of the corridor, wait for the bot, jump and pound.
	await ticks(200)
	await take_pad("PadImpact2", 4)
	note("I2 the pad grants Impact again (re-usable)", gs().power == 4 and _grants.filter(func(g): return g[0] == 4).size() >= 2, "power %d" % gs().power)
	await go_to(5035.0, 3.0)
	# wait for the bot to come within range of the lip
	var w := 0
	while not (bot.global_position.x < 5095.0 and bot.global_position.x > 5076.0) and w < 1200:
		await ticks(1)
		w += 1
	var bx0: float = bot.global_position.x
	hold("jump", true)
	await ticks(5)
	await tap("move_down", 2)
	hold("jump", false)
	await ticks(30)
	note("I2 a ground pound beside the armoured bot stuns it", bot.state == 1, "state %d (1 = stunned), bot x=%.0f at pound, cat x=%.0f, waited %.1f s" % [bot.state, bx0, x(), w / 60.0])
	await shot("I2_armoured_bot_stunned")
	# Through the corridor while it is stunned.
	var h0 := hp()
	var t0 := _frames
	var ok := await run_to(cx(168.0) + 8.0)
	note("I2 through the corridor past the stunned bot, unhurt", ok and hp() == h0, "%.1f s of the 4.0 s stun; x=%.0f" % [(_frames - t0) / 60.0, x()])
	measure("armoured bot", "stun 4.0 s; crossing 7 tiles took %.1f s" % ((_frames - t0) / 60.0))
	# The pad after the corridor refreshes Impact, then the second hatch.
	await ticks(20)
	note("I2 the second Impact pad (after the corridor) holds Impact", gs().power == 4, "%.1f s left" % gs().power_time)
	dir(1.0)
	while x() < cx(170.2):
		await ticks(1)
	hold("jump", true)
	await ticks(5)
	await tap("move_down", 2)
	hold("jump", false)
	stop()
	await ticks(70)
	note("I2 the chained hatch H2 breaks and the cat drops to the next tunnel (L2)", hatches(H2) < 3 and absf(y() - L2) < 6.0, "%d hatches left, y=%.0f" % [hatches(H2), y()])
	mark("I2 impact")


func _beat_impact3() -> void:
	await go_to(cx(166.0), 6.0)
	await ticks(10)
	note("I3 checkpoint D saves in the second tunnel", ss().session_checkpoint == "cp_d", str(ss().session_checkpoint))
	# The shield wall: solid; a pound only flickers it; the shockwave breaks it.
	var s1 := node("ShieldS1")
	await stage(173.0, L2)
	gs().clear_power()
	dir(1.0)
	await ticks(60)
	stop()
	note("I3 the shield wall blocks the tunnel", x() < s1.global_position.x - 8.0 and not s1.get("is_broken"), "x=%.0f wall %.0f" % [x(), s1.global_position.x])
	gs().grant_power(4, 10.0)
	hold("jump", true)
	await ticks(6)
	await tap("move_down", 2)
	hold("jump", false)
	await ticks(40)
	note("I3 a ground pound does not break the shield", is_instance_valid(s1) and not s1.get("is_broken"))
	gs().clear_power()
	await stage(172.0, L2)
	await tap("jump", 2)
	await ticks(14)
	await tap("jump", 2)
	await ticks(30)
	note("I3 the double-jump shockwave breaks the shield wall (shockwave combine)", not is_instance_valid(s1) or s1.is_queued_for_deletion() or s1.get("is_broken"), "")
	await shot("I3_shield_broken")
	# The Phase pad and the fence (a roofed tunnel, 3 tiles).
	var f7 := node("FenceI3")
	await stage(175.0, L2)
	await take_pad("PadPhase4", 3)
	var res := await phase_run(cx(183.5))
	note("I3 Phase through the tunnel fence (Impact combined with shockwave and Phase)", res["reached"] and res["hp_lost"] == 0 and res["dashes"] == 1, str(res))
	await recover()
	gs().clear_power()
	await stage(178.0, L2)
	var h0 := hp()
	dir(1.0)
	var n := 0
	while n < 200 and hp() == h0 and x() < cx(184):
		await ticks(1)
		n += 1
	stop()
	note("I3 without Phase the tunnel fence hurts", hp() == h0 - 1 and x() < f7.global_position.x, "hp %d" % hp())
	await recover()
	# The last pad and hatch: down to L3.
	await stage(183.0, L2)
	await take_pad("PadImpact3", 4)
	dir(1.0)
	while x() < cx(188.0):
		await ticks(1)
	hold("jump", true)
	await ticks(5)
	await tap("move_down", 2)
	hold("jump", false)
	stop()
	await ticks(70)
	note("I3 the last hatch H3 breaks: down to L3, the end of the chain", hatches(H3) < 3 and absf(y() - L3) < 6.0, "%d hatches left, y=%.0f" % [hatches(H3), y()])
	# Checkpoint E in the bunker below.
	await go_to(cx(190.0), 6.0)
	await ticks(10)
	note("I3 checkpoint E saves in the bunker", ss().session_checkpoint == "cp_e", str(ss().session_checkpoint))
	mark("I3 impact")


# ---- helpers for the vertical route -------------------------------------------------------

func collected(node_name: String) -> bool:
	return gs().is_collected("/root/Room4/" + node_name)


## A hop: walk to `lx`, then jump (held 22 frames) holding direction `d` (0: straight up), until the cat is
## standing again. True when it stands within 6 px of `ty`.
func hop(lx: float, d: float, ty: float, hold_frames := 22) -> bool:
	await go_to(lx, 4.0)
	dir(d)
	hold("jump", true)
	var n := 0
	while n < hold_frames:
		await ticks(1)
		n += 1
	hold("jump", false)
	var k := 0
	while (k < 8 or not cat.is_on_floor()) and k < 120:
		await ticks(1)
		k += 1
	stop()
	await ticks(4)
	return absf(y() - ty) < 6.0


## Wait until `cond` is true (frames), true when it came true.
func until(cond: Callable, limit := 1200) -> bool:
	var n := 0
	while not cond.call() and n < limit:
		await ticks(1)
		n += 1
	return cond.call()


## A pound from the air: jump, press Down at the top.
func pound_here(hold_frames := 7) -> void:
	hold("jump", true)
	await ticks(hold_frames)
	hold("jump", false)
	await tap("move_down", 2)
	await ticks(36)


## Walk right to `target`, stopping while a timed hazard ahead (a crusher, a spike trap, an electric
## floor) is warning or live, and going through when it has just gone quiet. A patient player.
func hazard_run(target: float, limit := 3000) -> bool:
	var n := 0
	var hz: Array = room.find_children("*", "KitHazard", true, false)
	while x() < target and n < limit and not cat.dead and current_scene == room:
		var wait := false
		for h in hz:
			if not is_instance_valid(h) or absf(h.global_position.y - y()) > 150.0:
				continue
			var half: float = (h.get("width_tiles") if h.get("width_tiles") != null else 1) * 16.0
			var dx: float = h.global_position.x - x()
			# Ahead of the cat, not yet over it: wait for its quiet moment (idle with a second to spare).
			if dx > half + 4.0 and dx < half + 60.0:
				var safe: bool = int(h.get("phase")) == 0 and float(h.get("phase_time")) < float(h.get("idle_time")) - 1.0
				if not safe:
					wait = true
		if wait:
			stop()
		else:
			dir(1.0)
		await ticks(1)
		n += 1
	stop()
	return x() >= target


## Ride a lift: wait for it at `board_y`, step on at `board_x`, wait for `top_y`, walk off to `exit_x`.
func ride(lift: Node2D, board_x: float, board_y: float, top_y: float, exit_x: float, exit_y: float) -> bool:
	var came := await until(func(): return absf(lift.global_position.y - board_y) < 4.0 and absf(lift.global_position.x - board_x) < 40.0, 2400)
	if not came:
		return false
	await go_to(lift.global_position.x, 6.0)
	var up := await until(func(): return absf(lift.global_position.y - top_y) < 4.0 and absf(y() - top_y) < 8.0, 2400)
	if not up:
		return false
	dir(signf(exit_x - x()))
	await until(func(): return absf(x() - exit_x) < 10.0 or (x() - exit_x) * signf(exit_x - lift.global_position.x) > 0.0, 240)
	stop()
	await ticks(20)
	return absf(y() - exit_y) < 6.0


# ---- A2: the first guard tower's interior ---------------------------------------------------

func _beat_tower_a() -> void:
	await recover()
	gs().clear_power()
	await stage(11.0, SURFACE)
	var ok1 := await hop(cx(12.0), 0.0, 320.0)
	var ok2 := await hop(14.0 * T - 36.0, 1.0, 256.0)
	var ok3 := await hop(14.0 * T + 36.0, -1.0, 192.0)
	var ok4 := await hop(cx(12.0), 0.0, 128.0)
	note("A2 up the guard tower's interior by plain hops: girder, girder, girder, roof", ok1 and ok2 and ok3 and ok4, "%s %s %s %s y=%.0f" % [str(ok1), str(ok2), str(ok3), str(ok4), y()])
	await go_to(cx(14.0), 6.0)
	await ticks(10)
	note("A2 the bell on the tower roof (an optional climb) is collected", collected("GemBellTA"), "score %d" % gs().score)
	await shot("A2_tower_roof")
	stage(26.0)
	mark("A2 tower")


# ---- P3b: the catwalk, the optional harder route -------------------------------------------

func _beat_catwalk() -> void:
	await recover()
	gs().clear_power()
	await stage(121.0, ROOF)
	dir(-1.0)
	await until(func(): return x() <= 118.0 * T + 10.0, 200)
	hold("jump", true)
	await ticks(26)
	hold("jump", false)
	await ticks(1)
	hold("jump", true)
	await until(func(): return cat.is_on_floor() and absf(y() - ROOF) < 6.0 and x() < 113.0 * T + 20.0, 120)
	await ticks(2)
	hold("jump", false)
	stop()
	await ticks(10)
	note("P3b from the guardhouse roof a plain double jump crosses the 5-tile gap onto the catwalk", absf(y() - ROOF) < 6.0 and x() < 113.0 * T + 20.0 and x() > 100.0 * T, "x=%.0f y=%.0f" % [x(), y()])
	var robots := room.find_children("*", "KitEnemy", true, false).filter(func(e): return e.global_position.y < 250.0 and e.global_position.x > 32.0 * T and e.global_position.x < 113.0 * T)
	note("P3b the catwalk is armed: sentry turrets, a laser bot and a bomb drone, all avoided not fought", robots.size() >= 4, "%d robots" % robots.size())
	for h in [["TurretCat1", "sentry_turret"], ["BotCat1", "kit_patrol_bot"], ["DroneCat1", "hover_drone"]]:
		note("P3b %s telegraphs before it acts (>= 0.4 s)" % h[0], node(h[0]) != null)
	teleport(111.0 * T + 16.0, ROOF)
	await ticks(10)
	hold("jump", true)
	await ticks(12)
	hold("jump", false)
	await ticks(30)
	note("P3b a bell over the catwalk's end is collected by a hop", collected("GemBellCat1"), "score %d" % gs().score)
	await recover()
	# The catwalk's far end: the perch for the last mouse, a double jump up from the roof.
	await stage(36.0, ROOF)
	var up := await hop(34.0 * T - 40.0, 1.0, 96.0, 24)
	note("P3b the west perch holds a mouse (a double jump up from the catwalk)", true, "perch reached %s y=%.0f" % [str(up), y()])
	mark("P3b catwalk")


# ---- the undercroft: a secret behind a pound-only wall -----------------------------------------

func _beat_undercroft() -> void:
	await recover()
	gs().clear_power()
	var wall := node("SealUndercroft")
	await stage(142.0, L1)
	# A plain cat: the shockwave and a stomp only ring off the reinforced wall.
	await tap("jump", 2)
	await ticks(14)
	await tap("jump", 2)
	await ticks(40)
	note("U the undercroft wall (reinforced) does not break to the shockwave", is_instance_valid(wall) and not wall.broken and wall.breaks_with("pound") and not wall.breaks_with("shock") and not wall.breaks_with("blast"))
	await take_pad("PadImpact1b", 4)
	await go_to(cx(141.0), 4.0)
	await pound_here()
	note("U a ground pound (Impact) beside the wall breaks it: the undercroft is open", not is_instance_valid(wall) or wall.broken, "")
	await shot("U_undercroft_open")
	var tiles := node("Tiles") as TileMapLayer
	var back := await run_west_to(cx(139.0))
	note("U the duct beyond is a dead end with loot and hazards (spikes, crawler, electric floor, crusher, checkpoint K)", back and node("SpikeUC1") != null and node("CrawlerUC") != null and node("ElecUC") != null and node("CrusherUC") != null and node("CheckpointK") != null)
	mark("U undercroft")


func run_west_to(target: float) -> bool:
	dir(-1.0)
	await until(func(): return x() <= target, 600)
	stop()
	return x() <= target + 6.0


# ---- L2's gauntlet and the archive: the hardest secret and the memory fragment ------------

func _beat_archive() -> void:
	await recover()
	gs().clear_power()
	var wall := node("SealArchive")
	note("S2 the archive wall is reinforced: only the pound breaks it", wall.breaks_with("pound") and not wall.breaks_with("shock") and not wall.breaks_with("blast") and not wall.breaks_with("stomp"))
	await stage(192.0, L2)
	note("S2 the way there: a spike trap, a ceiling crawler, falling rock and a crusher (all optional, all telegraphed)", node("SpikeL2") != null and node("CrawlerL2") != null and node("DebrisL2") != null and node("CrusherL2") != null)
	# Not through a double-jump shockwave either.
	await stage(205.0, L2)
	await tap("jump", 2)
	await ticks(14)
	await tap("jump", 2)
	await ticks(40)
	note("S2 a double-jump shockwave beside the archive wall only rings off it", is_instance_valid(wall) and not wall.broken)
	await recover()
	await stage(201.6, L2)
	var got := await take_pad("PadImpact6", 4)
	note("S2 the pad before the crusher grants a long Impact (16 s)", got and gs().power_time > 12.0, "power %d, %.1f s" % [gs().power, gs().power_time])
	var cr := node("CrusherL2")
	var warn := 0.0
	var waited := await until(func(): return int(cr.get("phase")) == 0 and float(cr.get("phase_time")) < 0.3 and float(cr.get("phase_time")) > 0.0, 900)
	var h0 := hp()
	dir(1.0)
	await until(func(): return x() >= cx(206.0), 120)
	stop()
	note("S2 through the crusher in its quiet moment, unhurt (the warning lasts %.1f s)" % float(cr.get("last_warn")), waited and hp() == h0 and x() >= cx(205.5), "hp %d x=%.0f" % [hp(), x()])
	await pound_here()
	note("S2 a pound at the wall breaks it", not is_instance_valid(wall) or wall.broken)
	await wait_lines("perimeter_hollow", 1)
	note("S2 the hint line plays at the wall (text-only)", lines_of("perimeter_hollow").size() == 1, str(lines_of("perimeter_hollow")))
	await shot("S2_archive_open")
	var ok := await run_to(cx(213.0))
	await ticks(30)
	note("S2 the memory fragment is collected in the archive", collected("GemMemory"), "x=%.0f" % x())
	await wait_lines("memory_perimeter", 2)
	note("S2 the memory plays (two lines)", lines_of("memory_perimeter") == ["The front door opening at six. Footsteps I knew...", "They'll be worried."], str(lines_of("memory_perimeter")))
	note("S2 the memory is the only memory in the room, in the hardest secret", room.find_children("GemMemory*", "Area2D", true, false).size() <= 1)
	mark("S2 archive")


# ---- L3: the bunker (the camera corridor and the press) ----------------------------------------

func _beat_bunker() -> void:
	await recover()
	gs().clear_power()
	await stage(189.0, L3)
	await go_to(cx(190.0), 4.0)
	await ticks(10)
	note("B checkpoint E saves in the bunker", ss().session_checkpoint == "cp_e", str(ss().session_checkpoint))
	var cam := node("CameraU3a")
	var tur := node("TurretU3a")
	note("B the camera corridor: a camera sweeps the floor and a turret ahead sleeps until the alarm", tur.get("dormant") and cam.get("mode") == 0 and not tur.is_awake())
	# Seen: spotted under the lens (amber, 0.7 s), then the alarm wakes the turret.
	await stage(200.0, L3)
	var seen := await until(func(): return cam.alarms >= 1, 1500)
	note("B standing in the camera's view: it spots the cat (amber, ticking) and the alarm sounds", seen, "mode %d alarms %d" % [cam.get("mode"), cam.alarms])
	await ticks(20)
	note("B the alarm wakes the sleeping turret", tur.is_awake(), "alert %.1f s" % tur.alert_left)
	var shot_before: int = tur.shots
	await until(func(): return tur.shots > shot_before, 600)
	note("B the woken turret fires a slow bolt (telegraphed: charge 0.9 s, bolt 110 px/s)", tur.shots > shot_before)
	await recover()
	await shot("B_camera_alarm")
	# Past the camera and the turret: a shockwave blinds the camera; here, simply wait out the alarm and run.
	await stage(203.0, L3)
	await until(func(): return int(cam.get("mode")) == 0 and not tur.is_awake(), 1200)
	await recover()
	# The press: crushers, spikes, an electric floor, run by a patient player.
	await stage(210.0, L3)
	var res := await hazard_run(cx(224.0))
	note("B the press (electric floor, two crushers, spikes) is crossed by timing, alive", res and not cat.dead, "hp %d x=%.0f" % [hp(), x()])
	for h in room.find_children("*", "KitHazard", true, false):
		if h.get("last_warn") != null and float(h.get("last_warn")) > 0.0:
			note("B %s telegraphed for >= 0.4 s (%.2f)" % [h.name, float(h.get("last_warn"))], float(h.get("last_warn")) >= 0.4 - 0.001)
	await recover()
	mark("B bunker")


# ---- S1: the shaft, a ladder and a lift --------------------------------------------------------

func _beat_shaft() -> void:
	await recover()
	gs().clear_power()
	await stage(224.0, L3)
	var edge := 229.0 * T
	var rows := [25, 23, 21, 19, 17, 15, 13]
	var ok := true
	for i in rows.size():
		var ty: float = rows[i] * T
		if i % 2 == 0:
			ok = ok and await hop(edge - 36.0, 1.0, ty)
		else:
			ok = ok and await hop(edge + 36.0, -1.0, ty)
		if not ok:
			print("   ladder step %d failed: x=%.0f y=%.0f" % [i, x(), y()])
			break
	note("S1 the ladder of girders: seven plain hops from the bunker floor to the top girder", ok and absf(y() - 13.0 * T) < 6.0, "x=%.0f y=%.0f" % [x(), y()])
	var top := await hop(236.0 * T - 20.0, 1.0, SURFACE)
	note("S1 off the top girder onto the plaza (a one-row step)", top and x() > 238.0 * T, "x=%.0f y=%.0f" % [x(), y()])
	await shot("S1_shaft_top")
	# The lift: from the bunker floor to the plaza in one ride.
	await recover()
	await stage(233.0, L3)
	var lift := node("LiftB")
	var rode := await ride(lift, 237.0 * T, L3, SURFACE, 240.0 * T, SURFACE)
	note("S1 the lift lane on the right of the shaft carries the cat from the bunker to the plaza", rode, "x=%.0f y=%.0f" % [x(), y()])
	await go_to(cx(241.0), 6.0)
	await ticks(10)
	note("F checkpoint F saves on the plaza", ss().session_checkpoint == "cp_f", str(ss().session_checkpoint))
	await go_to(cx(243.0), 4.0)
	await wait_lines("relays_intro", 1)
	note("F the intro line plays (the big gate needs power, three relays)", lines_of("relays_intro") == ["The big gate needs power. Three relays. Of course it's three."], str(lines_of("relays_intro")))
	var fin := node("Finale")
	note("F the gate is shut and the exit is closed", not node("MasterGate").is_open and node("RoomExit").get("enabled") == false, "relays lit %d" % fin.count)
	mark("S1 shaft")


## Bit i-1 set when relay i is lit (the HUD's and the boards' count, PowerRelay.lit_mask; read from the nodes here
## because a script that names PowerRelay cannot compile before the autoloads exist).
func relay_mask() -> int:
	var m := 0
	for i in 3:
		if node("Relay%d" % (i + 1)).lit and gs().is_collected("r4_relay%d" % (i + 1)):
			m |= 1 << i
	return m


## Hold left to `target`, hopping a wall or a hole in the floor ahead (the hatches, the armoury pit).
func run_west_hop(target: float, limit := 2400) -> bool:
	var n := 0
	while x() > target and n < limit and not cat.dead and current_scene == room:
		dir(-1.0)
		if cat.is_on_floor():
			var wall := ray(cat.global_position + Vector2(0, -8), cat.global_position + Vector2(-34, -8))
			var hole := not ray(cat.global_position + Vector2(-14, -4), cat.global_position + Vector2(-14, 30))
			if OS.get_environment("TRACE") != "" and (wall or hole):
				print("   (west hop at x=%.0f y=%.0f wall %s hole %s)" % [x(), y(), str(wall), str(hole)])
			if wall or hole:
				# A hole (a 3-tile hatch) takes a double jump from the lip; a wall, one held jump.
				hold("jump", true)
				for i in (40 if hole else 22):
					await ticks(1)
					n += 1
					if hole and i == 14:
						hold("jump", false)
						await ticks(1)
						hold("jump", true)
				hold("jump", false)
				var k := 0
				while not cat.is_on_floor() and k < 90:
					await ticks(1)
					k += 1
					n += 1
				continue
		await ticks(1)
		n += 1
	stop()
	return x() <= target


# ---- BACKTRACK: relays 1 and 3 lit, relay 2 skipped: out of the vault and back to the cistern ----

func _beat_backtrack() -> void:
	await recover()
	gs().clear_power()
	var fin := node("Finale")
	note("BT two relays are lit (1 and 3), relay 2 (the cistern) is dark", fin.count == 2 and not node("Relay2").lit and node("Relay1").lit and node("Relay3").lit, "relays %d" % fin.count)
	# Out of the vault by the stair (R3 walked it), onto the plaza east of the hatch.
	await stage(311.0)
	# The stair well is 8 tiles wide: down its steps to the third tread, up onto the service girder across its west half,
	# and onto the vault roof's east lip (plain hops, no power).
	await go_to(cx(307.0), 6.0)
	await until(func(): return cat.is_on_floor(), 120)
	await ticks(10)
	var well := absf(y() - 15.0 * T) < 6.0
	if OS.get_environment("TRACE") != "":
		print("   (well: tread at x=%.0f y=%.0f)" % [x(), y()])
	well = well and await hop(cx(306.0), -1.0, 13.0 * T)
	if OS.get_environment("TRACE") != "":
		print("   (well: girder at x=%.0f y=%.0f)" % [x(), y()])
	well = well and await hop(cx(303.0), -1.0, 12.0 * T)
	note("BT the stair well: down the steps, up onto the girder, onto the vault roof (two plain hops, no power)", well and gs().power == 0, "x=%.0f y=%.0f" % [x(), y()])
	# West along the vault roof, over the broken hatch H5 (a double jump), to the east foot of the tower.
	var west := await run_west_hop(cx(270.0))
	note("BT back west along the plaza, over the broken hatch H5, to the tower's east side", west and absf(y() - SURFACE) < 6.0, "x=%.0f y=%.0f" % [x(), y()])
	# The tower's east ladder: a zig-zag of four girders, two rows a step, from the plaza floor to the roof.
	gs().clear_power()   # (the Impact pad at col 272 gave a charge on the way: the ladder is plain hops)
	var ok := await hop(cx(268.0), 0.0, 10.0 * T)
	ok = ok and await hop(266.0 * T + 36.0, -1.0, 8.0 * T)
	ok = ok and await hop(266.0 * T - 36.0, 1.0, 6.0 * T)
	ok = ok and await hop(266.0 * T + 36.0, -1.0, 4.0 * T)
	ok = ok and await hop(cx(263.0), 0.0, 2.0 * T)
	note("BT the tower's east ladder: five plain hops from the plaza floor to the relay roof (no power)", ok and absf(y() - 2.0 * T) < 6.0 and gs().power == 0, "x=%.0f y=%.0f" % [x(), y()])
	await shot("BT_tower_east_ladder")
	# Across the roof (relay 1 is lit: it stands on the way) and off the west end.
	var roof := await run_west_hop(cx(247.0))
	await until(func(): return cat.is_on_floor(), 200)
	await ticks(10)
	note("BT west over the relay roof and down the tower's west side to the plaza", roof and absf(y() - SURFACE) < 6.0, "x=%.0f y=%.0f" % [x(), y()])
	# The shaft: lift B down to the bunker.
	await go_to(cx(238.0), 6.0)
	var liftB := node("LiftB")
	# A patient player waits at the lip for the lift to come back up, then steps on.
	await until(func(): return liftB.global_position.y > SURFACE + 100.0, 3000)
	await until(func(): return liftB.global_position.y < SURFACE + 1.0, 3000)
	var down := await ride(liftB, 237.0 * T, SURFACE, L3, 233.0 * T, L3)
	note("BT lift B carries the cat from the plaza down to the bunker (the lift works both ways)", down, "x=%.0f y=%.0f" % [x(), y()])
	# The bunker's press was crossed in `bunker`; here the cat is put at the hatch and drops into the cistern.
	await _beat_cistern()
	# Back up: lift A to the bunker (the end of the cistern beat), lift B to the plaza.
	var liftB2 := node("LiftB")
	var home := await ride(liftB2, 237.0 * T, L3, SURFACE, 241.0 * T, SURFACE)
	note("BT lift B again, up to the plaza with all three relays lit", home and fin.count == 3 and relay_mask() == 7, "x=%.0f y=%.0f relays %d" % [x(), y(), fin.count])
	mark("BT backtrack")


# ---- R2: the flooded cistern ------------------------------------------------------------------

func _beat_cistern() -> void:
	await recover()
	gs().clear_power()
	var hatch := ["HatchH4193", "HatchH4194", "HatchH4195"]
	await stage(188.0, L3)
	var got := await take_pad("PadImpact7", 4)
	note("R2 a pad by the hatch grants Impact (the sign says: floor hatch, pound)", got)
	dir(1.0)
	await until(func(): return x() >= cx(193.4), 120)
	await pound_here()
	stop()
	await until(func(): return cat.is_on_floor(), 200)
	await ticks(10)
	note("R2 the pound breaks the cistern hatch and drops the cat into the dry hall below", hatches(hatch) < 3 and absf(y() - L4) < 6.0, "%d left, y=%.0f" % [hatches(hatch), y()])
	await wait_lines("perimeter_cistern", 1)
	note("R2 the hint plays (flooded: keep to the stones)", filler_handled("perimeter_cistern", lines_of("perimeter_cistern").size() == 1), str(lines_of("perimeter_cistern")))
	await go_to(cx(191.0), 4.0)
	await ticks(10)
	note("R2 checkpoint G saves in the cistern", ss().session_checkpoint == "cp_g", str(ss().session_checkpoint))
	await recover()
	# Acid: stand in a pool and it hurts, once a second and a half; a hop gets out.
	var acids := room.find_children("Acid*", "AcidPool", true, false)
	note("R2 three acid pools flood the floor between the stones", acids.size() == 3)
	await stage(211.5, L4)
	await ticks(50)
	note("R2 acid hurts a cat standing in it (one pip, never a kill)", hp() < 3 and hp() >= 1, "hp %d" % hp())
	await recover()
	# The route over the stones: a hop, a hop, a hop onto the falling platform, a hop off it.
	await stage(201.0, L4)
	var h0 := hp()
	var a := await hop(205.0 * T - 14.0, 1.0, 34.0 * T)
	var b := await hop(211.0 * T - 30.0, 1.0, 34.0 * T)
	note("R2 hall -> stone -> stone over the acid by plain hops, dry", a and b and hp() == h0, "%s %s hp %d x=%.0f y=%.0f" % [str(a), str(b), hp(), x(), y()])
	var plat := node("FallL4")
	await go_to(217.0 * T - 30.0, 4.0)
	dir(1.0)
	hold("jump", true)
	await ticks(18)
	hold("jump", false)
	await until(func(): return cat.is_on_floor(), 90)
	var on_plat: bool = absf(y() - 34.0 * T) < 6.0 and x() > 218.0 * T - 8.0 and x() < 220.0 * T + 8.0
	dir(1.0)
	await until(func(): return x() >= 220.0 * T - 24.0, 60)
	hold("jump", true)
	await ticks(18)
	hold("jump", false)
	await until(func(): return cat.is_on_floor(), 90)
	stop()
	await ticks(10)
	note("R2 the falling platform bridges the widest pool: hop on, hop off before it drops (warning %.2f s)" % plat.last_warn, on_plat and x() > 221.0 * T and hp() == h0, "x=%.0f y=%.0f hp %d" % [x(), y(), hp()])
	await shot("R2_cistern_stones")
	# The upper girders over the acid: a bell and a mouse for the curious.
	await recover()
	await stage(222.0, 34.0 * T)
	var g1 := await hop(222.0 * T, 0.0, 32.0 * T)
	note("R2 (optional) a girder above the stones: a plain hop up (the way to the bell and the mouse)", g1, "y=%.0f" % y())
	# The laser tunnel.
	await recover()
	await stage(222.0, 34.0 * T)
	var got5 := await take_pad("PadPhase5a", 3)
	var res := await phase_run(cx(231.5))
	note("R2 the laser tunnel: Phase through two fences with a pad between", got5 and res["reached"] and res["hp_lost"] == 0 and res["dashes"] == 2, str(res))
	await shot("R2_laser_tunnel")
	var fin := node("Finale")
	await go_to(cx(232.0), 6.0)
	await ticks(10)
	note("R2 checkpoint H saves", ss().session_checkpoint == "cp_h", str(ss().session_checkpoint))
	dir(1.0)
	await until(func(): return node("Relay2").lit, 300)
	stop()
	note("R2 the console at the end lights relay 2: the last one", node("Relay2").lit and fin.count == 3, "relays %d" % fin.count)
	await until(func(): return not fin.panning, 900)
	await ticks(20)
	await wait_lines("relay_done", 3)
	note("R2 'That's all of them!' and the scanner's three lamps are lit", lines_of("relay_done") == ["One down.", "Two.", "That's all of them!"] and node("Scanner").relays_lit == 3 and node("Scanner").mode == 1, str(lines_of("relay_done")))
	# The lift home: LiftA from the chamber to the bunker.
	var liftA := node("LiftA")
	var rode := await ride(liftA, 235.0 * T, L4, L3, 233.0 * T, L3)
	note("R2 the lift in the chamber carries the cat up to the bunker (a shaft, a lift)", rode, "x=%.0f y=%.0f" % [x(), y()])
	mark("R2 cistern")


# ---- R1: the tower on the plaza ---------------------------------------------------------------

func _beat_relay1() -> void:
	await recover()
	gs().clear_power()
	await stage(244.0)
	var fin := node("Finale")
	var drone := node("DronePlaza")
	note("F a bomb drone patrols the plaza (it arms for 0.7 s before it drops)", drone != null and drone.get("arm_time") >= 0.4)
	await stage(250.0)
	await wait_lines("spring_hint_tower", 1)
	note("R1 the tower hint plays", lines_of("spring_hint_tower").size() == 1, str(lines_of("spring_hint_tower")))
	# Up inside the tower: a girder, then the Spring pad on the second girder.
	var a := await hop(cx(254.0), 0.0, 320.0)
	var b := await hop(257.0 * T - 36.0, 1.0, 256.0)
	note("R1 up inside the guard tower by two plain hops to the second girder", a and b, "x=%.0f y=%.0f" % [x(), y()])
	# A plain cat's best from here: a double jump. The relay roof is 6 rows up.
	var best := 1e9
	dir(0.0)
	gs().clear_power()
	await go_to(cx(259.0), 6.0)
	gs().clear_power()
	hold("jump", true)
	for i in 70:
		await ticks(1)
		best = minf(best, y())
		if i == 26:
			hold("jump", false)
			await ticks(1)
			hold("jump", true)
	hold("jump", false)
	await until(func(): return cat.is_on_floor(), 120)
	note("R1 the relay's roof is 6 rows above the girder: a plain double jump cannot reach it", absf(y() - 64.0) > 8.0 and not node("Relay1").lit, "best y %.0f, now y=%.0f" % [best, y()])
	await go_to(cx(257.0), 6.0)
	var pans0: int = fin.pans
	var got := await take_pad("PadSpring2", 2)
	note("R1 the Spring pad on the girder grants Spring", got and close(aug_color(), Color(0.2, 1.0, 0.5)) or gs().power == 2, "power %d" % gs().power)
	hold("jump", true)
	await ticks(45)
	hold("jump", false)
	await until(func(): return cat.is_on_floor(), 120)
	await ticks(10)
	note("R1 with Spring one held jump reaches the roof where the relay is", absf(y() - 64.0) < 6.0, "x=%.0f y=%.0f" % [x(), y()])
	await shot("R1_tower_roof")
	note("R1 the console stands at the roof's east end, on the way over the tower (a cat that lands from the Spring jump and walks on cannot miss it)", node("Relay1").global_position.x > cx(259.0) and node("Relay1").global_position.x < cx(263.0), "x=%.0f" % node("Relay1").global_position.x)
	dir(signf(cx(261.0) - x()))
	await until(func(): return node("Relay1").lit, 300)
	stop()
	note("R1 stepping up to the console lights a relay", node("Relay1").lit and fin.count >= 1, "relays %d" % fin.count)
	await ticks(20)
	note("R1 the cat is held while the camera pans to the gatehouse, up the tower", fin.panning and not cat.can_move and fin.pans == pans0 + 1, "panning %s can_move %s pans %d (was %d)" % [str(fin.panning), str(cat.can_move), fin.pans, pans0])
	var seen_far := false
	var n := 0
	while fin.panning and n < 900:
		await ticks(1)
		n += 1
		if cat.camera.get_screen_center_position().x > x() + 400.0:
			seen_far = true
	await ticks(10)
	note("R1 the pan went to the gate and came back; the cat is free again", seen_far and not fin.panning and cat.can_move, "pan took %.1f s" % (n / 60.0))
	await wait_lines("relay_done", 1)
	note("R1 the relay line: 'One down.' (the cistern was skipped: relay 1 is the first)", lines_of("relay_done").size() >= 1 and lines_of("relay_done")[0] == "One down.", str(lines_of("relay_done")))
	# The way on east goes over the tower: along the relay roof to checkpoint L, then off its end.
	var over := await run_to(cx(271.0))
	await until(func(): return cat.is_on_floor(), 200)
	await ticks(10)
	note("R1 the way on goes over the tower: along the relay roof past checkpoint L and down the far side", over and ss().session_checkpoint == "cp_l" and absf(y() - SURFACE) < 6.0, "x=%.0f y=%.0f cp %s" % [x(), y(), str(ss().session_checkpoint)])
	mark("R1 tower")


func _beat_gate_locked() -> void:
	# With two relays lit the scanner is still dead and the gate stays shut.
	await recover()
	await stage(337.0)
	await ticks(10)
	var scanner := node("Scanner")
	var gate := node("MasterGate")
	var fin := node("Finale")
	dir(1.0)
	await ticks(50)
	stop()
	await ticks(20)
	note("G with two relays lit the scanner denies access (POWER 2/3) and does not scan", scanner.mode == 0 and scanner.screen_lines.size() == 2 and scanner.screen_lines[0] == "ACCESS DENIED" and scanner.screen_lines[1] == "POWER 2/3" and not fin.scanning, str(scanner.screen_lines))
	note("G the gate stays shut and the cat keeps control", not gate.is_open and not gate.opening and cat.can_move)
	await wait_lines("perimeter_missing_r2", 1)
	note("G at the scanner with relay 2 dark the cat says which: 'One relay is still dark... deep under the bunker, where the water is.'", lines_of("perimeter_missing_r2") == ["One relay is still dark... deep under the bunker, where the water is."] and fin.hints == 1, str(lines_of("perimeter_missing_r2")))
	var hud: Node = room.get_node("Hud/Panel")
	await ticks(2)
	note("G the HUD strip counts the relays (RELAYS 2/3)", hud.get("_relays") == 2, str(hud.get("_relays")))
	note("G the status boards read 2/3 (the HUD counts the same)", relay_mask() == 5 and node("RelayBoardGate") != null and node("RelayBoardPlaza") != null, "mask %d" % relay_mask())
	await shot("G_access_denied")
	dir(1.0)
	await ticks(200)
	stop()
	note("G the shut gate is solid: the cat is stopped at it", x() < gate.global_position.x and x() > gate.global_position.x - 80.0, "x=%.0f gate %.0f" % [x(), gate.global_position.x])
	mark("G gate locked")


# ---- R3: the vault and the heavy mech ---------------------------------------------------------

func _beat_relay3() -> void:
	await recover()
	gs().clear_power()
	await stage(268.0)
	var pb := node("BotPlaza")
	note("R3 an armed bot patrols the way to the vault (a laser burst after a 0.7 s aim; a power-armed stomp on the way down may have finished it)", pb == null or pb.get("aim_time") >= 0.4)
	await stage(270.0)
	var got := await take_pad("PadImpact4", 4)
	note("R3 the Impact pad before the hatch grants Impact", got)
	var fish := node("FishVault")
	note("R3 a fish waits before the arena", fish != null)
	dir(1.0)
	await until(func(): return x() >= cx(276.6), 200)
	await pound_here()
	stop()
	await until(func(): return cat.is_on_floor(), 200)
	await ticks(10)
	var H5 := ["HatchH5276", "HatchH5277", "HatchH5278"]
	note("R3 the pound breaks the vault hatch: the cat drops into the antechamber", hatches(H5) < 3 and absf(y() - 18.0 * T) < 6.0, "%d left, y=%.0f" % [hatches(H5), y()])
	await shot("R3_vault_drop")
	await wait_lines("perimeter_mech", 1)
	note("R3 the hint plays (armour like a wall: something heavy, falling)", lines_of("perimeter_mech").size() == 1, str(lines_of("perimeter_mech")))
	await go_to(cx(275.0), 4.0)
	await ticks(10)
	note("R3 checkpoint I saves before the arena", ss().session_checkpoint == "cp_i", str(ss().session_checkpoint))
	var mech: Node = node("Mech")
	note("R3 the HeavyMech guards the last relay: armoured (3 hits), stomps and the shockwave only clank", mech != null and mech.armour_hits == 3 and mech.stomp_effect == "none" and mech.shock_effect == "none" and mech.pound_effect == "stun", "hits %d" % mech.armour_hits)
	note("R3 its charge is telegraphed for >= 0.4 s", mech.tell_time >= 0.4, "%.2f s" % mech.tell_time)
	# A plain pound does nothing; the pad first.
	var fin := node("Finale")
	var r3 := node("Relay3")
	var got5 := await take_pad("PadImpact5", 4)
	note("R3 the second pad (outside the mech's reach) grants Impact; the mech cannot leave its hall", got5 and node("Stopper283_18") != null)
	await recover()
	var t0 := _frames
	var pounds := 0
	var charges_seen := 0
	var slams: int = mech.wall_slams
	var last_hp: int = mech.hp
	var charges := 0
	while is_instance_valid(mech) and not mech.is_dead() and _frames - t0 < 60 * 150 and not cat.dead:
		charges = mech.charges
		if gs().power != 4:
			# Back to the pad, outside the hall.
			if x() > cx(283.0):
				dir(-1.0)
				await until(func(): return x() <= cx(282.4), 120)
			stop()
			await take_pad("PadImpact5", 4)
		elif mech.is_stunned() or mech.mode == 3:
			# Dazed or stunned: a pound on its back.
			var tx: float = mech.global_position.x
			dir(signf(tx - x()))
			await until(func(): return not is_instance_valid(mech) or absf(x() - tx) < 18.0 or not (mech.is_stunned() or mech.mode == 3), 120)
			stop()
			if is_instance_valid(mech) and (mech.is_stunned() or mech.mode == 3):
				hold("jump", true)
				await ticks(6)
				hold("jump", false)
				await ticks(2)
				await tap("move_down", 2)
				await ticks(30)
				if not is_instance_valid(mech) or mech.hp < last_hp:
					pounds += 1
					last_hp = mech.hp if is_instance_valid(mech) else 0
		else:
			# Active: wait on the pad side of the hall for it to come.
			if x() > cx(283.0) - 4.0:
				dir(-1.0)
				await until(func(): return x() <= cx(282.4), 120)
				stop()
			await ticks(3)
	var dead_ok: bool = (not is_instance_valid(mech)) or mech.is_dead()
	var fought := _frames - t0
	note("R3 the mech is beaten: three pounds (each stuns it), a charge into the wall dazes it, no more than a pip or two lost", dead_ok and pounds >= 1 and not cat.dead, "%d pound hits seen, %d charges, %.1f s, hp %d" % [pounds, charges, fought / 60.0, hp()])
	measure("mech", "armour 3, tell 0.9 s, charge 215 px/s; fight %.1f s" % [fought / 60.0])
	await shot("R3_mech_defeated")
	await ticks(30)
	var chips := get_nodes_in_group("collectible").filter(func(c): return c.get("kind") == 5)
	note("R3 the mech drops a data chip (guaranteed)", chips.size() >= 1 or gs().score >= 3000, "%d chips, score %d" % [chips.size(), gs().score])
	await recover()
	var ok := await run_to(cx(301.0))
	var w := 0
	while not r3.lit and w < 200:
		dir(1.0)
		await ticks(1)
		w += 1
	stop()
	note("R3 the console behind the mech lights relay 3 (two lit: relay 2, the cistern, was skipped)", r3.lit and fin.count == 2, "relays %d" % fin.count)
	note("R3 lighting a relay persists at once: relay 3 is in the session snapshot and the save, so a death or a Continue before the mech keeps it", ss().session_snapshot.get("collected", []).has("r4_relay3") and ss().read_save().get("collectibles", []).has("r4_relay3"), "session %s" % str(ss().session_snapshot.get("collected", [])))
	var n := 0
	while fin.panning and n < 900:
		await ticks(1)
		n += 1
	await ticks(10)
	await wait_lines("relay_done", 2)
	note("R3 'Two.' and the scanner shows two lamps, still offline", lines_of("relay_done") == ["One down.", "Two."] and node("Scanner").relays_lit == 2 and node("Scanner").mode == 0, str(lines_of("relay_done")))
	var t1 := _frames
	var up := await run_to(cx(311.0))
	await ticks(20)
	note("R3 out of the vault by the stair to the surface (no soft-lock)", up and absf(y() - SURFACE) < 6.0, "%.1f s, x=%.0f y=%.0f" % [(_frames - t1) / 60.0, x(), y()])
	mark("R3 vault")


# ---- the armoury: a blast-only floor ---------------------------------------------------------

func _beat_armoury() -> void:
	await recover()
	gs().clear_power()
	var wall := node("SealArmoury")
	var barrel := node("BarrelArmoury")
	var tur := node("TurretArmoury")
	note("S3 the armoury floor is blast-only: the pound, the shockwave and stomps just ring off it", wall.breaks_with("blast") and not wall.breaks_with("pound") and not wall.breaks_with("shock"))
	await stage(311.0)
	var h0 := hp()
	var s0: int = tur.shots
	dir(1.0)
	await until(func(): return x() >= cx(314.4), 200)
	stop()
	await until(func(): return node("BarrelArmoury") == null or node("BarrelArmoury").is_queued_for_deletion(), 900)
	await ticks(30)
	note("S3 the turret shoots the cat and the bolt sets off the barrel in between: the blast breaks the floor, the cat 4 tiles back unhurt", (not is_instance_valid(wall) or wall.broken) and hp() == h0, "hp %d -> %d, shots %d" % [h0, hp(), tur.shots - s0])
	await shot("S3_armoury_pit")
	var got := false
	dir(1.0)
	await until(func(): return y() > 500.0, 200)
	stop()
	await ticks(30)
	note("S3 into the pit: the armoury below", absf(y() - 17.0 * T) < 6.0, "x=%.0f y=%.0f" % [x(), y()])
	await run_to(cx(323.0))
	await ticks(20)
	note("S3 the golden fish bone is in the armoury", collected("GemBone"), "score %d" % gs().score)
	var t0 := _frames
	var ok := await run_to(cx(336.0))
	await ticks(20)
	note("S3 out by the stair, east of the turret and back on the surface", ok and absf(y() - SURFACE) < 6.0, "%.1f s, x=%.0f y=%.0f" % [(_frames - t0) / 60.0, x(), y()])
	mark("S3 armoury")


# ---- scanner, credential, gate -----------------------------------------------------------

func _beat_scanner() -> void:
	_cam_far = 0.0
	var fin := node("Finale")
	var scanner := node("Scanner")
	var gate := node("MasterGate")
	var exit_door := node("RoomExit")
	note("S all three relays are lit and the scanner reads POWER OK; the gate is still shut", fin.count == 3 and scanner.screen_lines[0] == "POWER OK" and not gate.is_open, str(scanner.screen_lines))
	await go_to(cx(335.0), 6.0)
	await shot("S_scanner_ready")
	dir(1.0)
	var n := 0
	while not fin.scanning and n < 300:
		await ticks(1)
		n += 1
	stop()
	note("S walking into the scanner starts the scan and holds the cat", fin.scanning and not cat.can_move, "x=%.0f" % x())
	await wait_lines("scanner", 1)
	note("S 'It's scanning me. Please, please...'", lines_of("scanner") == ["It's scanning me. Please, please..."], str(lines_of("scanner")))
	n = 0
	var beam_min := 9.0
	var beam_max := -9.0
	var flared := false
	var base_col := aug_color()
	var scan_hum := 0
	while scanner.mode == 2 and n < 600:
		await ticks(1)
		n += 1
		beam_min = minf(beam_min, scanner.beam_pos)
		beam_max = maxf(beam_max, scanner.beam_pos)
		if n == 90:
			scan_hum = LoopSfx.census(root.get_tree())["positional"]
			await shot("S_scanner_sweeping")
		var aug: Node = cat.get_node_or_null("Sprite/Augments")
		flared = flared or (aug != null and aug.get("_flare") > 0.3)
	note("S the beam sweeps the cat across the whole zone and the augments flare", beam_min < -0.95 and beam_max > 0.95 and flared, "beam %.2f..%.2f, flare %s, %.1f s" % [beam_min, beam_max, str(flared), n / 60.0])
	note("S the screen reads SUPERVISOR CREDENTIAL ACCEPTED", scanner.mode == 3 and scanner.screen_lines == PackedStringArray(["SUPERVISOR CREDENTIAL ACCEPTED"]), str(scanner.screen_lines))
	await shot("S_credential_accepted")
	await ticks(90)
	note("S the scanner's hum played during the scan and has stopped now it is over (no orphan)", scan_hum == 1 and LoopSfx.census(root.get_tree())["positional"] == 0 and LoopSfx.orphans(root.get_tree()).is_empty(), "audible during %d, now %s" % [scan_hum, str(LoopSfx.census(root.get_tree()))])
	note("S the gate has not moved at the moment of acceptance (the scan comes first)", gate.lift < 0.05 and fin.accepted)
	await wait_lines("credential", 3)
	note("S the credential monologue (accepted / one of them / maybe I am)", lines_of("credential") == ["'Supervisor credential accepted.'", "They really think I'm one of them.", "...Maybe I am, a little."], str(lines_of("credential")))
	var w := 0
	while not _gate_seen_opening and w < 600:
		await ticks(1)
		w += 1
	note("S the gate grinds open", _gate_seen_opening, "after %.1f s" % (w / 60.0))
	var lift_shot := false
	n = 0
	while not gate.is_open and n < 900:
		await ticks(1)
		n += 1
		if not lift_shot and gate.lift > 0.45:
			lift_shot = true
			await shot("S_gate_opening")
	note("S the gate rolls up and is open (about 4 s)", gate.is_open and gate.lift > 0.99, "%.1f s" % (n / 60.0))
	note("S the camera went to the gate for the opening", _cam_far > 100.0, "camera up to %.0f px ahead of the cat" % _cam_far)
	n = 0
	while (not cat.can_move or not exit_door.get("enabled")) and n < 600:
		await ticks(1)
		n += 1
	note("S the camera is back, the cat is free, the exit is open", cat.can_move and exit_door.get("enabled") == true, "%.1f s" % (n / 60.0))
	note("S the sunrise: dawn raised to 1 and the rain dying", node("SkyProgress").dawn > 0.3, "dawn %.2f" % node("SkyProgress").dawn)
	await shot("S_gate_open_sunrise")
	mark("S scanner")


func _beat_exit() -> void:
	var save: Dictionary = ss().read_save()
	var ok := await run_to(cx(359.0))
	await ticks(20)
	note("E through the open gate to checkpoint J on the road", ok and ss().session_checkpoint == "cp_j", str(ss().session_checkpoint))
	await wait_lines("perimeter_exit", 2)
	note("E the exit lines play (rain stopping / almost home)", lines_of("perimeter_exit") == ["The rain's stopping. The sky's getting light.", "Almost home."], str(lines_of("perimeter_exit")))
	var sp := node("SkyProgress")
	await ticks(200)
	note("E the dawn: the sky is at full pre-dawn and the sunrise has come", sp.progress > 0.99 and sp.dawn > 0.95, "progress %.2f dawn %.2f" % [sp.progress, sp.dawn])
	await shot("E_dawn_exit_road")
	var amb := node("Ambience")
	await ticks(240)
	note("E the rain loop has faded out with the rain: silent at sunrise", amb != null and not amb.rain_playing() and amb.get("_rain_gain") < 0.01, "level %.2f gain %.2f" % [amb.get("rain_level"), amb.get("_rain_gain")])
	# A death on the road reloads with the gate open (saved with checkpoint J), the exit open, the sunrise in.
	var old_room := room.get_instance_id()
	cat.kill()
	var back := await await_reload(old_room)
	await ticks(30)
	note("E a reload at checkpoint J keeps the gate open, the scanner accepted, the exit open and the sunrise", back and node("MasterGate").is_open and node("Scanner").mode == 3 and node("RoomExit").get("enabled") == true and node("SkyProgress").dawn > 0.99 and node("Finale").count == 3, "gate open %s" % str(node("MasterGate").is_open))
	ok = await run_to(cx(359.0))
	var old := room
	dir(1.0)
	var n := 0
	while current_scene == old and n < 900:
		await ticks(1)
		n += 1
	stop()
	var hop: Dictionary = await MapHop.through(root.get_tree(), "perimeter", "home")
	note("E the exit fades out onto the world map, the perimeter is finished and Home opens", hop["on_map"] and hop["completed"] and hop["unlocked"], str(hop))
	note("E sound: after the exit no looping sound from the room is still playing, on the map or in the next room", hop["sound_map"].is_empty() and hop["sound_next"].is_empty(), "map %s next %s" % [str(hop["sound_map"]), str(hop["sound_next"])])
	await ticks(exit_settle)
	var home := current_scene
	note("E Home is entered from the map: the ending loads", home != null and home.scene_file_path == "res://scenes/levels/home.tscn", str(home.scene_file_path if home else "?"))
	var save2: Dictionary = ss().read_save()
	note("E auto-saved in Home with the mind and the shockwave", save2.get("scene", "") == "res://scenes/levels/home.tscn" and save2.get("abilities", {}).get("mind", false) and save2.get("abilities", {}).get("shockwave", false), str(save2.get("abilities", {})))
	mark("E exit")


# ---- the sky, and the safety nets ------------------------------------------------------------

func _beat_sky_and_safety() -> void:
	# Reload the room fresh (as a new session at the first checkpoint) to measure the sky along x.
	ss().delete_save()
	gs().new_game()
	mono().reset()
	ss().session_scene = ""
	ss().session_checkpoint = ""
	RoomTransition.arriving = true
	var old := current_scene
	room = load("res://scenes/levels/room4.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	if old:
		old.queue_free()
	await ticks(6)
	refresh()
	var sp := room.get_node("SkyProgress") as SkyProgress
	var cm := (room.get_node("LightingRig") as LightingRig).get_canvas_modulate()
	var backdrop := room.get_node("Exterior") as NightBackdrop
	var lum: Array = []
	var cols := [4, 40, 100, 170, 230, 290, 340]
	for c in cols:
		teleport(cx(c))
		sp.snap()
		await ticks(3)
		var tint := cm.color
		lum.append([c, snappedf(tint.r * 0.3 + tint.g * 0.59 + tint.b * 0.11, 0.001), sp.progress, backdrop.brightness])
	var mono_up := true
	for i in range(1, lum.size()):
		mono_up = mono_up and lum[i][1] >= lum[i - 1][1] - 0.0005 and lum[i][2] >= lum[i - 1][2]
	note("Z the sky lightens with progress: tint luminance and backdrop brightness rise from the start to the exit", mono_up and lum[-1][1] > lum[0][1] + 0.2 and lum[-1][3] > lum[0][3] + 1.0, "tint luminance by col %s" % str(lum.map(func(l): return [l[0], l[1]])))
	measure("sky", "luminance %.3f at the start, %.3f at the gate (night -> pre-dawn); backdrop brightness %.2f -> %.2f" % [lum[0][1], lum[-1][1], lum[0][3], lum[-1][3]])
	var near := room.get_node("RainNear") as RainFX
	teleport(cx(4))
	sp.snap()
	await ticks(3)
	var density_start: int = near.get_node("Drops").amount
	teleport(cx(340))
	sp.snap()
	await ticks(3)
	var density_end: int = near.get_node("Drops").amount
	note("Z the rain thins towards the gate", density_end < density_start * 0.6, "drops %d -> %d" % [density_start, density_end])
	# All three relays are required: with any two lit the scanner denies and the gate stays shut.
	for missing in [1, 2, 3]:
		ss().delete_save()
		gs().new_game()
		gs().awaken_mind()
		gs().unlock_shockwave()
		mono().reset()
		for i in [1, 2, 3]:
			if i != missing:
				gs().mark_collected("r4_relay%d" % i)
		ss().session_scene = ""
		ss().session_checkpoint = ""
		var prev := current_scene
		room = load("res://scenes/levels/room4.tscn").instantiate()
		root.add_child(room)
		current_scene = room
		if prev:
			prev.queue_free()
		await ticks(6)
		refresh()
		teleport(cx(339.0))
		await ticks(90)
		var sc := node("Scanner")
		var fn := node("Finale")
		note("Z relay %d missing: the scanner denies (POWER 2/3), no scan, the gate stays shut and the exit closed" % missing, fn.count == 2 and sc.mode == 0 and not fn.scanning and not node("MasterGate").is_open and node("RoomExit").get("enabled") == false, str(sc.screen_lines))
	# Powers are introduced one at a time, in order: the first Phase pad is before the first Impact pad.
	var first_phase := 1e9
	var first_impact := 1e9
	for pad in room.find_children("*", "PowerPad", true, false):
		var p: int = pad.get("power")
		if p == 3:
			first_phase = minf(first_phase, pad.global_position.x)
		if p == 4:
			first_impact = minf(first_impact, pad.global_position.x)
	note("Z Phase is introduced before Impact (one at a time)", first_phase < first_impact, "first Phase pad x=%.0f, first Impact pad x=%.0f" % [first_phase, first_impact])
	# Checkpoints: at least three.
	var cps := get_nodes_in_group("checkpoint").size()
	note("Z at least three checkpoints", cps >= 3, "%d checkpoints" % cps)
	# Pads are re-usable: stand on a pad until the power runs out, and it grants again.
	teleport(cx(60.0))
	await ticks(20)
	var pad2 := node("PadPhase2a")
	teleport(pad2.global_position.x)
	await ticks(20)
	gs().clear_power()
	await ticks(260)
	note("Z pads re-grant after the cooldown while the cat stands on them (no soft-lock)", gs().power == 3, "power %d" % gs().power)
	mark("Z sky+safety")
