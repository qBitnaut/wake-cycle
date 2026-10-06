## Drives the real Cat through every beat of Warehouse Room 1 with scripted
## input (Input.action_press, the same path a keyboard takes), in the real
## scene with the real physics, using plain movement only: run, jump, double
## jump, crouch, a stomp. No teleporting. Prints PASS or FAIL for each beat.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/room1_playthrough.gd
##
## Wake-up (input locked, then the stretch) -> platforming -> the pool
## (unavoidable) -> the struggle -> TransformSequence -> the awakening
## monologue -> the nanofluid crate monologue -> the loading door -> Room 2
## (auto-saved). Asserts that no power was granted before the pool, that a bot
## stomp does nothing without powers, and that pushing the crate does not
## thrash the cat's animation. Exit code 1 if any beat fails. It deletes
## user://save.json before and after.
## STUB_ANIMS=1 injects stand-in crawl / crouch_idle / push animations into the
## cat's SpriteFrames at run time, to prove the hookup used once the real ones land.
extends SceneTree

const T := 32.0
const HumanSweep := preload("res://tools/audit/human_sweep.gd")
const FLOOR_Y := 320.0

var room: Node2D
var cat: CharacterBody2D
var results: Array = []
var _hurt := 0
var _frames := 0
var _beat_start := 0
var _timeline: Array = []
var _lines: Array = []
var _set_done := {}
var _sub_cine := [0, 0, 0, "", 0.0]   # close-up samples: [seen, plate overlaps cat, plate off window, first miss, widest gap to the window bottom, game px]
var _sub_play := [0, 0, 0, ""]   # same in normal play (plate vs cat and crate in the game frame)
var _zoom_state: Array = []  # per subtitle line: [close-up pass live, subtitles overlaid on it]


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


## Stand-ins for the animations the art branch adds: clones of walk / crouch.
func _stub_anims() -> void:
	var sf: SpriteFrames = cat.sprite.sprite_frames
	for pair in [["crawl", "walk"], ["crouch_idle", "idle"], ["push", "walk"]]:
		if sf.has_animation(pair[0]):
			continue
		sf.add_animation(pair[0])
		sf.set_animation_speed(pair[0], 8.0)
		for i in sf.get_frame_count(pair[1]):
			sf.add_frame(pair[0], sf.get_frame_texture(pair[1], i))
	print("  (stub animations injected)")


func has_anim(a: String) -> bool:
	return cat.sprite.sprite_frames.has_animation(a)


## Every frame a line is showing: where does the plate sit against the cat?
## During a close-up: in window pixels against the zoomed cat. Otherwise in the
## game frame against the cat's sprite rect and the crate.
func _sample_subtitle() -> void:
	var mono := root.get_node_or_null("Monologue")
	if mono == null or not mono.is_speaking() or mono._root.modulate.a < 0.3 or room == null or not is_instance_valid(room) or cat == null or not is_instance_valid(cat):
		return
	var cz := CineZoom.current()
	var cr: Rect2 = mono.cat_screen_rect()
	if cz != null and cz.is_overlaid(mono):
		var pw: Rect2 = mono.plate_window_rect()
		var cw: Rect2 = mono.cat_window_rect()
		_sub_cine[0] += 1
		if pw.intersects(cw):
			_sub_cine[1] += 1
			_sub_cine[3] = _sub_cine[3] if _sub_cine[3] != "" else "plate %s cat %s" % [str(pw), str(cw)]
		if not Rect2(Vector2.ZERO, Vector2(DisplayServer.window_get_size())).encloses(pw):
			_sub_cine[2] += 1
		_sub_cine[4] = maxf(_sub_cine[4], (float(DisplayServer.window_get_size().y) - pw.end.y) / cz.overlay_rect_to_window(Rect2(0, 0, 1, 1)).size.x)
	elif cz == null:
		var pr: Rect2 = mono.plate_rect()
		_sub_play[0] += 1
		var crate := room.get_node_or_null("NanofluidCrate") as Node2D
		var hit := pr.intersects(cr)
		if crate:
			hit = hit or pr.intersects(crate.get_global_transform_with_canvas() * Rect2(-66.0, -112.0, 200.0, 112.0))
		if hit:
			_sub_play[1] += 1
			_sub_play[3] = _sub_play[3] if _sub_play[3] != "" else "plate %s cat %s x=%.0f" % [str(pr), str(cr), x()]
		if not Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(pr):
			_sub_play[2] += 1


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

