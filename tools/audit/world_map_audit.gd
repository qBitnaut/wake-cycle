## World map audit: drives the map with scripted movement input
## (Input.action_press, the same path a keyboard takes) in the real scene.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/world_map_audit.gd
##
## Checks: the registry is sound; a fresh game has only the warehouse open;
## opening the map after each level completes it, unlocks the next one, plays
## the reveal and walks the cat there; walking left/right (and down a fork)
## goes node to node; Up or Jump on a level picks that level's scene (stub
## check: level_chosen with the registry path, nothing is loaded); locked nodes
## cannot be entered or walked to; a secret appears only once its conditions
## hold; a bonus placeholder opens when it gets a scene; the save round-trips
## (save.json "map" and a Continue onto the map); a RoomExit pointing at the
## map scene counts as finishing its level; only movement actions do anything.
## Exit code 1 if any check fails. Deletes user://save.json (use XDG_DATA_HOME
## to keep a real profile out of it).
extends SceneTree

const MAP := "res://scenes/ui/world_map.tscn"
const SAVE := "user://save.json"

var WM: GDScript
var REG: GDScript
var results: Array = []
var map: Node2D
var _chosen: Array = []


func gs() -> Node:
	return root.get_node("GameState")


func ss() -> Node:
	return root.get_node("SaveSystem")


func _initialize() -> void:
	_main.call_deferred()


func note(label: String, ok: bool, detail := "") -> void:
	results.append([label, ok, detail])
	print("%s  %-66s %s" % ["PASS" if ok else "FAIL", label, detail])


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func secs(s: float) -> void:
	await ticks(int(s * 60.0))


func tap(action: String) -> void:
	Input.action_press(action)
	await ticks(2)
	Input.action_release(action)
	await ticks(1)


func hold(action: String, on := true) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "dash"]:
		Input.action_release(a)


## Replace the running scene with a fresh map instance (as a level exit would:
## the save session is a level's, so the map does not restore its own last
## snapshot, which only a Continue onto the map should do).
func open_map(done: String) -> void:
	if map and is_instance_valid(map):
		map.queue_free()
		await process_frame
	ss().session_scene = ""
	WM.set("_pending", done)
	map = load(MAP).instantiate()
	map.level_chosen.connect(func(id, path): _chosen.append([id, path]))
	root.add_child(map)
	current_scene = map
	await process_frame


func wait_reveal(limit := 20.0) -> bool:
	var t := 0.0
	while map.get("auto") and t < limit:
		await ticks(6)
		t += 0.1
	await ticks(4)
	return not map.get("auto")


## Walk with a held direction until the cat stops on a node (or time runs out).
func walk(action: String, limit := 8.0) -> String:
	hold(action)
	await ticks(3)
	var t := 0.0
	while t < limit:
		await ticks(6)
		t += 0.1
		if map.get("at_node") != "" and t > 0.2:
			break
	hold(action, false)
	await ticks(2)
	return String(map.get("at_node"))


func _main() -> void:
	WM = load("res://scripts/ui/world_map.gd")
	REG = load("res://scripts/systems/level_registry.gd")
	WM.set("load_levels", false)
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	await check_registry()
	await check_fresh_game()
	await check_progression()
	await check_walking()
	await check_locked()
	await check_secret_and_bonus()
	await check_save_round_trip()
	await check_room_exit_inference()
	await check_movement_only()
	var fails := results.filter(func(r): return not r[1])
	print("\n%d checks, %d failed" % [results.size(), fails.size()])
	for f in fails:
		print("  FAILED: ", f[0], "  ", f[2])
	quit(1 if fails.size() > 0 else 0)


# ---- the registry ------------------------------------------------------------------

