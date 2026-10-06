## Renders Room 1 stop by stop (needs a display or xvfb): the cat is placed at
## each x and a frame is saved. Not a test: a way to look at the level.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --script res://tools/audit/room1_tour.gd -- --skip-intro <outdir> [x:label[:y] ...]
## With no stops it tours every beat.
extends SceneTree

const DEFAULT_STOPS := [
	"144:a_nook:766", "480:b_crates:766", "760:b_deck_bot:766", "1200:b_belt_spikes:766", "1500:b_racks:766", "1700:b_rack_top:574",
	"1640:c_mezz_arrival:510", "1300:c_mezz_camera:510", "900:c_detour_deck:638", "520:c_bot_lane:510", "350:c_lift_foot:510",
	"380:d_roof_start:254", "720:d_falling:254", "980:d_drone:254", "1300:d_loft:254", "1560:d_ride:254", "1840:d_doorway:254",
	"1980:e_shaft_top:254", "2000:e_shaft_drop:700", "2080:f_machine:766", "2400:f_crusher:766", "2900:f_hatch:766",
	"2000:g_base:1054", "2320:g_drain:1054", "2640:g_electric:1054", "2950:g_lab:1054", "3560:h_pool_approach:1054",
	"3880:h_pool:1054", "4120:i_crate:1054", "300:j_closet:1054", "600:j_tunnel:1054",
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
		var cam: Camera2D = _cat.camera
		print("SHOT ", label, " cat ", _cat.global_position, " view centre ", cam.get_screen_center_position())
	_stop += 1
	if _stop >= _stops.size():
		quit()
		return false
	var parts := String(_stops[_stop]).split(":")
	_cat.global_position = Vector2(float(parts[0]), float(parts[2]) if parts.size() > 2 else 300.0)
	_cat.velocity = Vector2.ZERO
	return false
