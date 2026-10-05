## Plays the whole game in one headless run: a fresh Room 1 (the intro, the pool,
## the exit), Room 2, Room 3, Room 4, Home, the credits, and back to a fresh Room 1,
## with scripted input in the real scenes with the real physics. It reuses each room's
## own playthrough routine (room1_playthrough.gd ... home_playthrough.gd: their
## _setup(true) and beats, with the scenes entered through the real exits), and adds
## continuity assertions at every transition plus continue-from-save checks from a
## Room 3 and a Room 4 checkpoint.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/full_game.gd
## FROM=room2|room3|room4|home starts the chain at that room as the previous exit leaves
## the cat (for iterating; the full run is the one that counts).
## Exit code 1 on any failure. Deletes user://save.json and user://complete.json (use
## XDG_DATA_HOME to keep a real profile out of it).
##
## The routines extend SceneTree so each can run alone; here their source is loaded
## as a Node with a few SceneTree shims (root, current_scene, physics_frame, ...), so
## the audit files stay the single source of truth.
extends SceneTree

const ROOM1 := "res://scenes/levels/room1.tscn"
const ROOM2 := "res://scenes/levels/room2.tscn"
const ROOM3 := "res://scenes/levels/room3.tscn"
const ROOM4 := "res://scenes/levels/room4.tscn"
const HOME := "res://scenes/levels/home.tscn"

const SHIM := """
var root: Window:
	get:
		return get_tree().root
var current_scene: Node:
	get:
		return get_tree().current_scene
	set(v):
		get_tree().current_scene = v
var physics_frame: Signal:
	get:
		return get_tree().physics_frame
var process_frame: Signal:
	get:
		return get_tree().process_frame
func get_nodes_in_group(g: StringName) -> Array[Node]:
	return get_tree().get_nodes_in_group(g)
func change_scene_to_file(p: String) -> int:
	return get_tree().change_scene_to_file(p)
func quit(_code := 0) -> void:
	pass
"""

var results: Array = []          ## [name, ok, detail] of the chain's own checks
var _counts: Array = []          ## [label, passed, total] per routine
var _frames := 0
var _shots := ""
var _shot_n := 0
var _pre_exit := {}              ## GameState just before a room's exit beat
var _cat_in_room: Node2D


func gs() -> Node:
	return root.get_node("GameState")


func ss() -> Node:
	return root.get_node("SaveSystem")


func mono() -> Node:
	return root.get_node("Monologue")


func _initialize() -> void:
	_main.call_deferred()


func ticks(n: int) -> void:
	for i in n:
		await physics_frame
		_frames += 1


func note(label: String, ok: bool, detail := "") -> void:
	results.append([label, ok, detail])
	print("%s  %-70s %s" % ["PASS" if ok else "FAIL", label, detail])


func shot(label: String) -> void:
	if _shots == "":
		return
	await ticks(20)
	_shot_n += 1
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [_shots, _shot_n, label])
	print("   shot %s" % label)


## A routine from an audit file, as a Node with the SceneTree shims.
func routine(path: String) -> Node:
	var src := FileAccess.get_file_as_string(path)
	var rx := RegEx.create_from_string("(?m)^extends SceneTree\\s*$")
	src = rx.sub(src, "extends Node\n" + SHIM)
	var gd := GDScript.new()
	gd.source_code = src
	var err := gd.reload()
	if err != OK:
		push_error("full_game: cannot compile %s (%d)" % [path, err])
		quit(2)
	var n: Node = gd.new()
	n.name = path.get_file().get_basename()
	root.add_child(n)
	return n


func done(label: String, r: Node) -> void:
	var passed := 0
	for e in r.results:
		if e[1]:
			passed += 1
		else:
			print("   (%s) FAIL: %s %s" % [label, e[0], e[2]])
	_counts.append([label, passed, r.results.size()])
	# Let go of the routine's per-frame hooks.
	for c in process_frame.get_connections():
		if c["callable"].get_object() == r:
			process_frame.disconnect(c["callable"])
	r.set("beat_hook", Callable())


