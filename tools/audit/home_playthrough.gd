## Plays the Home ending start to finish with scripted movement input
## (Input.action_press, the same path a keyboard takes), in the real scenes
## with the real physics: no teleporting.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/home_playthrough.gd
##
## Arrival (as Room 4 leaves the cat: mind awake, augments on, a room change
## with its auto-save) -> the walk (home_arrival; sparrows take off; puddles
## ring; things glint and drip) -> the steps (home_flap) -> the cat flap (the
## facade dissolves, the cat comes out inside) -> the sunbeam (input locks and
## stays locked: circle, sit, lie down, sleep; the augments dim to a slow
## breathing glow; the close-up eases in) -> home_final, in order -> the warm
## fade -> the credits (the title, the roll, "The End"; holding a movement
## speeds the roll, a movement press leaves) -> Room 1 from the very start.
## Prints MEASURE lines with the timings. Exit code 1 if any check fails.
## Deletes user://save.json and user://complete.json (use XDG_DATA_HOME to
## keep a real profile out of it).
extends SceneTree

const HOME := "res://scenes/levels/home.tscn"
const CREDITS := "res://scenes/ui/credits.tscn"
const ROOM1 := "res://scenes/levels/room1.tscn"

var room: Node2D
var cat: CharacterBody2D
var results: Array = []
var _frames := 0
var _anims: Array = []      # the cat's animations, in order, during the settle
var _lines: Array = []


func gs() -> Node:
	return root.get_node("GameState")


func ss() -> Node:
	return root.get_node("SaveSystem")


func mono() -> Node:
	return root.get_node("Monologue")


func _initialize() -> void:
	_main.call_deferred()


func hold(action: String, on := true) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func ticks(n: int) -> void:
	for i in n:
		await physics_frame
		_frames += 1


func secs(s: float) -> void:
	await ticks(int(s * 60.0))


func x() -> float:
	return cat.global_position.x


func note(label: String, ok: bool, detail := "") -> void:
	results.append([label, ok, detail])
	print("%s  %-64s %s" % ["PASS" if ok else "FAIL", label, detail])


func measure(label: String, detail: String) -> void:
	print("MEASURE  %-40s %s" % [label, detail])


func lines_of(id: String) -> Array:
	return mono().history.filter(func(l): return l[0] == id).map(func(l): return l[1])


## Walk right (plain movement) until x >= target or the predicate holds.
func walk_to(target: float, limit := 3600) -> bool:
	var n := 0
	hold("move_right")
	while x() < target and n < limit and cat.can_move:
		await ticks(1)
		n += 1
	hold("move_right", false)
	return x() >= target


func wait_until(cond: Callable, limit := 3600) -> bool:
	var n := 0
	while not cond.call() and n < limit:
		await ticks(1)
		n += 1
	return n < limit


## Standalone: Home as Room 4 leaves the cat. In the full-game chain
## (tools/audit/full_game.gd) Home is already loaded: _setup(true).
func _main() -> void:
	await _setup(false)
	await _beats()
	_report()


func _setup(chained: bool) -> void:
	if not chained:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://complete.json"))
		ss().delete_save()
		# As Room 4 leaves it: the mind awake, the shockwave, arriving through an exit.
		gs().new_game()
		gs().awaken_mind()
		gs().unlock_shockwave()
		mono().reset()
		load("res://scripts/systems/room_transition.gd").set("arriving", true)
		change_scene_to_file(HOME)
		await ticks(10)
	room = current_scene
	cat = room.get_node("Cat")


func _beats() -> void:
	await _arrival()
	await _walk()
	await _flap()
	await _settle()
	await _credits()


func _arrival() -> void:
	note("A Home loads", room.scene_file_path == HOME, room.scene_file_path)
	var save: Dictionary = ss().read_save()
	note("A auto-saved on arrival, mind and shockwave kept", save.get("scene", "") == HOME and save.get("abilities", {}).get("mind", false) and save.get("abilities", {}).get("shockwave", false), str(save))
	note("A fades up out of the dark (a slow fade)", room.get_node_or_null("RoomFade") != null)
	var aug: Node = cat.get_node_or_null("Sprite/Augments")
	note("A the augments show", aug != null and aug.get("shown") == true)
	note("A no HUD: nothing to score here", room.get_node_or_null("Hud") == null)
	note("A the cat strolls (walk speed under the run threshold)", cat.get("run_speed") < 117.0, str(cat.get("run_speed")))
	note("A no power is active", gs().power == 0)


