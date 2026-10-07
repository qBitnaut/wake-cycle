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
		if OS.get_environment("GO_TRACE") != "" and n % 60 == 0:
			print("   go %.0f: %s vx=%.0f" % [target, st(), cat.velocity.x])
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
	if OS.get_environment("SWEEP") != "0":
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
	cat.hurt_taken.connect(func(_hp):
		_hurt += 1
		print("  (hurt at x=%.0f y=%.0f)" % [x(), y()]))
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
	var tp := OS.get_environment("TELEPORT")   # dev: "x,y" to start a route test mid-level
	if tp != "":
		var xy := tp.split(",")
		cat.global_position = Vector2(float(xy[0]), float(xy[1]))
		cat.velocity = Vector2.ZERO
		await ticks(10)
	var only := OS.get_environment("ONLY")
	if only == "crateedge":
		await _run_steps(_route_data()["crateedge"], "crateedge")
		_finish()
		return
	if only == "lifttest":
		await _run_steps(_route_data()["lifttest"], "lifttest")
		_finish()
		return      # dev: "racks,mezz" to run just those beats
	for b in BEATS:
		if only != "" and not only.split(",").has(b):
			continue
		await _route_beat(b)
		await _after(b)
	if only != "":
		if only.split(",").has("pool"):
			await _beat_pool()
			await _beat_exit()
		_finish()
		return
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


## The route beats, in order (tools/audit/room1_route.json holds the steps).
const BEATS := ["crates", "floor", "racks", "mezz", "lift", "roof", "office", "shaft", "basement", "tunnel", "drain", "lab"]
var _route: Dictionary = {}
var _score_mark := 0
var _hp_mark := 3


func _route_data() -> Dictionary:
	if _route.is_empty():
		_route = JSON.parse_string(FileAccess.get_file_as_string("res://tools/audit/room1_route.json"))
	return _route


func _route_beat(beat_name: String) -> void:
	if _route.is_empty():
		_route = JSON.parse_string(FileAccess.get_file_as_string("res://tools/audit/room1_route.json"))
	await _run_steps(_route[beat_name], beat_name)
	mark(beat_name)


## Named actors' state, as the room publishes it: name -> [x, y, phase/mode, dangerous, open].
func watch(n: String, idx: int) -> Variant:
	var w: Dictionary = room.call("_watch")
	return w[n][idx] if w.has(n) else null


