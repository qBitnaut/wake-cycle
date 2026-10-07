## The Continue and Start Over pads: who gets one, where they are, how they are activated
## (sit and wait 1 s), what Start Over wipes, and that a completed game has neither.
##   XDG_DATA_HOME=/tmp/wc-continue-data godot --headless --path . --fixed-fps 60 --script res://tools/audit/continue_audit.gd -- --skip-intro
## Writes user://save.json, so run it with XDG_DATA_HOME set. Exit code 1 on any FAIL.
extends SceneTree

const R1 := "res://scenes/levels/room1.tscn"
const R3 := "res://scenes/levels/room3.tscn"
const HOME := "res://scenes/levels/home.tscn"
var fails := 0
var room: Node2D
var cat: CharacterBody2D


func gs() -> Node:
	return root.get_node("GameState")


func ss() -> Node:
	return root.get_node("SaveSystem")


func note(label: String, ok: bool, detail := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	_main.call_deferred()


func write_save(d: Dictionary) -> void:
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func v2(scene: String, cp: String) -> Dictionary:
	return {"version": 2, "scene": scene, "checkpoint": cp, "abilities": {"shockwave": false, "mind": true},
		"keys": [], "letters": 1, "letter_mask": 3, "collectibles": ["gone_node"], "health": 3, "score": 10,
		"map": {"completed": ["warehouse", "ghost"], "unlocked": ["yard", "ghost"], "node": "stacks"}}


## A save with a lot of progress, to prove Start Over wipes all of it.
func rich(scene: String, cp: String) -> Dictionary:
	var d := v2(scene, cp)
	d["score"] = 4200
	d["letter_mask"] = 7
	d["letters"] = 3
	d["keys"] = ["brass"]
	d["collectibles"] = ["/root/Room3/GemX", "/root/Room1/GemA", "kill:/root/Room3/Bot1"]
	d["pending_memory"] = "memory_warehouse"
	d["abilities"] = {"shockwave": true, "mind": true}
	return d


func fresh_room1() -> void:
	ss().session_scene = ""
	ss().session_checkpoint = ""
	gs().new_game()
	change_scene_to_file(R1)
	await ticks(12)
	room = current_scene
	cat = room.get_node("Cat")
	while not cat.can_move:
		await ticks(1)


func pad() -> Node2D:
	return room.get_node("ContinuePad")


func over() -> Node2D:
	return room.get_node("StartOverPad")


## From the wake spot, a plain jump (jump held, drifting left) onto the Start Over ledge.
func hop_to_ledge() -> void:
	Input.action_press("jump")
	Input.action_press("move_left")
	var n := 0
	while n < 150:
		await ticks(1)
		n += 1
		if n > 12 and cat.is_on_floor():
			break
		if n > 8 and cat.velocity.y > 0.0 and cat.global_position.x < over().global_position.x + 20.0:
			Input.action_release("move_left")
	Input.action_release("jump")
	Input.action_release("move_left")
	await ticks(2)


## Stand still for `secs` of physics time where the cat is.
func stand(secs: float) -> void:
	await ticks(int(secs * 60.0))


func walk_to(tx: float) -> void:
	var n := 0
	while absf(cat.global_position.x - tx) > 4.0 and n < 900:
		var d := signf(tx - cat.global_position.x)
		Input.action_press("move_right" if d > 0 else "move_left")
		Input.action_release("move_left" if d > 0 else "move_right")
		await ticks(1)
		n += 1
	Input.action_release("move_left")
	Input.action_release("move_right")


func _main() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))

	await fresh_room1()
	note("1 fresh profile: no pad", not pad().visible and not ss().has_save())

	write_save({"version": 1, "scene": R3, "checkpoint": "cp_old", "abilities": {}})
	await fresh_room1()
	note("2 v1 save: no pad, save discarded", not pad().visible and not ss().has_save() and not FileAccess.file_exists("user://save.json"), ss().last_discard)
	write_save({"scene": R3, "checkpoint": "cp_a"})
	note("2b unversioned save discarded", not ss().has_save() and not FileAccess.file_exists("user://save.json"), ss().last_discard)

	write_save(v2(R3, "cp_a"))
	await fresh_room1()
	var p := pad()
	note("3 valid v2 save: pad shown, left of the wake spot, sign 'Room 3: The Stacks'", p.visible and p.global_position.x < cat.global_position.x - 32.0 and p.sign_text == "Room 3: The Stacks", "%s x=%.0f" % [p.sign_text, p.global_position.x])
	var so := over()
	note("3a Start Over pad: shown with a save, above the Continue pad, red-orange vs teal, its own sign", so.visible and so.global_position.y < p.global_position.y - 48.0 and absf(so.global_position.x - p.global_position.x) < 48.0 and so.sign_lines()[0] == "START OVER" and p.sign_lines()[0] == "CONTINUE" and absf(so.accent().h - p.accent().h) > 0.1, "so %s pad %s" % [str(so.global_position), str(p.global_position)])
	var mono := root.get_node("Monologue")
	var lines_before: int = mono.history.size()
	await walk_to(p.global_position.x + 90.0)
	var charge_max := 0.0
	for i in 40:  # a brush-past, walking straight through at full speed
		Input.action_press("move_left")
		await ticks(1)
		charge_max = maxf(charge_max, p.charge)
		if cat.global_position.x < p.global_position.x - 70.0:
			break
	Input.action_release("move_left")
	await ticks(5)
	note("3b brush-past does not trigger", current_scene == room and charge_max < 1.0, "max charge %.2f" % charge_max)
	await walk_to(p.global_position.x)
	await ticks(20)
	note("3b2 the pad's tease is a meow, not words: no mind yet, so no subtitle and no narration", mono.meow_log.any(func(m): return m[0] == "continue_tease") and mono.history.size() == lines_before and mono.voice_log.is_empty() and not mono.is_speaking(), str(mono.meow_log))
	note("3c standing charges the ring but not yet (0.33 s), and the cat is sitting", current_scene == room and p.charge > 0.2 and p.charge < 1.0 and cat.sprite.animation == "sit", "%.2f %s" % [p.charge, cat.sprite.animation])
	await stand(0.4)
	note("3c2 0.73 s of standing still is not enough (1.0 s needed)", current_scene == room and p.charge > 0.6 and p.charge < 1.0, "%.2f" % p.charge)
	# A short stand then off the plate: the ring drains and nothing fires.
	await walk_to(p.global_position.x + 90.0)
	await stand(0.6)
	note("3c3 a short stand, then walking off, never triggers; the ring drains", current_scene == room and p.charge == 0.0, "%.2f" % p.charge)
	await walk_to(p.global_position.x)
	await stand(0.6)
	note("3c4 0.6 s standing (the old threshold) does not trigger now", current_scene == room and p.charge < 1.0, "%.2f" % p.charge)
	await ticks(60)
	await ticks(60)
	var r3 := current_scene
	note("3d sitting 1.0 s loads Room 3 at cp_a", r3.scene_file_path == R3 and ss().session_checkpoint == "cp_a", "%s %s" % [r3.scene_file_path, ss().session_checkpoint])
	var card := r3.find_child("TitleCard", true, false)
	note("3e title card shows 'The Stacks'", card != null and card.get_child_count() >= 1 and (card.get_child(card.get_child_count() - 1) as Label).text == "The Stacks")
	var spawn: Vector2 = r3.get_node("Cat").global_position
	var cpn: Node2D = null
	for c in get_nodes_in_group("checkpoint"):
		if c.checkpoint_id == "cp_a":
			cpn = c
	note("3f cat is at cp_a", cpn != null and spawn.distance_to(cpn.global_position) < 40.0, str(spawn))
	note("3g stale map ids and unknown collectibles are harmless", "ghost" not in gs().map_completed and "ghost" not in gs().map_unlocked and gs().map_node == "stacks")

	write_save(v2(R3, "cp_removed"))
	var d: Dictionary = ss().read_save()
	note("4 removed checkpoint id falls back to the room start", d.get("checkpoint", "x") == "" and ss().last_fallback)
	ss().session_scene = ""
	ss().session_checkpoint = ""
	ss().continue_game()
	await ticks(20)
	var r3b := current_scene
	var st: Vector2 = r3b.get_node(r3b.start_path).global_position
	note("4b Room 3 opens at its start", r3b.scene_file_path == R3 and r3b.get_node("Cat").global_position.distance_to(st) < 40.0 and ss().session_checkpoint == "", str(r3b.get_node("Cat").global_position))

	write_save(v2(R3, "cp_a"))
	await fresh_room1()
	var start_x := cat.global_position.x
	await walk_to(start_x + 200.0)
	note("5 walking right from the wake spot never triggers Continue", current_scene == room and pad().charge == 0.0 and cat.global_position.x > start_x + 150.0, "x=%.0f" % cat.global_position.x)

	# The Start Over ledge: reachable with a plain jump from the wake spot.
	write_save(rich(R3, "cp_a"))
	await fresh_room1()
	var floor_y := cat.global_position.y
	await walk_to(start_x)
	await stand(0.3)
	await hop_to_ledge()
	var so2 := over()
	note("7 a plain jump from the wake spot lands on the Start Over ledge (no powers)", so2.overlaps_body(cat) and cat.is_on_floor() and cat.global_position.y < floor_y - 48.0 and not gs().shockwave_unlocked and not gs().intelligence, "cat %s floor %.0f pad %s" % [str(cat.global_position), floor_y, str(so2.global_position)])
	note("7b the cat on the ledge is at the pad, on the floor of the ledge", so2.overlaps_body(cat) and cat.is_on_floor(), "cat %s pad %s" % [str(cat.global_position), str(so2.global_position)])
	await ticks(24)
	note("7c standing on it sits the cat at once and fills the ring (0.33 s)", cat.sprite.animation == "sit" and so2.charge > 0.1 and so2.charge < 0.6, "%s %.2f" % [cat.sprite.animation, so2.charge])
	await stand(0.4)
	note("7d 0.73 s is not enough: nothing wiped", ss().has_save() and current_scene == room and so2.charge < 1.0, "%.2f" % so2.charge)
	# Drop off the right end (a brush past the plate): the ring drains and nothing fires.
	await walk_to(so2.global_position.x + 70.0)
	await stand(0.5)
	note("7e leaving the plate drains the ring; the save is untouched", ss().has_save() and current_scene == room and so2.charge == 0.0, "%.2f" % so2.charge)
	await walk_to(start_x)
	await hop_to_ledge()
	var old_room := current_scene
	await walk_to(so2.global_position.x)
	await stand(1.3)
	note("8 sitting 1.0 s on Start Over fires: the soft meow (no words)", mono.meow_log.any(func(m): return m[0] == "startover") and mono.history.is_empty() and mono.voice_log.is_empty() and not mono.is_speaking(), str(mono.meow_log))
	await ticks(150)
	note("8b the save is wiped completely", not ss().has_save() and not FileAccess.file_exists("user://save.json"))
	note("8c a new game: no abilities, no map progress, score 0, nothing collected, no pending memory", gs().score == 0 and gs().collected.is_empty() and gs().letter_mask == 0 and gs().keys.is_empty() and not gs().intelligence and not gs().shockwave_unlocked and gs().map_completed.is_empty() and gs().map_unlocked.is_empty() and gs().map_node == "" and gs().pending_memory == "", str(gs().snapshot()))
	room = current_scene
	cat = room.get_node("Cat")
	note("8d Room 1 restarted fresh at the wake spot (a new scene, the cat awake and moving)", room != old_room and room.scene_file_path == R1 and cat.can_move and absf(cat.global_position.x - start_x) < 8.0 and ss().session_checkpoint == "", "%s %s" % [str(cat.global_position), str(cat.can_move)])
	note("8e both pads are gone", not pad().visible and not over().visible and not ss().has_save())
	note("8f the session snapshot is the fresh game's", ss().session_snapshot.get("score", -1) == 0 and ss().session_snapshot.get("collected", ["x"]).is_empty())
	note("8g no checkpoint is written by the restart", not FileAccess.file_exists("user://save.json"))

	# Walking right with a save around is still a plain new game; its first checkpoint overwrites the old save.
	write_save(rich(R3, "cp_a"))
	await fresh_room1()
	await walk_to(cat.global_position.x + 120.0)
	note("9 walking right keeps the old save untouched until the first checkpoint", ss().has_save() and int(ss().read_save().get("score", 0)) == 4200)
	gs().new_game()
	ss().save_checkpoint("cp_a", R1)
	note("9b the new run's first checkpoint overwrites it", int(ss().read_save().get("score", -1)) == 0 and String(ss().read_save().get("scene", "")) == R1)

	# Completion: no pad afterwards, and the Home auto-save cannot come back.
	write_save(rich(R3, "cp_a"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://complete.json"))
	ss().session_scene = ""
	ss().session_checkpoint = ""
	gs().new_game()
	RoomTransition.arriving = true  # Home saves on arrival: the save the bug left behind
	change_scene_to_file(HOME)
	await ticks(30)
	var home := current_scene
	note("10 arriving in Home auto-saves a checkpoint (the Continue-to-house trap)", ss().has_save() and String(ss().read_save().get("scene", "")) == HOME)
	home._settle()  # the cat reaches the cushion: the final sleep begins
	await ticks(2)
	note("10b the final sleep begins: the save is cleared at once (not at the end of the credits)", not ss().has_save() and not FileAccess.file_exists("user://save.json") and ss().is_complete() and ss().session_checkpoint == "" and ss().session_snapshot.is_empty())
	ss().persist_collected("/root/Home/Late")
	note("10c nothing written afterwards can resurrect a save", not FileAccess.file_exists("user://save.json"))
	ss().mark_complete()
	note("10d the credits' own mark_complete is harmless", not ss().has_save() and ss().is_complete())
	await fresh_room1()
	note("10e the next launch: no Continue pad, no Start Over pad, no save", not pad().visible and not over().visible and not ss().has_save())
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://complete.json"))

	# A memory waiting for the mind (found in Room 1 before the goo) survives a checkpoint save and a Continue.
	gs().new_game()
	gs().pending_memory = "memory_warehouse"
	ss().save_checkpoint("cp_a", R1)
	note("6 the pending memory is written with the checkpoint", String(ss().read_save().get("pending_memory", "")) == "memory_warehouse")
	gs().new_game()
	note("6b a new game forgets it", gs().pending_memory == "")
	ss().session_scene = ""
	ss().session_checkpoint = ""
	ss().continue_game()
	await ticks(20)
	note("6c Continue restores it", gs().pending_memory == "memory_warehouse" and not gs().intelligence, gs().pending_memory)
	gs().restore(gs().snapshot())
	note("6d snapshot / restore keep it (a respawn)", gs().pending_memory == "memory_warehouse")
	gs().awaken_mind()
	note("6e once the mind is awake it plays (both lines, subtitles) and the flag clears", mono.play_pending_memory() and gs().pending_memory == "" and mono.is_speaking() and not mono.play_pending_memory())

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	print("%s" % ("CONTINUE AUDIT PASS" if fails == 0 else "CONTINUE AUDIT FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
