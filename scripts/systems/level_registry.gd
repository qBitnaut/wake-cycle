class_name LevelRegistry
extends RefCounted
## The level registry (res://data/levels.json) and the map progress rules.
## Data only: the world map (WorldMap) draws and walks it; room exits and save
## code can ask it which level a scene is, and what finishing it opens.
##
## Nodes are levels (with a scene) and junctions (path forks, no scene).
## Paths join two nodes, optionally bending through `via` points.
##
## Progress lives in GameState (map_completed, map_unlocked, map_node), so it is
## saved and restored with everything else. The rules:
##   unlocked   the start level, or listed in the `unlocks` of a completed level
##   open       a level that is unlocked and meets its `requires` (a bonus or
##              secret level also needs its scene to exist: placeholders stay
##              shut); a junction with open levels on two or more sides
##   enterable  an open level whose scene exists (junctions are walked through)
##   visible    anything but a secret level that is not open yet
## A path can be walked when both of its ends are open.

const DATA := "res://data/levels.json"

static var _data := {}
static var _nodes := {}        # id -> node dict (levels and junctions)
static var _adj := {}          # id -> [ [other id, path index, forward] ]
static var _loaded := false
## Test hook: per-level field overrides, e.g. {"water_tower": {"scene": "res://..."}}.
static var overrides := {}


static func load_data(force := false) -> void:
	if _loaded and not force:
		return
	_loaded = true
	_data = {}
	_nodes = {}
	_adj = {}
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f == null:
		push_warning("LevelRegistry: %s missing" % DATA)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_warning("LevelRegistry: %s is not a JSON object" % DATA)
		return
	_data = parsed
	for lv in _data.get("levels", []):
		_nodes[String(lv["id"])] = lv
	for j in _data.get("junctions", []):
		var d: Dictionary = j.duplicate()
		d["junction"] = true
		_nodes[String(j["id"])] = d
	var paths: Array = _data.get("paths", [])
	for i in paths.size():
		var a := String(paths[i]["a"])
		var b := String(paths[i]["b"])
		if not _nodes.has(a) or not _nodes.has(b):
			push_warning("LevelRegistry: path %d joins unknown nodes %s, %s" % [i, a, b])
			continue
		_adj.get_or_add(a, []).append([b, i, true])
		_adj.get_or_add(b, []).append([a, i, false])


# ---- the data ------------------------------------------------------------------

static func start_id() -> String:
	load_data()
	return String(_data.get("start", ""))


static func final_id() -> String:
	load_data()
	return String(_data.get("final", ""))


static func map_size() -> Vector2:
	load_data()
	var s: Array = _data.get("size", [2070, 360])
	return Vector2(s[0], s[1])


## Every level (not junctions), in story order.
static func level_ids() -> Array:
	load_data()
	var out: Array = []
	for lv in _data.get("levels", []):
		out.append(String(lv["id"]))
	out.sort_custom(func(a, b): return float(get_level(a).get("order", 0)) < float(get_level(b).get("order", 0)))
	return out


static func junction_ids() -> Array:
	load_data()
	return _data.get("junctions", []).map(func(j): return String(j["id"]))


static func has(id: String) -> bool:
	load_data()
	return _nodes.has(id)


## The node's dictionary with test overrides applied ({} if unknown).
static func get_level(id: String) -> Dictionary:
	load_data()
	var d: Dictionary = _nodes.get(id, {})
	if overrides.has(id):
		d = d.duplicate()
		d.merge(overrides[id], true)
	return d


static func is_junction(id: String) -> bool:
	return bool(get_level(id).get("junction", false))


static func is_bonus(id: String) -> bool:
	return bool(get_level(id).get("bonus", false))


static func is_secret(id: String) -> bool:
	return bool(get_level(id).get("secret", false))


## A story level: not a bonus, a secret or a junction.
static func is_main(id: String) -> bool:
	return has(id) and not is_junction(id) and not is_bonus(id) and not is_secret(id)


static func level_name(id: String) -> String:
	return String(get_level(id).get("name", id))