func _walk() -> void:
	var t0 := _frames
	var ok := await walk_to(700.0)
	await wait_until(func(): return lines_of("home_arrival").size() >= 2, 900)
	note("B home_arrival plays on the first steps", lines_of("home_arrival") == ["The sun. I forgot how warm it is.", "This street. That fence. I know this place."], str(lines_of("home_arrival")))
	var anim: String = cat.get("sprite").animation
	ok = await walk_to(1660.0) and ok
	var birds: Node = room.get_node("Birds")
	note("B sparrows take off as the cat passes", birds.get("flown") >= 3, "flown %d" % birds.get("flown"))
	var p3: Node = room.get_node("Puddle3").get("puddle")
	note("B the big puddle ripples under the cat", p3.get("_ripples").size() > 0)
	ok = await walk_to(3080.0) and ok
	note("B the street is walkable with plain movement", ok, "x=%.0f" % x())
	measure("street walk (to the steps)", "%.1f s" % ((_frames - t0) / 60.0))
	var front: Node = room.get_node("Glints")
	var back: Node = room.get_node("GlintsBack")
	note("B wet things glint and drip", front.get("glints_spawned") > 20 and front.get("drops_landed") > 3 and back.get("glints_spawned") > 10, "front %d/%d back %d/%d" % [front.get("glints_spawned"), front.get("drops_landed"), back.get("glints_spawned"), back.get("drops_landed")])
	note("B walking plays the walk animation", anim == "walk", anim)


func _flap() -> void:
	var t0 := _frames
	hold("move_right")
	await wait_until(func(): return int(room.get("beat")) != 0, 900)
	note("C the flap trigger takes the cat (walking into the door)", int(room.get("beat")) == 1)
	note("C input is locked while it goes through", not cat.can_move)
	hold("move_right", false)
	await wait_until(func(): return lines_of("home_flap").size() >= 1, 600)
	note("C home_flap plays at the steps", lines_of("home_flap") == ["Still unlocked. They left it open for me."], str(lines_of("home_flap")))
	# The facade's eave drips and window glints go with it, falling drops too.
	var wet_max := 0
	var n := 0
	while int(room.get("beat")) != 2 and n < 600:
		wet_max = maxi(wet_max, int(room.call("facade_wet")))
		await ticks(1)
		n += 1
	await wait_until(func(): return float(room.get("facade_amount")) <= 0.0, 120)
	note("C the facade has dissolved", float(room.get("facade_amount")) <= 0.0 and not room.get_node("Facade").visible)
	note("C ... and its drips and glints faded with it (none left inside)", wet_max > 0 and int(room.call("facade_wet")) == 0, "%d at the dissolve, %d now" % [wet_max, int(room.call("facade_wet"))])
	note("C the cat is inside, past the door, visible", x() > 3270.0 and cat.get("sprite").modulate.a > 0.99, "x=%.0f" % x())
	note("C control is back inside", cat.can_move)
	measure("through the flap", "%.1f s" % ((_frames - t0) / 60.0))
	var t1 := _frames
	hold("move_right")
	await wait_until(func(): return int(room.get("beat")) >= 3, 900)
	measure("door to the sunbeam", "%.1f s" % ((_frames - t1) / 60.0))
	note("C walking into the sunbeam starts the settle", int(room.get("beat")) == 3)
	# The story counts as complete the moment the final sleep begins: the Home auto-save is gone then,
	# not at the end of the credits (a browser closed mid-credits must leave no Continue to the house).
	note("C the final sleep has begun: the run's save is cleared and the game is marked complete", ss().call("is_complete") and not ss().has_save() and ss().session_scene == "" and ss().session_snapshot.is_empty(), "save %s" % str(ss().has_save()))


