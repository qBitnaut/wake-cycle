## Renders Room 1 stop by stop (needs a display or xvfb): the cat is placed at
## each x and a frame is saved. Not a test: a way to look at the level.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --script res://tools/audit/room1_tour.gd -- --skip-intro <outdir> [x:label[:y] ...]
## With no stops it tours every beat.
extends SceneTree

const DEFAULT_STOPS := [
	"180:a_nook", "400:a_hall", "560:b_crate_stairs", "800:b_catwalk_start:200", "1040:b_catwalk_gap:200", "1230:b_descent",
	"1500:c_hall_start", "1700:c_puddle_window", "2000:d_crawl_entry", "2350:e_fence", "2700:e_plate",
	"3000:f_key_deck", "3300:f_door", "3600:g_steam", "4000:h_flood", "4300:i_pool_approach",
	"4800:i_in_pool", "5000:j_door",
]

var _stops: Array = []
var _outdir := "/tmp/room1_tour"
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
	root.get_node("SaveSystem").delete_save()  # a stale save would arm the CONTINUE pad
	var room: Node = load("res://scenes/levels/room1.tscn").instantiate()
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
	_cat.global_position = Vector2(float(parts[0]), float(parts[2]) if parts.size() > 2 else 300.0)
	_cat.velocity = Vector2.ZERO
	return false
