## Renders Home stop by stop (needs a display or xvfb): the cat is placed at
## each x and a frame is saved. Not a test: a way to look at the level.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --script res://tools/audit/home_tour.gd -- <outdir> [x:label[:open] ...]
## A stop with a third field "open" dissolves the facade first (the inside).
extends SceneTree

const DEFAULT_STOPS := [
	"80:a_arrival", "420:a_first_puddle", "900:b_sage", "1300:c_small_tree", "1620:c_big_puddle",
	"2040:d_lamp", "2350:d_rose", "2780:e_home_tree", "3060:e_garden", "3180:e_steps",
	"3300:f_inside:open", "3500:f_spot:open",
]

var _stops: Array = []
var _outdir := "/tmp/home_tour"
var _cat: Node2D
var _frame := 0
var _stop := -1
var _started := false


func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	if rest.size() > 0:
		_outdir = rest[0]
	_stops = rest.slice(1) if rest.size() > 1 else DEFAULT_STOPS
	DirAccess.make_dir_recursive_absolute(_outdir)
	_start.call_deferred()


func _start() -> void:
	var room: Node = load("res://scenes/levels/home.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	_cat = room.get_node("Cat")
	_started = true


func _process(_d: float) -> bool:
	if not _started:
		return false
	_frame += 1
	if _frame % 40 != 0:
		return false
	if _stop >= 0:
		var label: String = String(_stops[_stop]).split(":")[1]
		root.get_texture().get_image().save_png("%s/%02d_%s.png" % [_outdir, _stop + 1, label])
		print("SHOT ", label)
	_stop += 1
	if _stop >= _stops.size():
		quit()
		return false
	var parts := String(_stops[_stop]).split(":")
	if parts.size() > 2 and parts[2] == "open":
		current_scene.call("_set_facade", 0.0)
		current_scene.call("_light_inside", _cat.get("sprite"))
		current_scene.set("beat", 2)
	_cat.global_position = Vector2(float(parts[0]), 300.0)
	return false