func _settle() -> void:
	# Keep holding right: the cat must not move off its spot.
	var spot: float = room.get("spot_x")
	var min_x := 99999.0
	var max_x := -99999.0
	var asleep_at := -1
	var cz_max := 1.0
	var t0 := _frames
	var spr: AnimatedSprite2D = cat.get("sprite")
	while int(room.get("beat")) < 4 and _frames - t0 < 900:
		if _anims.is_empty() or _anims.back() != spr.animation:
			_anims.append(spr.animation)
		if String(room.get("settle_step")) != "step_in":
			min_x = minf(min_x, x())
			max_x = maxf(max_x, x())
		await ticks(1)
	if _anims.back() != spr.animation:
		_anims.append(spr.animation)
	hold("move_right", false)  # held all through the settle: it moved nothing
	hold("jump")  # a jump press is movement too: it must change nothing
	await ticks(3)
	hold("jump", false)
	asleep_at = _frames
	note("D the cat settles: walk, sit, lie down, sleep", _has_order(_anims, ["walk", "sit", "lie_down", "sleep_breath"]), str(_anims))
	note("D input stays locked: the cat keeps to its spot", max_x - min_x <= 9.0 and absf(x() - spot) <= 5.0, "x %.0f..%.0f spot %.0f" % [min_x, max_x, spot])
	note("D it sleeps on the cushion (sprite raised onto it)", cat.get("sprite").position.y < CatFrames.SPRITE_Y - 0.5, str(cat.get("sprite").position.y))
	measure("settle (spot to asleep)", "%.1f s" % ((_frames - t0) / 60.0))
	var aug: Node = cat.get_node("Sprite/Augments")
	await secs(7.0)
	var e1: float = aug.call("emitter_energy")
	var lo := 9.0
	var hi := 0.0
	# No flicker: the sprite holds a whole-pixel transform (no scale) and only
	# the breath's frames change, each held for its whole duration.
	var steady := true
	var changes := 0
	var last := spr.frame
	var held := 0
	var shortest := 99999
	for k in 300:
		await ticks(1)
		var e: float = aug.call("emitter_energy")
		lo = minf(lo, e)
		hi = maxf(hi, e)
		steady = steady and spr.scale == Vector2.ONE and spr.position == spr.position.round() and spr.animation == "sleep_breath"
		held += 1
		if spr.frame != last:
			changes += 1
			if changes > 1:
				shortest = mini(shortest, held)
			held = 0
			last = spr.frame
	note("D asleep it holds still: whole pixels, no scaling", steady, "scale %s pos %s" % [spr.scale, spr.position])
	note("D ... and breathes slowly (each frame held 0.3 s or more)", changes >= 3 and shortest >= 17, "%d frame changes in 5 s, shortest hold %d ticks" % [changes, shortest])
	note("D the house stays dry inside", int(room.call("facade_wet")) == 0)
	note("D the augments stay on and settle to a dim glow", aug.get("shown") and aug.call("is_sleeping") and hi <= 0.35 and e1 <= 0.35, "%.2f..%.2f" % [lo, hi])
	note("D ... that breathes slowly", hi - lo > 0.06, "%.2f..%.2f" % [lo, hi])
	var cz: Node = room.get("cine")
	note("D the close-up eases in", cz != null and float(cz.get("zoom")) > 1.8, "zoom %.2f" % (float(cz.get("zoom")) if cz else 0.0))
	note("D the music has come in (the director's home track, faded up)", root.get_node("AudioDirector").music_key == "home" and root.get_node("AudioDirector").music_db() > -20.0, "key %s %.1f dB" % [root.get_node("AudioDirector").music_key, root.get_node("AudioDirector").music_db()])
	var want := [
		"Home. It smells like home.",
		"I don't know exactly what I am now. Something more than I was.",
		"But some things are still simple.",
		"Warm sun. Soft cushion. Safe.",
		"...Wake cycle complete.",
	]
	await wait_until(func(): return lines_of("home_final").size() >= 5 and not mono().is_speaking(), 3600)
	note("D home_final, every line in order", lines_of("home_final") == want, str(lines_of("home_final")))
	measure("asleep to the last line's end", "%.1f s" % ((_frames - asleep_at) / 60.0))
	note("D still asleep, still on the spot", cat.get("sprite").animation == "sleep_breath" and absf(x() - spot) <= 5.0)
	var t1 := _frames
	await wait_until(func(): return current_scene != room, 900)
	measure("last line to the credits", "%.1f s" % ((_frames - t1) / 60.0))


func _has_order(seq: Array, want: Array) -> bool:
	var i := 0
	for a in seq:
		if i < want.size() and a == want[i]:
			i += 1
	return i == want.size()