func check_registry() -> void:
	REG.call("load_data", true)
	var ids: Array = REG.call("level_ids")
	var main: Array = ids.filter(func(i): return REG.call("is_main", i))
	note("registry: five story levels in order", main == ["warehouse", "yard", "stacks", "perimeter", "home"], str(main))
	note("registry: starts at the warehouse, ends at home", REG.call("start_id") == "warehouse" and REG.call("final_id") == "home")
	var extras: Array = ids.filter(func(i): return not REG.call("is_main", i))
	note("registry: 2-3 bonus/secret placeholders", extras.size() >= 2 and extras.size() <= 3, str(extras))
	var bad: Array = []
	for i in REG.call("paths").size():
		var pts: PackedVector2Array = REG.call("path_points", i)
		if pts.size() < 2:
			bad.append(i)
	note("registry: every path joins two known nodes", bad.is_empty(), str(bad))
	for id in main:
		var scene: String = REG.call("scene_of", id)
		var exists := ResourceLoader.exists(scene)
		if exists:
			note("scene exists: %s -> %s" % [id, scene], true)
		else:
			# Not a failure on a branch that lacks the room (it is open but
			# cannot be entered until the scene lands).
			print("INFO  scene missing on this branch: %s -> %s" % [id, scene])
	# Gem totals in the registry match the scenes (counted from the .tscn text).
	for id in main:
		var scene: String = REG.call("scene_of", id)
		if not FileAccess.file_exists(scene):
			continue
		var txt := FileAccess.get_file_as_string(scene)
		var n := 0
		for line in txt.split("\n"):
			if line.begins_with("[node name=\"Gem"):
				n += 1
		var want: int = REG.call("gems_total", id)
		if n == 0 and want > 0:
			print("INFO  %s has no gems in %s on this branch (a stub?)" % [id, scene])
		elif n > 0 or want > 0:
			note("gem total matches the scene: %s" % id, n == want, "registry %d, scene %d" % [want, n])
	note("map art: placement file exists", FileAccess.file_exists("res://assets/art_hd/map/map_art.json"))


# ---- a fresh game --------------------------------------------------------------------

func check_fresh_game() -> void:
	gs().new_game()
	await open_map("")
	await ticks(10)
	var open: Array = REG.call("open_levels")
	note("fresh game: only the warehouse is open", open == ["warehouse"], str(open))
	note("fresh game: the cat stands on the warehouse", map.get("at_node") == "warehouse")
	var at := await walk("move_right", 1.5)
	note("fresh game: walking right goes nowhere (the yard is locked)", at == "warehouse", at)
	note("fresh game: the yard cannot be entered", not map.call("enter_level", "yard"))
	# Jumping ahead (a deep link, an old save): the route behind is completed
	# quietly; only the level ahead is news for the reveal.
	gs().new_game()
	var fresh: Array = REG.call("complete", "stacks")
	note("jumping ahead: only the next level is news", fresh == ["perimeter"], str(fresh))
	note("jumping ahead: the route behind is completed", gs().map_completed.has("warehouse") and gs().map_completed.has("yard"))


# ---- after each level ------------------------------------------------------------------