func _run_steps(steps: Array, label: String) -> void:
	for st in steps:
		var op: String = st[0]
		match op:
			"go":
				await go_to(float(st[1]), float(st[2]) if st.size() > 2 else 6.0)
			"hop":
				await hop(float(st[1]), int(st[2]), int(st[3]) if st.size() > 3 else 0, int(st[4]) if st.size() > 4 else 999)
			"runhop":
				await run_hop_d(float(st[1]), float(st[2]), int(st[3]), int(st[4]) if st.size() > 4 else 0)
			"crawl":
				hold("move_down", true)
				dir(float(st[1]))
				var n := 0
				while (x() - float(st[2])) * float(st[1]) < 0.0 and n < 1500:
					await ticks(1)
					n += 1
				hold("move_down", false)
				dir(0.0)
				await ticks(20)
			"off":
				# Walk off an edge in direction d past x, steer the other way for a few frames.
				var d := float(st[1])
				dir(d)
				var n := 0
				while (x() - float(st[2])) * d < 0.0 and n < 1500:
					await ticks(1)
					n += 1
				if int(st[4]) > 0:
					dir(float(st[3]))
					await ticks(int(st[4]))
					dir(0.0)
				n = 0
				while cat.is_on_floor() and n < 40:   # still on the ledge: keep walking
					await ticks(1)
					n += 1
				n = 0
				while not cat.is_on_floor() and n < 600:
					await ticks(1)
					n += 1
				dir(0.0)
				await ticks(8)
			"wait", "waitgt", "waitlt":
				var n := 0
				while n < 1800:
					var v: Variant = watch(String(st[1]), int(st[2]))
					var want: Variant = st[3]
					var ok := false
					if v != null:
						if op == "wait":
							ok = v == want or (v is bool and str(v) == str(want)) or (typeof(v) == TYPE_INT and typeof(want) == TYPE_FLOAT and float(v) == want) or (typeof(v) == TYPE_FLOAT and float(v) == float(want) and false)
						elif op == "waitgt":
							ok = float(v) > float(want)
						else:
							ok = float(v) < float(want)
					if ok:
						break
					await ticks(1)
					n += 1
				note("%s waited for %s[%s] %s %s" % [label, st[1], st[2], op, str(st[3])], n < 1800, "%d ticks" % n)
			"expect":
				var ok := cat.is_on_floor() and absf(x() - float(st[2])) <= float(st[4]) and absf(y() - float(st[3])) <= float(st[5])
				note(String(st[1]), ok, "x=%.0f y=%.0f (want %s, %s)" % [x(), y(), str(st[2]), str(st[3])])
			"cpcheck":
				note("%s checkpoint %s saves" % [label, st[1]], ss().session_checkpoint == String(st[1]), str(ss().session_checkpoint))
			"letters":
				note("%s letters %d" % [label, int(st[1])], gs().letters == int(st[1]) or gs().letter_mask == int(st[1]), "mask %d" % gs().letter_mask)
			"mask":
				note(String(st[1]), gs().letter_mask == int(st[2]), "mask %d" % gs().letter_mask)
			"board":
				# Step onto the moving lift only while it is down at the catwalk's level.
				var n := 0
				while n < 3000:
					var ly: float = float(watch(String(st[1]), 1))
					var lx: float = float(watch(String(st[1]), 0))
					if cat.is_on_floor() and absf(y() - ly) < 8.0 and absf(x() - lx) < 28.0:
						break
					if x() > 392.0 and ly < 500.0 and absf(y() - 516.0) < 6.0:
						dir(0.0)   # the lift is away: wait on the catwalk
					else:
						dir(-1.0 if x() > float(st[2]) else 1.0)
					await ticks(1)
					n += 1
				dir(0.0)
				await ticks(4)
			"key":
				note(String(st[1]), gs().keys.has("brass"), str(gs().keys))
			"gone":
				note(String(st[1]), room.get_node_or_null(String(st[2])) == null, "x=%.0f" % x())
			"opendoor":
				dir(1.0)
				var dn := 0
				while room.get_node_or_null(String(st[1])) != null and dn < 400:
					await ticks(1)
					dn += 1
				dir(0.0)
				await ticks(10)
			"setpos":
				var sn := room.get_node_or_null(String(st[1])) as Node2D
				if sn:
					sn.global_position = Vector2(float(st[2]), float(st[3]))
					sn.set("linear_velocity", Vector2.ZERO)
			"pos":
				var nd := room.get_node_or_null(String(st[1]))
				print("   pos %s %s" % [st[1], str(nd.global_position) if nd else "gone"])
			"gorel":
				await go_to(x() + float(st[1]), 6.0)
			"hp0":
				_hp_mark = gs().health
			"hp":
				note(String(st[1]), gs().health >= _hp_mark, "hp %d (was %d)" % [gs().health, _hp_mark])
			"markscore":
				_score_mark = gs().score
			"scoreup":
				note(String(st[1]), gs().score - _score_mark >= int(st[2]), "score +%d" % (gs().score - _score_mark))
			"collected":
				note(String(st[1]), gs().collected.any(func(c): return String(c).ends_with("/" + String(st[2]))), str(gs().collected.size()))
			"hold":
				await ticks(int(st[1]))
			"nopower":
				note("%s no powers yet" % label, no_powers())
			"stand":
				stop()
				await ticks(int(st[1]))
			"snap":
				print("   @ %s: %s" % [label, st_()])
			"note":
				note(String(st[1]), true)


func st_() -> String:
	return "x=%.0f y=%.0f floor=%s hp=%d" % [x(), y(), cat.is_on_floor(), gs().health]


