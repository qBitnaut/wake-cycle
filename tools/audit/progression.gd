## The progression check: can the cat ever be left somewhere it can no longer finish the room?
##
## USAGE (from the project root)
##   godot --headless --path . --script res://tools/audit/progression.gd
##       every room with required objectives (CONFIG below); exit code 1 and a line per
##       stranded region when a room has one. full_game.gd runs the same check (PROGRESSION=0 skips).
##   ROOMS=room4   a subset (any scene in scenes/levels/ with a CONFIG entry of the same name, or a scratch copy of
##                 one: ROOMS=room4_main uses room4's)
##   MAP=1         print each room's stranded positions as text (X) over the room's collision
##
## WHY: tools/audit/softlock.gd proves the cat can always reach an exit or a checkpoint. That is not
## enough when the exit is gated by things the cat must go and collect: a one-way drop east of a
## missed relay is not a soft-lock to softlock.gd (a checkpoint is always reachable) but the room can
## no longer be finished. Room 4's Master Gate needs three relays; the first version let the cat pass
## Relay 3 without Relay 2 and gave it no way back west.
##
## WHAT IT DOES, per room (the movement model, pads and powers are softlock.gd's Model)
##  1. CONFIG names the room's objectives (a relay, the key) and its gates (the Master Gate, the
##     locked door), each gate with the objectives that open it.
##  2. A gate whose objectives are not all collected is SOLID (its rectangle is added to the room's
##     collision); softlock.gd treats every gate as open. Subsets of collected objectives that close
##     the same gates share one graph, so a room needs one pass per distinct set of closed gates.
##  3. The cat enters from the player start and every checkpoint (a respawn comes back there with no
##     power), except the checkpoints a gate's "beyond" lists while that gate is shut (the dawn road
##     checkpoint past the Master Gate cannot have been touched yet). Cracked floors the cat can pound
##     break, as in softlock.gd.
##  4. For every position the cat can enter and every objective some subset still lacks, the objective
##     must be reachable from that position by moves a player can count on (walks, jumps, drops, and
##     pad hops that carry on with their power). Dying and respawning at a checkpoint is NOT a way
##     back: the respawn is the LAST checkpoint, which is exactly where the cat is stranded.
##     Positions that fail are grouped into regions and reported with the objective they cannot reach.
##
## NOT MODELLED (as in softlock.gd): shutters, plates, switches, shield panels, crates and enemies are
## treated as open; only the gates in CONFIG close. A gate behind which the objectives sit is fine:
## they are only required while the gate is shut.
extends SceneTree

const SL := preload("res://tools/audit/softlock.gd")
const T := 32
const HW := 11.0
const STAND_H := 26.0

## room -> {objectives: [{name, rect}], gates: [{name, needs: [objective names], rect}]}
## beyond: the checkpoints on the far side of the gate, not starts while it is shut.
## rect: "floor" = node origin on the floor line, size from the node's `size` (relays, the conduit);
## "shape" = the first rectangle CollisionShape2D of the instanced scene (a pickup, a door);
## "gate" = the Master Gate (width x height_tiles, origin = middle of the base).
const CONFIG := {
	# Room 1's brass key and the vault door are optional loot (the office tier is a side branch), Room 2's
	# plates, shutters and gate are the player's own actions: neither room has a required objective.
	# The "shape" rect and a gate's "needs" are here for a room that gains one.
	"room3": {
		"objectives": [{"name": "Conduit", "rect": "floor"}],
		"gates": [],
	},
	"room4": {
		"objectives": [
			{"name": "Relay1", "rect": "floor"},
			{"name": "Relay2", "rect": "floor"},
			{"name": "Relay3", "rect": "floor"},
		],
		"gates": [{"name": "MasterGate", "needs": ["Relay1", "Relay2", "Relay3"], "rect": "gate", "beyond": ["CheckpointJ"]}],
	},
}

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
	return _cat_values


func _main() -> void:
	var ids: Array = CONFIG.keys()
	var want := OS.get_environment("ROOMS")
	if want != "":
		ids = Array(want.split(","))
	audit(note, ids, OS.get_environment("MAP") == "1")
	var ok_all := results.all(func(r): return r[1])
	print("== %d checks, %s" % [results.size(), "ALL PASS" if ok_all else "FAILURES"])
	quit(0 if ok_all else 1)


## One check per room: no stranded region. `note_cb` is called as note_cb(label, ok, detail).
func audit(note_cb: Callable, ids: Array, show_map := false) -> void:
	for id in ids:
		if config_key(id) == "":
			note_cb.call("PROGRESSION %s: no required objectives" % id, true, "skipped")
			continue
		var t0 := Time.get_ticks_msec()
		var found := check_room(id, show_map)
		note_cb.call("PROGRESSION %s: every required objective stays reachable" % id, found["lines"].is_empty(), "%d objectives, %d graphs, %d ms" % [found["objectives"], found["graphs"], Time.get_ticks_msec() - t0])
		for l in found["lines"]:
			print("   %s  %s" % [id, l])