static func scene_of(id: String) -> String:
	return String(get_level(id).get("scene", ""))


static func position_of(id: String) -> Vector2:
	var p: Array = get_level(id).get("pos", [0, 0])
	return Vector2(p[0], p[1])


static func order_of(id: String) -> float:
	return float(get_level(id).get("order", 0.0))


## The level whose scene is `scene_path` ("" if none).
static func id_for_scene(scene_path: String) -> String:
	if scene_path == "":
		return ""
	for id in level_ids():
		if scene_of(id) == scene_path:
			return id
	return ""


static func has_scene(id: String) -> bool:
	var s := scene_of(id)
	return s != "" and ResourceLoader.exists(s)


static func paths() -> Array:
	load_data()
	return _data.get("paths", [])


## Path `index` as a polyline of world points, from its `a` end to its `b` end.
static func path_points(index: int) -> PackedVector2Array:
	var p: Dictionary = paths()[index]
	var pts := PackedVector2Array([position_of(String(p["a"]))])
	for v in p.get("via", []):
		pts.append(Vector2(v[0], v[1]))
	pts.append(position_of(String(p["b"])))
	return pts


## [[other id, path index, forward], ...] for the paths that touch `id`.
## `forward` is true when `id` is the path's `a` end.
static func links(id: String) -> Array:
	load_data()
	return _adj.get(id, [])


# ---- progress ------------------------------------------------------------------

static func _gs() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GameState") if Engine.get_main_loop() else null


static func completed() -> Array:
	var gs := _gs()
	return gs.map_completed if gs else []


static func unlocked() -> Array:
	var gs := _gs()
	return gs.map_unlocked if gs else []


static func is_completed(id: String) -> bool:
	return completed().has(id)


static func is_unlocked(id: String) -> bool:
	return id == start_id() or unlocked().has(id) or is_completed(id)


## The level's `requires`: {"letters": n} (C-A-T letters found), {"gems": n}
## (gems collected anywhere), {"collected": [pickup ids]}, {"completed": [ids]}.
static func requirements_met(id: String) -> bool:
	var req: Dictionary = get_level(id).get("requires", {})
	if req.is_empty():
		return true
	var gs := _gs()
	if gs == null:
		return false
	if req.has("letters") and int(gs.letters) < int(req["letters"]):
		return false
	if req.has("gems") and total_gems_found() < int(req["gems"]):
		return false
	for c in req.get("collected", []):
		if not gs.is_collected(String(c)):
			return false
	for c in req.get("completed", []):
		if not is_completed(String(c)):
			return false
	return true


static func is_open(id: String) -> bool:
	if not has(id):
		return false
	if is_junction(id):
		var sides := 0
		for l in links(id):
			if _reaches_open_level(String(l[0]), id, {}):
				sides += 1
		return sides >= 2
	return _level_open(id)


static func _level_open(id: String) -> bool:
	return is_unlocked(id) and requirements_met(id) and (is_main(id) or has_scene(id))


static func _reaches_open_level(id: String, came_from: String, seen: Dictionary) -> bool:
	if seen.has(id):
		return false
	seen[id] = true
	if not is_junction(id):
		return _level_open(id)
	for l in links(id):
		if String(l[0]) != came_from and _reaches_open_level(String(l[0]), id, seen):
			return true
	return false


static func is_enterable(id: String) -> bool:
	return not is_junction(id) and is_open(id) and has_scene(id)


static func is_visible(id: String) -> bool:
	if not has(id):
		return false
	if is_secret(id):
		return is_open(id)
	if is_junction(id):
		return is_open(id)
	return true


## Both ends open: the cat may walk it.
static func is_path_open(index: int) -> bool:
	var p: Dictionary = paths()[index]
	return is_open(String(p["a"])) and is_open(String(p["b"]))


## Neither end hidden: drawn (faintly if not open).
static func is_path_visible(index: int) -> bool:
	var p: Dictionary = paths()[index]
	for end in [String(p["a"]), String(p["b"])]:
		if is_secret(end) and not is_open(end):
			return false
	return true