func check_progression() -> void:
	gs().new_game()
	gs().awaken_mind()
	var chain := [["warehouse", "yard"], ["yard", "stacks"], ["stacks", "perimeter"], ["perimeter", "home"]]
	var fps_pan: Array = []
	for step in chain:
		var done: String = step[0]
		var nxt: String = step[1]
		var before: Array = gs().map_completed.duplicate()
		await open_map(done)
		var revealing: bool = map.get("auto")
		var cam0: float = map.get("cam_x")
		var cams: Array = []
		var t := 0.0
		while map.get("auto") and t < 20.0:
			await ticks(6)
			t += 0.1
			cams.append(map.get("cam_x"))
		await ticks(4)
		note("after %s: the reveal plays" % done, revealing and not before.has(done))
		note("after %s: completed" % done, gs().map_completed.has(done))
		note("after %s: %s unlocked and open" % [done, nxt], gs().map_unlocked.has(nxt) and REG.call("is_open", nxt))
		note("after %s: the cat walked to %s" % [done, nxt], map.get("at_node") == nxt, "at %s after %.1f s" % [map.get("at_node"), t])
		note("after %s: map_node saved as %s" % [done, nxt], gs().map_node == nxt and String(ss().read_save().get("map", {}).get("node", "")) == nxt)
		var span := 0.0
		for c in cams:
			span = maxf(span, absf(float(c) - cam0))
		note("after %s: the camera panned along the new path" % done, span > 120.0, "pan %.0f px in %.1f s" % [span, t])
		fps_pan.append(t)
		# Skipping: a jump press during the reveal speeds it up.
	print("MEASURE  reveal durations (s): ", fps_pan)
	# Skip check: the same reveal with a jump press is much quicker.
	gs().new_game()
	await open_map("warehouse")
	await ticks(30)
	await tap("jump")
	var t2 := 0.0
	while map.get("auto") and t2 < 20.0:
		await ticks(6)
		t2 += 0.1
	note("a jump during the reveal hurries it (skip)", t2 < 3.5 and map.get("at_node") == "yard", "%.1f s" % t2)
	note("the skip press does not go into the level", _chosen.is_empty() or _chosen.back()[0] != "yard")


# ---- walking and going in ---------------------------------------------------------------------

func check_walking() -> void:
	# Everything up to the perimeter done: the cat on the perimeter.
	gs().new_game()
	REG.call("complete", "stacks")
	await open_map("")
	await ticks(10)
	map.set("at_node", "perimeter")
	map.get("cat").position = REG.call("position_of", "perimeter")
	gs().map_node = "perimeter"
	var at := await walk("move_left", 10.0)
	note("walk left: perimeter -> stacks (down the fire escape, through the fork)", at == "stacks", at)
	at = await walk("move_left", 10.0)
	note("walk left: stacks -> yard (down the stairs, past the drain fork)", at == "yard", at)
	at = await walk("move_left", 10.0)
	note("walk left: yard -> warehouse", at == "warehouse", at)
	at = await walk("move_left", 2.0)
	note("walk left at the warehouse: nowhere to go", at == "warehouse", at)
	at = await walk("move_right", 10.0)
	note("walk right: warehouse -> yard", at == "yard", at)
	# Turning round mid-path.
	hold("move_right")
	await secs(0.6)
	var mid: String = map.get("at_node")
	hold("move_right", false)
	await tap("move_left")
	var t := 0.0
	while map.get("at_node") == "" and t < 6.0:
		await ticks(6)
		t += 0.1
	note("a press against the walk turns the cat round", mid == "" and map.get("at_node") == "yard", "at %s" % map.get("at_node"))
	# Going in: Jump and Up pick the level's scene (stub: nothing is loaded).
	_chosen.clear()
	await ticks(20)
	await tap("jump")
	await ticks(5)
	var ok: bool = _chosen.size() == 1 and _chosen[0][0] == "yard" and _chosen[0][1] == REG.call("scene_of", "yard")
	note("Jump on the yard picks the yard's scene", ok, str(_chosen))
	note("the yard's scene path exists", ResourceLoader.exists(String(REG.call("scene_of", "yard"))))
	await open_map("")
	await ticks(10)
	map.set("at_node", "warehouse")
	map.get("cat").position = REG.call("position_of", "warehouse")
	_chosen.clear()
	await ticks(20)
	await tap("move_up")
	await ticks(5)
	note("Up on the warehouse picks room1.tscn", _chosen.size() == 1 and _chosen[0][1] == "res://scenes/levels/room1.tscn", str(_chosen))
	# Home: the final node plays the ending.
	gs().new_game()
	REG.call("complete", "perimeter")
	await open_map("")
	await ticks(10)
	map.set("at_node", "home")
	map.get("cat").position = REG.call("position_of", "home")
	_chosen.clear()
	await ticks(20)
	await tap("jump")
	await ticks(5)
	note("Jump on home picks the ending (home.tscn)", _chosen.size() == 1 and _chosen[0][1] == "res://scenes/levels/home.tscn", str(_chosen))
	# Revisiting: a finished level can be entered again.
	await open_map("")
	await ticks(10)
	map.set("at_node", "warehouse")
	map.get("cat").position = REG.call("position_of", "warehouse")
	_chosen.clear()
	await ticks(20)
	await tap("jump")
	await ticks(5)
	note("a finished level can be revisited", _chosen.size() == 1 and _chosen[0][0] == "warehouse", str(_chosen))


