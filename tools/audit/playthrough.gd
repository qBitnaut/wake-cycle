## Drives the real Cat through every beat of the test room with scripted
## input (Input.action_press, the same path a keyboard takes), in the real
## scene with the real physics. Prints PASS or FAIL for each beat.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/playthrough.gd
##
## Exit code 1 if any beat fails. It never teleports: the run is continuous,
## so a pad, pit, key or door that cannot be passed fails every beat after it.
## It deletes user://save.json before and after (checkpoints write one).
extends SceneTree

const T := 32.0
const HumanSweep := preload("res://tools/audit/human_sweep.gd")
const G := 10
const FLOOR_Y := 320.0

var room: Node2D
var cat: CharacterBody2D
var results: Array = []
var _stats := {"hurt": 0}


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
	hold("dash", false)


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func x() -> float:
	return cat.global_position.x


func y() -> float:
	return cat.global_position.y


## Walk to x (stops there).
func go_to(target: float, tol := 6.0, limit := 900) -> bool:
	var n := 0
	while absf(x() - target) > tol and n < limit:
		dir(signf(target - x()))
		await physics_frame
		n += 1
	dir(0.0)
	await ticks(6)
	return n < limit


## Run (no stopping) until x passes target in direction d.
func run_past(target: float, d: float, limit := 900) -> bool:
	var n := 0
	while (x() - target) * d < 0.0 and n < limit:
		dir(d)
		await physics_frame
		n += 1
	return n < limit


## From the current position: jump, double-jump after `dj` frames (0 = none),
## keep holding direction d, and release when back on the floor.
func leap(d: float, dj := 28, max_frames := 300, land_y := -1.0) -> void:
	hold("jump", true)
	dir(d)
	var t := 0
	while t < max_frames:
		await physics_frame
		t += 1
		if t == 3:
			pass
		if dj > 0 and t == dj:
			hold("jump", false)
			await physics_frame
			hold("jump", true)
		if t > 8 and cat.is_on_floor():
			break
	stop()
	await ticks(4)


func note(name: String, ok: bool, detail := "") -> void:
	results.append([name, ok, detail])
	print("%s  %-34s %s" % ["PASS" if ok else "FAIL", name, detail])


func node(path: String) -> Node:
	return room.get_node_or_null(path)


func cat_hp() -> int:
	return gs().health


# ---- the run --------------------------------------------------------------