func _credits() -> void:
	await ticks(5)
	var c := current_scene
	note("E the credits scene follows", c != null and c.scene_file_path == CREDITS, str(c.scene_file_path if c else "?"))
	var ui: Node = c.get_node("Ui")
	var white: ColorRect = ui.get_node("WarmWhite")
	note("E it opens on the warm white the ending faded to", white.modulate.a > 0.99 and white.color.r > 0.95 and white.color.b < 0.95)
	var title_seen := 0.0
	var t0 := _frames
	for k in 600:
		await ticks(1)
		for l in ui.get_children():
			if l is Label and l.text == "Wake Cycle":
				title_seen = maxf(title_seen, l.modulate.a)
	note("E the title card \"Wake Cycle\" shows", title_seen > 0.95)
	await wait_until(func(): return int(c.get("step")) == 2, 900)
	note("E the room is revealed and the roll starts", int(c.get("step")) == 2 and white.modulate.a < 0.05)
	var roll: Control = ui.get_node("Roll")
	var texts: Array = roll.get_children().map(func(l): return l.text)
	note("E the credits name the jam, the theme and the restriction", texts.has("A Jamference game jam entry") and texts.has("Theme: Cat and Robot") and texts.has("Restriction: Movement input only"))
	note("E ... the maker and the crew", texts.has("Chris (qBitnaut)") and texts.has("with the AI crew in Claude Code:") and texts.has("Janeway, orchestrating;"))
	note("E ... the asset authors", texts.has("The cat: Pet Cats Pack - luizmelo") and texts.has("monogram - datagoblin") and texts.has("- Luis Zuno (ansimuz), harmonised") and texts.has("- bart and rubberduck, recoloured"))
	note("E ... the sound as generated with ElevenLabs, the narrator's voice named", texts.has("generated with ElevenLabs") and texts.has("Narrator: Will - Relaxed Optimist"))
	var gone := ["Junkala", "SubspaceAudio", "Kenney", "qubodup", "SFX Loops", "Chiptunes"]
	note("E ... and none of the retired audio packs", texts.all(func(t): return gone.all(func(g): return not String(t).contains(g))))
	note("E ... and ends with thanks", texts.back() == "Thanks for playing.", str(texts.back()))
	var y0 := roll.position.y
	await secs(2.0)
	var y1 := roll.position.y
	var slow := y0 - y1
	hold("jump")
	await secs(2.0)
	var fast := y1 - roll.position.y
	note("E holding a movement speeds the roll up", fast > slow * 3.0, "%.0f px vs %.0f px in 2 s" % [fast, slow])
	await wait_until(func(): return bool(c.get("roll_done")), 7200)
	hold("jump", false)
	measure("credits roll (2 s slow, then held)", "%.1f s" % ((_frames - t0) / 60.0))
	await wait_until(func(): return int(c.get("step")) == 3, 900)
	var end: Label = null
	for l in ui.get_children():
		if l is Label and l.text == "The End":
			end = l
	await secs(2.0)
	note("E \"The End\" shows", end != null and end.modulate.a > 0.95)
	note("E it waits (no return without a movement yet)", current_scene == c and int(c.get("step")) == 3)
	hold("move_left")
	await ticks(2)
	hold("move_left", false)
	await wait_until(func(): return current_scene != c, 600)
	await ticks(30)
	var r1 := current_scene
	note("E a movement press returns to Room 1", r1 != null and r1.scene_file_path == ROOM1, str(r1.scene_file_path if r1 else "?"))
	note("E ... from the very start (asleep, the intro)", r1 != null and int(r1.get("beat")) == 0)
	note("E ... as a fresh game (no mind, no shockwave, no monologue)", not gs().intelligence and not gs().shockwave_unlocked and mono().history.is_empty())
	note("E the game is marked complete and the checkpoint cleared", ss().call("is_complete") and not ss().has_save())
	note("E ... and Room 1's pads are gone: no Continue pad, no Start Over pad", not r1.get_node("ContinuePad").visible and not r1.get_node("StartOverPad").visible)
	note("E the ending music is gone", root.get_node("AudioDirector").music_key != "home", "key %s" % root.get_node("AudioDirector").music_key)


func _report() -> void:
	var failed := results.filter(func(r): return not r[1])
	print("")
	print("%d checks, %d failed" % [results.size(), failed.size()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://complete.json"))
	quit(1 if failed.size() > 0 else 0)