## Standalone: a fresh Room 1, every beat, the checkpoint and respawn beats. In the
## full-game chain (tools/audit/full_game.gd) the scene is already loaded and the run
## stops at the exit: see _setup(true) and _beats(true).
func _main() -> void:
	await HumanSweep.lab(self, "room1", note, "LAB ")
	await _setup(false)
	await _beats(false)
	_finish()


func _setup(chained: bool) -> void:
	if not chained:
		ss().delete_save()
		room = load("res://scenes/levels/room1.tscn").instantiate()
		root.add_child(room)
		current_scene = room
	else:
		room = current_scene
	await ticks(4)
	cat = room.get_node("Cat")
	cat.hurt_taken.connect(func(_hp): _hurt += 1)
	cat.died.connect(func(): print("  (cat died at x=%.0f y=%.0f)" % [x(), y()]))
	var mono := root.get_node("Monologue")
	mono.line_started.connect(func(id: String, text: String):
		_lines.append([id, text])
		var cz := CineZoom.current()
		_zoom_state.append([cz != null, cz != null and cz.is_overlaid(mono)]))
	mono.set_finished.connect(func(id: String): _set_done[id] = true)
	process_frame.connect(_sample_subtitle)
	if OS.get_environment("STUB_ANIMS") != "":
		_stub_anims()


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


