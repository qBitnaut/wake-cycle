## Renders Room 4 as zoomed-out strips of the whole level (needs a display or xvfb with a big screen):
## the cat and the HUD are hidden, a Camera2D at `zoom` looks at x ranges of tiles.
##   xvfb-run -a -s "-screen 0 3840x2160x24" godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --script res://tools/audit/room4_map.gd -- <outdir> [zoom] [col0:col1 ...]
## Default: zoom 0.6 and two strips (0-200, 184-384): each image is 3840 x 780 px of the whole 1280 px height.
extends SceneTree

var _outdir := "/tmp/room4_map"
var _zoom := 0.6
var _strips: Array = ["0:200", "184:384"]
var _cam: Camera2D
var _frame := 0
var _n := -1
var _started := false


func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	if rest.size() > 0:
		_outdir = rest[0]
	if rest.size() > 1:
		_zoom = float(rest[1])
	if rest.size() > 2:
		_strips = rest.slice(2)
	DirAccess.make_dir_recursive_absolute(_outdir)
	_start.call_deferred()


func _start() -> void:
	root.get_node("SaveSystem").delete_save()
	root.get_node("GameState").intelligence = true
	root.get_node("GameState").shockwave_unlocked = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(3840, 780)
	var room: Node = load("res://scenes/levels/room4.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	room.get_node("Cat").visible = false
	room.get_node("Hud").visible = false
	_cam = Camera2D.new()
	_cam.zoom = Vector2(_zoom, _zoom)
	room.add_child(_cam)
	_cam.make_current()
	_started = true


func _process(_d: float) -> bool:
	if not _started:
		return false
	_frame += 1
	if _frame % 40 != 0:
		return false
	if _n >= 0:
		root.get_texture().get_image().save_png("%s/map_%d.png" % [_outdir, _n])
		print("SHOT ", _n)
	_n += 1
	if _n >= _strips.size():
		quit()
		return false
	var p := String(_strips[_n]).split(":")
	var x0 := float(p[0]) * 32.0
	var x1 := float(p[1]) * 32.0
	_cam.position = Vector2((x0 + x1) * 0.5, 640.0)
	return false