# ---- locked nodes --------------------------------------------------------------------------------

func check_locked() -> void:
	gs().new_game()
	REG.call("complete", "perimeter")
	await open_map("")
	await ticks(10)
	note("bonus placeholders stay locked without a scene", not REG.call("is_open", "water_tower") and not REG.call("is_open", "signal_box"))
	note("a locked bonus is visible (greyed)", REG.call("is_visible", "water_tower"))
	note("enter_level refuses a locked node", not map.call("enter_level", "water_tower"))
	# At the fork under the water tower, Up does not climb the locked ladder.
	map.set("at_node", "fork_tower")
	map.get("cat").position = REG.call("position_of", "fork_tower")
	await ticks(10)
	await tap("move_up")
	await ticks(30)
	note("Up at the fork does not climb to a locked bonus", map.get("at_node") == "fork_tower" and map.get("cat").position == REG.call("position_of", "fork_tower"))
	map.set("at_node", "fork_signal")
	map.get("cat").position = REG.call("position_of", "fork_signal")
	await ticks(10)
	await tap("move_up")
	await ticks(30)
	note("Up at the signal fork does not climb either", map.get("at_node") == "fork_signal")
	# A level not yet reached cannot be walked to or entered.
	gs().new_game()
	REG.call("complete", "warehouse")
	note("the stacks are locked after the warehouse", not REG.call("is_open", "stacks"))
	note("no route to a locked level", (REG.call("route", "yard", "stacks") as Array).is_empty())


# ---- secret and bonus ------------------------------------------------------------------------------

func check_secret_and_bonus() -> void:
	REG.set("overrides", {"drain": {"scene": "res://scenes/levels/test_room.tscn"}, "water_tower": {"scene": "res://scenes/levels/test_room.tscn"}})
	gs().new_game()
	REG.call("complete", "yard")
	note("the secret stays hidden without the C-A-T letters", not REG.call("is_visible", "drain"))
	for i in 3:
		gs().collect_letter(i)
	note("with all three letters the secret appears", REG.call("is_visible", "drain") and REG.call("is_open", "drain"))
	await open_map("")
	await ticks(10)
	map.set("at_node", "yard")
	map.get("cat").position = REG.call("position_of", "yard")
	gs().map_node = "yard"
	# Right from the yard reaches the fork; with two ways on, the cat waits there.
	hold("move_right")
	await ticks(3)
	hold("move_right", false)
	var t := 0.0
	while map.get("at_node") == "" and t < 6.0:
		await ticks(6)
		t += 0.1
	note("at a real fork the cat stops", map.get("at_node") == "fork_drain", String(map.get("at_node")))
	var at := await walk("move_down", 6.0)
	note("Down at the fork walks to the secret drain", at == "drain", at)
	# The bonus: finishing the stacks now opens the water tower too.
	gs().new_game()
	REG.call("complete", "yard")
	await open_map("stacks")
	var fresh_open: bool = REG.call("is_open", "water_tower")
	await wait_reveal()
	note("a bonus with a scene opens with its level", fresh_open)
	note("after the reveal the cat is on the main route (perimeter)", map.get("at_node") == "perimeter", String(map.get("at_node")))
	REG.set("overrides", {})


# ---- saving -------------------------------------------------------------------------------------------

