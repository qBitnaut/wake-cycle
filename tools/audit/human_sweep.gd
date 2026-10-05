## The human-margin sweep: how wide is the range of ordinary inputs that makes a
## required hop work? A scripted best-case proves a jump is POSSIBLE; this proves
## it is FAIR. Shared by tools/audit/margins.gd (every room) and the room audits.
##
## A spot is a Dictionary:
##   name      label
##   sx, sy    where the cat starts (floor, with a run-up before the hop)
##   d         run direction (1 or -1)
##   edge      x of the wall face (kind "wall") or of the take-off lip (kind "gap")
##   kind      "wall" (a climb: take-off before a face) or "gap" (a long jump)
##   tx0, tx1  the landing box x range; ty its surface y (standing, +-6 px)
##   offsets   optional: take-off offsets to sweep instead of the defaults (a short tread)
##   moves     [[power, style, intended]] power 0 plain, 1 Surge, 2 Spring;
##             style "single" or "double"; intended true -> must land in at least
##             MIN_RATE of the sweep, false -> must land in none of it, null ->
##             measured and printed, never asserted
##
## The sweep (the "realistic window"), run with the real Cat, real physics:
##   take-off position  wall: 12..66 px before the face (a run at the wall, the jump
##                      called anywhere in the last two body lengths);
##                      gap: from 28 px before the lip to 8 px past it (the cat's
##                      body still overlaps the lip, and coyote time)
##   double jump press  0.32..0.77 s after the first press, every 3 frames: from just
##                      before the apex of the first jump (about 0.35 s) through the apex
##                      to the late fall. A press earlier than that throws the first
##                      jump away (it fails every gap and wall, with every power): a
##                      player who double taps that fast is not what the rooms are sized for
##   hold of a single   release at 0.9, 1.0, 1.2, 1.6 and "never" times the jump's
##                      own apex time (a player who means to jump high holds it
##                      through the rise)
## Direction is held the whole time, as a player holding the stick toward the goal.
extends RefCounted

const MIN_RATE := 0.90

const WALL_OFFSETS := [12.0, 18.0, 24.0, 30.0, 36.0, 42.0, 48.0, 54.0, 60.0, 66.0]
const GAP_OFFSETS := [-8.0, -4.0, 0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 28.0]   ## px before the lip
const DJ_FRAMES := [19, 22, 25, 28, 31, 34, 37, 40, 43, 46]
const HOLD_APEX := [0.9, 1.0, 1.2, 1.6, 99.0]

var tree: SceneTree
var room: Node
var cat: CharacterBody2D
var trials := 0


func _init(t: SceneTree, r: Node, c: CharacterBody2D) -> void:
	tree = t
	room = r
	cat = c


## Make the room bare architecture for the sweep: no pad grants a power behind the trial's
## back, nothing can hurt or kill the cat (a death reloads the scene under the sweep), no
## bot, drone or turret moves. Call once after the room has loaded.
## (No Hazard or Cat type is named here: naming a class would compile cat.gd before the
## autoloads exist when a tool loads this script.)
func prepare() -> void:
	cat.set("death_y", 1e9)
	for pad in room.find_children("*", "PowerPad", true, false):
		pad.set("_cd", 1e9)
	for n in room.find_children("*", "Node", true, false):
		var path := String(n.get_script().resource_path) if n.get_script() != null else ""
		if n.get("phase_through") != null:
			n.set("collision_mask", 0)
		elif n.is_in_group("enemy") or path.ends_with("search_drone.gd") or path.ends_with("laser_turret.gd"):
			n.process_mode = Node.PROCESS_MODE_DISABLED
			if n is Node2D:
				n.position.y -= 4000.0
	await tree.physics_frame


func _gs() -> Node:
	return tree.root.get_node("GameState")


