## Renders Room 3 stop by stop (needs a display or xvfb): the cat is placed at
## each x and a frame is saved. Not a test: a way to look at the level.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --script res://tools/audit/room3_tour.gd -- --skip-intro <outdir> [x:label[:y] ...]
## With no stops it tours every beat. The rain follows the camera, so each stop needs a second to settle.
extends SceneTree

const DEFAULT_STOPS := [
	"130:a_arrival:1152", "900:b1_wall_foot:1152", "1072:b1_pad:1152", "1250:b2_shed:960", "1500:b2_ledge:768",
	"1900:c_long_roof:576", "2150:d_conduit:576", "2500:e_crates:576", "2800:e_bot:576", "3100:e_switch:576",
	"3300:f_bay_enter:576", "3700:f_bay_mid:576", "4020:f_bay_gate:576", "4300:g_roof_run:576", "4440:g_tower_foot:576",
	"4600:g_tower_top:384", "4900:g_gap:384", "5200:g_exit_roof:384", "5340:g_exit:384",
]

var _stops: Array = []
var _outdir := "/tmp/room3_tour"
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
	root.get_node("SaveSystem").delete_save()
	root.get_node("GameState").intelligence = true  # arrives from Room 1 with the mind awake
	var room: Node = load("res://scenes/levels/room3.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	_cat = room.get_node("Cat")
	_started = true


func _process(_d: float) -> bool:
	if not _started:
		return false
	_frame += 1
	if _frame % 45 != 0:
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
	_cat = current_scene.get_node("Cat")
	_cat.global_position = Vector2(float(parts[0]), float(parts[2]) if parts.size() > 2 else 1152.0)
	_cat.velocity = Vector2.ZERO
	return false
