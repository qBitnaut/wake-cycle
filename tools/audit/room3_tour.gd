## Renders Room 3 stop by stop (needs a display or xvfb): the cat is placed at
## each x and a frame is saved. Not a test: a way to look at the level.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --script res://tools/audit/room3_tour.gd -- --skip-intro <outdir> [x:label[:y] ...]
## With no stops it tours every beat. The rain follows the camera, so each stop needs a second to settle.
extends SceneTree

const DEFAULT_STOPS := [
	"130:a_arrival:1408", "1000:b1_wall_foot:1408", "1250:b2_shed:1216", "1500:b2_ledge:1024", "1800:c_long_roof:832",
	"2150:c_corridor_mouth:832", "2500:c_crawlers:832", "2800:c_pit1:832", "3100:c_hopper:832", "3350:c_pit2:832",
	"3650:c_lift_foot:832", "3640:d_lift_top:640", "3440:d_conduit:640", "3260:d_crates:640", "2900:d_bot:640",
	"2520:d_switch:640", "2200:d_light_well:640", "2400:e_roof_start:448", "2620:e_pump_house:448", "2820:e_turret:448",
	"2960:e_barrels:448", "3170:e_vent_pad:448", "3250:e_vent_pillar:256", "3230:e_crane_deck:128", "3560:e_skywalk:128",
	"3700:e_roof_east:448", "3770:u_lift_foot:832", "4000:u_corridor:832", "4300:u_shaft_edge:832", "4420:u_pillar:1024", "4330:u_west_pit:1216", "4580:u_far_landing:832", "4000:f_bay:448", "4560:f_gate:448", "4900:g_tower_foot:448", "5000:g_tower_top:256",
	"5300:g_exit_pit:256", "5420:g_exit:256",
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