## Every open level (not junctions).
static func open_levels() -> Array:
	return level_ids().filter(func(i): return is_open(i))


## The start level is always unlocked; make sure GameState lists it.
static func ensure_start() -> void:
	var gs := _gs()
	if gs and start_id() != "" and not gs.map_unlocked.has(start_id()):
		gs.map_unlocked.append(start_id())


## Finish level `id`: mark it completed and unlock its `unlocks`. The main
## story levels before it (lower order) are completed too, so a deep link or
## an old save never leaves the route behind the cat closed. Returns the
## levels that became open because of this, in story order.
static func complete(id: String) -> Array:
	var gs := _gs()
	if gs == null or not has(id) or is_junction(id):
		return []
	ensure_start()
	var before := open_levels()
	var todo: Array = [id]
	for other in level_ids():
		if is_main(other) and order_of(other) < order_of(id) and not is_completed(other):
			todo.push_front(other)
	for lv in todo:
		if not gs.map_completed.has(lv):
			gs.map_completed.append(lv)
		if not gs.map_unlocked.has(lv):
			gs.map_unlocked.append(lv)
		for u in get_level(lv).get("unlocks", []):
			if not gs.map_unlocked.has(String(u)):
				gs.map_unlocked.append(String(u))
	var fresh: Array = []
	for lv in open_levels():
		if not before.has(lv) and lv != id:
			fresh.append(lv)
	return fresh


## Shortest walkable route from `from` to `to` over open nodes, as node ids
## including both ends ([] if there is none).
static func route(from: String, to: String) -> Array:
	if from == to:
		return [from]
	var prev := {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for l in links(cur):
			var nxt := String(l[0])
			if prev.has(nxt) or not is_path_open(int(l[1])):
				continue
			prev[nxt] = cur
			if nxt == to:
				var out: Array = [to]
				var k := cur
				while k != "":
					out.push_front(k)
					k = prev[k]
				return out
			queue.append(nxt)
	return []


## The polyline of the path between two neighbouring nodes, from `from` to `to`.
static func segment(from: String, to: String) -> PackedVector2Array:
	for l in links(from):
		if String(l[0]) == to:
			var pts := path_points(int(l[1]))
			if not bool(l[2]):
				pts.reverse()
			return pts
	return PackedVector2Array()


## The whole route as one polyline.
static func route_points(ids: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(ids.size() - 1):
		var seg := segment(String(ids[i]), String(ids[i + 1]))
		if out.size() > 0 and seg.size() > 0:
			seg.remove_at(0)
		out.append_array(seg)
	if out.is_empty() and ids.size() == 1:
		out.append(position_of(String(ids[0])))
	return out


# ---- collectibles ---------------------------------------------------------------

## C-A-T letters hidden in level `id` (from the registry), e.g. ["C", "A", "T"].
static func letters_in(id: String) -> Array:
	return get_level(id).get("collectibles", {}).get("letters", [])


## The letters of `letters_in(id)` that have been found.
static func letters_found(id: String) -> Array:
	var gs := _gs()
	var out: Array = []
	for l in letters_in(id):
		var bit := "CAT".find(String(l))
		if gs and bit >= 0 and (int(gs.letter_mask) >> bit) & 1:
			out.append(String(l))
	return out


static func gems_total(id: String) -> int:
	return int(get_level(id).get("collectibles", {}).get("gems", 0))


## Gems picked up in level `id`: collected pickup ids are node paths under the
## level's root ("/root/Room2/GemA1"), so they are counted by that prefix.
static func gems_found(id: String) -> int:
	var root := String(get_level(id).get("root", ""))
	var gs := _gs()
	if root == "" or gs == null:
		return 0
	var prefix := "/root/%s/" % root
	var n := 0
	for c in gs.collected:
		var s := String(c)
		if s.begins_with(prefix) and s.get_file().begins_with("Gem"):
			n += 1
	return n


static func total_gems_found() -> int:
	var gs := _gs()
	if gs == null:
		return 0
	return gs.collected.filter(func(c): return String(c).get_file().begins_with("Gem")).size()