func _beats(chained: bool) -> void:
	await _beat_intro()
	await _after("intro")
	await _beat_b()
	await _after("b")
	await _beat_c()
	await _after("c")
	await _beat_d()
	await _after("d")
	await _beat_e()
	await _after("e")
	await _beat_f()
	await _after("f")
	await _beat_g()
	await _after("g")
	await _beat_h()
	await _after("h")
	await _beat_pool()
	await _after("pool")
	await _beat_exit()
	await _after("exit")
	if not chained:
		await _beat_continue()
		await _after("continue")
		await _beat_respawn()
		await _after("respawn")
	var headless_win: bool = DisplayServer.window_get_size() == Vector2i.ZERO
	if headless_win:  # --headless has a 0x0 window: the window-space check lives in web_room1.mjs
		_sub_cine = [999, 0, 0, "(headless: no window; web_room1.mjs checks this in window pixels)", 0.0]
	note("I subtitles sit at the window bottom and never lie on the zoomed cat during the close-up", _sub_cine[0] > 20 and _sub_cine[1] == 0 and _sub_cine[2] == 0 and _sub_cine[4] <= 16.0, "%d frames sampled, %d overlap, %d off-window, at most %.0f game px above the window bottom %s" % [_sub_cine[0], _sub_cine[1], _sub_cine[2], _sub_cine[4], _sub_cine[3]])
	note("J subtitles never cover the cat or the crate in normal play (right after the close-up too), and stay on screen", _sub_play[0] > 200 and _sub_play[1] == 0 and _sub_play[2] == 0, "%d frames sampled, %d overlap, %d off-screen %s" % [_sub_play[0], _sub_play[1], _sub_play[2], _sub_play[3]])


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
	note("A bonus letter A peeking out behind the cardboard box", gs().letters == 1 and gs().letter_mask == 2, "mask %d" % gs().letter_mask)
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
	# The bot faces the way it walks (the art faces right: flipped when it goes left).
	var face_ok := true
	for i in 90:
		await ticks(1)
		if bot.state == 0 and absf(bot.velocity.x) > 1.0 and bot.sprite.flip_h != (bot.velocity.x < 0.0):
			face_ok = false
	note("C the patrol bot faces the way it walks", face_ok)
	# Stomp it without powers: the cat bounces, nothing else happens.
	var hp0: int = gs().health
	var bx0: float = bot.global_position.x
	cat.global_position = Vector2(bot.global_position.x, bot.global_position.y - 80.0)
	cat.velocity = Vector2(0.0, 220.0)
	var bounced := false
	var flinched := false
	for i in 40:
		await ticks(1)
		bounced = bounced or cat.velocity.y < -300.0
		flinched = flinched or bot._flinch > 0.0
	note("C stomping the bot without powers bounces the cat", bounced and flinched, "bounced %s flinch %s" % [bounced, flinched])
	note("C ...does no damage: no stun, no befriend, no hurt", bot.state == 0 and bot.stomps == 0 and gs().health == hp0 and not cat.dead, "state %d stomps %d hp %d" % [bot.state, bot.stomps, gs().health])
	await go_to(1440.0)
	await ticks(90)
	note("C ...and the bot keeps patrolling", bot.state == 0 and absf(bot.global_position.x - bx0) > 6.0 and absf(bot.velocity.x) > 1.0, "x %.0f -> %.0f" % [bx0, bot.global_position.x])
	# Now get past it by hopping over, as a player would.
	hold("move_right", true)
	var n := 0
	var stomped_again := 0
	while x() < 1830.0 and n < 1800 and not cat.dead:
		if zone.puddle._ripples.size() > 0:
			rippled = true
		var d: float = bot.global_position.x - x()
		if d > 30.0 and d < 62.0 and cat.is_on_floor():
			hold("jump", true)
			await ticks(22)
			hold("jump", false)
		else:
			hold("jump", false)
		await ticks(1)
		n += 1
	stop()
	await ticks(20)
	note("C waded through the puddle, ripple + splash", rippled, "ripples seen")
	note("C hopped over the patrol bot and got past", x() >= 1830.0 and not cat.dead and bot.stomps == 0, "x=%.0f hp %d stomps %d" % [x(), gs().health, bot.stomps])
	# The harm logic is kept, gated: a bot that is not armoured (or a cat with powers) yields.
	var gated: bool = not bot.can_be_harmed()
	bot.armoured = false
	var open_: bool = bot.can_be_harmed()
	bot.armoured = true
	note("C stun/befriend logic kept, gated behind powers", gated and open_)
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
	var seen := {}
	while x() < 2190.0 and n < 1200:
		await ticks(1)
		n += 1
		if absf(cat.velocity.x) > 14.0:
			seen[cat.sprite.animation] = true
	note("D crawled under the beam (crouch)", x() >= 2150.0 and gs().score > 0, "x=%.0f score %d" % [x(), gs().score])
	var want_move := "crawl" if has_anim("crawl") else "crouch"
	note("D crawling plays '%s' (crawl when it exists, else crouch)" % want_move, seen.size() == 1 and seen.has(want_move), str(seen.keys()))
	dir(0.0)
	await ticks(20)
	var want_idle := "crouch_idle" if has_anim("crouch_idle") else "crouch"
	note("D still, crouched: '%s'" % want_idle, cat.crouched and cat.sprite.animation == want_idle, cat.sprite.animation)
	stop()
	await ticks(10)
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
	var sw := 0  # animation changes while pushing
	var sw_frames := 0
	var last_anim := ""
	var pushing_anims := {}
	var win_start := -1
	var plate_n := -1
	while n < 900 and (plate_n < 0 or n - plate_n < 90):  # push on for 1.5 s past the plate: shoving against the stopper
		await ticks(1)
		n += 1
		if plate_n < 0 and node("PlateA").active:
			plate_n = n
		var near := absf(crate.global_position.x - x()) < 32.0
		if near and win_start < 0:
			win_start = n
		if win_start >= 0:
			sw_frames += 1
			pushing_anims[cat.sprite.animation] = true
			if cat.sprite.animation != last_anim:
				sw += 1
			last_anim = cat.sprite.animation
	stop()
	await ticks(40)
	var secs := maxf(sw_frames / 60.0, 0.01)
	note("E pushing the crate: no animation thrash", sw <= 3 and sw / secs <= 2.0, "%d switches in %.1f s (%.1f/s), anims %s" % [sw, secs, sw / secs, str(pushing_anims.keys())])
	var want_push := "push" if has_anim("push") else "walk"
	note("E pushing plays '%s' (push when it exists, else walk)" % want_push, pushing_anims.has(want_push) and not pushing_anims.has("idle"), str(pushing_anims.keys()))
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
	note("I the first line starts at mind_awakened, during the close-up, drawn on its overlay", not _zoom_state.is_empty() and _zoom_state[0][0] and _zoom_state[0][1], str(_zoom_state[0]) if not _zoom_state.is_empty() else "no line")
	var awake_ids := _lines.filter(func(l): return l[0] == "awakening")
	note("I the awakening monologue starts with the mind (subtitles)", awake_ids.size() >= 1 and awake_ids[0][1] == "...Wait. Whaa- what?", "%d line(s) so far: %s" % [awake_ids.size(), str(awake_ids[0][1]) if awake_ids.size() else "-"])
	await ticks(40)  # the fade-in is done
	var mono_node := root.get_node("Monologue")
	var plate: Control = mono_node._plate
	var view := root.get_visible_rect().size
	note("I the plate is a whole-pixel rect", plate.position == plate.position.round() and plate.size == plate.size.round(), "plate %s %s view %s" % [str(plate.position), str(plate.size), str(view)])
	note("I no container line before the mind awakened / before the cat gets there", not root.get_node("Monologue").has_played("nanofluid_container"))
	mark("I pool+transform")


