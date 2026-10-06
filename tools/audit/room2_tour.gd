## Renders Room 2 stop by stop (needs a display or xvfb): the cat is placed at
## each x and a frame is saved. Not a test: a way to look at the level.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --script res://tools/audit/room2_tour.gd -- --skip-intro <outdir> [x:label[:y] ...]
## With no stops it tours every beat. The rain follows the camera, so each stop needs a second to settle.
extends SceneTree

const DEFAULT_STOPS := [
	"130:a_arrival:768", "500:a_yard:768", "1000:b1_tunnel_mouth:768", "1110:b1_pad:768", "1500:b1_run:768",
	"1900:b2_checkpoint:768", "2150:b2_gap_edge:768", "2228:b2_gap_lip:768", "2700:b2_landing:768",
	"2400:u_landing:1024", "1700:u_vault_lane:1024", "1480:u_vault:1216", "3100:u_crawl:1088",
	"3700:u_electric:1024", "4500:u_spur:1024", "2900:r_stair:700", "3100:r_roof1:512", "3650:r_bridge:512",
	"3950:r_crane_stair:448", "4260:r_cab:256", "4370:r_lift:256", "3150:b3_pad:768", "3500:b3_lane:768",
	"3900:b3_gate:768", "4350:d_dock:768", "4700:d_canopy:768", "5000:d_hut:768", "5300:b4_drone_start:768",
	"5800:b4_pit:768", "6100:b4_vent:768", "6700:e_fence:768", "6900:e_exit:768",
]

var _stops: Array = []
var _outdir := "/tmp/room2_tour"
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
	var room: Node = load("res://scenes/levels/room2.tscn").instantiate()
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
	_cat.global_position = Vector2(float(parts[0]), float(parts[2]) if parts.size() > 2 else 768.0)
	_cat.velocity = Vector2.ZERO
	return false