## The CONFIG entry for a scene: its own name, or the room it is a scratch copy of ("room4_main" -> "room4"), else "".
func config_key(id: String) -> String:
	if CONFIG.has(id):
		return id
	var base := id.get_slice("_", 0)
	return base if CONFIG.has(base) else ""


## The subsets of objective indices, grouped by the set of gates they leave shut.
## Returns {closed-gate key: {"closed": [gate idx], "lacking": {objective idx: true}}}.
func _configs(cfg: Dictionary) -> Dictionary:
	var objs: Array = cfg["objectives"]
	var gates: Array = cfg["gates"]
	var out := {}
	for mask in (1 << objs.size()):
		var have := []
		for i in objs.size():
			if mask & (1 << i):
				have.append(String(objs[i]["name"]))
		var closed := []
		for gi in gates.size():
			var needs: Array = gates[gi]["needs"]
			if not needs.all(func(n): return have.has(n)):
				closed.append(gi)
		var key := ",".join(closed.map(func(g): return str(g)))
		if not out.has(key):
			out[key] = {"closed": closed, "lacking": {}}
		for i in objs.size():
			if not (mask & (1 << i)):
				out[key]["lacking"][i] = true
	return out


func _rect_of(scene: Node, spec: Dictionary) -> Rect2:
	var n := scene.get_node(String(spec["name"])) as Node2D
	var pos := n.global_position
	match String(spec["rect"]):
		"floor":
			var s: Vector2 = n.get("size")
			return Rect2(pos + Vector2(-s.x * 0.5, -s.y), s)
		"gate":
			var w := float(n.get("width"))
			var h := float(n.get("height_tiles")) * T
			return Rect2(pos + Vector2(-w * 0.5, -h), Vector2(w, h))
		_:
			for k in n.get_children():
				if k is CollisionShape2D and k.shape is RectangleShape2D:
					var s2: Vector2 = k.shape.size
					return Rect2(pos + k.position - s2 * 0.5, s2)
	return Rect2()


func check_room(id: String, show_map := false) -> Dictionary:
	var cfg: Dictionary = CONFIG[config_key(id)]
	var scene: Node = load("res://scenes/levels/%s.tscn" % id).instantiate()
	var obj_rects: Array = []
	for o in cfg["objectives"]:
		obj_rects.append(_rect_of(scene, o))
	var gate_rects: Array = []
	for g in cfg["gates"]:
		gate_rects.append(_rect_of(scene, g))
	var cp_names: Array = []
	var start_names: Array = []
	if scene.get_node_or_null("PlayerStart") != null:
		start_names.append("PlayerStart")
	for c in scene.get_children():
		if c.get_script() != null and String(c.get_script().resource_path.get_file()) == "checkpoint.gd":
			cp_names.append(String(c.name))
			start_names.append(String(c.name))
	scene.free()
	var lines: Array = []
	var cfgs := _configs(cfg)
	for key in cfgs:
		var closed: Array = cfgs[key]["closed"]
		var lacking: Array = cfgs[key]["lacking"].keys()
		var m := SL.Model.new(cat_values())
		m.load_room(id)
		for gi in closed:
			m.rects.append(gate_rects[gi])
		var skip: Array = []
		for gi in closed:
			skip.append_array(cfg["gates"][gi].get("beyond", []))
		var entered := _enter(m, skip, start_names)
		var shut := ", ".join(closed.map(func(g): return String(cfg["gates"][g]["name"])))
		var rev := _reverse(m, entered)
		var stranded_any := {}
		for oi in lacking:
			var oname := String(cfg["objectives"][oi]["name"])
			var goal: Array = []
			for k in entered:
				if _touches(m, k, obj_rects[oi]):
					goal.append(k)
			if goal.is_empty():
				lines.append("%s is never reachable from the start (gates shut: %s)" % [oname, shut if shut != "" else "none"])
				continue
			var good := {}
			for k in goal:
				good[k] = true
			m._back(rev, good, goal.duplicate())
			var bad := {}
			for k in entered:
				if not good.has(k):
					bad[k] = true
					stranded_any[k] = true
			for g in _regions(m, bad):
				var cps: Array = []
				for ci in m.checkpoints.size():
					var r: Rect2 = m.checkpoints[ci]
					var cn := m._drop_node(Vector2(r.position.x + r.size.x * 0.5, r.end.y))
					if cn >= 0 and g["cells"].has(cn) and ci < cp_names.size():
						cps.append(String(cp_names[ci]))
				lines.append("STRANDED %s: cannot get back to %s (gates shut: %s)%s" % [m.box_str(g), oname, shut if shut != "" else "none", (", respawns here: " + "/".join(cps)) if not cps.is_empty() else ""])
		if show_map and not stranded_any.is_empty():
			print(_map(m, stranded_any))
	return {"lines": lines, "objectives": cfg["objectives"].size(), "graphs": cfgs.size()}


