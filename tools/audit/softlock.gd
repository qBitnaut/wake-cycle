## The soft-lock detector: can the cat ever be left somewhere it cannot leave?
##
## USAGE (from the project root)
##   godot --headless --path . --script res://tools/audit/softlock.gd
##       every room (room1 room2 room3 room4 home test_room); about a minute. Exit code 1 and a
##       line per soft-lock when a room has one. full_game.gd runs the same check (SOFTLOCK=0 skips).
##   ROOMS=room3,room4   a subset (any scene in scenes/levels/ by its file name, so a scratch
##                       copy of a redesign works too)
##   MAP=1        print the room as text: # solid, = one-way, o somewhere the cat can stand, X a soft-lock
##   VALIDATE=1   drop the cat into every flagged region in the REAL scene with the real physics and
##                search plain inputs for a way out; each region is reported CONFIRMED or ESCAPED.
##                Needs --fixed-fps 60 (headless physics frames are otherwise real time):
##                godot --headless --path . --fixed-fps 60 --script res://tools/audit/softlock.gd
##   SELFTEST=1   run the detector against synthetic levels with a known answer (a pit, a pad, a hollow)
##   CALIBRATE=1  print the detector's own cat model next to tools/audit/reach.gd's numbers
##   Robustness probes (not for the audit; for a redesign you want to be generous):
##   JUMP_SCALE=0.95  weaker jumps: what it newly flags is a way out that needs the exact numbers
##   NO_COYOTE=1      no jump after leaving a ledge, for getting in as well as out
##
## WHAT IT DOES, per room, with no scene running
##  1. Reads the room's collision (the Tiles layer, static bodies, cracked floors) and its pads,
##     checkpoints, exit and killing hazards from the scene file itself.
##  2. Simulates the cat's real movement frame by frame (constants read from scenes/player/cat.tscn,
##     so a retune is picked up; CALIBRATE=1 checks it against reach.gd) and builds a graph of every
##     standing position, 4 px apart: walks, crawls, drops off a lip, and every plain jump, double
##     jump and coyote jump, with Surge (run speed), Spring (jump) and Phase (dash) variants.
##  3. Searches that graph from the player start and every checkpoint (a respawn comes back with no
##     power). A pad hands out its power for its real duration and a power move is only taken while
##     the charge lasts; Impact breaks the cracked floors it can pound. Every position the cat can
##     reach, with a power that may then run out, is "enterable".
##  4. A position is SAFE when, with NO power, the cat can still reach the exit or a checkpoint, or a
##     pad whose power then carries it on to one of those (pads chain). Everything else is a
##     soft-lock. Ways OUT are the moves a player can count on: a jump in the 0.1 s after leaving
##     a ledge (coyote time) gets the cat in but does not count as a way out. Dying is not a way
##     out either, except that a pit open to the void is not a place (the cat just respawns): a
##     region whose ONLY exit is dying (a hollow tunnel under a floor whose mouth opens onto a
##     pit) is flagged ("the only way out is dying"); falling out of the world from a spot the cat
##     can walk away from is fine.
##  4b. A static "slit" check (SLIT line per room): a one-way girder strip directly under a solid tile
##     (inside a slab) whose row is open to the side lets the cat walk into the slab. Fix: make that
##     cell solid (CROSS), as Rooms 1 and 3 do under their floors.
##  5. Each group of connected soft-lock positions is reported with its tile box, how the cat gets in
##     and its kind: POCKET (no power helps: a 1-2 tile gap under a lip or floor, an overhang, a dead
##     end) or POWER-GATED (a power would get the cat out, but no pad is reachable from there).
##
## NOT MODELLED (treated as open, so they can only hide a soft-lock, never invent one): shutters,
## locked doors, gates, laser solids, shield panels and breakable crates (all opened by the
## player's own actions), pushable crates, enemies. There are no moving platforms in this game.
##
## FOR A LEVEL REDESIGN: run it after every builder change; a clean room prints "0 soft-locks".
## A flagged region is fixed by level design: fill the pocket (make the ledge a full column), seal
## a hollow row at a pit, add stairs or a ledge the plain jump reaches, or put a pad inside. Then
## re-run margins.gd (the "needs power X" properties) and VALIDATE=1 if you doubt the model.
extends SceneTree

const T := 32
const Q := 4                    ## standing positions are this many px apart
const HW := 11.0                ## half the cat's width
const STAND_H := 26.0
const CROUCH_H := 14.0
const DT := 1.0 / 60.0
const EPS := 0.001
const MAXF := 300               ## frames of one flight
const INF_T := 1.0e9
const POUND_RADIUS := 46.0

var results: Array = []
var _cat_values := {}


func _initialize() -> void:
	_main.call_deferred()


func note(label: String, ok: bool, detail := "") -> void:
	results.append([label, ok, detail])
	print("%s  %-72s %s" % ["PASS" if ok else "FAIL", label, detail])


func cat_values() -> Dictionary:
	if _cat_values.is_empty():
		var c: Node = load("res://scenes/player/cat.tscn").instantiate()
		for k in ["run_speed", "accel", "air_accel", "air_friction", "turn_accel", "crouch_speed", "gravity", "fall_gravity_mult", "max_fall", "jump_velocity", "double_jump_velocity", "jump_cut", "surge_mult", "spring_mult", "spring_air_mult", "spring_air_boost", "spring_air_cap", "dash_speed", "dash_time"]:
			_cat_values[k] = float(c.get(k))
		c.free()
		# JUMP_SCALE=0.9: a robustness probe. A cat with weaker jumps (0.9 -> about 20% less height):
		# whatever it newly flags is a way out that works only with the jump's exact numbers.
		var sc := OS.get_environment("JUMP_SCALE")
		if sc != "":
			for k in ["jump_velocity", "double_jump_velocity"]:
				_cat_values[k] = _cat_values[k] * float(sc)
	return _cat_values


func _main() -> void:
	if OS.get_environment("CALIBRATE") == "1":
		calibrate()
		quit()
		return
	var ids := ["room1", "room2", "room3", "room4", "home", "test_room"]
	var want := OS.get_environment("ROOMS")
	if want != "":
		ids = Array(want.split(","))
	if OS.get_environment("SELFTEST") == "1":
		selftest(note)
		ids = []
	await audit(note, ids, OS.get_environment("VALIDATE") == "1", OS.get_environment("MAP") == "1")
	var ok_all := results.all(func(r): return r[1])
	print("== %d checks, %s" % [results.size(), "ALL PASS" if ok_all else "FAILURES"])
	quit(0 if ok_all else 1)


## One check per room: zero soft-locks, zero pockets. `note` is called as note(label, ok, detail).
func audit(note_cb: Callable, ids: Array, validate := false, show_map := false) -> void:
	for id in ids:
		var m := Model.new(cat_values())
		m.coyote = OS.get_environment("NO_COYOTE") != "1"
		m.load_room(id)
		var t0 := Time.get_ticks_msec()
		m.analyze()
		var groups: Array = m.groups
		var pockets := groups.filter(func(g): return g["kind"] == "POCKET").size()
		var gated := groups.size() - pockets
		note_cb.call("SOFTLOCK %s: zero soft-locks, zero pockets" % id, groups.is_empty(), "%d standing positions, %d pockets, %d power-gated, %d ms" % [m.entered_count, pockets, gated, Time.get_ticks_msec() - t0])
		note_cb.call("SLIT %s: no one-way tile inside a slab interior is exposed sideways" % id, m.slits.is_empty(), "%d cells %s" % [m.slits.size(), str(m.slits.slice(0, 6))])
		for g in groups:
			print("   %s  %s" % [id, m.describe(g)])
		if show_map:
			print(m.ascii_map())
		if validate and not groups.is_empty():
			await _validate(m, groups)