func snap() -> Dictionary:
	var g := gs()
	return {
		"score": g.score, "keys": g.keys.duplicate(), "letter_mask": g.letter_mask,
		"collected": g.collected.duplicate(), "mind": g.intelligence, "shock": g.shockwave_unlocked,
		"health": g.health,
	}


func _aug_shown() -> bool:
	var cat := current_scene.get_node_or_null("Cat")
	var aug: Node = cat.get_node_or_null("Sprite/Augments") if cat else null
	return aug != null and aug.get("shown") == true


## Continuity at a room-to-room transition. `scene` is where the cat now is.
func transition(label: String, scene: String, want_mind: bool, want_shock: bool, augments := true) -> void:
	var s := current_scene
	note("%s the next room is %s" % [label, scene.get_file()], s != null and s.scene_file_path == scene, str(s.scene_file_path if s else "?"))
	note("%s mind %s, shockwave %s" % [label, want_mind, want_shock], gs().intelligence == want_mind and gs().shockwave_unlocked == want_shock, "mind %s shock %s" % [gs().intelligence, gs().shockwave_unlocked])
	note("%s no power carried through the exit (pads are the only source)" % label, gs().power == 0, "power %d" % gs().power)
	var save: Dictionary = ss().read_save()
	note("%s auto-saved on arrival with the same abilities" % label, save.get("scene", "") == scene and save.get("abilities", {}).get("mind", false) == want_mind and save.get("abilities", {}).get("shockwave", false) == want_shock, str(save.get("abilities", {})))
	if augments:
		note("%s the augments show on the cat" % label, _aug_shown())
	if not _pre_exit.is_empty():
		var now := snap()
		var kept := true
		for k in _pre_exit["keys"]:
			kept = kept and now["keys"].has(k)
		var coll := true
		for c in _pre_exit["collected"]:
			coll = coll and now["collected"].has(c)
		note("%s score, keys, letters and pickups carried (nothing lost)" % label, now["score"] >= _pre_exit["score"] and kept and coll and (now["letter_mask"] & _pre_exit["letter_mask"]) == _pre_exit["letter_mask"], "score %d -> %d, %d pickups" % [_pre_exit["score"], now["score"], now["collected"].size()])
		note("%s health carried (a hit stays a hit; no free heal)" % label, now["health"] <= maxi(_pre_exit["health"], now["health"]) and now["health"] >= 1, "hp %d -> %d" % [_pre_exit["health"], now["health"]])
		_pre_exit = {}
	await shot(label.to_lower().replace(" ", "_").replace(">", "to"))