## A running jump in direction d: run until x passes jx, take off, hold direction for
## dir_frames, double jump at frame dj (0 = none).
func run_hop_d(d: float, jx: float, dir_frames: int, dj := 0) -> void:
	dir(d)
	var n := 0
	while (x() - jx) * d < 0.0 and n < 600:
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


func _beat_pool() -> void:
	# The pool cannot be jumped over: take a run-up and double jump from the lip.
	var signalled := [false]
	room.nanotech_absorbed_started.connect(func(): signalled[0] = true)
	var gs_signalled := [false]
	gs().nanotech_absorbed_started.connect(func(): gs_signalled[0] = true)
	await go_to(3660.0)
	dir(1.0)
	while x() < 3712.0 - 6.0:
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
	note("I jumping the pool fails: the cat is caught", room.get("beat") == 3 and caught_x < 4032.0, "caught at x=%.0f (pool 3712..4032)" % caught_x)
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
	var ai := -1
	for k in _lines.size():
		if _lines[k][0] == "awakening":
			ai = k
			break
	note("I the first awakening line starts at mind_awakened, during the close-up, drawn on its overlay", ai >= 0 and ai < _zoom_state.size() and _zoom_state[ai][0] and _zoom_state[ai][1], str(_zoom_state[ai]) if ai >= 0 and ai < _zoom_state.size() else "no line")
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
	await go_to(3990.0, 8.0)
	await hop(1.0, 12)
	note("J out of the pool and up onto the far sill", on_floor_at(1024.0) and x() > 4034.0, "x=%.0f y=%.0f" % [x(), y()])
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
	await go_to(4128.0, 6.0)
	await ticks(6)
	note("J the container trigger fires after the mind awakens", mono.has_played("nanofluid_container") and gs().intelligence, "x=%.0f y=%.0f" % [x(), y()])
	n = 0
	while not _set_done.has("nanofluid_container") and n < 3000:
		await ticks(1)
		n += 1
	var cont: Array = _lines.filter(func(l): return l[0] == "nanofluid_container")
	note("J container monologue: four lines", cont.size() == 4 and cont[0][1].begins_with("'Experimental Nanofluid'..."), "%d lines" % cont.size())
	await go_to(4176.0, 6.0)
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
	note("K CONTINUE pad shown with a save, BEHIND the cat (left of the wake spot)", pad.visible and pad.global_position.x < 144.0 - T, "pad x=%.0f" % pad.global_position.x)
	var old_room := room
	while not cat.can_move:
		await ticks(1)
	# Walking right (a new game) never touches it.
	await go_to(600.0, 6.0)
	await go_to(144.0, 6.0)
	note("K walking right and back does not continue", current_scene == old_room and pad.charge == 0.0)
	# Deliberately standing on it does.
	await go_to(pad.global_position.x, 4.0)
	var n := 0
	while is_instance_valid(old_room) and old_room == current_scene and n < 600:
		await ticks(1)
		n += 1
	dir(0.0)
	await ticks(30)
	room = current_scene
	cat = room.get_node("Cat")
	note("K continue loads the checkpoint", absf(x() - 1072.0) < 12.0 and ss().session_checkpoint == "cp_a", "x=%.0f cp %s" % [x(), ss().session_checkpoint])
	mark("continue")


func _beat_respawn() -> void:
	# Dying reloads the room at the last checkpoint: no intro again, control at once.
	cat.kill()
	await ticks(100)
	room = current_scene
	cat = room.get_node("Cat")
	var hud: CanvasLayer = node("Hud")
	note("L death respawns at the checkpoint, no intro", absf(x() - 1072.0) < 12.0 and cat.can_move and hud.visible and room.get("beat") == 1, "x=%.0f beat %s" % [x(), str(room.get("beat"))])
	note("L no pads in Room 1, nothing unlocked on a fresh respawn", room.find_children("*", "PowerPad", true, false).is_empty() and gs().power == 0)
	mark("respawn")
