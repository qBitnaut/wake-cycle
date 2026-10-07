## The Continue pad: who gets one, where it is, how it is activated.
##   XDG_DATA_HOME=/tmp/wc-continue-data godot --headless --path . --fixed-fps 60 --script res://tools/audit/continue_audit.gd -- --skip-intro
## Writes user://save.json, so run it with XDG_DATA_HOME set. Exit code 1 on any FAIL.
extends SceneTree

const R1 := "res://scenes/levels/room1.tscn"
const R3 := "res://scenes/levels/room3.tscn"
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
	note("3c standing charges the ring but not yet (0.33 s)", current_scene == room and p.charge > 0.2 and p.charge < 1.0, "%.2f" % p.charge)
	await ticks(60)
	await ticks(60)
	var r3 := current_scene
	note("3d standing 0.6 s loads Room 3 at cp_a", r3.scene_file_path == R3 and ss().session_checkpoint == "cp_a", "%s %s" % [r3.scene_file_path, ss().session_checkpoint])
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

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	print("%s" % ("CONTINUE AUDIT PASS" if fails == 0 else "CONTINUE AUDIT FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
