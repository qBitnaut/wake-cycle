## Drives the real Cat through every beat of Room 4, "The Perimeter", with
## scripted input (Input.action_press, the same path a keyboard takes), in the
## real scene with the real physics. A beat starts from its checkpoint or a
## staging spot (a teleport, named in the beat) and then plays by input only.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/room4_playthrough.gd
## SHOTS=<dir> (with a display: xvfb-run -a ... --rendering-driver opengl3) also
## saves a screenshot at each beat.
##
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
const SURFACE := 320.0
const L1 := 448.0
const L2 := 576.0
const L3 := 704.0

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
	# Approach from the left, a step onto it, a step off.
	await go_to(px - 36.0, 6.0)
	dir(1.0)
	var n := 0
	while gs().power != power and n < 420:
		await ticks(1)
		n += 1
	stop()
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
		if d_near >= 34.0 and d_near <= 46.0 and _frames - last_dash > 30 and gs().power == 3:
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

func _main() -> void:
	_shots = OS.get_environment("SHOTS")
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	ss().delete_save()
	gs().new_game()
	mono().reset()
	# As Room 3 leaves the cat: mind awake, shockwave unlocked, no power. The room's own safety net
	# is tested too (BEAT A starts from a bare GameState on purpose).
	mono().line_started.connect(func(id: String, text: String): _lines.append([id, text]))
	ss().session_scene = ""
	ss().session_checkpoint = ""
	RoomTransition.arriving = true
	room = load("res://scenes/levels/room4.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await ticks(4)
	refresh()
	gs().power_changed.connect(func(p: int, _d: float):
		if p != 0:
			_grants.append([p, on_pad()]))
	process_frame.connect(_sample_drone)

	await _beat_arrival()
	await _beat_phase1()
	await _beat_phase2()
	await _beat_phase3()
	await _beat_impact1()
	await _beat_impact2()
	await _beat_impact3()
	await _beat_relay1()
	await _beat_relay2()
	await _beat_gate_locked()
	await _beat_relay3()
	await _beat_scanner()
	await _beat_exit()
	await _beat_sky_and_safety()

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
	await wait_lines("perimeter_arrival", 2)
	note("A arrival monologue, two lines", lines_of("perimeter_arrival") == ["Fences. Lasers. Lights that watch.", "'Authorised units only.' ...Am I a unit now?"], str(lines_of("perimeter_arrival")))
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
		for r in range(-3, 6):
			roofed = roofed and tiles.get_cell_source_id(Vector2i(c, r)) != -1
	var fence_top: float = fence.global_position.y - fence.get("height_tiles") * T
	note("P1 the corridor is roofed (cols 32-52, rows -3..5) and the fence reaches the roof: no way over", roofed and absf(fence_top - 192.0) < 1.0, "fence top y=%.0f, roof underside y=192" % fence_top)
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
	note("P1 the first-use monologue plays (through it / cyan)", lines_of("phase_first") == ["Through it?! I went through it!", "Cyan. Like slipping between raindrops."], str(lines_of("phase_first")))
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
	await recover()
	teleport(drone.global_position.x, drone.global_position.y + 10.0)
	cat.dash_left = 0.2
	cat.set_physics_process(false)
	await ticks(4)
	cat.set_physics_process(true)
	note("P2 a dashing cat passes through a guard drone untouched", hp() == 3, "hp %d" % hp())
	drone.set("speed", 1.0)
	await recover()
	# The corridor, for real: pad, five dashes.
	await stage(56.0)
	await take_pad("PadPhase2a", 3)
	var h1 := hp()
	var res := await phase_run(cx(108))
	note("P2 the whole corridor by input: pads, dashes through three fences and two drones, unhurt", res["reached"] and res["hp_lost"] == 0 and res["dashes"] >= 5, str(res))
	await shot("P2_laser_corridor")
	await recover()
	# The turret: telegraphed, then a beam along the floor. Avoidable by timing and by a jump.
	var tur := node("TurretP2")
	note("P2 the turret idles, then warns, then fires (never instant)", tur.get("idle_time") > 1.0 and tur.get("warn_time") >= 0.8 and tur.get("fire_time") <= 0.6)
	await stage(101.5)   # just outside the beam (it starts at x=3312, col 103.5)
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
	await stage(jump_col - 2.5 if spring else maxf(jump_col - 1.0, 115.4))
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
		if air == 27:
			hold("jump", false)
			await ticks(1)
			hold("jump", true)
		if air == 40:
			hold("jump", false)
		if air > 50 and cat.is_on_floor():
			break
	stop()
	await ticks(20)
	return {"on_roof": absf(y() - 96.0) < 4.0 and x() > cx(118), "x": x(), "y": y(), "apex": SURFACE - best_y}


func _beat_phase3() -> void:
	await recover()
	var plain := await _roof_jump(116.0, false)
	note("P3 the roof is 7 rows up: a plain cat (best double jump) cannot reach it", not plain["on_roof"], "plain apex %.0f px of the 224 needed, ended x=%.0f y=%.0f" % [plain["apex"], plain["x"], plain["y"]])
	measure("roof: plain double jump", "%.0f px up; the roof is 224 px up" % plain["apex"])
	var sp := await _roof_jump(116.0, true)
	note("P3 with Spring the same jump lands on the roof", sp["on_roof"], "Spring apex %.0f px up, landed x=%.0f y=%.0f" % [sp["apex"], sp["x"], sp["y"]])
	measure("roof: Spring double jump", "%.0f px up, %.0f px of spare over the 224 needed" % [sp["apex"], sp["apex"] - 224.0])
	# Sweep the take-off column: a real window to jump in.
	var good: Array = []
	for c in [114.5, 115.0, 115.5, 116.0, 116.5, 117.0, 117.4]:
		var r := await _roof_jump(c, true)
		if r["on_roof"]:
			good.append(c)
	note("P3 Spring: a comfortable window of take-off columns lands on the roof", good.size() >= 4, "lands from cols %s" % str(good))
	# For real from the pad: walk onto it, run, jump, double jump.
	await recover()
	gs().clear_power()
	await stage(112.0)
	await take_pad("PadSpring1", 2)
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
		if air == 27:
			hold("jump", false)
			await ticks(1)
			hold("jump", true)
		if air == 40:
			hold("jump", false)
	stop()
	await ticks(30)
	note("P3 up the guardhouse from the real pad", absf(y() - 96.0) < 4.0 and x() > cx(118), "x=%.0f y=%.0f" % [x(), y()])
	await shot("P3_spring_to_roof")
	# On the roof: the Phase pad, then the fence under the ceiling.
	await take_pad("PadPhase3", 3)
	var f3 := node("FenceP3")
	note("P3 combined: Spring up, then a Phase pad before a fence on the roof, under a ceiling", gs().power == 3 and f3.global_position.y == 96.0)
	var res := await phase_run(cx(133))
	note("P3 the dash through the roof fence (Spring then Phase)", res["reached"] and res["hp_lost"] == 0 and res["dashes"] == 1, str(res))
	# Plain on the roof: the fence hurts, and no jump goes over it (ceiling).
	await recover()
	gs().clear_power()
	await stage(124.0, 96.0)
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
	await stage(133.0, 96.0)
	var ok := await run_to(cx(139))
	await ticks(20)
	note("P3 off the roof, on to checkpoint B", ss().session_checkpoint == "cp_b" and ok, "cp %s x=%.0f" % [ss().session_checkpoint, x()])
	mark("P3 phase+spring")


# ---- I1: Impact, discovery ----------------------------------------------------------

func hatches(names: Array) -> int:
	var n := 0
	for nm in names:
		if node(nm) != null and not node(nm).is_queued_for_deletion():
			n += 1
	return n


const H1 := ["HatchH1a", "HatchH1b", "HatchH1c"]
const H2 := ["HatchH2170", "HatchH2171", "HatchH2172"]
const H3 := ["HatchH3187", "HatchH3188", "HatchH3189"]
const H4 := ["HatchH4299", "HatchH4300", "HatchH4301"]


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
	note("I1 up onto the ledge by a plain jump (2 rows)", ok and absf(y() - 256.0) < 4.0, "x=%.0f y=%.0f" % [x(), y()])
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
	var w1 := node("WallGate")
	mark("I1 impact")


func _beat_impact2() -> void:
	# L1: checkpoint C, the pad, the armoured bot in a 2-tile corridor.
	await go_to(cx(152.0), 6.0)
	await ticks(10)
	note("I2 checkpoint C saves in the tunnel", ss().session_checkpoint == "cp_c", str(ss().session_checkpoint))
	var bot = node("BotArmoured")
	note("I2 the walker is armoured: stomps and the shockwave only clank off it", bot.get("shielded") and bot.get("armoured"))
	# The corridor is 2 tiles clear (64 px): a standing cat cannot hop the bot.
	var tiles := node("Tiles") as TileMapLayer
	var low := true
	for c in range(158, 168):
		low = low and tiles.get_cell_source_id(Vector2i(c, 11)) != -1 and tiles.get_cell_source_id(Vector2i(c, 12)) == -1
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
	# Checkpoint E, the stair, out to the surface.
	await go_to(cx(191.0), 6.0)
	await ticks(10)
	note("I3 checkpoint E saves", ss().session_checkpoint == "cp_e", str(ss().session_checkpoint))
	var t0 := _frames
	var ok := await run_to(cx(209.0))
	note("I3 the stair climbs out of the tunnels to the surface (no soft-lock)", ok and absf(y() - SURFACE) < 6.0, "%.1f s, x=%.0f y=%.0f" % [(_frames - t0) / 60.0, x(), y()])
	mark("I3 impact")


# ---- the relays -----------------------------------------------------------------------

func _beat_relay1() -> void:
	await recover()
	gs().clear_power()
	await stage(209.0)
	await go_to(cx(211.0), 4.0)
	await ticks(10)
	note("F checkpoint F saves on the plaza", ss().session_checkpoint == "cp_f", str(ss().session_checkpoint))
	await go_to(cx(213.0), 4.0)
	await wait_lines("relays_intro", 1)
	note("F the intro line plays (the big gate needs power, three relays)", lines_of("relays_intro") == ["The big gate needs power. Three relays. Of course it's three."])
	var fin := node("Finale")
	note("F three relays exist and none is lit; the gate is shut and the exit is closed", fin.count == 0 and not node("MasterGate").is_open and node("RoomExit").get("enabled") == false and node("Scanner").relays_lit == 0)
	await shot("F_plaza_relay_sign")
	# Relay 1 sits on a tower 7 rows up: a plain double jump cannot reach it.
	var plain := await _tower_jump(false)
	note("R1 the tower is 7 rows up: a plain cat cannot reach the relay", not plain["on_tower"] and not node("Relay1").lit, "apex %.0f px of 224" % plain["apex"])
	var sp := await _tower_jump(true)
	note("R1 with Spring (pad at col 217) the cat reaches the tower top", sp["on_tower"], "apex %.0f px, x=%.0f y=%.0f" % [sp["apex"], sp["x"], sp["y"]])
	await ticks(2)
	# The relay lights; the finale pans to the gate and back.
	var pans0: int = fin.pans
	dir(1.0)
	var w := 0
	while not node("Relay1").lit and w < 300:
		await ticks(1)
		w += 1
	stop()
	note("R1 stepping up to the console lights relay 1", node("Relay1").lit and fin.count == 1, "relays %d" % fin.count)
	await ticks(20)
	note("R1 the cat is held while the camera pans to the gatehouse", fin.panning and not cat.can_move and fin.pans == pans0 + 1)
	var seen_far := false
	var n := 0
	while fin.panning and n < 900:
		await ticks(1)
		n += 1
		if cat.camera.get_screen_center_position().x > x() + 800.0:
			seen_far = true
	await ticks(10)
	note("R1 the pan went to the gate and came back; the cat is free again", seen_far and not fin.panning and cat.can_move, "pan took %.1f s" % (n / 60.0))
	await wait_lines("relay_done", 1)
	note("R1 'One down.'", lines_of("relay_done") == ["One down."], str(lines_of("relay_done")))
	note("R1 the scanner's first lamp is lit", node("Scanner").relays_lit == 1)
	await shot("R1_relay_lit")
	# Off the tower's right edge, to checkpoint G.
	var ok := await run_to(cx(233.0))
	await ticks(20)
	note("R1 down from the tower to checkpoint G", ok and ss().session_checkpoint == "cp_g", str(ss().session_checkpoint))
	mark("R1 spring tower")


func _tower_jump(spring: bool) -> Dictionary:
	await recover()
	gs().clear_power()
	await stage(219.0)
	if spring:
		await take_pad("PadSpring2", 2)
	await go_to(cx(219.0) + 10.0, 4.0) if not spring else await ticks(1)
	dir(1.0)
	var jump_col := 219.5 if not spring else 219.5
	while x() < cx(jump_col) + 36.0:
		await ticks(1)
	hold("jump", true)
	var air := 0
	var best_y := 1e9
	while air < 110:
		await ticks(1)
		air += 1
		best_y = minf(best_y, y())
		if air == 27:
			hold("jump", false)
			await ticks(1)
			hold("jump", true)
		if air == 40:
			hold("jump", false)
		if air > 50 and cat.is_on_floor():
			break
	stop()
	await ticks(20)
	return {"on_tower": absf(y() - 96.0) < 4.0 and x() > cx(222.0), "x": x(), "y": y(), "apex": SURFACE - best_y}


func _beat_relay2() -> void:
	# A death at checkpoint G brings the cat back with relay 1 still lit (saved with the checkpoint).
	await recover()
	var old_room := room.get_instance_id()
	cat.kill()
	var back := await await_reload(old_room)
	var fin2 := node("Finale")
	note("R2 after a death the checkpoint restores relay 1 (lit, scanner 1/3) and the broken hatches stay broken", back and node("Relay1").lit and node("Relay1").restored and fin2.count == 1 and node("Scanner").relays_lit == 1 and hatches(H1) < 3 and absf(x() - cx(233.0)) < 14.0, "relays %d, x=%.0f" % [fin2.count, x()])
	# The searchlight drone between the tower and the maze.
	await recover()
	gs().clear_power()
	await stage(233.0)
	await ticks(10)
	var h0 := hp()
	_lit_frames = 0
	var drone := node("SearchDrone")
	var ok := await run_to(cx(244.0))
	note("R2 the searchlight drone is triggered and a running cat stays ahead of it, never seen", ok and drone.get("state") >= 1 and _lit_frames == 0 and not drone.get("alarmed"), "drone state %d, lit %d frames, x=%.0f" % [drone.get("state"), _lit_frames, x()])
	await shot("R2_searchlight_drone")
	# Seen: standing in the beam raises the alarm and sends the cat back to checkpoint G (no death, no hit).
	await recover()
	var old0 := room.get_instance_id()
	ss().respawn()      # (a fresh drone: it is one-shot)
	await await_reload(old0)
	drone = node("SearchDrone")
	await ticks(10)
	var old_id := room.get_instance_id()
	var died0 := _died
	var hp_seen := hp()
	teleport(cx(238.0))
	var wd := 0
	while not drone.get("alarmed") and wd < 1200:
		await ticks(1)
		wd += 1
	var alarm_after := wd / 60.0
	var reloaded := await await_reload(old_id)
	note("R2 standing in the searchlight raises the alarm and sends the cat back to checkpoint G: no death, no hit", reloaded and absf(x() - cx(233.0)) < 14.0 and ss().session_checkpoint == "cp_g" and _died == died0 and hp() == hp_seen and cat.can_move, "after %.1f s, back at x=%.0f" % [alarm_after, x()])
	drone = node("SearchDrone")
	# The maze: plain, the first fence hurts.
	await recover()
	gs().clear_power()
	await stage(248.0)
	var f := node("FenceR2a")
	var h1 := hp()
	dir(1.0)
	var n := 0
	while n < 300 and hp() == h1:
		await ticks(1)
		n += 1
	stop()
	await ticks(20)
	note("R2 without Phase the maze's first fence hurts and pushes back", hp() == h1 - 1 and x() < f.global_position.x, "hp %d" % hp())
	await recover()
	# The maze for real: pad, three fences and a drone, the plate at the end.
	await stage(243.5)
	await take_pad("PadPhase5a", 3)
	var res := await phase_run(cx(281.0))
	note("R2 Phase through the laser maze: three fences and a drone, unhurt", res["reached"] and res["hp_lost"] == 0 and res["dashes"] >= 4, str(res))
	var fin := node("Finale")
	var pans0: int = fin.pans
	await go_to(cx(282.0), 6.0)
	var w := 0
	while not node("Relay2").lit and w < 120:
		await ticks(1)
		w += 1
	note("R2 the plate at the end lights relay 2", node("Relay2").lit and fin.count == 2, "relays %d" % fin.count)
	await shot("R2_relay_lit")
	var n2 := 0
	while fin.panning and n2 < 800:
		await ticks(1)
		n2 += 1
	await ticks(10)
	await wait_lines("relay_done", 2)
	note("R2 'Two.' and the camera was back with the cat", lines_of("relay_done") == ["One down.", "Two."] and cat.can_move and fin.pans == pans0 + 1, str(lines_of("relay_done")))
	var ok2 := await run_to(cx(289.0))
	await ticks(20)
	note("R2 out of the maze to checkpoint H", ok2 and ss().session_checkpoint == "cp_h", str(ss().session_checkpoint))
	mark("R2 phase maze")


func _beat_gate_locked() -> void:
	# With two relays lit the scanner is still dead and the gate stays shut.
	await recover()
	await stage(329.0)
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
	await shot("G_access_denied")
	# The gate blocks the way: running at it from the scanner stops at the door.
	dir(1.0)
	await ticks(200)
	stop()
	note("G the shut gate is solid: the cat is stopped at it", x() < gate.global_position.x and x() > gate.global_position.x - 80.0, "x=%.0f gate %.0f" % [x(), gate.global_position.x])
	mark("G gate locked")


func _beat_relay3() -> void:
	# Relay 3: Impact opens the hatch above the vault, the shockwave breaks the shield.
	await recover()
	gs().clear_power()
	await stage(291.0)
	var s2 := node("ShieldS2")
	var r3 := node("Relay3")
	await take_pad("PadImpact4", 4)
	dir(1.0)
	while x() < cx(300.0):
		await ticks(1)
	stop()
	# (Without Impact the floor does not break: shown at the first hatch.) Here the real thing.
	hold("jump", true)
	await ticks(5)
	await tap("move_down", 2)
	hold("jump", false)
	stop()
	await ticks(70)
	note("R3 the hatch above the vault breaks to the pound and drops the cat into the vault", hatches(H4) < 3 and absf(y() - L1) < 6.0, "%d hatches left, y=%.0f" % [hatches(H4), y()])
	await shot("R3_vault_drop")
	# The relay is behind a shield wall.
	await go_to(cx(303.0), 6.0)
	dir(1.0)
	await ticks(50)
	stop()
	note("R3 the relay alcove is shielded: the shield blocks the way", x() < s2.global_position.x and not r3.lit, "x=%.0f shield %.0f" % [x(), s2.global_position.x])
	var fin := node("Finale")
	var pans0: int = fin.pans
	await tap("jump", 2)
	await ticks(14)
	await tap("jump", 2)
	await ticks(30)
	note("R3 a double-jump shockwave breaks the shield", not is_instance_valid(s2) or s2.is_queued_for_deletion() or s2.get("is_broken"))
	await go_to(cx(309.0), 6.0)
	var w := 0
	while not r3.lit and w < 200:
		await ticks(1)
		w += 1
	note("R3 the switch in the vault lights relay 3", r3.lit and fin.count == 3, "relays %d" % fin.count)
	await shot("R3_relay_lit")
	var n := 0
	while fin.panning and n < 800:
		await ticks(1)
		n += 1
	await ticks(10)
	await wait_lines("relay_done", 3)
	note("R3 'That's all of them!' and the scanner's three lamps are lit", lines_of("relay_done") == ["One down.", "Two.", "That's all of them!"] and node("Scanner").relays_lit == 3 and node("Scanner").mode == 1, str(lines_of("relay_done")))
	# Out of the vault by the stair.
	var t0 := _frames
	var ok := await run_to(cx(318.0))
	await ticks(20)
	note("R3 out of the vault by the stair to checkpoint I (no soft-lock)", ok and absf(y() - SURFACE) < 6.0 and ss().session_checkpoint == "cp_i", "%.1f s, cp %s" % [(_frames - t0) / 60.0, ss().session_checkpoint])
	mark("R3 vault")


# ---- scanner, credential, gate -----------------------------------------------------------

func _beat_scanner() -> void:
	_cam_far = 0.0
	var fin := node("Finale")
	var scanner := node("Scanner")
	var gate := node("MasterGate")
	var exit_door := node("RoomExit")
	note("S all three relays are lit and the scanner reads POWER OK; the gate is still shut", fin.count == 3 and scanner.screen_lines[0] == "POWER OK" and not gate.is_open, str(scanner.screen_lines))
	await go_to(cx(325.0), 6.0)
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
	while scanner.mode == 2 and n < 600:
		await ticks(1)
		n += 1
		beam_min = minf(beam_min, scanner.beam_pos)
		beam_max = maxf(beam_max, scanner.beam_pos)
		if n == 90:
			await shot("S_scanner_sweeping")
		var aug: Node = cat.get_node_or_null("Sprite/Augments")
		flared = flared or (aug != null and aug.get("_flare") > 0.3)
	note("S the beam sweeps the cat across the whole zone and the augments flare", beam_min < -0.95 and beam_max > 0.95 and flared, "beam %.2f..%.2f, flare %s, %.1f s" % [beam_min, beam_max, str(flared), n / 60.0])
	note("S the screen reads SUPERVISOR CREDENTIAL ACCEPTED", scanner.mode == 3 and scanner.screen_lines == PackedStringArray(["SUPERVISOR CREDENTIAL ACCEPTED"]), str(scanner.screen_lines))
	await shot("S_credential_accepted")
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
	await ticks(100)
	var stub := current_scene
	note("E the exit leads to the Home stub", stub != null and stub.scene_file_path == "res://scenes/levels/stubs/after_room4.tscn", str(stub.scene_file_path if stub else "?"))
	note("E the stub says 'Home - coming soon'", stub != null and stub.get_node_or_null("ComingSoon") != null and stub.get_node("ComingSoon").text == "Home - coming soon")
	var save2: Dictionary = ss().read_save()
	note("E auto-saved in the stub with the mind and the shockwave", save2.get("scene", "") == "res://scenes/levels/stubs/after_room4.tscn" and save2.get("abilities", {}).get("mind", false) and save2.get("abilities", {}).get("shockwave", false), str(save2.get("abilities", {})))
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
		teleport(cx(329.0))
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