## Continue from the checkpoint the routine just saved, as a fresh launch would: the
## in-memory game is wiped, the save read from disk, the room entered at the checkpoint.
func continue_check(r: Node, label: String, want_shock: bool) -> void:
	var cp: String = ss().session_checkpoint
	var scene: String = current_scene.scene_file_path
	var save: Dictionary = ss().read_save()
	if r.has_method("_run_lab"):  # Room 3's audit hooks live on the room instance the Continue replaces
		r._prior_unlocks += r.room.get("shock_unlocks")
		r._prior_violations += int(r.room.get("power_violations"))
	note("%s a checkpoint save exists on disk" % label, cp != "" and save.get("checkpoint", "") == cp and save.get("scene", "") == scene, "cp %s, save %s" % [cp, str(save.get("checkpoint", ""))])
	# What the save on disk holds: a Continue must restore exactly this (not the live state,
	# which has moved on since the checkpoint).
	var before := {
		"score": int(save.get("score", 0)), "keys": save.get("keys", []).duplicate(), "letter_mask": int(save.get("letter_mask", 0)),
		"collected": save.get("collectibles", []).duplicate(), "health": int(save.get("health", 3)),
	}
	var spawn := Vector2.ZERO
	for c in get_nodes_in_group("checkpoint"):
		if c.checkpoint_id == cp:
			spawn = c.spawn_position()
	# A fresh launch: nothing in memory.
	gs().new_game()
	mono().reset()
	ss().session_scene = ""
	ss().session_checkpoint = ""
	ss().session_snapshot = {}
	var old := current_scene
	var ok: bool = ss().continue_game()
	var n := 0
	while (current_scene == null or current_scene == old or current_scene.get_node_or_null("Cat") == null) and n < 600:
		await ticks(1)
		n += 1
	await ticks(30)
	var s := current_scene
	var cat: Node2D = s.get_node("Cat")
	note("%s Continue loads the room at the checkpoint" % label, ok and s.scene_file_path == scene and ss().session_checkpoint == cp and cat.global_position.distance_to(spawn) < 40.0, "cat %s spawn %s" % [str(cat.global_position.round()), str(spawn.round())])
	note("%s the mind and the shockwave are as saved (shockwave %s)" % [label, want_shock], gs().intelligence and gs().shockwave_unlocked == want_shock, "mind %s shock %s" % [gs().intelligence, gs().shockwave_unlocked])
	var now := snap()
	var coll := true
	for c in before["collected"]:
		coll = coll and now["collected"].has(c)
	var same_keys: bool = now["keys"].size() == before["keys"].size()
	for k in before["keys"]:
		same_keys = same_keys and now["keys"].has(k)
	note("%s score, keys, letters, pickups and health restored from the save" % label, now["score"] == before["score"] and same_keys and now["letter_mask"] == before["letter_mask"] and coll and now["collected"].size() == before["collected"].size() and now["health"] == before["health"], "score %d/%d, %d pickups, hp %d/%d" % [now["score"], before["score"], now["collected"].size(), now["health"], before["health"]])
	note("%s no power held after a Continue" % label, gs().power == 0)
	note("%s the augments show, control is back" % label, _aug_shown() and cat.can_move)
	note("%s a death now respawns at the same checkpoint" % label, ss().session_checkpoint == cp)
	r.refresh()
	await shot(label.to_lower().replace(" ", "_"))


func _main() -> void:
	_shots = OS.get_environment("SHOTS")
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://complete.json"))
	ss().delete_save()
	gs().new_game()
	mono().reset()
	ss().session_scene = ""
	ss().session_checkpoint = ""
	ss().session_snapshot = {}
	RoomTransition.arriving = false
	var base := "res://tools/audit/"

	# ---- Room 3's lab first: the hop parameters its route uses (its own throwaway room) ----
	var r3 := routine(base + "room3_playthrough.gd")
	await r3._run_lab()
	gs().new_game()
	mono().reset()
	ss().delete_save()
	ss().session_scene = ""
	ss().session_checkpoint = ""
	ss().session_snapshot = {}
	RoomTransition.arriving = false

	var from := OS.get_environment("FROM")
	var order := ["room1", "room2", "room3", "room4", "home"]
	var start := order.find(from) if from != "" else 0
	if start > 0:
		gs().awaken_mind()
		if start >= 3:
			gs().unlock_shockwave()
		RoomTransition.arriving = true
		change_scene_to_file([ROOM1, ROOM2, ROOM3, ROOM4, HOME][start])
		await ticks(2)

	# ---- Room 1: a fresh game ----
	if start == 0:
		change_scene_to_file(ROOM1)
		await ticks(2)
	if start == 0:
		note("START a fresh game: nothing awake, nothing unlocked, full health", not gs().intelligence and not gs().shockwave_unlocked and gs().power == 0 and gs().health == 3 and gs().score == 0 and gs().collected.is_empty())
	var r1 := routine(base + "room1_playthrough.gd")
	if start <= 0:
		r1.beat_hook = func(_r, b): _pre_exit = snap() if b == "pool" else _pre_exit
		r1.exit_settle = 2
		await r1._setup(true)
		await r1._beats(true)
		done("room1", r1)
		await transition("R1>R2", ROOM2, true, false)

	# ---- Room 2 ----
	if start <= 1:
		var r2 := routine(base + "room2_playthrough.gd")
		r2.beat_hook = func(_r, b): _pre_exit = snap() if b == "drone" else _pre_exit
		r2.exit_settle = 2
		await r2._setup(true)
		await r2._beats()
		done("room2", r2)
		await transition("R2>R3", ROOM3, true, false)

	# ---- Room 3 ----
	if start <= 2:
		r3.beat_hook = func(r, b):
			if b == "spring_use":
				await continue_check(r, "C3a Room 3 checkpoint (before the conduit)", false)
			elif b == "combine":
				await continue_check(r, "C3b Room 3 checkpoint (after the conduit, on the exit roof)", true)
				_pre_exit = snap()
		r3.exit_settle = 2
		await r3._setup(true)
		await r3._beats()
		done("room3", r3)
		await transition("R3>R4", ROOM4, true, true)

	# ---- Room 4 ----
	if start <= 3:
		var r4 := routine(base + "room4_playthrough.gd")
		r4.beat_hook = func(r, b):
			if b == "gate_locked":
				await continue_check(r, "C4 Room 4 checkpoint", true)
			elif b == "scanner":
				_pre_exit = snap()
		r4.exit_settle = 2
		await r4._setup(true)
		await r4._beats(true)
		done("room4", r4)
		await transition("R4>HOME", HOME, true, true)

	# ---- Home, the credits, a fresh Room 1 ----
	var rh := routine(base + "home_playthrough.gd")
	await rh._setup(true)
	await rh._beats()
	done("home", rh)
	await _fresh_room1()
	await shot("back_in_room1")
	_report()