func _main() -> void:
	await HumanSweep.lab(self, "test_room", note, "LAB ")
	ss().delete_save()
	room = load("res://scenes/levels/test_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await ticks(4)
	cat = room.get_node("Cat")
	cat.hurt_taken.connect(func(_hp): _stats["hurt"] += 1)
	cat.died.connect(func(): print("  (cat died at x=%.0f y=%.0f)" % [x(), y()]))
	await ticks(30)

	await _beat_a()
	await _beat_b()
	await _beat_c()
	await _beat_d()
	await _beat_e()
	await _beat_f()
	await _beat_g()
	await _beat_h()
	await _beat_i()

	var ok_all := true
	for r in results:
		ok_all = ok_all and r[1]
	print("== %d beats, %s" % [results.size(), "ALL PASS" if ok_all else "FAILURES"])
	ss().delete_save()
	quit(0 if ok_all else 1)


func _beat_a() -> void:
	var start_ok := absf(x() - 304.0) < 4.0 and cat.is_on_floor()
	note("A start on floor", start_ok, "x=%.0f y=%.0f" % [x(), y()])
	await go_to(12 * T + 16)
	await ticks(10)
	note("A checkpoint A saves", ss().session_checkpoint == "cp_a", str(ss().session_checkpoint))
	# gems at cols 14/15 are 48 / 80 px up: jump for them
	var s0: int = gs().score
	await go_to(14 * T + 16)
	hold("jump", true)
	await ticks(20)
	stop()
	await go_to(15 * T + 16)
	await leap(0.0, 0)
	note("A gems collected", gs().score > s0, "score %d" % gs().score)


func _beat_b() -> void:
	# Pit A: 6 tiles wide (cols 17-22). Needs the double jump.
	var edge := 17 * T
	await go_to(edge - 160.0)
	await run_past(edge + 8.0, 1.0)
	await leap(1.0, 28)
	var landed := cat.is_on_floor() and x() > 23 * T and absf(y() - FLOOR_Y) < 2.0
	note("B pit A crossed (6 tiles, double jump)", landed, "x=%.0f y=%.0f" % [x(), y()])
	if not landed:
		return
	# Single jump must NOT make it: verified separately by reach.gd (max single gap 4.5 tiles).
	await go_to(25 * T + 16)
	await ticks(6)
	note("B shockwave unlocked", gs().shockwave_unlocked)
	# Letter C on the girder deck (92 px up): jump straight up under it.
	await go_to(26 * T + 16)
	await leap(0.0, 28)
	await ticks(10)
	note("B letter C on the deck", gs().letters >= 1, "letters %d" % gs().letters)
	# Walk off the deck and on to the corridor.
	await go_to(29 * T + 16)
	await go_to(31 * T + 8)
	# Double jump in the corridor: the shockwave breaks the 3-high crate stack.
	hold("jump", true)
	await ticks(10)
	hold("jump", false)
	await ticks(2)
	hold("jump", true)
	await ticks(14)
	stop()
	await ticks(30)
	var crates := 0
	for n in get_nodes_in_group("breakable"):
		if str(n.name).begins_with("CrateStack"):
			crates += 1
	note("B crate stack broken by shockwave", crates == 0, "%d crates left" % crates)
	# Drops must have fallen to the floor.
	var floating := 0
	var drops := 0
	for n in room.get_children():
		if n is Area2D and n.get("persist") == false:
			drops += 1
			if absf(n.global_position.y - FLOOR_Y) > 1.0:
				floating += 1
	note("B drops rest on the floor", drops == 2 and floating == 0, "%d drops, %d floating" % [drops, floating])
	var s0: int = gs().score
	var hp0 := cat_hp()
	await go_to(36 * T)
	note("B corridor passable, drops collected", gs().score > s0 and cat_hp() >= hp0, "score +%d" % (gs().score - s0))


func _beat_c() -> void:
	# Wide pit: 8 tiles (cols 41-48): needs Surge and the double jump.
	await go_to(38 * T + 16)
	await ticks(4)
	note("C surge pad", gs().power == 1, "power %d" % gs().power)
	var edge := 41 * T
	await run_past(edge + 8.0, 1.0)
	await leap(1.0, 28)
	var landed := cat.is_on_floor() and x() > 49 * T and absf(y() - FLOOR_Y) < 2.0
	note("C pit C crossed (8 tiles, surge + double)", landed, "x=%.0f y=%.0f" % [x(), y()])


func _beat_d() -> void:
	await go_to(52 * T + 16)
	await ticks(4)
	note("D spring pad", gs().power == 2, "power %d" % gs().power)
	# Tall wall: 6 tiles (192 px) with a slab. Spring + double jump to the top.
	await go_to(54 * T - 6.0)
	hold("jump", true)
	dir(1.0)
	var t := 0
	while t < 200:
		await physics_frame
		t += 1
		if t == 22:
			hold("jump", false)
			await physics_frame
			hold("jump", true)
		if t > 10 and cat.is_on_floor():
			break
	stop()
	await ticks(6)
	var top := cat.is_on_floor() and absf(y() - 128.0) < 3.0 and x() >= 55 * T and x() <= 59 * T
	note("D tall wall climbed (spring + double)", top, "x=%.0f y=%.0f" % [x(), y()])
	if not top:
		return
	var s0: int = gs().score
	await go_to(57 * T + 16)
	await leap(0.0, 0)
	note("D top gem", gs().score > s0, "score +%d" % (gs().score - s0))
	await go_to(59 * T + 16)
	# drop off the slab's right end
	await go_to(62 * T)
	note("D back on the floor", cat.is_on_floor() and absf(y() - FLOOR_Y) < 2.0, "y=%.0f" % y())


func _beat_e() -> void:
	# The standing cat must be blocked by the low beam (cols 64-68)...
	await go_to(62 * T)
	dir(1.0)
	await ticks(90)
	stop()
	var blocked := x() < 64 * T + 4.0
	note("E tunnel blocks the standing cat", blocked, "x=%.0f" % x())
	# ... and the crouching cat crawls through.
	hold("move_down", true)
	dir(1.0)
	await ticks(1)
	var n := 0
	while x() < 70 * T and n < 900:
		await physics_frame
		n += 1
	stop()
	await ticks(10)
	note("E crawl through the tunnel", x() >= 70 * T - 8.0, "x=%.0f letters %d" % [x(), gs().letters])
	note("E letter A collected", gs().letters >= 2, "letters %d" % gs().letters)
	await ticks(30)
	await go_to(71 * T + 16)
	note("E checkpoint B", ss().session_checkpoint == "cp_b", str(ss().session_checkpoint))


func _beat_f() -> void:
	var crate := node("PushCrate") as RigidBody2D
	var plate := node("PlateA")
	var fence := node("FenceA")
	await go_to(75 * T)
	dir(1.0)
	var n := 0
	while not plate.active and n < 900:
		await physics_frame
		n += 1
	await ticks(5)
	stop()
	note("F crate pushed onto the plate", plate.active and not fence.active, "crate x=%.0f (plate 2576)" % crate.global_position.x)
	# Keep shoving: the stopper must hold the crate on the plate (no overshoot).
	dir(1.0)
	await ticks(90)
	stop()
	await ticks(20)
	var settled: bool = absf(crate.global_position.x - 80 * T - 16.0) < 8.0 and plate.active
	note("F crate cannot be overshot past the plate", settled, "x=%.0f" % crate.global_position.x)
	await leap(1.0, 0)
	await ticks(4)
	var hp0 := cat_hp()
	await go_to(86 * T)
	note("F through the fence", x() > 85 * T and cat_hp() == hp0, "x=%.0f hp %d" % [x(), cat_hp()])


func _beat_g() -> void:
	var f := node("FenceTimed")
	await go_to(87 * T + 8)
	var hp0 := cat_hp()
	# Wait for the beam to go off, then cross the 3-tile corridor.
	var n := 0
	while not f.active and n < 600:  # wait for the beam to fire...
		await physics_frame
		n += 1
	while f.active and n < 1200:  # ...then cross at the start of its off window
		await physics_frame
		n += 1
	await ticks(3)
	await run_past(93 * T, 1.0)
	stop()
	note("G timed fence crossed in its off window", x() > 92 * T and cat_hp() == hp0, "x=%.0f hp %d" % [x(), cat_hp()])
	# Shock switch on the 1-tile pillar: double jump near it.
	await go_to(93 * T + 8)
	var sw := node("SwitchA")
	hold("jump", true)
	dir(1.0)
	var t := 0
	while t < 120:
		await physics_frame
		t += 1
		if t == 20:
			hold("jump", false)
			await physics_frame
			hold("jump", true)
		if t > 8 and cat.is_on_floor():
			break
	stop()
	note("G shock switch thrown", sw.active, "x=%.0f" % x())
	var fb := node("FenceB")
	hp0 = cat_hp()
	await run_past(101 * T, 1.0)
	stop()
	note("G switched fence B crossed", x() > 100 * T and cat_hp() == hp0 and not fb.active, "x=%.0f hp %d" % [x(), cat_hp()])


func _beat_h() -> void:
	await go_to(103 * T + 16)
	await ticks(4)
	note("H phase pad", gs().power == 3, "power %d" % gs().power)
	var fd := node("FenceDash")
	await go_to(108 * T + 16 - 34.0)
	var hp0 := cat_hp()
	# Dash through while the beam is on.
	var n := 0
	while not fd.active and n < 600:
		await physics_frame
		n += 1
	await ticks(2)
	dir(1.0)
	hold("dash", true)
	await ticks(2)
	hold("dash", false)
	await ticks(16)
	stop()
	note("H dashed through the live beam", x() > 109 * T and cat_hp() == hp0, "x=%.0f hp %d (beam %s)" % [x(), cat_hp(), fd.active])
	# Key on the girder deck.
	await go_to(113 * T + 16)
	await leap(0.0, 28)
	await ticks(10)
	note("H key taken from the deck", gs().keys.has("brass"), str(gs().keys))
	# Door.
	await go_to(118 * T)
	dir(1.0)
	await ticks(60)
	stop()
	note("H door opened with the key", node("DoorBrass") == null or x() > 121 * T, "x=%.0f" % x())
	await go_to(122 * T)


func _beat_i() -> void:
	var bot := node("Bot")
	# Get past the patrol bot: hop over it when it comes close.
	var n := 0
	while x() < 133 * T and n < 1800 and not cat.dead:
		var bx: float = bot.global_position.x
		var near: bool = absf(bx - x()) < 90.0 and bot.state == 0
		if near and cat.is_on_floor():
			hold("jump", true)
			dir(1.0)
			await ticks(8)
			hold("jump", false)
			await physics_frame
			hold("jump", true)
			await ticks(6)
		else:
			dir(1.0)
			hold("jump", false)
		await physics_frame
		n += 1
	stop()
	await ticks(20)
	note("I past the patrol bot", x() >= 133 * T and not cat.dead, "x=%.0f hp %d" % [x(), cat_hp()])
	if cat.dead:
		return
	# The bot's stopper: it must not have wandered past col 132.
	await ticks(60)
	note("I bot stays inside its stoppers", bot.global_position.x < 133 * T + 4.0 and bot.global_position.x > 123 * T, "bot x=%.0f" % bot.global_position.x)
	# Spikes (cols 134-135): one running hop.
	await go_to(133 * T - 12.0)
	await run_past(133 * T + 4.0, 1.0)
	await leap(1.0, 0)
	note("I spikes cleared", not cat.dead and x() > 136 * T, "x=%.0f dead=%s" % [x(), cat.dead])
	await go_to(139 * T + 16)
	await ticks(4)
	note("I impact pad", gs().power == 4, "power %d" % gs().power)
	# Ground pound onto the cracked floor (cols 142-143).
	await go_to(140 * T)
	hold("jump", true)
	dir(1.0)
	var t := 0
	var pounded := false
	while t < 200:
		await physics_frame
		t += 1
		if t == 14:
			hold("jump", false)
			await physics_frame
			hold("jump", true)
		if not pounded and x() >= 142 * T + 16.0 and not cat.is_on_floor() and t > 20:
			dir(0.0)
			hold("jump", false)
			hold("move_down", true)
			pounded = true
		if pounded and cat.is_on_floor() and y() > 330.0:
			break
		if t > 150 and cat.is_on_floor():
			break
	stop()
	await ticks(30)
	var cracked := get_nodes_in_group("breakable").filter(func(n): return str(n.name).begins_with("Cracked")).size()
	note("I cracked floor broken by the ground pound", cracked == 0 and y() > 330.0, "left %d, y=%.0f" % [cracked, y()])
	note("I letter T in the chamber", gs().letters >= 3, "letters %d" % gs().letters)
	# Climb out of the chamber and reach checkpoint C.
	hold("jump", true)
	dir(1.0)
	await ticks(40)
	stop()
	await go_to(147 * T + 16)
	await ticks(10)
	note("I out of the chamber, checkpoint C", ss().session_checkpoint == "cp_c" and gs().letters == 3, "cp %s letters %d" % [ss().session_checkpoint, gs().letters])
