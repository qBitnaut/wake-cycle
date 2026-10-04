## Drives the real Cat through every beat of Warehouse Room 1 with scripted
## input (Input.action_press, the same path a keyboard takes), in the real
## scene with the real physics, using plain movement only: run, jump, double
## jump, crouch, a stomp. No teleporting. Prints PASS or FAIL for each beat.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/room1_playthrough.gd
##
## Wake-up (input locked, then the stretch) -> platforming -> the pool
## (unavoidable) -> the struggle -> TransformSequence -> shockwave unlocked ->
## the loading door -> Room 2 (auto-saved). Asserts that no power was granted
## before the pool. Exit code 1 if any beat fails. It deletes user://save.json
## before and after.
extends SceneTree

const T := 32.0
const FLOOR_Y := 320.0

var room: Node2D
var cat: CharacterBody2D
var results: Array = []
var _hurt := 0
var _frames := 0
var _beat_start := 0
var _timeline: Array = []


func gs() -> Node:
	return root.get_node("GameState")


func ss() -> Node:
	return root.get_node("SaveSystem")


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


func go_to(target: float, tol := 6.0, limit := 900) -> bool:
	var n := 0
	while absf(x() - target) > tol and n < limit:
		dir(signf(target - x()))
		await ticks(1)
		n += 1
	dir(0.0)
	await ticks(6)
	return n < limit


## One jump: hold jump and direction `d` for `dir_frames` frames, double jump
## at frame `dj` (0 = none), keep jump held for `hold_frames`, then wait to land.
func hop(d: float, dir_frames: int, dj := 0, hold_frames := 999, max_frames := 300) -> void:
	hold("jump", true)
	dir(d)
	var t := 0
	while t < max_frames:
		await ticks(1)
		t += 1
		if t == dir_frames:
			dir(0.0)
		if t == hold_frames:
			hold("jump", false)
		if dj > 0 and t == dj:
			hold("jump", false)
			await ticks(1)
			hold("jump", true)
		if OS.get_environment("HOP_TRACE") != "":
			print("   t=%d %s" % [t, st()])
		if t > 8 and cat.is_on_floor():
			break
	stop()
	await ticks(8)


## A running jump: run right, take off at x >= jx, hold direction for dir_frames.
func run_hop(jx: float, dir_frames: int, dj := 0) -> void:
	dir(1.0)
	var n := 0
	while x() < jx and n < 400:
		await ticks(1)
		n += 1
	hold("jump", true)
	var t := 0
	while t < 300:
		await ticks(1)
		t += 1
		if t == dir_frames:
			dir(0.0)
		if dj > 0 and t == dj:
			hold("jump", false)
			await ticks(1)
			hold("jump", true)
		if t > 8 and cat.is_on_floor():
			break
	stop()
	await ticks(8)


func note(name: String, ok: bool, detail := "") -> void:
	results.append([name, ok, detail])
	print("%s  %-46s %s" % ["PASS" if ok else "FAIL", name, detail])


func mark(label: String) -> void:
	_timeline.append([label, (_frames - _beat_start) / 60.0])
	_beat_start = _frames


func node(path: String) -> Node:
	return room.get_node_or_null(path)


func on_floor_at(ty: float, tol := 3.0) -> bool:
	return cat.is_on_floor() and absf(y() - ty) < tol


func st() -> String:
	return "x=%.0f y=%.0f floor=%s vy=%.0f" % [x(), y(), cat.is_on_floor(), cat.velocity.y]


func no_powers() -> bool:
	return gs().power == 0 and not gs().shockwave_unlocked and room.get("power_violations") == 0


# ---- the run --------------------------------------------------------------