func _hold(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _dir(d: float) -> void:
	_hold("move_right", d > 0.0)
	_hold("move_left", d < 0.0)


func _stop() -> void:
	_dir(0.0)
	_hold("jump", false)
	_hold("move_down", false)


func _ticks(n: int) -> void:
	for i in n:
		await tree.physics_frame


func _apex_frames(power: int) -> float:
	var v: float = cat.jump_velocity * (cat.spring_mult if power == 2 else 1.0)
	var g: float = cat.gravity
	return v / g * 60.0


## One trial. dj < 0: a single jump released after `hold` frames (< 0: never).
## dj >= 0: a double jump pressed on frame dj (the jump held until just before it).
func trial(spot: Dictionary, power: int, jump_x: float, dj: int, hold: int) -> bool:
	trials += 1
	var d: float = spot["d"]
	cat.global_position = Vector2(spot["sx"], spot["sy"])
	cat.velocity = Vector2.ZERO
	if power == 0:
		_gs().clear_power()
	else:
		_gs().grant_power(power, 999.0)
	_stop()
	await _ticks(4)
	var n := 0
	while (cat.global_position.x - jump_x) * d < 0.0 and n < 900:
		_dir(d)
		await _ticks(1)
		n += 1
	_hold("jump", true)
	var f := 0
	var y0 := cat.global_position.y
	while f < 240:
		_dir(d)
		await _ticks(1)
		f += 1
		if dj >= 0:
			if f == dj:
				_hold("jump", false)
			elif f == dj + 1:
				_hold("jump", true)
			elif f == dj + 40:
				_hold("jump", false)
		elif hold >= 0 and f == hold:
			_hold("jump", false)
		if f > 6 and cat.is_on_floor() and cat.velocity.y >= 0.0:
			break
		if cat.global_position.y > y0 + 700.0:
			break
	var ok: bool = cat.is_on_floor() and cat.global_position.x >= spot["tx0"] and cat.global_position.x <= spot["tx1"] and absf(cat.global_position.y - spot["ty"]) < 6.0
	_stop()
	await _ticks(2)
	return ok


## Success rate of one (power, style) over the whole sweep. `want` lets the audit stop
## as soon as the verdict is certain: "min" (an intended move: stop once more than 10%
## of the sweep has failed), "none" (a blocked move: stop at the first landing), or
## "full" (run everything: the before/after reports). A stopped run has hits/total of
## the trials run so far.
func rate(spot: Dictionary, power: int, style: String, want := "full") -> Dictionary:
	var offs: Array = spot.get("offsets", WALL_OFFSETS if spot["kind"] == "wall" else GAP_OFFSETS)
	var hits := 0
	var total := 0
	var planned: int = offs.size() * (DJ_FRAMES.size() if style == "double" else HOLD_APEX.size())
	var allowed_misses := int(floor(planned * (1.0 - MIN_RATE)))
	for o in offs:
		var jx: float = spot["edge"] - spot["d"] * o
		if style == "double":
			for dj in DJ_FRAMES:
				total += 1
				if await trial(spot, power, jx, dj, -1):
					hits += 1
				if (want == "none" and hits > 0) or (want == "min" and total - hits > allowed_misses):
					return _result(hits, total, true)
		else:
			var apex := _apex_frames(power)
			for h in HOLD_APEX:
				total += 1
				var hold_f := -1 if h > 50.0 else int(round(apex * h))
				if await trial(spot, power, jx, -1, hold_f):
					hits += 1
				if (want == "none" and hits > 0) or (want == "min" and total - hits > allowed_misses):
					return _result(hits, total, true)
	return _result(hits, total, false)


func _result(hits: int, total: int, stopped: bool) -> Dictionary:
	return {"hits": hits, "total": total, "stopped": stopped, "rate": float(hits) / float(maxi(total, 1))}


static func power_name(p: int) -> String:
	return ["plain", "Surge", "Spring"][p]


## Run every move of every spot. `note` is Callable(name: String, ok: bool, detail: String).
## Returns {spot name: {"plain single": rate, ...}} for reports.
func run(spots: Array, note: Callable, label := "", full := false) -> Dictionary:
	var report := {}
	for spot in spots:
		var rates := {}
		var bad_intended := []
		var bad_blocked := []
		var parts := []
		for m in spot["moves"]:
			var want := "full" if full else ("min" if m[2] == true else "none" if m[2] == false else "skip")
			if want == "skip":
				continue
			var r: Dictionary = await rate(spot, m[0], m[1], want)
			var key := "%s %s" % [power_name(m[0]), m[1]]
			rates[key] = r["rate"]
			parts.append("%s %s %d/%d%s" % [key, "ok" if m[2] == true else "blocked" if m[2] == false else "info", r["hits"], r["total"], "+" if r.get("stopped", false) else ""])
			if m[2] == true and r["rate"] < MIN_RATE:
				bad_intended.append("%s %.0f%%" % [key, r["rate"] * 100.0])
			if m[2] == false and r["hits"] > 0:
				bad_blocked.append("%s %.0f%%" % [key, r["rate"] * 100.0])
		report[spot["name"]] = rates
		var intended: Array = spot["moves"].filter(func(m): return m[2] == true)
		if not intended.is_empty():
			note.call("%sSWEEP %s: intended move lands in >= %d%% of human inputs" % [label, spot["name"], int(MIN_RATE * 100.0)],
				bad_intended.is_empty(), "; ".join(parts))
		note.call("%sSWEEP %s: the unintended ways land in 0%%" % [label, spot["name"]],
			bad_blocked.is_empty(), ("; ".join(parts) if intended.is_empty() else "none") if bad_blocked.is_empty() else ", ".join(bad_blocked))
	return report


## A throwaway copy of `room_id` ("room1".."room4", "test_room") swept with the spots of
## tools/audit/spots.gd; `note` is Callable(name, ok, detail). The room audits call this
## first (before their own run, which loads its own room), tools/audit/margins.gd calls it
## for every room. `only` filters spots by name (a substring), `full` runs every trial.
## Leaves no scene behind; resets GameState (the audit's own setup follows).
static func lab(host: Object, room_id: String, note: Callable, label := "", full := false, only := "") -> Dictionary:
	# `host` is the audit (a SceneTree, or a Node when full_game.gd runs the routine as a node).
	var tree: SceneTree = host if host is SceneTree else (host as Node).get_tree()
	var Spots = load("res://tools/audit/spots.gd")
	var gs := tree.root.get_node("GameState")
	var ss := tree.root.get_node("SaveSystem")
	ss.delete_save()
	gs.new_game()
	# Awake from the first frame (Room 1 then starts as a revisit: no intro to wait out).
	if room_id != "test_room":
		gs.awaken_mind()
	ss.session_scene = ""
	ss.session_checkpoint = ""
	RoomTransition.arriving = room_id != "room1" and room_id != "test_room"   # an arrival, not a fresh game
	var room: Node = load("res://scenes/levels/%s.tscn" % room_id).instantiate()
	tree.root.add_child(room)
	tree.current_scene = room
	for i in 6:
		await tree.physics_frame
	var c: CharacterBody2D = room.get_node("Cat")
	# Tuning comparisons: SPRING_MULT=1.28 SPRING_AIR=1.28 reproduces the old Spring.
	if OS.get_environment("SPRING_MULT") != "":
		c.set("spring_mult", float(OS.get_environment("SPRING_MULT")))
	if OS.get_environment("SPRING_AIR") != "":
		c.set("spring_air_mult", float(OS.get_environment("SPRING_AIR")))
	var sweep = new(tree, room, c)
	await sweep.prepare()
	var spots: Array = Spots.for_room(room_id)
	if only != "":
		spots = spots.filter(func(sp): return String(sp["name"]).contains(only))
	var report: Dictionary = await sweep.run(spots, note, label, full)
	room.queue_free()
	tree.current_scene = null
	await tree.physics_frame
	await tree.physics_frame
	ss.delete_save()
	gs.new_game()
	# The sweep walks over checkpoints: forget them, or the next room spawns at one.
	ss.session_scene = ""
	ss.session_checkpoint = ""
	ss.session_snapshot = {}
	tree.root.get_node("Monologue").reset()
	RoomTransition.arriving = false
	# Room 1 remembers that its intro was skipped (a static): the audit's own run needs it again.
	load("res://scripts/systems/room1.gd").set("intro_done", false)
	return report