# ---------------------------------------------------------------------------------------
# Real-physics validation: drop the cat into a flagged region and try to get out.
# ---------------------------------------------------------------------------------------

func _validate(m: Model, groups: Array) -> void:
	var gs := root.get_node("GameState")
	var ss := root.get_node("SaveSystem")
	ss.delete_save()
	gs.new_game()
	if m.room_id != "test_room":
		gs.awaken_mind()
	ss.session_scene = ""
	ss.session_checkpoint = ""
	var room: Node = load("res://scenes/levels/%s.tscn" % m.room_id).instantiate()
	root.add_child(room)
	current_scene = room
	for i in 6:
		await physics_frame
	var cat: CharacterBody2D = room.get_node("Cat")
	# The sweep's own preparation: no pad hands out a power behind the trial's back, nothing
	# moves. Hazards stay live: a hazard that really kills counts as a way out.
	for pad in room.find_children("*", "PowerPad", true, false):
		pad.set("_cd", 1e9)
	for n in room.find_children("*", "Node", true, false):
		var path := String(n.get_script().resource_path) if n.get_script() != null else ""
		if n.is_in_group("enemy") or path.ends_with("search_drone.gd") or path.ends_with("laser_turret.gd") or path.ends_with("guard_drone.gd"):
			n.process_mode = Node.PROCESS_MODE_DISABLED
			if n is Node2D:
				n.position.y -= 4000.0
	# A death reloads the scene under the search: the audit watches for it instead (a fall past
	# the death line, or touching a hazard that kills) and counts it as the way out it is.
	var death_y: float = cat.get("death_y")
	cat.set("death_y", 1.0e9)
	for hz in room.find_children("*", "Hazard", true, false):
		hz.set("active", false)
	for g in groups:
		var res := await _escape_search(m, g, cat, gs, death_y)
		if res["escaped"]:
			note_validation(m, g, "ESCAPED", res["detail"])
		else:
			note_validation(m, g, "CONFIRMED", res["detail"])
	room.queue_free()
	current_scene = null
	await physics_frame
	await physics_frame
	ss.delete_save()
	gs.new_game()
	ss.session_scene = ""
	ss.session_checkpoint = ""
	ss.session_snapshot = {}


func note_validation(m: Model, g: Dictionary, verdict: String, detail: String) -> void:
	print("   VALIDATE %s %s: %s  %s" % [m.room_id, m.box_str(g), verdict, detail])
	results.append(["VALIDATE %s %s" % [m.room_id, m.box_str(g)], verdict == "CONFIRMED", verdict + " " + detail])


## Breadth-first search over landing positions, every plain input the model knows, in the
## real scene. Escaped = the cat lands outside the flagged cells, dies, or falls out.
func _escape_search(m: Model, g: Dictionary, cat: CharacterBody2D, gs: Node, death_y: float) -> Dictionary:
	var cells: Dictionary = g["cells"]            ## node key -> true
	var seeds: Array = g["seeds"]
	var seen := {}
	var queue: Array = []
	var from_idx: Array = []
	var via: Array = []
	for k in seeds:
		queue.append(m.key_pos(k))
		from_idx.append(-1)
		via.append({})
	var inputs: Array = m.validation_inputs()
	var trials := 0
	var deaths := 0
	var qi := 0
	while qi < queue.size() and qi < 400:
		var p: Vector2 = queue[qi]
		qi += 1
		for v in inputs:
			trials += 1
			var r := await _real_trial(cat, gs, p, v, death_y, m.kills)
			if r["fell"]:
				if not g["death_only"]:
					return {"escaped": true, "detail": "dies/falls out after %d trials from %s" % [trials, str(p)]}
				deaths += 1   # the only exit of a death-only region is dying: not a way out
				continue
			if r["landed"]:
				var lp: Vector2 = r["pos"]
				var lk := m.near_node(lp, cells)
				if lk == -1:
					var path := "%s -> %s" % [_input_str(v), str(lp.round())]
					var at := qi - 1
					while at >= 0 and from_idx[at] >= 0:
						path = "%s %s -> " % [str((queue[at] as Vector2).round()), _input_str(via[at])] + path
						at = from_idx[at]
					return {"escaped": true, "detail": "lands at %s outside the region after %d trials: %s" % [str(lp.round()), trials, path]}
				var sk := Vector2i(roundi(lp.x / 8.0), roundi(lp.y))
				if not seen.has(sk):
					seen[sk] = true
					queue.append(lp)
					from_idx.append(qi - 1)
					via.append(v)
	return {"escaped": false, "detail": "%d positions, %d trials, no way out%s" % [qi, trials, (" but dying (%d trials)" % deaths) if deaths > 0 else ""]}


func _input_str(v: Dictionary) -> String:
	if v.is_empty():
		return "start"
	return "[dir %d%s%s%s]" % [int(v["dir"]), (" jump hold %d" % int(v["hold"])) if v["jump"] else " walk", (" airjump@%d" % int(v["dj"])) if v["dj"] >= 0 else "", " no-steer" if v["stop_air"] else ""]


func _real_trial(cat: CharacterBody2D, gs: Node, p: Vector2, v: Dictionary, death_y: float, kills: Array) -> Dictionary:
	cat.global_position = p
	cat.velocity = Vector2.ZERO
	gs.clear_power()
	Input.action_release("jump")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_down")
	await physics_frame
	await physics_frame
	var d: float = v["dir"]
	var left_floor := false
	var out := {"landed": false, "fell": false, "pos": p}
	for f in 200:
		var jump_on := false
		if v["jump"]:
			jump_on = f < int(v["hold"]) or (v["dj"] >= 0 and f >= int(v["dj"]) and f < int(v["dj"]) + 20)
			if v["dj"] >= 0 and f == int(v["dj"]) - 1:
				jump_on = false
		var air_d: float = d if (not v["stop_air"] or not left_floor) else 0.0
		if air_d > 0.0:
			Input.action_press("move_right")
			Input.action_release("move_left")
		elif air_d < 0.0:
			Input.action_press("move_left")
			Input.action_release("move_right")
		else:
			Input.action_release("move_left")
			Input.action_release("move_right")
		if jump_on:
			Input.action_press("jump")
		else:
			Input.action_release("jump")
		await physics_frame
		if cat.global_position.y > death_y:
			out["fell"] = true
			break
		var box := Rect2(cat.global_position.x - 11.0, cat.global_position.y - 26.0, 22.0, 26.0)
		for kr in kills:
			if box.intersects(kr):
				out["fell"] = true
		if out["fell"]:
			break
		if not cat.is_on_floor():
			left_floor = true
		elif left_floor or f > 40:
			out["landed"] = true
			out["pos"] = cat.global_position
			break
	Input.action_release("jump")
	Input.action_release("move_left")
	Input.action_release("move_right")
	return out