func _main() -> void:
	ss().delete_save()
	room = load("res://scenes/levels/room1.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await ticks(4)
	cat = room.get_node("Cat")
	cat.hurt_taken.connect(func(_hp): _hurt += 1)
	cat.died.connect(func(): print("  (cat died at x=%.0f y=%.0f)" % [x(), y()]))

	await _beat_intro()
	await _beat_b()
	await _beat_c()
	await _beat_d()
	await _beat_e()
	await _beat_f()
	await _beat_g()
	await _beat_h()
	await _beat_pool()
	await _beat_exit()
	await _beat_continue()
	await _beat_respawn()

	var ok_all := true
	for r in results:
		ok_all = ok_all and r[1]
	print("== timeline (s, scripted run):")
	var total := 0.0
	for e in _timeline:
		total += e[1]
		print("   %-14s %6.1f" % [e[0], e[1]])
	print("   %-14s %6.1f" % ["TOTAL", total])
	print("== %d beats, %s, hurt %d" % [results.size(), "ALL PASS" if ok_all else "FAILURES", _hurt])
	ss().delete_save()
	quit(0 if ok_all else 1)


func _beat_intro() -> void:
	note("A input locked, cat asleep", not cat.can_move and cat.forced_anim.begins_with("sleep"), "anim %s" % cat.forced_anim)
	var x0 := x()
	dir(1.0)
	hold("jump", true)
	await ticks(90)  # the black is still lifting
	stop()
	note("A mashing keys in the dark does nothing", absf(x() - x0) < 1.0 and not cat.can_move, "dx=%.1f" % (x() - x0))
	var hud: CanvasLayer = node("Hud")
	note("A HUD hidden during the intro", not hud.visible)
	var n := 0
	while not cat.can_move and n < 2000:
		await ticks(1)
		n += 1
	note("A title done, stretch played, control granted", cat.can_move and n < 2000, "after %.1f s" % ((n + 94) / 60.0))
	note("A HUD shown, no power UI", hud.visible and gs().power == 0 and not gs().shockwave_unlocked)
	await ticks(10)
	var start_ok := absf(x() - 144.0) < 8.0 and cat.is_on_floor()
	note("A starts in the nook on the floor", start_ok, "x=%.0f y=%.0f" % [x(), y()])
	await go_to(112.0, 4.0)
	note("A bonus letter A tucked in the cardboard box", gs().letters == 1 and gs().letter_mask == 2, "mask %d" % gs().letter_mask)
	var cp: Node = node("ContinuePad")
	note("A continue pad hidden without a save", not cp.visible)
	mark("intro")


func _beat_b() -> void:
	await go_to(430.0)
	await hop(1.0, 14)
	note("B crate step 1 (1 tile)", on_floor_at(288.0) and x() > 448.0 and x() < 512.0, "x=%.0f y=%.0f" % [x(), y()])
	await go_to(498.0, 4.0)
	await hop(1.0, 12)
	note("B crate step 2 (2 tiles)", on_floor_at(256.0) and x() > 544.0 and x() < 608.0, "x=%.0f y=%.0f" % [x(), y()])
	await go_to(596.0, 4.0)
	await hop(1.0, 12)
	note("B crate step 3: the catwalk level", on_floor_at(224.0) and x() > 640.0, "x=%.0f y=%.0f" % [x(), y()])
	# Gap: 3 tiles (96 px) between the decks.
	await go_to(820.0, 4.0)
	await run_hop(892.0, 60)
	note("B catwalk gap crossed (3 tiles, single jump)", on_floor_at(228.0) and x() > 992.0, "x=%.0f y=%.0f" % [x(), y()])
	# Secret letter C: drop off deck 2's left end into the pocket under the gap.
	dir(-1.0)
	var dn := 0
	while not (x() < 985.0 and cat.is_on_floor() and y() > 300.0) and dn < 300:
		await ticks(1)
		dn += 1
	stop()
	await go_to(944.0, 4.0)
	await ticks(6)
	note("B secret letter C under the catwalk gap", gs().letter_mask == 3, "mask %d" % gs().letter_mask)
	await go_to(1120.0, 4.0)
	await hop(1.0, 12)
	await go_to(1180.0)
	await ticks(30)
	note("B descent stairs", cat.is_on_floor() and y() > 250.0, "x=%.0f y=%.0f" % [x(), y()])
	await go_to(1240.0, 6.0)
	await hop(1.0, 12)
	await go_to(1360.0)
	await ticks(10)
	note("B checkpoint A saves", ss().session_checkpoint == "cp_a", str(ss().session_checkpoint))
	note("B no powers yet", no_powers())
	mark("B catwalk")


func _beat_c() -> void:
	# Wade through the first puddle (cols 44-47).
	var zone = node("PuddleHall1")
	var rippled := false
	await go_to(1440.0)
	var bot = node("Bot")
	hold("move_right", true)
	var n := 0
	while x() < 1830.0 and n < 1800 and not cat.dead:
		if zone.puddle._ripples.size() > 0:
			rippled = true
		var d: float = bot.global_position.x - x()
		# Stomp it: a jump with the bot a little ahead lands on its head.
		if d > 30.0 and d < 62.0 and cat.is_on_floor() and bot.state == 0:
			hold("jump", true)
			await ticks(22)
			hold("jump", false)
		elif bot.state != 0 and d > 0.0 and d < 70.0 and cat.is_on_floor():
			# stunned bots still hurt nobody; just run past
			hold("jump", false)
		else:
			hold("jump", false)
		await ticks(1)
		n += 1
	stop()
	await ticks(20)
	note("C waded through the puddle, ripple + splash", rippled, "ripples seen")
	note("C stomped the patrol bot and got past", x() >= 1830.0 and not cat.dead and bot.stomps >= 1, "x=%.0f hp %d stomps %d" % [x(), gs().health, bot.stomps])
	mark("C hall")


func _beat_d() -> void:
	await go_to(1880.0)
	dir(1.0)
	await ticks(100)
	stop()
	note("D low beam blocks the standing cat", x() < 1952.0, "x=%.0f" % x())
	hold("move_down", true)
	dir(1.0)
	var n := 0
	while x() < 2190.0 and n < 1200:
		await ticks(1)
		n += 1
	stop()
	await ticks(20)
	note("D crawled under the beam (crouch)", x() >= 2150.0 and gs().score > 0, "x=%.0f score %d" % [x(), gs().score])
	mark("D crawl")


func _beat_e() -> void:
	await go_to(2330.0)
	var fence: Node = node("FenceTimed")
	var hp0: int = gs().health
	for i in 600:  # wait for the beam to fire, then for it to drop
		if fence.active:
			break
		await ticks(1)
	for i in 600:
		if not fence.active:
			break
		await ticks(1)
	await ticks(2)
	dir(1.0)
	while x() < 2500.0 and not cat.dead:
		await ticks(1)
	stop()
	note("E timed fence crossed in its off window", x() >= 2500.0 and gs().health == hp0, "x=%.0f hp %d" % [x(), gs().health])
	# The crate and the plate.
	await go_to(2490.0)
	var crate: Node = node("PushCrate")
	var shutter: Node = node("Shutter")
	note("E shutter shut at first", not shutter.open)
	dir(1.0)
	var n := 0
	while not node("PlateA").active and n < 900:
		await ticks(1)
		n += 1
	stop()
	await ticks(40)
	note("E crate pushed onto the plate, shutter opens", node("PlateA").active and shutter.open, "crate x=%.0f" % crate.global_position.x)
	await ticks(30)
	await hop(1.0, 26)
	await go_to(2790.0)
	note("E crate rests on the plate", absf(crate.global_position.x - 2704.0) < 40.0 and node("PlateA").active and shutter.open, "crate x=%.0f" % crate.global_position.x)
	await go_to(2860.0)
	note("E through the shutter", x() > 2850.0, "x=%.0f" % x())
	mark("E fence+crate")


func _beat_f() -> void:
	await go_to(2950.0)
	await hop(1.0, 12)
	await hop(1.0, 12)
	note("F stairs up to the key deck", on_floor_at(228.0), "x=%.0f y=%.0f" % [x(), y()])
	await go_to(3070.0, 5.0)
	await go_to(3120.0)
	await ticks(6)
	note("F brass key on the deck", gs().keys.has("brass"), str(gs().keys))
	await go_to(3140.0, 5.0)
	dir(1.0)
	await ticks(100)
	stop()
	await ticks(20)
	note("F back down", cat.is_on_floor() and y() > 300.0, "x=%.0f y=%.0f" % [x(), y()])
	await go_to(3300.0)
	dir(1.0)
	var n := 0
	while node("DoorBrass") != null and n < 300:
		await ticks(1)
		n += 1
	await go_to(3420.0)
	note("F door opened with the key", node("DoorBrass") == null and not gs().keys.has("brass"), "x=%.0f" % x())
	await go_to(3472.0)
	await ticks(10)
	note("F checkpoint B saves", ss().session_checkpoint == "cp_b", str(ss().session_checkpoint))
	note("F no powers yet", no_powers())
	mark("F key+door")


func _beat_g() -> void:
	# Three cycling steam vents. Wait in the pocket before each, cross when it
	# has just gone safe.
	var hp0: int = gs().health
	var steps := [[3510.0, "Steam1", 3640.0], [3670.0, "Steam2", 3800.0], [3830.0, "Steam3", 3960.0]]
	var worst := 99.0
	for s in steps:
		await go_to(s[0] - 40.0 if s[0] == 3510.0 else s[0], 5.0)
		var vent = node(s[1])
		var seen_danger := false
		for i in 900:
			if vent.is_dangerous():
				seen_danger = true
			elif seen_danger:
				break
			await ticks(1)
		note("G %s cycles on and off" % s[1], seen_danger and not vent.is_dangerous())
		dir(1.0)
		while x() < s[2] and not cat.dead:
			await ticks(1)
		stop()
		await ticks(4)
	note("G steam dodged, no hits", gs().health == hp0 and not cat.dead, "x=%.0f hp %d" % [x(), gs().health])
	mark("G steam")


func _beat_h() -> void:
	await go_to(4050.0)
	# The flooded hall: puddles to wade, letter T on its perch (crates, then the double jump).
	await go_to(4080.0)
	await hop(1.0, 12)
	await hop(1.0, 12)
	note("H crates up to the T perch", cat.is_on_floor() and y() < 280.0, "x=%.0f y=%.0f" % [x(), y()])
	await go_to(4140.0, 5.0)
	await hop(1.0, 24, 18)
	note("H bonus letter T on the high perch: all three, bonus score", gs().letters == 3 and gs().score >= 5000, "letters %d score %d" % [gs().letters, gs().score])
	await go_to(4240.0, 6.0)
	dir(1.0)
	await ticks(60)
	stop()
	await ticks(40)
	# Up onto the near sill (one tile), to the lip of the pool.
	await go_to(4330.0, 4.0)
	await hop(1.0, 10)
	await go_to(4400.0)
	note("H up on the sill at the lip of the pool, still no powers, mind asleep", on_floor_at(288.0) and no_powers() and not gs().intelligence, "x=%.0f y=%.0f" % [x(), y()])
	mark("H flooded hall")


func _beat_pool() -> void:
	# The pool cannot be jumped over: take a run-up and double jump from the lip.
	var signalled := [false]
	room.nanotech_absorbed_started.connect(func(): signalled[0] = true)
	var gs_signalled := [false]
	gs().nanotech_absorbed_started.connect(func(): gs_signalled[0] = true)
	await go_to(4350.0)
	dir(1.0)
	while x() < 4416.0 - 6.0:
		await ticks(1)
	hold("jump", true)
	var t := 0
	while t < 200 and room.get("beat") == 1:
		await ticks(1)
		t += 1
		if t == 20:
			hold("jump", false)
			await ticks(1)
			hold("jump", true)
	stop()
	var caught_x := x()
	note("I jumping the pool fails: the cat is caught", room.get("beat") == 3 and caught_x < 4736.0, "caught at x=%.0f (pool 4416..4736)" % caught_x)
	note("I nanotech_absorbed_started on the level and on GameState", signalled[0] and gs_signalled[0])
	note("I input locked in the pool", not cat.can_move)
	var x0 := x()
	dir(1.0)
	hold("jump", true)
	await ticks(60)
	stop()
	note("I the cat is stuck: feet do not move", absf(x() - x0) < 3.0 and cat.is_on_floor(), "dx=%.1f" % (x() - x0))
	var seq := room.get_node_or_null("TransformSequence")
	var n := 0
	while room.get("beat") != 4 and n < 2600:
		await ticks(1)
		if seq == null:
			seq = room.get_node_or_null("TransformSequence")
		n += 1
	note("I TransformSequence ran and finished", room.get("beat") == 4 and n < 2600, "after %.1f s" % (n / 60.0))
	note("I the goo's gift: the mind is awakened, no power, no shockwave", gs().intelligence and not gs().shockwave_unlocked and room.get("power_violations") == 0 and gs().power == 0)
	note("I control returns", cat.can_move)
	mark("I pool+transform")


func _beat_exit() -> void:
	# Walk out. The double jump now bursts.
	await go_to(4690.0, 8.0)
	await hop(1.0, 12)
	note("J out of the pool and up onto the far sill", on_floor_at(288.0) and x() > 4730.0, "x=%.0f y=%.0f" % [x(), y()])
	dir(1.0)
	var n := 0
	while current_scene == room and n < 600:
		await ticks(1)
		n += 1
	stop()
	await ticks(90)
	var r2 := current_scene
	note("J exit fades out and loads Room 2", r2 != null and r2.scene_file_path == "res://scenes/levels/room2.tscn", str(r2.scene_file_path if r2 else "?"))
	var save: Dictionary = ss().read_save()
	note("J auto-saved at the start of Room 2", save.get("scene", "") == "res://scenes/levels/room2.tscn" and save.get("abilities", {}).get("mind", false) and not save.get("abilities", {}).get("shockwave", true), str(save.get("abilities", {})))
	note("J the cat keeps its augments in Room 2 (mind flag set)", r2 != null and r2.get_node_or_null("Cat/Sprite/Augments") != null and gs().intelligence)
	note("J Room 2 stub shows the coming-soon text", r2 != null and r2.get_node_or_null("ComingSoon") != null)
	mark("J exit")


func _beat_continue() -> void:
	# A save from checkpoint A: a fresh Room 1 shows the CONTINUE pad a few tiles
	# from the wake spot, and stepping on it loads the checkpoint.
	ss().delete_save()
	ss().save_checkpoint("cp_a", "res://scenes/levels/room1.tscn")
	ss().session_scene = ""
	ss().session_checkpoint = ""
	var tree := current_scene.get_tree()
	tree.change_scene_to_file("res://scenes/levels/room1.tscn")
	await ticks(10)
	room = current_scene
	cat = room.get_node("Cat")
	var pad: Node2D = node("ContinuePad")
	var gap := absf(pad.global_position.x - 144.0) / T
	note("K CONTINUE pad shown with a save, a few tiles from the wake spot", pad.visible and gap > 2.0 and gap < 8.0, "%.1f tiles" % gap)
	var old_room := room
	var n := 0
	dir(1.0)
	while is_instance_valid(old_room) and old_room == current_scene and n < 600:
		await ticks(1)
		n += 1
	dir(0.0)
	await ticks(30)
	room = current_scene
	cat = room.get_node("Cat")
	note("K continue loads the checkpoint", absf(x() - 1360.0) < 12.0 and ss().session_checkpoint == "cp_a", "x=%.0f cp %s" % [x(), ss().session_checkpoint])
	mark("continue")


func _beat_respawn() -> void:
	# Dying reloads the room at the last checkpoint: no intro again, control at once.
	cat.kill()
	await ticks(100)
	room = current_scene
	cat = room.get_node("Cat")
	var hud: CanvasLayer = node("Hud")
	note("L death respawns at the checkpoint, no intro", absf(x() - 1360.0) < 12.0 and cat.can_move and hud.visible and room.get("beat") == 1, "x=%.0f beat %s" % [x(), str(room.get("beat"))])
	note("L no pads in Room 1, nothing unlocked on a fresh respawn", room.find_children("*", "PowerPad", true, false).is_empty() and gs().power == 0)
	mark("respawn")