func check_save_round_trip() -> void:
	gs().new_game()
	gs().awaken_mind()
	await open_map("yard")
	await wait_reveal()
	var d: Dictionary = ss().read_save()
	var m: Dictionary = d.get("map", {})
	note("save: written on the map", d.get("scene", "") == MAP, String(d.get("scene", "")))
	note("save: map.completed has the warehouse and the yard", (m.get("completed", []) as Array).has("warehouse") and (m.get("completed", []) as Array).has("yard"), str(m.get("completed", [])))
	note("save: map.unlocked has the stacks", (m.get("unlocked", []) as Array).has("stacks"))
	note("save: map.node is the stacks", m.get("node", "") == "stacks")
	note("save: the old fields are all still there", d.has("checkpoint") and d.has("abilities") and d.has("letters") and d.has("collectibles") and d.has("health") and d.has("score") and d.has("version"))
	# Continue: wipe the run, load the save, the map comes back as it was.
	map.queue_free()
	await process_frame
	gs().new_game()
	ss().session_scene = ""
	var ok: bool = ss().continue_game()
	await process_frame
	await ticks(20)
	map = current_scene as Node2D
	note("continue: lands on the map", ok and map != null and map.scene_file_path == MAP)
	note("continue: progress restored", gs().map_completed.has("yard") and gs().map_unlocked.has("stacks"), str(gs().map_completed))
	note("continue: the cat is back on the stacks", map != null and map.get("at_node") == "stacks", String(map.get("at_node")) if map else "")
	# An old save without "map" still restores everything else.
	var before: Array = gs().map_completed.duplicate()
	gs().restore({"health": 2, "score": 10, "keys": [], "letter_mask": 1, "mind": true, "collected": [], "shockwave": false})
	note("an old snapshot without map keeps the map progress", gs().map_completed == before and gs().health == 2)


# ---- RoomExit -> map ------------------------------------------------------------------------------------

func check_room_exit_inference() -> void:
	if map and is_instance_valid(map):
		map.queue_free()
		await process_frame
	gs().new_game()
	gs().awaken_mind()
	# The cat was in Room 2; its RoomExit's next_scene is the map scene.
	ss().session_scene = "res://scenes/levels/room2.tscn"
	var rt: GDScript = load("res://scripts/systems/room_transition.gd")
	rt.set("arriving", true)
	WM.set("_pending", "")
	change_scene_to_file(MAP)
	await process_frame
	await process_frame
	await ticks(5)
	map = current_scene as Node2D
	note("a RoomExit to the map scene counts as finishing that room", gs().map_completed.has("yard"), str(gs().map_completed))
	await wait_reveal()
	note("... and the reveal walks on to the stacks", map.get("at_node") == "stacks", String(map.get("at_node")))


# ---- movement only ------------------------------------------------------------------------------------------

func check_movement_only() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/world_map.gd") + FileAccess.get_file_as_string("res://scripts/ui/map_marker.gd")
	var banned := ["ui_accept", "ui_select", "ui_cancel", "InputEventMouse", "mouse_entered", "gui_input", "pressed.connect", "func _unhandled_input(", "func _input("]
	var found: Array = banned.filter(func(b): return src.contains(b))
	note("map scripts read only movement actions", found.is_empty(), str(found))
	var stoppers: Array = []
	for c in map.find_children("*", "Control", true, false):
		if (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			stoppers.append(c.name)
	note("no clickable controls on the map", stoppers.is_empty(), str(stoppers))
	# A click and Enter do nothing.
	_chosen.clear()
	var at: String = map.get("at_node")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(320, 300)
	Input.parse_input_event(click)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	await ticks(20)
	enter.pressed = false
	Input.parse_input_event(enter)
	click.pressed = false
	Input.parse_input_event(click)
	await ticks(5)
	note("a mouse click and the Enter key do nothing", _chosen.is_empty() and map.get("at_node") == at)
	release_all()
