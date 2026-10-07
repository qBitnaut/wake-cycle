extends Node
## Checkpoint saves in user://save.json (IndexedDB-backed on the web build) plus
## the in-session respawn bookkeeping. Registered as the autoload "SaveSystem".

const SAVE_PATH := "user://save.json"
## Written once the game has been finished (the Home ending's credits).
const COMPLETE_PATH := "user://complete.json"
## Save format / content version. Bump it whenever rooms, checkpoint ids or the map
## change in a way that makes an old save point somewhere wrong. A save written by any
## other version is DISCARDED on read (see read_save), so no Continue pad is offered for
## it. v1: the pre-v2 rooms. v2: the rebuilt tall rooms.
const SAVE_VERSION := 2
const CHECKPOINT_SCENE := "res://scenes/actors/checkpoint.tscn"
const WORLD_MAP_SCENE := "res://scenes/ui/world_map.tscn"

var session_scene := ""
var session_checkpoint := ""
var session_snapshot := {}
var _respawning := false
## Why the last save was thrown away ("" = none); for the audits.
var last_discard := ""
## True when read_save had to fall back to the room start (stale checkpoint id).
var last_fallback := false
var _cp_cache := {}


## A Continue is offered only for a save that is valid for THIS build.
func has_save() -> bool:
	return not read_save().is_empty()


## The save on disk, validated. An incompatible save (other version, unreadable, its
## room gone) is deleted and {} returned. A stale checkpoint id (not in the room any
## more) falls back to the room start (""), unknown map nodes are dropped.
func read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return _discard("unreadable")
	var d: Dictionary = parsed
	if int(d.get("version", 0)) != SAVE_VERSION:
		return _discard("version %s, this build is %d" % [str(d.get("version", "none")), SAVE_VERSION])
	var scene := String(d.get("scene", ""))
	if scene == "" or not ResourceLoader.exists(scene):
		return _discard("room %s is gone" % scene)
	last_fallback = false
	var cp := String(d.get("checkpoint", ""))
	if cp != "" and not _scene_has_checkpoint(scene, cp):
		d["checkpoint"] = ""
		last_fallback = true
	if d.get("map") is Dictionary:
		d["map"] = _clean_map(d["map"])
	return d


func _discard(reason: String) -> Dictionary:
	last_discard = reason
	delete_save()
	return {}


## Map progress restricted to nodes the world map still has.
func _clean_map(m: Dictionary) -> Dictionary:
	var out := {"completed": [], "unlocked": [], "node": ""}
	for k in ["completed", "unlocked"]:
		for id in m.get(k, []):
			if LevelRegistry.has(String(id)):
				out[k].append(String(id))
	var n := String(m.get("node", ""))
	out["node"] = n if LevelRegistry.has(n) else ""
	return out


## Is `id` the checkpoint_id of a Checkpoint placed in the scene? (Reads the packed
## scene's state; nothing is instantiated.)
func _scene_has_checkpoint(scene_path: String, id: String) -> bool:
	var key := scene_path + "#" + id
	if _cp_cache.has(key):
		return _cp_cache[key]
	var found := false
	var ps := load(scene_path) as PackedScene
	if ps:
		var st := ps.get_state()
		for i in st.get_node_count():
			var inst := st.get_node_instance(i)
			if inst == null or inst.resource_path != CHECKPOINT_SCENE:
				continue
			var cp := "cp1"  # Checkpoint's default
			for j in st.get_node_property_count(i):
				if st.get_node_property_name(i, j) == "checkpoint_id":
					cp = String(st.get_node_property_value(i, j))
			if cp == id:
				found = true
				break
	_cp_cache[key] = found
	return found


## "Room 3" for a story room, "" otherwise (the title card's small line).
func saved_room_label(d: Dictionary) -> String:
	var id := LevelRegistry.id_for_scene(String(d.get("scene", "")))
	return "Room %d" % int(LevelRegistry.order_of(id)) if id != "" and LevelRegistry.is_main(id) else ""


## "Room 3: The Stacks" for the Continue sign (numbered); the name alone for the title card.
func saved_room_name(d: Dictionary, numbered := false) -> String:
	var scene := String(d.get("scene", ""))
	if scene == WORLD_MAP_SCENE:
		return "The World Map"
	var id := LevelRegistry.id_for_scene(scene)
	if id == "":
		return scene.get_file().get_basename().capitalize()
	var n := LevelRegistry.level_name(id)
	if numbered and LevelRegistry.is_main(id):
		return "Room %d: %s" % [int(LevelRegistry.order_of(id)), n]
	return n


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Called by a checkpoint: remember it for respawns and write it to disk.
func save_checkpoint(id: String, scene_path: String) -> void:
	session_scene = scene_path
	session_checkpoint = id
	session_snapshot = GameState.snapshot()
	var data := {
		"version": SAVE_VERSION,
		"scene": scene_path,
		"checkpoint": id,
		"abilities": {"shockwave": GameState.shockwave_unlocked, "mind": GameState.intelligence},
		"keys": GameState.keys.duplicate(),
		"letters": GameState.letters,
		"letter_mask": GameState.letter_mask,
		"collectibles": GameState.collected.duplicate(),
		"health": GameState.health,
		"score": GameState.score,
		"map": GameState.map_snapshot(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveSystem: cannot write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data))
	f.close()


## Called by a level on _ready. Returns the checkpoint id to spawn at ("" = level start).
func begin_level(scene_path: String) -> String:
	if session_scene != scene_path:
		session_scene = scene_path
		session_checkpoint = ""
		session_snapshot = GameState.snapshot()
		_respawning = false
	else:
		GameState.restore(session_snapshot)
		if _respawning:
			GameState.set_health(GameState.MAX_HEALTH)
			_respawning = false
	return session_checkpoint


## Death: reload the level at the last checkpoint.
func respawn() -> void:
	_respawning = true
	get_tree().reload_current_scene()


## Load the save from disk and enter its level at its checkpoint.
## With `from` (the pad), fades out and in again with the room's title card.
func continue_game(from: Node = null) -> bool:
	var d := read_save()
	if d.is_empty():
		return false
	session_scene = String(d["scene"])
	session_checkpoint = String(d.get("checkpoint", ""))
	session_snapshot = {
		"health": maxi(int(d.get("health", GameState.MAX_HEALTH)), 1),
		"score": int(d.get("score", 0)),
		"keys": d.get("keys", []),
		"letter_mask": int(d.get("letter_mask", (1 << int(d.get("letters", 0))) - 1)),
		"mind": bool(d.get("abilities", {}).get("mind", false)),
		"collected": d.get("collectibles", []),
		"shockwave": bool(d.get("abilities", {}).get("shockwave", false)),
	}
	if d.has("map"):
		session_snapshot["map"] = d["map"]
	_respawning = false
	if from != null:
		RoomTransition.continue_to(from, session_scene, saved_room_name(d), saved_room_label(d))
	else:
		get_tree().change_scene_to_file(session_scene)
	return true


## The game is finished: remember that (with the score and letters), and
## clear the checkpoint, so the next run starts from the beginning.
func mark_complete() -> void:
	var f := FileAccess.open(COMPLETE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"complete": true, "score": GameState.score, "letters": GameState.letters}))
		f.close()
	delete_save()
	session_scene = ""
	session_checkpoint = ""
	session_snapshot = {}


func is_complete() -> bool:
	return FileAccess.file_exists(COMPLETE_PATH)
