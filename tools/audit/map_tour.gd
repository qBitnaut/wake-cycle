## Renders the world map at set moments (needs a display or xvfb): opens it as
## a level's exit would and saves frames. Not a test: a way to look at it.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --script res://tools/audit/map_tour.gd -- <outdir> <completed id> [frame:label ...]
## A label of the form "go=<id>" teleports the cat onto that node first;
## "key=<action>" taps an input action.
extends SceneTree

var _outdir := "/tmp/map_tour"
var _done := ""
var _stops: Array = []
var _frame := 0
var _map: Node


func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	if rest.size() > 0:
		_outdir = rest[0]
	if rest.size() > 1:
		_done = rest[1]
	_stops = rest.slice(2) if rest.size() > 2 else ["30:open", "90:stamp", "150:draw", "210:lit", "300:walk", "420:arrived"]
	DirAccess.make_dir_recursive_absolute(_outdir)
	_start.call_deferred()


func _start() -> void:
	var gs := root.get_node("GameState")
	gs.new_game()
	gs.awaken_mind()
	var wm: GDScript = load("res://scripts/ui/world_map.gd")
	wm.set("_pending", _done)
	wm.set("load_levels", false)
	_map = load("res://scenes/ui/world_map.tscn").instantiate()
	root.add_child(_map)
	current_scene = _map


func _process(_d: float) -> bool:
	if _map == null:
		return false
	_frame += 1
	for s in _stops:
		var parts := String(s).split(":")
		if int(parts[0]) != _frame:
			continue
		var label := parts[1]
		if label.begins_with("go="):
			var id := label.substr(3)
			_map.set("at_node", id)
			_map.get("cat").position = load("res://scripts/systems/level_registry.gd").position_of(id)
			_map.call("_show_label", id)
		elif label.begins_with("key="):
			var act := label.substr(4)
			var ev := InputEventAction.new()
			ev.action = act
			ev.pressed = true
			Input.parse_input_event(ev)
			_release.call_deferred(act)
		else:
			root.get_texture().get_image().save_png("%s/%03d_%s.png" % [_outdir, _frame, label])
			print("SHOT ", label)
	var last := 0
	for s in _stops:
		last = maxi(last, int(String(s).split(":")[0]))
	if _frame > last:
		quit()
	return false


func _release(act: String) -> void:
	await process_frame
	await process_frame
	var ev := InputEventAction.new()
	ev.action = act
	ev.pressed = false
	Input.parse_input_event(ev)