func _beat_exit() -> void:
	# Walk out.
	await go_to(4690.0, 8.0)
	await hop(1.0, 12)
	note("J out of the pool and up onto the far sill", on_floor_at(288.0) and x() > 4730.0, "x=%.0f y=%.0f" % [x(), y()])
	# The awakening monologue finishes (five lines) whether or not the cat moves.
	var mono := root.get_node("Monologue")
	var n := 0
	while not _set_done.has("awakening") and n < 3000:
		await ticks(1)
		n += 1
	var awake: Array = _lines.filter(func(l): return l[0] == "awakening").map(func(l): return l[1])
	note("J awakening monologue: all five lines played, in order", awake == ["...Wait. Whaa- what?", "Everything is... louder. Sharper. Brighter.", "I've been awake before. Never like this.", "I can think. I mean really think.", "Where am I? What is this place?"], "%d lines" % awake.size())
	note("J subtitle text is plain ASCII Monogram can draw", _lines.all(func(l): return l[1] == mono.clean(l[1]) and not " \u2014 ".is_subsequence_of(l[1])))
	# The container: stepping up to it reads it (mind awake).
	note("J the container is not read before the cat reaches it", not mono.has_played("nanofluid_container"), "x=%.0f" % x())
	await go_to(4832.0, 6.0)
	await ticks(6)
	note("J the container trigger fires after the mind awakens", mono.has_played("nanofluid_container") and gs().intelligence, "x=%.0f y=%.0f" % [x(), y()])
	n = 0
	while not _set_done.has("nanofluid_container") and n < 3000:
		await ticks(1)
		n += 1
	var cont: Array = _lines.filter(func(l): return l[0] == "nanofluid_container")
	note("J container monologue: four lines", cont.size() == 4 and cont[0][1].begins_with("'Experimental Nanofluid'..."), "%d lines" % cont.size())
	await go_to(4880.0, 6.0)
	await ticks(6)
	note("J the exit hint plays once the container was read", mono.has_played("exit_hint"))
	dir(1.0)
	n = 0
	while current_scene == room and n < 600:
		await ticks(1)
		n += 1
	stop()
	var hop: Dictionary = await MapHop.through(root.get_tree(), "warehouse", "yard")
	note("J the exit fades out onto the world map, the warehouse is finished and the yard opens", hop["on_map"] and hop["completed"] and hop["unlocked"], str(hop))
	note("J sound: after the exit no looping sound from the room is still playing, on the map or in the next room", hop["sound_map"].is_empty() and hop["sound_next"].is_empty(), "map %s next %s" % [str(hop["sound_map"]), str(hop["sound_next"])])
	await ticks(exit_settle)
	var r2 := current_scene
	note("J the yard is entered from the map: Room 2 loads", r2 != null and r2.scene_file_path == "res://scenes/levels/room2.tscn", str(r2.scene_file_path if r2 else "?"))
	var save: Dictionary = ss().read_save()
	note("J auto-saved at the start of Room 2", save.get("scene", "") == "res://scenes/levels/room2.tscn" and save.get("abilities", {}).get("mind", false) and not save.get("abilities", {}).get("shockwave", true), str(save.get("abilities", {})))
	note("J the cat keeps its augments in Room 2 (mind flag set)", r2 != null and r2.get_node_or_null("Cat/Sprite/Augments") != null and gs().intelligence)
	var r2cat: Node2D = r2.get_node("Cat") if r2 != null else null
	note("J Room 2 (The Yard) starts: the cat at the warehouse door, control, no power, mind awake", r2cat != null and absf(r2cat.global_position.x - 112.0) < 12.0 and r2cat.can_move and gs().power == 0 and not gs().shockwave_unlocked and gs().intelligence, "x=%.0f" % (r2cat.global_position.x if r2cat else -1.0))
	var wn := 0
	while not _lines.any(func(l): return l[0] == "yard_arrival") and wn < 1200:  # it queues behind the exit hint
		await ticks(1)
		wn += 1
	note("J Room 2 greets the cat with its first thought (Rain. Cold. Real.)", _lines.any(func(l): return l[0] == "yard_arrival" and l[1] == "Rain. Cold. Real."), str(_lines.filter(func(l): return l[0] == "yard_arrival")))
	note("J Room 2 has Surge pads (four on the floor, one on the roofs) and nothing that grants another power", r2 != null and r2.find_children("*", "PowerPad", true, false).size() >= 4 and r2.find_children("*", "PowerPad", true, false).all(func(p): return p.get("power") == 1))
	mark("J exit")


func _beat_continue() -> void:
	# A save from checkpoint A: a fresh Room 1 shows the CONTINUE pad a few tiles
	# from the wake spot, and stepping on it loads the checkpoint.
	ss().delete_save()
	gs().new_game()  # a pre-pool checkpoint: the mind is not awake yet
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
