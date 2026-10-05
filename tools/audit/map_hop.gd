## Shared by the audits: what a room's exit does now. The exit lands on the world
## map (the level is completed, its unlocks open, the map plays its reveal), and the
## next room is entered from the map the way the player does it.
##   var hop: Dictionary = await MapHop.through(root.get_tree(), "warehouse", "yard")
## Returns {on_map, completed, unlocked, entered, scene, sound_map, sound_next}; the caller
## notes them. sound_map / sound_next list the looping sounds still playing outside the
## current scene (LoopSfx.orphans) on the map and after the next room loaded: both empty
## means the room's loops (drones, scanners, beds) all stopped with it.
class_name MapHop
extends RefCounted

const MAP := "res://scenes/ui/world_map.tscn"


static func scene_is(tree: SceneTree, path: String) -> bool:
	return tree.current_scene != null and tree.current_scene.scene_file_path == path


## Waits for the map after an exit, lets its reveal finish, then goes into `next`.
static func through(tree: SceneTree, completed: String, next: String, limit := 6000) -> Dictionary:
	var out := {"on_map": false, "completed": false, "unlocked": false, "entered": false, "scene": "?", "sound_map": [], "sound_next": []}
	var n := 0
	while not scene_is(tree, MAP) and n < limit:
		await tree.physics_frame
		n += 1
	out["on_map"] = scene_is(tree, MAP)
	if not out["on_map"]:
		out["scene"] = str(tree.current_scene.scene_file_path) if tree.current_scene else "?"
		return out
	var map: Node = tree.current_scene
	for i in 20:
		await tree.physics_frame
	out["sound_map"] = LoopSfx.orphans(tree)
	await tree.physics_frame
	var gs: Node = tree.root.get_node("GameState")
	out["completed"] = gs.map_completed.has(completed)
	out["unlocked"] = gs.map_unlocked.has(next)
	n = 0
	while map.get("auto") and n < limit:
		await tree.physics_frame
		n += 1
	n = 0
	while not map.enter_level(next) and n < 600:
		await tree.physics_frame
		n += 1
	var want := LevelRegistry.scene_of(next)
	n = 0
	while (not scene_is(tree, want) or tree.current_scene.get_node_or_null("Cat") == null) and n < limit:
		await tree.physics_frame
		n += 1
	for i in 20:
		await tree.physics_frame
	out["sound_next"] = LoopSfx.orphans(tree)
	out["entered"] = scene_is(tree, want)
	out["scene"] = str(tree.current_scene.scene_file_path) if tree.current_scene else "?"
	return out