## The detector against levels with a known answer: a pit too deep for the cat is a soft-lock
## unless a pad stands inside it (a pad outside does not help); a hollow under the floor at a
## pit is a pocket unless it is plated. Run by full_game.gd before the rooms.
func selftest(note_cb: Callable) -> void:
	var cases := [
		["a 3-tile pit is climbable", 3, false, false, 0, 0],
		["a 6-tile pit with nothing in it is a soft-lock (needs Spring)", 6, false, false, 0, 1],
		["a Spring pad before the 6-tile pit does not save the cat inside", 6, false, true, 0, 1],
		["a Spring pad inside the 6-tile pit does", 6, true, false, 0, 0],
		["a hollow under the floor at an open pit is a pocket", 0, false, false, 1, 2],
		["the same hollow plated at the pit is not", 0, false, false, 2, 0],
		["a solid floor under a pit has no pocket", 0, false, false, 0, 0],
	]
	for c in cases:
		var m := Model.new(cat_values())
		m.make_test_world(c[1], c[2], c[3], c[4])
		m.analyze()
		note_cb.call("SOFTLOCK selftest: %s" % c[0], m.groups.size() == c[5], "%d regions, want %d" % [m.groups.size(), c[5]])
	# The slit check: a girder row under the floor open at the pit is a slit, plated at its ends it is not.
	for c in [["an exposed one-way row inside the floor slab is a slit", 1, true], ["the same row sealed by solid at both ends is not", 2, false], ["a solid slab has no slit", 0, false]]:
		var m := Model.new(cat_values())
		m.make_test_world(0, false, false, c[1])
		note_cb.call("SLIT selftest: %s" % c[0], m.slits.is_empty() != c[2], "%d cells" % m.slits.size())


func calibrate() -> void:
	var m := Model.new(cat_values())
	m.make_flat_world()
	m.probe_y = m.flat_y
	print("== detector cat model on a flat world (reach.gd measures: none 122/223 px, height 95.2/171.0;")
	print("   surge 182/334; spring 193/297, height 211.7/315.6)")
	for cls in [0, 1, 2]:
		var name: String = ["none", "surge", "spring"][cls]
		var single := 0.0
		var dbl := 0.0
		for dj in [-1, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56]:
			m.fly(m.flat_edge + 8.0, m.flat_y, m.speed(cls), 1, true, 0, 99, dj, -1, cls)
			if m.fr_kind == 0:
				var travel: float = m.fr_x - (m.flat_edge + 8.0)
				if dj < 0:
					single = maxf(single, travel)
				else:
					dbl = maxf(dbl, travel)
		print("%-7s single %.0f px   double %.0f px" % [name, single, dbl])
	for cls in [0, 2]:
		var name: String = ["none", "", "spring"][cls]
		var hs := 0.0
		var hd := 0.0
		for dj in [-1, 10, 14, 18, 22, 26, 30, 34, 38, 42, 46]:
			var h := m.apex_height(0.0, cls, dj)
			if dj < 0:
				hs = h
			else:
				hd = maxf(hd, h)
		print("%-7s height single %.1f px   double %.1f px" % [name, hs, hd])


# ---------------------------------------------------------------------------------------
# The model
# ---------------------------------------------------------------------------------------