func _touches(m: Object, k: int, r: Rect2) -> bool:
	var x: float = m.key_x(k)
	var y: float = m.key_y(k)
	return Rect2(x - HW, y - STAND_H, HW * 2.0, STAND_H).intersects(r)


## Everything the cat can reach from the player start and from every checkpoint except `skip` (the
## checkpoints beyond a shut gate), as softlock.gd's Model.analyze does: a respawn comes back at a
## checkpoint with no power. Returns {node key: true}.
func _enter(m: Object, skip: Array = [], names: Array = []) -> Dictionary:
	var best := {}
	var guard := 0
	while guard < 12:
		guard += 1
		m.pending_breaks = {}
		var roots: Array = []
		for i in m.starts.size():
			if i < names.size() and skip.has(names[i]):
				continue
			var n: int = m._drop_node(m.starts[i])
			if n >= 0:
				roots.append([n, 0, SL.INF_T])
		best = m.search(roots, true, {})
		if m.pending_breaks.is_empty():
			break
		for cc in m.pending_breaks:
			m._set_cell(cc.x, cc.y, 0)
			m.broken[cc] = true
		m.reset_graph()
	var entered := {}
	for sk in best:
		entered[sk / 8] = true
	return entered


## The reverse graph over the entered positions: human moves, plus pad hops (a pad carries on with its power).
func _reverse(m: Object, entered: Dictionary) -> Dictionary:
	var pad_reach := {}
	for pi in m.pads.size():
		var p: Dictionary = m.pads[pi]
		var starts_p: Array = []
		var members: Array = []
		for k in entered:
			if m.pads_at(k).has(pi):
				starts_p.append([k, int(p["power"]), float(p["dur"])])
				members.append(k)
		if starts_p.is_empty():
			continue
		var res: Dictionary = m.search(starts_p, true, {}, true)
		var set := {}
		for sk in res:
			set[sk / 8] = true
		for k in members:
			pad_reach[k] = set
	var rev := {}
	for k in entered:
		var e: Array = m.edges(k, 0)
		for to in e[2]:
			if to >= 0:
				if not rev.has(to):
					rev[to] = []
				rev[to].append(k)
		if pad_reach.has(k):
			for to in pad_reach[k]:
				if to != k:
					if not rev.has(to):
						rev[to] = []
					rev[to].append(k)
	return rev


## Connected regions of `bad` positions (moves that go both ways in the picture: undirected).
func _regions(m: Object, bad: Dictionary) -> Array:
	var adj := {}
	for k in bad:
		var e: Array = m.edges(k, 0)
		for to in e[2]:
			if to >= 0 and bad.has(to):
				if not adj.has(k):
					adj[k] = []
				if not adj.has(to):
					adj[to] = []
				adj[k].append(to)
				adj[to].append(k)
	var seen := {}
	var out: Array = []
	for k0 in bad:
		if seen.has(k0):
			continue
		var cells := {}
		var stack := [k0]
		seen[k0] = true
		var x0 := INF
		var x1 := -INF
		var y0 := INF
		var y1 := -INF
		while not stack.is_empty():
			var k: int = stack.pop_back()
			cells[k] = true
			x0 = minf(x0, m.key_x(k))
			x1 = maxf(x1, m.key_x(k))
			y0 = minf(y0, m.key_y(k))
			y1 = maxf(y1, m.key_y(k))
			if adj.has(k):
				for to in adj[k]:
					if not seen.has(to):
						seen[to] = true
						stack.append(to)
		out.append({"cells": cells, "x0": x0, "x1": x1, "y0": y0, "y1": y1})
	return out


func _map(m: Object, stranded: Dictionary) -> String:
	var marks := {}
	for k in stranded:
		marks[Vector2i(floori(m.key_x(k) / T), floori((m.key_y(k) - 1.0) / T))] = true
	var lines: Array = []
	for cy in range(m.gy0, m.gy0 + m.gh):
		var row := ""
		var any := false
		for cx in range(m.gx0, m.gx0 + m.gw):
			var ch := " "
			if marks.has(Vector2i(cx, cy)):
				ch = "X"
				any = true
			elif m.cell(cx, cy) == 1:
				ch = "#"
			elif m.cell(cx, cy) >= 2:
				ch = "="
			row += ch
		if any:
			lines.append("%4d %s" % [cy, row])
	return "\n".join(lines)