## After the credits: a brand-new game in Room 1.
func _fresh_room1() -> void:
	var s := current_scene
	var cat: Node2D = s.get_node_or_null("Cat")
	note("END back in Room 1 after the credits", s != null and s.scene_file_path == ROOM1, str(s.scene_file_path if s else "?"))
	note("END a fresh game: no mind, no shockwave, no power, full health, no score", not gs().intelligence and not gs().shockwave_unlocked and gs().power == 0 and gs().health == 3 and gs().score == 0 and gs().keys.is_empty() and gs().letter_mask == 0 and gs().collected.is_empty(), str(snap()))
	note("END no checkpoint, no ContinuePad, the game marked complete", not ss().has_save() and ss().session_checkpoint == "" and ss().is_complete() and not s.get_node("ContinuePad").visible)
	note("END the cat has no augments again, and starts asleep", cat != null and cat.get_node_or_null("Sprite/Augments") == null and not cat.can_move and cat.forced_anim.begins_with("sleep"), "anim %s" % (cat.forced_anim if cat else "?"))
	note("END the monologue starts over", mono().history.is_empty())
	# The intro plays again, then control.
	var n := 0
	while cat != null and not cat.can_move and n < 2400:
		await ticks(1)
		n += 1
	note("END the intro plays again and hands over control", cat != null and cat.can_move and n < 2400, "after %.1f s" % (n / 60.0))
	note("END no power UI, the shockwave locked again", gs().power == 0 and not gs().shockwave_unlocked)
	# A second Room 1 start through the deep-link path is a fresh one too: nothing is left in GameState.
	cat.set_can_move(false)


func _report() -> void:
	var total := 0
	var passed := 0
	print("")
	print("== per routine")
	for c in _counts:
		print("   %-8s %3d / %3d" % [c[0], c[1], c[2]])
		passed += c[1]
		total += c[2]
	var own := results.filter(func(r): return r[1]).size()
	print("   %-8s %3d / %3d  (continuity + continue-from-save)" % ["chain", own, results.size()])
	passed += own
	total += results.size()
	var failed := total - passed
	print("== %d checks, %s, %d frames" % [total, "ALL PASS" if failed == 0 else "%d FAILED" % failed, _frames])
	for r in results:
		if not r[1]:
			print("   FAIL: %s %s" % [r[0], r[2]])
	ss().delete_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://complete.json"))
	quit(1 if failed > 0 else 0)