class Model extends RefCounted:
	var C: Dictionary
	var room_id := ""
	# tuning (px, seconds), from the cat
	var run_speed: float
	var accel: float
	var air_accel: float
	var air_friction: float
	var turn_accel: float
	var crouch_speed: float
	var gravity: float
	var fall_mult: float
	var max_fall: float
	var jump_v: float
	var djump_v: float
	var jump_cut: float
	var surge_mult: float
	var spring_mult: float
	var spring_air: float
	var spring_boost: float
	var spring_cap: float
	var dash_speed: float
	var dash_frames: int

	# world
	var gx0 := 0
	var gy0 := 0
	var gw := 0
	var gh := 0
	var grid := PackedByteArray()          ## 0 empty, 1 solid, 2 one-way (top), 3 one-way (top + 4)
	var base_grid := PackedByteArray()
	var rects: Array = []                  ## solid Rect2
	var cracked := {}                      ## Vector2i cell -> true (ground-pound floors)
	var broken := {}
	var pads: Array = []                   ## {rect, power, dur}
	var checkpoints: Array = []
	var exits: Array = []
	var kills: Array = []
	var starts: Array = []                 ## Vector2 feet positions the cat can begin at
	var death_y := 1.0e9
	var tiles_text := {}

	# flight result
	var fr_kind := 2                       ## 0 landed, 1 fell out of the world, 2 never landed
	var fr_x := 0.0
	var fr_y := 0.0
	var fr_f := 0

	# graph
	var _edges := {}                       ## ekey -> [PackedInt32Array targets, PackedFloat32Array costs]
	var _flags := {}                       ## node key -> bit mask
	var _pads_at := {}                     ## node key -> Array of pad indices
	var pending_breaks := {}
	var entered := {}                      ## node key -> true (reached in any state)
	var entered_count := 0
	var groups: Array = []
	var slits: Array = []                  ## Vector2i cells: a girder-strip tile in a slab interior with an exposed side
	var parent := {}                       ## state key -> state key it was reached from
	var flat_edge := 600.0
	var flat_y := 400.0
	var coyote := true                     ## coyote jumps (NO_COYOTE=1 probes without them)
	var probe_y := INF                     ## calibration: report the x where the feet cross this y falling

	const F_EXIT := 1
	const F_CHECK := 2
	const F_KILL := 4

	func _init(c: Dictionary) -> void:
		C = c
		run_speed = c["run_speed"]
		accel = c["accel"]
		air_accel = c["air_accel"]
		air_friction = c["air_friction"]
		turn_accel = c["turn_accel"]
		crouch_speed = c["crouch_speed"]
		gravity = c["gravity"]
		fall_mult = c["fall_gravity_mult"]
		max_fall = c["max_fall"]
		jump_v = c["jump_velocity"]
		djump_v = c["double_jump_velocity"]
		jump_cut = c["jump_cut"]
		surge_mult = c["surge_mult"]
		spring_mult = c["spring_mult"]
		spring_air = c["spring_air_mult"]
		spring_boost = c["spring_air_boost"]
		spring_cap = c["spring_air_cap"]
		dash_speed = c["dash_speed"]
		dash_frames = ceili(c["dash_time"] * 60.0)

	func speed(cls: int) -> float:
		return run_speed * (surge_mult if cls == 1 else 1.0)

	# ---- world construction ---------------------------------------------------------

	func _set_bounds(cx0: int, cy0: int, cx1: int, cy1: int) -> void:
		gx0 = cx0
		gy0 = cy0
		gw = cx1 - cx0
		gh = cy1 - cy0
		grid = PackedByteArray()
		grid.resize(gw * gh)

	func make_flat_world() -> void:
		_set_bounds(-4, 0, 90, 20)
		for cx in range(-4, 19):
			for cy in range(12, 20):
				grid[(cy - gy0) * gw + (cx - gx0)] = 1
		flat_edge = 19.0 * T
		flat_y = 12.0 * T
		death_y = 100000.0

	## A synthetic level for self-tests: a floor with a pit (cols 20-23), the player at the left,
	## the exit at the right. deep: tiles of pit above its floor (a solid bottom, 0 = open to the
	## void); pad_inside / pad_outside: a Spring pad in the pit / before it; hollow: the truss row
	## under the floor is a one-way slab (1), a slab with plated ends at the pit (2), or solid (0).
	func make_test_world(deep: int, pad_inside: bool, pad_outside: bool, hollow := 0) -> void:
		_set_bounds(-2, 0, 60, 30)
		death_y = 600.0
		var pit_w := 4 if deep > 0 else 5
		for cx in range(-2, 60):
			var in_pit := cx >= 20 and cx < 20 + pit_w
			for cy in range(10, 30):
				var v := 1
				if in_pit and (deep == 0 or cy < 10 + deep):
					v = 0
				elif cy == 11 and hollow > 0 and not in_pit:
					v = 3
					if hollow == 2 and (cx == 19 or cx == 20 + pit_w):
						v = 1
				elif cy > 10 and deep == 0 and cy > 12 and not in_pit:
					v = 1
				_set_cell(cx, cy, v)
		starts.append(Vector2(3 * T + 16, 10 * T))
		exits.append(Rect2(55 * T, 10 * T - 96, 24, 96))
		if pad_outside:
			pads.append({"rect": Rect2(10 * T, 10 * T - 10, 44, 10), "power": 2, "dur": 10.0})
		if pad_inside:
			pads.append({"rect": Rect2(21 * T, (10 + deep) * T - 10, 44, 10), "power": 2, "dur": 10.0})
		find_slits()

	func load_room(id: String) -> void:
		room_id = id
		var scene: Node = load("res://scenes/levels/%s.tscn" % id).instantiate()
		var lim: Rect2i = scene.get("limits")
		death_y = float(lim.end.y + int(scene.get("death_margin")))
		var layer := scene.get_node_or_null("Tiles") as TileMapLayer
		var used := Rect2i(0, 0, 1, 1)
		if layer != null:
			used = layer.get_used_rect()
		var lx := floori(float(lim.position.x) / T)
		var rx := ceili(float(lim.end.x) / T)
		_set_bounds(mini(used.position.x, lx) - 1, mini(used.position.y, 0) - 1, maxi(used.end.x, rx) + 1, maxi(used.end.y, ceili(death_y / T)) + 1)
		if layer != null:
			for c in layer.get_used_cells():
				var td := layer.get_cell_tile_data(c)
				if td == null or td.get_collision_polygons_count(0) == 0:
					continue
				var pts := td.get_collision_polygon_points(0, 0)
				var v := 1
				if td.is_collision_polygon_one_way(0, 0):
					v = 3 if pts[0].y > -15.0 else 2
				grid[(c.y - gy0) * gw + (c.x - gx0)] = v
		_walk(scene, Vector2.ZERO)
		base_grid = grid.duplicate()
		find_slits()
		var start_node := scene.get_node_or_null("PlayerStart")
		if start_node != null:
			starts.append(start_node.position)
		for cp in checkpoints:
			var r: Rect2 = cp
			starts.append(Vector2(r.position.x + r.size.x * 0.5, r.end.y))
		scene.free()

	func _shape_rect(body: Node, offset: Vector2) -> Rect2:
		for k in body.get_children():
			if k is CollisionShape2D and k.shape is RectangleShape2D:
				var s: Vector2 = k.shape.size
				var p: Vector2 = offset + (body as Node2D).position + k.position
				return Rect2(p - s * 0.5, s)
		return Rect2()

	func _walk(n: Node, offset: Vector2) -> void:
		for c in n.get_children():
			if not c is Node2D:
				continue
			var sp := String(c.get_script().resource_path.get_file()) if c.get_script() != null else ""
			var pos: Vector2 = offset + (c as Node2D).position
			if sp == "pad.gd":
				var pw := int(c.get("power"))
				if pw >= 1 and pw <= 4:
					pads.append({"rect": _shape_rect(c, offset), "power": pw, "dur": float(c.get("duration"))})
			elif sp == "checkpoint.gd":
				checkpoints.append(_shape_rect(c, offset))
			elif c is Area2D and String(c.name) == "SpotTrigger":
				exits.append(_shape_rect(c, offset))   ## Home: the sunbeam where the cat falls asleep
			elif sp == "room_exit.gd":
				var s: Vector2 = c.get("size")
				exits.append(Rect2(pos + Vector2(-s.x * 0.5, -s.y), s))
			elif sp == "hazard.gd" and bool(c.get("kill")):
				kills.append(_shape_rect(c, offset))
			elif c is StaticBody2D and (c.collision_layer & 1) != 0:
				_add_body(c, sp, offset)
			if c.scene_file_path == "" and not c is TileMapLayer:
				_walk(c, pos)

	func _add_body(c: StaticBody2D, sp: String, offset: Vector2) -> void:
		if sp == "breakable.gd":
			if String(c.get("breaks_on")) == "pound":
				var r := _shape_rect(c, offset)
				var cell := Vector2i(floori(r.position.x / T + 0.5), floori(r.position.y / T + 0.5))
				cracked[cell] = true
				_set_cell(cell.x, cell.y, 1)
			return
		if sp != "":
			return   # shutter, door, gate, shield panel: opened by the player's own actions
		for k in c.get_children():
			if k is CollisionShape2D and k.shape is RectangleShape2D:
				var s: Vector2 = k.shape.size
				var p: Vector2 = offset + c.position + k.position
				rects.append(Rect2(p - s * 0.5, s))
			elif k is CollisionPolygon2D:
				_poly_rects(k.polygon, offset + c.position + k.position)

	## A solid polygon as rectangles: vertical slices 4 px wide, merged while the top stays level.
	func _poly_rects(poly: PackedVector2Array, off: Vector2) -> void:
		var x0 := INF
		var x1 := -INF
		var y1 := -INF
		var sy := INF
		for p in poly:
			x0 = minf(x0, p.x)
			x1 = maxf(x1, p.x)
			y1 = maxf(y1, p.y)
			sy = minf(sy, p.y)
		var cur_top := NAN
		var cur_x := x0
		var x := x0
		while x < x1:
			var top := NAN
			var y := sy
			while y <= y1:
				if Geometry2D.is_point_in_polygon(Vector2(x + 2.0, y + 0.5), poly):
					top = y
					break
				y += 1.0
			if not is_equal_approx(top, cur_top) and not (is_nan(top) and is_nan(cur_top)):
				if not is_nan(cur_top):
					rects.append(Rect2(Vector2(cur_x, cur_top) + off, Vector2(x - cur_x, y1 - cur_top)))
				cur_top = top
				cur_x = x
			x += 4.0
		if not is_nan(cur_top):
			rects.append(Rect2(Vector2(cur_x, cur_top) + off, Vector2(x1 - cur_x, y1 - cur_top)))

	func _set_cell(cx: int, cy: int, v: int) -> void:
		if cx >= gx0 and cx < gx0 + gw and cy >= gy0 and cy < gy0 + gh:
			grid[(cy - gy0) * gw + (cx - gx0)] = v

	## The "slit" check: a one-way girder strip (value 3) directly under a solid tile is inside a slab,
	## not on a face; if its row is open to the side (air, or a plain walkable girder) the cat can enter
	## that thin gap sideways and be hidden or stuck in the floor. A run of such cells sealed at both
	## ends by solid is a hollow the cat can not enter and is fine.
	func find_slits() -> void:
		slits = []
		for cy in range(gy0, gy0 + gh):
			for cx in range(gx0, gx0 + gw):
				if not _is_slit_cell(cx, cy):
					continue
				for dx in [-1, 1]:
					var n := cell(cx + dx, cy)
					if n != 1 and not _is_slit_cell(cx + dx, cy):
						slits.append(Vector2i(cx, cy))
						break

	func _is_slit_cell(cx: int, cy: int) -> bool:
		return cell(cx, cy) == 3 and cell(cx, cy - 1) == 1

	func cell(cx: int, cy: int) -> int:
		if cx < gx0 or cx >= gx0 + gw:
			return 1
		if cy < gy0 or cy >= gy0 + gh:
			return 0
		return grid[(cy - gy0) * gw + (cx - gx0)]

	# ---- collision queries ----------------------------------------------------------

	func blocked(l: float, t: float, r: float, b: float) -> bool:
		var c0 := floori((l + EPS) / T)
		var c1 := floori((r - EPS) / T)
		var r0 := floori((t + EPS) / T)
		var r1 := floori((b - EPS) / T)
		for cy in range(r0, r1 + 1):
			for cx in range(c0, c1 + 1):
				if cell(cx, cy) == 1:
					return true
		for rc in rects:
			if rc.position.x < r - EPS and rc.end.x > l + EPS and rc.position.y < b - EPS and rc.end.y > t + EPS:
				return true
		return false

	func crouch_ok(x: float, y: float) -> bool:
		return not blocked(x - HW, y - CROUCH_H, x + HW, y)

	func stand_ok(x: float, y: float) -> bool:
		return not blocked(x - HW, y - STAND_H, x + HW, y)

	func supported(x: float, y: float) -> bool:
		var c0 := floori((x - HW + EPS) / T)
		var c1 := floori((x + HW - EPS) / T)
		var yi := roundi(y)
		if posmod(yi, T) == 0:
			var row := yi / T
			for cx in range(c0, c1 + 1):
				var v := cell(cx, row)
				if v == 1 or v == 2:
					return true
		elif posmod(yi - 4, T) == 0:
			var row2 := (yi - 4) / T
			for cx in range(c0, c1 + 1):
				if cell(cx, row2) == 3:
					return true
		for rc in rects:
			if absf(rc.position.y - y) < 0.01 and rc.position.x < x + HW - EPS and rc.end.x > x - HW + EPS:
				return true
		return false

	## Moving right (nx > x) or left: where the box stops. Returns nx unchanged if free.
	func move_x(x: float, nx: float, y: float) -> float:
		var top := y - STAND_H
		var r0 := floori((top + EPS) / T)
		var r1 := floori((y - EPS) / T)
		if nx > x:
			var pr := x + HW
			var nr := nx + HW
			var best := INF
			var cx := ceili((pr - EPS) / T)
			var cx_end := floori((nr - EPS) / T)
			while cx <= cx_end and best == INF:
				for cy in range(r0, r1 + 1):
					if cell(cx, cy) == 1:
						best = cx * T
						break
				cx += 1
			for rc in rects:
				if rc.position.x >= pr - EPS and rc.position.x < nr - EPS and rc.position.y < y - EPS and rc.end.y > top + EPS:
					best = minf(best, rc.position.x)
			if best < INF:
				return best - HW
		elif nx < x:
			var pl := x - HW
			var nl := nx - HW
			var best2 := -INF
			var cx2 := floori((pl + EPS) / T) - 1
			var cx_lo := floori((nl + EPS) / T)
			while cx2 >= cx_lo and best2 == -INF:
				for cy in range(r0, r1 + 1):
					if cell(cx2, cy) == 1:
						best2 = (cx2 + 1) * T
						break
				cx2 -= 1
			for rc in rects:
				if rc.end.x <= pl + EPS and rc.end.x > nl + EPS and rc.position.y < y - EPS and rc.end.y > top + EPS:
					best2 = maxf(best2, rc.end.x)
			if best2 > -INF:
				return best2 + HW
		return nx

	## Falling from y to ny (ny > y): the top face the feet meet first, or INF.
	func land_y(x: float, y: float, ny: float) -> float:
		var c0 := floori((x - HW + EPS) / T)
		var c1 := floori((x + HW - EPS) / T)
		var best := INF
		var rr := floori((y - 0.01 - 4.0) / T)
		var rr_end := floori((ny + EPS) / T)
		while rr <= rr_end and best == INF:
			for cx in range(c0, c1 + 1):
				var v := cell(cx, rr)
				var tp := -INF
				if v == 1 or v == 2:
					tp = rr * T
				elif v == 3:
					tp = rr * T + 4.0
				if tp >= y - 0.01 and tp <= ny + 1.0e-6:
					best = minf(best, tp)
			rr += 1
		for rc in rects:
			if rc.position.y >= y - 0.01 and rc.position.y <= ny + 1.0e-6 and rc.position.x < x + HW - EPS and rc.end.x > x - HW + EPS:
				best = minf(best, rc.position.y)
		return best

	## Rising from y to ny (ny < y): the ceiling the head meets first, as a feet y, or -INF.
	func ceil_y(x: float, y: float, ny: float) -> float:
		var c0 := floori((x - HW + EPS) / T)
		var c1 := floori((x + HW - EPS) / T)
		var ph := y - STAND_H
		var nh := ny - STAND_H
		var best := -INF
		var rr := floori((ph + EPS) / T)
		var rr_lo := floori((nh + EPS) / T) - 1
		while rr >= rr_lo and best == -INF:
			for cx in range(c0, c1 + 1):
				if cell(cx, rr) == 1:
					var bt := (rr + 1) * T
					if bt <= ph + EPS and bt >= nh + EPS:
						best = maxf(best, bt + STAND_H)
			rr -= 1
		for rc in rects:
			if rc.end.y <= ph + EPS and rc.end.y >= nh + EPS and rc.position.x < x + HW - EPS and rc.end.x > x - HW + EPS:
				best = maxf(best, rc.end.y + STAND_H)
		return best

	# ---- the flight simulation ------------------------------------------------------

	## One flight from feet (x, y). vx: starting horizontal speed. air: held direction in the
	## air (-1, 0, 1). jump: press jump on frame jd (a fall when false). cut: release the jump
	## that many frames after takeoff (a short hop; 99 never; ignored with Spring). dj: air jump
	## that many frames after takeoff (-1 never). dash_f: Phase dash on that frame (-1 never).
	## Result in fr_kind / fr_x / fr_y / fr_f.
	func fly(x0: float, y0: float, vx0: float, air: int, jump: bool, jd: int, cut: int, dj: int, dash_f: int, cls: int) -> void:
		var x := x0
		var y := y0
		var vx := vx0
		var vy := 0.0
		var air_jumps := 1
		var dash_left := 0
		var dash_dir := 0.0
		var sp := speed(cls)
		var jv := jump_v * (spring_mult if cls == 2 else 1.0)
		var cutf := (jd + cut) if (jump and cut >= 0 and cls != 2) else -1
		var djf := (jd + dj) if dj >= 0 else -1
		fr_kind = 2
		for f in range(MAXF):
			if jump and f == jd:
				vy = -jv
			if f == cutf and vy < 0.0:
				vy *= jump_cut
			if f == djf and air_jumps > 0 and f > 0:
				if cls == 2:
					var rising := maxf(-vy, 0.0)
					var base := djump_v * spring_air
					vy = -clampf(rising + base * spring_boost, base, maxf(spring_cap, base))
				else:
					vy = -djump_v
				air_jumps -= 1
			if f == dash_f and cls == 3:
				dash_left = dash_frames
				dash_dir = float(air) if air != 0 else (signf(vx) if vx != 0.0 else 1.0)
			if dash_left > 0:
				vx = dash_dir * dash_speed
				vy = 0.0
				dash_left -= 1
			else:
				var target := air * sp
				var a := air_friction
				if air != 0:
					a = air_accel
					if signf(float(air)) != signf(vx) and absf(vx) > 5.0:
						a = turn_accel
				vx = move_toward(vx, target, a * DT)
				var g := gravity * (fall_mult if vy > 0.0 else 1.0)
				vy = minf(vy + g * DT, max_fall)
			var nx := x + vx * DT
			var sx := move_x(x, nx, y)
			if sx != nx:
				vx = 0.0
			x = sx
			var ny := y + vy * DT
			if vy > 0.0:
				if y < probe_y and ny >= probe_y:
					fr_kind = 0
					fr_x = x
					fr_y = probe_y
					fr_f = f + 1
					return
				var ly := land_y(x, y, ny)
				if ly < INF:
					fr_kind = 0
					fr_x = x
					fr_y = ly
					fr_f = f + 1
					return
			elif vy < 0.0:
				var cy2 := ceil_y(x, y, ny)
				if cy2 > -INF:
					ny = cy2
					vy = 0.0
			y = ny
			if y > death_y:
				fr_kind = 1
				fr_x = x
				fr_y = y
				fr_f = f + 1
				return
		fr_x = x
		fr_y = y
		fr_f = MAXF

	## Highest rise (px above the takeoff) of a jump, with an optional air jump (calibration).
	func apex_height(vx0: float, cls: int, dj: int) -> float:
		var best := 0.0
		var cur := 0.0
		var x := 100.0
		var y := flat_y
		var vy := 0.0
		var air_jumps := 1
		var jv := jump_v * (spring_mult if cls == 2 else 1.0)
		vy = -jv
		for f in range(1, 200):
			if f == dj and air_jumps > 0:
				if cls == 2:
					var base := djump_v * spring_air
					vy = -clampf(maxf(-vy, 0.0) + base * spring_boost, base, maxf(spring_cap, base))
				else:
					vy = -djump_v
				air_jumps -= 1
			vy = minf(vy + gravity * (fall_mult if vy > 0.0 else 1.0) * DT, max_fall)
			y += vy * DT
			best = maxf(best, flat_y - y)
			if y >= flat_y and vy > 0.0:
				break
		return best

	# ---- nodes and edges ------------------------------------------------------------

	func key_of(x: float, y: float) -> int:
		return (roundi(y) + 4096) * 8192 + (roundi(x / Q) + 16)

	func key_x(k: int) -> float:
		return float((k % 8192) - 16) * Q

	func key_y(k: int) -> float:
		return float(k / 8192 - 4096)

	func key_pos(k: int) -> Vector2:
		return Vector2(key_x(k), key_y(k))

	func node_ok(x: float, y: float) -> bool:
		return crouch_ok(x, y) and supported(x, y)

	## The node a landing at (x, y) falls on: nearest valid 4 px position, or -1.
	func land_node(x: float, y: float) -> int:
		var xq := roundi(x / Q)
		var yi := roundi(y)
		for off in [0, -1, 1, -2, 2]:
			var cx := float(xq + off) * Q
			if node_ok(cx, yi):
				return key_of(cx, yi)
		return -1

	func near_node(p: Vector2, cells: Dictionary) -> int:
		var xq := roundi(p.x / Q)
		for dx in range(-3, 4):
			for dy in range(-1, 2):
				var k := key_of(float(xq + dx) * Q, p.y + dy)
				if cells.has(k):
					return k
		return -1

	func flags_of(k: int) -> int:
		if _flags.has(k):
			return _flags[k]
		var x := key_x(k)
		var y := key_y(k)
		var box := Rect2(x - HW, y - STAND_H, HW * 2.0, STAND_H)
		var f := 0
		for r in exits:
			if box.intersects(r):
				f |= F_EXIT
		for r in checkpoints:
			if box.intersects(r):
				f |= F_CHECK
		for r in kills:
			if box.intersects(r):
				f |= F_KILL
		_flags[k] = f
		return f

	func pads_at(k: int) -> Array:
		if _pads_at.has(k):
			return _pads_at[k]
		var x := key_x(k)
		var y := key_y(k)
		var box := Rect2(x - HW, y - STAND_H, HW * 2.0, STAND_H)
		var out := []
		for i in pads.size():
			if box.intersects(pads[i]["rect"]):
				out.append(i)
		_pads_at[k] = out
		return out

	## The floor height the cat walks onto at nx from feet y: level, or up/down a gentle slope
	## (a few px per step; only the home street's ramp has one). INF when it cannot walk there.
	func _walk_y(nx: float, y: float) -> float:
		for dy in [0.0, -1.0, 1.0, -2.0, 2.0, -3.0, 3.0]:
			if node_ok(nx, y + dy):
				return y + dy
		return INF

	func _add_edge(tg: PackedInt32Array, co: PackedFloat32Array, to: int, cost: float) -> void:
		for i in tg.size():
			if tg[i] == to:
				if cost < co[i]:
					co[i] = cost
				return
		tg.append(to)
		co.append(cost)

	## Record the flight's outcome as an edge. `human` false marks a move a player cannot count
	## on (a jump in the 0.1 s after leaving a ledge): it can get the cat INTO a place but is not
	## counted as a way OUT (edges() keeps the two lists apart).
	func _result_edge(e: Array, human := true) -> void:
		var to := -2
		if fr_kind == 1:
			to = -1
		elif fr_kind == 0:
			to = land_node(fr_x, fr_y)
		if to == -2 or (to == -1 and fr_kind != 1):
			return
		_add_edge(e[0], e[1], to, fr_f * DT)
		if human:
			_add_edge(e[2], e[3], to, fr_f * DT)

	## Class 0 plain, 1 Surge, 2 Spring, 3 Phase. Targets are node keys; -1 is the void.
	func edges(k: int, cls: int) -> Array:
		var ek := k * 4 + cls
		if _edges.has(ek):
			return _edges[ek]
		var tg := PackedInt32Array()
		var co := PackedFloat32Array()
		var e := [tg, co, PackedInt32Array(), PackedFloat32Array()]
		var x := key_x(k)
		var y := key_y(k)
		var sp := speed(cls)
		var stand_here := stand_ok(x, y)
		var near_edge := false
		for d in [-1, 1]:
			var nx: float = x + d * Q
			if not crouch_ok(nx, y) and _walk_y(nx, y) == INF:
				near_edge = true
				continue
			var wy := _walk_y(nx, y)
			if wy != INF:
				var slow := not stand_here or not stand_ok(nx, wy)
				_add_edge(tg, co, key_of(nx, wy), Q / (crouch_speed if slow else sp))
				_add_edge(e[2], e[3], key_of(nx, wy), Q / (crouch_speed if slow else sp))
				# Close to a lip: sample takeoffs every 4 px.
				if not supported(x + d * 16.0, y) or not crouch_ok(x + d * 16.0, y):
					near_edge = true
			else:
				near_edge = true
				# Off the lip: creep or run, steer, air jump or not, coyote jump.
				for vx0 in [d * crouch_speed, d * sp]:
					for air in [d, 0]:
						for dj in [-1, 8, 16, 26, 38]:
							fly(nx, y, vx0, air, false, 0, 99, dj, -1, cls)
							_result_edge(e)
						if cls == 3:
							for df in [0, 10, 20]:
								fly(nx, y, vx0, air, false, 0, 99, -1, df, cls)
								_result_edge(e)
					if stand_here and coyote:
						for jd in [3, 6]:
							for air in [d, 0]:
								for dj in [-1, 16, 28]:
									fly(nx, y, vx0, air, true, jd, 99, dj, -1, cls)
									_result_edge(e, false)
		if stand_here and (near_edge or posmod(roundi(x / Q), 4) == 0):
			for vx0 in [-sp, 0.0, sp]:
				var dirs := [-1, 0, 1]
				if vx0 > 0.0:
					dirs = [1, 0]
				elif vx0 < 0.0:
					dirs = [-1, 0]
				for air in dirs:
					var cuts := [99] if cls == 2 else [5, 11, 99]
					for cut in cuts:
						fly(x, y, vx0, air, true, 0, cut, -1, -1, cls)
						_result_edge(e)
					for dj in [8, 14, 20, 26, 32, 40, 50]:
						fly(x, y, vx0, air, true, 0, 99, dj, -1, cls)
						_result_edge(e)
					if cls == 3:
						for df in [0, 8, 16, 26]:
							for dj in [-1, 20]:
								fly(x, y, vx0, air, true, 0, 99, dj, df, cls)
								_result_edge(e)
		_edges[ek] = e
		return e

	# ---- search ---------------------------------------------------------------------

	func _relax(best: Dictionary, queue: Array, par: Dictionary, sk: int, t: float, from_sk: int) -> void:
		var old: float = best.get(sk, -1.0)
		if t > old + 1.0e-6:
			best[sk] = t
			queue.append(sk)
			if from_sk >= 0 and not par.has(sk):
				par[sk] = from_sk

	## All states (node * 8 + class) reachable from `starts` ([[key, cls, t]]), t = seconds of
	## power left (INF_T for none). Class 4 (Impact) moves like plain and breaks cracked floors.
	func search(start_states: Array, with_pads := true, par := {}, human := false) -> Dictionary:
		var best := {}
		var queue: Array = []
		for s in start_states:
			_relax(best, queue, par, int(s[0]) * 8 + int(s[1]), float(s[2]), -1)
		var qi := 0
		while qi < queue.size():
			var sk: int = queue[qi]
			qi += 1
			var k := sk / 8
			var cls := sk % 8
			var t: float = best[sk]
			if cls != 0 and t <= 0.0:
				continue
			if cls != 0:
				_relax(best, queue, par, k * 8, INF_T, sk)
			if with_pads:
				for pi in pads_at(k):
					var p: Dictionary = pads[pi]
					_relax(best, queue, par, k * 8 + int(p["power"]), float(p["dur"]), sk)
			if cls == 4:
				_impact_breaks(k)
			var ecls := cls if (cls >= 1 and cls <= 3) else 0
			var e: Array = edges(k, ecls)
			var tg: PackedInt32Array = e[2] if human else e[0]
			var co: PackedFloat32Array = e[3] if human else e[1]
			for i in tg.size():
				var to := tg[i]
				if to < 0:
					continue
				if cls == 0:
					_relax(best, queue, par, to * 8, INF_T, sk)
				elif co[i] <= t:
					_relax(best, queue, par, to * 8 + cls, t - co[i], sk)
		return best

	## Standing on a cracked floor with Impact: a ground pound breaks the cracked floors in reach.
	func _impact_breaks(k: int) -> void:
		var x := key_x(k)
		var y := key_y(k)
		if posmod(roundi(y), T) != 0:
			return
		var row := roundi(y) / T
		var c0 := floori((x - HW + EPS) / T)
		var c1 := floori((x + HW - EPS) / T)
		var under := false
		for cx in range(c0, c1 + 1):
			if cracked.has(Vector2i(cx, row)) and cell(cx, row) == 1:
				under = true
		if not under:
			return
		var pos := Vector2(x, y - 8.0)
		for cc in cracked:
			if cell(cc.x, cc.y) != 1:
				continue
			var ctr := Vector2(cc.x * T + 16.0, cc.y * T + 16.0)
			var d := (pos - ctr).abs() - Vector2(16.0, 16.0)
			if d.max(Vector2.ZERO).length() <= POUND_RADIUS:
				pending_breaks[cc] = true

	func reset_graph() -> void:
		_edges = {}
		_flags = {}
		_pads_at = {}

	func analyze() -> void:
		var t_start := Time.get_ticks_msec()
		groups = []
		var roots: Array = []
		var best := {}
		var guard := 0
		while true:
			guard += 1
			pending_breaks = {}
			roots = []
			parent = {}
			for s in starts:
				var p: Vector2 = s
				var n := _drop_node(p)
				if n >= 0:
					roots.append([n, 0, INF_T])
			best = search(roots, true, parent)
			if pending_breaks.is_empty() or guard > 12:
				break
			for cc in pending_breaks:
				_set_cell(cc.x, cc.y, 0)
				broken[cc] = true
			reset_graph()

		entered = {}
		for sk in best:
			entered[sk / 8] = true
		entered_count = entered.size()
		# The power search from every pad (all its nodes at once: they are within one pad's 44 px):
		# where a charge can carry the cat.
		var pad_reach := {}
		for pi in pads.size():
			var p: Dictionary = pads[pi]
			var starts_p: Array = []
			var members: Array = []
			for k in entered:
				if pads_at(k).has(pi):
					starts_p.append([k, int(p["power"]), float(p["dur"])])
					members.append(k)
			if starts_p.is_empty():
				continue
			var res := search(starts_p, true, {}, true)
			var set := {}
			for sk in res:
				set[sk / 8] = true
			for k in members:
				pad_reach[k] = set
		# Backward reachability of the goals over: plain moves + pad hops. Two readings:
		# loose (the exit, a checkpoint, a kill, or a drop out of the world all count) and strict
		# (only the exit or a checkpoint: dying is not leaving).
		var rev := {}
		var good := {}
		var good_strict := {}
		var queue: Array = []
		var queue_s: Array = []
		for k in entered:
			var fl := flags_of(k)
			var e: Array = edges(k, 0)
			var tg: PackedInt32Array = e[2]
			if (fl & (F_EXIT | F_CHECK)) != 0:
				good_strict[k] = true
				queue_s.append(k)
			if fl != 0 or tg.has(-1):
				good[k] = true
				queue.append(k)
			for to in tg:
				if to >= 0:
					if not rev.has(to):
						rev[to] = []
					rev[to].append(k)
			if pad_reach.has(k):
				for m in pad_reach[k]:
					if m != k:
						if not rev.has(m):
							rev[m] = []
						rev[m].append(k)
		_back(rev, good, queue)
		_back(rev, good_strict, queue_s)
		var bad := {}
		var bad_death := {}
		for k in entered:
			if not good.has(k):
				bad[k] = true
			elif not good_strict.has(k):
				bad_death[k] = true
		_group(bad, good, best, "")
		_group(bad_death, good_strict, best, "POCKET")

	func _back(rev: Dictionary, good: Dictionary, queue: Array) -> void:
		var qi := 0
		while qi < queue.size():
			var n: int = queue[qi]
			qi += 1
			if rev.has(n):
				for f in rev[n]:
					if not good.has(f):
						good[f] = true
						queue.append(f)

	func _drop_node(p: Vector2) -> int:
		# The cat is placed on the floor: find the node it settles on.
		for off in [0.0, -2.0, 2.0, -6.0, 6.0]:
			fly(p.x + off, p.y - 2.0, 0.0, 0, false, 0, 99, -1, -1, 0)
			if fr_kind == 0:
				return land_node(fr_x, fr_y)
		return -1

	func _group(bad: Dictionary, good: Dictionary, best: Dictionary, force_kind: String) -> void:
		# Undirected adjacency among the soft-lock positions, then flood fill.
		var adj := {}
		for k in bad:
			var e: Array = edges(k, 0)
			for to in e[2]:
				if to >= 0 and bad.has(to):
					if not adj.has(k):
						adj[k] = []
					if not adj.has(to):
						adj[to] = []
					adj[k].append(to)
					adj[to].append(k)
		var seen := {}
		var new_groups := []
		for k0 in bad:
			if seen.has(k0):
				continue
			var cells := {}
			var stack := [k0]
			seen[k0] = true
			while not stack.is_empty():
				var k: int = stack.pop_back()
				cells[k] = true
				if adj.has(k):
					for to in adj[k]:
						if not seen.has(to):
							seen[to] = true
							stack.append(to)
			groups.append({"cells": cells})
			new_groups.append(groups[-1])
		for g in new_groups:
			_fill(g, good, best)
			g["death_only"] = force_kind != ""

	func _fill(g: Dictionary, good: Dictionary, best: Dictionary) -> void:
		var cells: Dictionary = g["cells"]
		var x0 := INF
		var x1 := -INF
		var y0 := INF
		var y1 := -INF
		for k in cells:
			x0 = minf(x0, key_x(k))
			x1 = maxf(x1, key_x(k))
			y0 = minf(y0, key_y(k))
			y1 = maxf(y1, key_y(k))
		g["x0"] = x0
		g["x1"] = x1
		g["y0"] = y0
		g["y1"] = y1
		# What gets it out: unlimited Surge / Spring / Phase from inside the group.
		var needs := []
		for cls in [1, 2, 3]:
			var starts_c: Array = []
			for k in cells:
				starts_c.append([k, cls, INF_T])
			var res := search(starts_c, false, {}, true)
			var out := false
			for sk in res:
				if good.has(sk / 8) and not cells.has(sk / 8):
					out = true
					break
			if out:
				needs.append(["", "Surge", "Spring", "Phase"][cls])
		g["needs"] = needs
		g["kind"] = "POWER-GATED" if not needs.is_empty() else "POCKET"
		# How the cat gets in: the state that reached the group first, and the one before it.
		var seeds := []
		var entry := ""
		for sk in best:
			var k: int = sk / 8
			if cells.has(k):
				seeds.append(k)
				if entry == "" and parent.has(sk):
					var ps: int = parent[sk]
					if not cells.has(ps / 8):
						entry = "from (%d, %d) with %s" % [roundi(key_x(ps / 8)), roundi(key_y(ps / 8)), ["no power", "Surge", "Spring", "Phase", "Impact"][ps % 8]]
		g["entry"] = entry
		# a few seeds spread through the group for the real-physics check
		var picks := []
		var list: Array = cells.keys()
		list.sort()
		var step := maxi(1, list.size() / 6)
		for i in range(0, list.size(), step):
			picks.append(list[i])
		g["seeds"] = picks

	func box_str(g: Dictionary) -> String:
		return "cols %d-%d rows %d-%d" % [floori(g["x0"] / T), floori(g["x1"] / T), floori((g["y0"] - 1.0) / T), floori((g["y1"] - 1.0) / T)]

	func describe(g: Dictionary) -> String:
		var s: String = "%s  %s: %d positions, x %d..%d, feet y %d..%d" % [g["kind"], box_str(g), g["cells"].size(), roundi(g["x0"]), roundi(g["x1"]), roundi(g["y0"]), roundi(g["y1"])]
		if g["kind"] == "POWER-GATED":
			s += ", needs " + "/".join(g["needs"])
		if g["death_only"]:
			s += ", the only way out is dying"
		if g["entry"] != "":
			s += ", entered " + g["entry"]
		return s

	## The inputs the real-physics check tries: run direction, hold, air jump, steering.
	func validation_inputs() -> Array:
		var out := []
		for d in [-1.0, 0.0, 1.0]:
			for stop in [false, true]:
				if d == 0.0 and stop:
					continue
				out.append({"dir": d, "jump": false, "hold": 0, "dj": -1, "stop_air": stop})
				for hold in [6, 14, 40]:
					out.append({"dir": d, "jump": true, "hold": hold, "dj": -1, "stop_air": stop})
				for dj in [10, 18, 26, 36]:
					out.append({"dir": d, "jump": true, "hold": dj - 1, "dj": dj, "stop_air": stop})
		return out

	func ascii_map() -> String:
		var bad := {}
		for g in groups:
			for k in g["cells"]:
				bad[Vector2i(floori(key_x(k) / T), floori((key_y(k) - 1.0) / T))] = true
		var enter := {}
		for k in entered:
			enter[Vector2i(floori(key_x(k) / T), floori((key_y(k) - 1.0) / T))] = true
		var lines := PackedStringArray()
		for cy in range(gy0 + 1, gy0 + gh - 1):
			var line := ""
			for cx in range(gx0 + 1, gx0 + gw - 1):
				var v := cell(cx, cy)
				var ch := "."
				if bad.has(Vector2i(cx, cy)):
					ch = "X"
				elif v == 1:
					ch = "#"
				elif v >= 2:
					ch = "="
				elif enter.has(Vector2i(cx, cy)):
					ch = "o"
				line += ch
			lines.append("%4d %s" % [cy, line])
		return "\n".join(lines)
