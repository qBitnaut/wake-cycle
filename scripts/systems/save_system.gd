extends Node
## Checkpoint saves in user://save.json (IndexedDB-backed on the web build) plus
## the in-session respawn bookkeeping. Registered as the autoload "SaveSystem".

const SAVE_PATH := "user://save.json"
## Written once the game has been finished (the Home ending's credits).
const COMPLETE_PATH := "user://complete.json"
const VERSION := 1

var session_scene := ""
var session_checkpoint := ""
var session_snapshot := {}
var _respawning := false


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) and not read_save().is_empty()


func read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Called by a checkpoint: remember it for respawns and write it to disk.
func save_checkpoint(id: String, scene_path: String) -> void:
	session_scene = scene_path
	session_checkpoint = id
	session_snapshot = GameState.snapshot()
	var data := {
		"version": VERSION,
		"scene": scene_path,
		"checkpoint": id,
		"abilities": {"shockwave": GameState.shockwave_unlocked, "mind": GameState.intelligence},
		"keys": GameState.keys.duplicate(),
		"letters": GameState.letters,
		"letter_mask": GameState.letter_mask,
		"collectibles": GameState.collected.duplicate(),
		"health": GameState.health,
		"score": GameState.score,
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
func continue_game() -> bool:
	var d := read_save()
	if d.is_empty() or not ResourceLoader.exists(String(d.get("scene", ""))):
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
	_respawning = false
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
