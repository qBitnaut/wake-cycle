## Renders Room 4 stop by stop (needs a display or xvfb): the cat is placed at each (x, y) and a frame
## is saved. Not a test: a way to look at the level. Stops are col:label:row (tile units, the cat stands
## on top of `row`). "FULL" renders the whole room zoomed out in tiles (see _full()).
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --script res://tools/audit/room4_tour.gd -- <outdir> [col:label:row ...]
## With no stops it tours every beat. The rain follows the camera, so each stop needs a second to settle.
extends SceneTree

const DEFAULT_STOPS := [
	"4:a_arrival:12", "14:a_tower:10", "40:p1_corridor:12", "76:p2_corridor:12", "113:p3_pad:12", "126:p3_roof:6",
	"96:catwalk:6", "60:catwalk_w:6", "143:i1_pad:10", "148:i1_hatch:12", "152:l1_cp:17", "162:l1_bot:17",
	"177:l2_shield:22", "195:l2_gauntlet:22", "204:l2_crusher:22", "212:archive:22", "191:l3_cp:27", "202:l3_camera:27",
	"217:l3_press:27", "230:s1_shaft:27", "230:s1_mid:19", "240:plaza:12", "256:r1_tower:10", "244:board_plaza:12", "264:east_ladder:12", "347:board_gate:12", "270:vault_pad:12",
	"280:vault_in:18", "292:vault_mech:18", "320:armoury:12", "322:armoury_in:17", "194:l4_hall:35", "212:l4_pools:34",
	"228:l4_lasers:35", "233:l4_relay:35", "340:scanner:12", "362:road:12",
]

var _stops: Array = []
var _outdir := "/tmp/room4_tour"
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
	root.get_node("GameState").intelligence = true
	root.get_node("GameState").shockwave_unlocked = true
	var room: Node = load("res://scenes/levels/room4.tscn").instantiate()
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
	_cat.global_position = Vector2(float(parts[0]) * 32.0 + 16.0, float(parts[2]) * 32.0)
	_cat.velocity = Vector2.ZERO
	return false
