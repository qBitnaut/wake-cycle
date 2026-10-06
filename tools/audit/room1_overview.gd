## Renders the whole of Room 1 (the tall warehouse) as one zoomed-out picture (full.png), plus
## windows of it at a larger scale (part1..part6.png). Needs a display or xvfb. Not a test: a way
## to look at the level.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1920x576 \
##     --script res://tools/audit/room1_overview.gd -- <outdir>
## A free Camera2D replaces the cat's, zoomed to fit the 4256 x 1152 px room in the window.
extends SceneTree

const ROOM := Vector2(4256, 1152)

var _out := "/tmp/room1_overview"
var _cam: Camera2D
var _frame := 0
var _step := -1
var _shots: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	DirAccess.make_dir_recursive_absolute(_out)
	_start.call_deferred()


func _start() -> void:
	root.get_node("SaveSystem").delete_save()
	root.get_node("GameState").new_game()
	root.get_node("GameState").awaken_mind()
	var room: Node = load("res://scenes/levels/room1.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	var cat: Node2D = room.get_node("Cat")
	cat.visible = false
	cat.set_physics_process(false)
	cat.global_position = Vector2(-5000, -5000)
	var rig = room.get("camera_rig")
	if rig != null:
		rig.set_physics_process(false)
	cat.camera.enabled = false
	_cam = Camera2D.new()
	room.add_child(_cam)
	_cam.enabled = true
	_cam.make_current()
	var win := Vector2(root.get_visible_rect().size)
	# [name, zoom, centre]: the whole room, then six windows of 1/3 x 1/2 of it (a 3 x 2 grid).
	var zfull := minf(win.x / ROOM.x, win.y / ROOM.y)
	_shots.append(["full", zfull, ROOM / 2.0])
	var wv := Vector2(ROOM.x / 3.0, ROOM.y / 2.0)
	var zpart := minf(win.x / wv.x, win.y / wv.y)
	var k := 1
	for row in 2:
		for col in 3:
			_shots.append(["part%d" % k, zpart, Vector2(wv.x * (col + 0.5), wv.y * (row + 0.5))])
			k += 1
	_step = 0
	_apply()


func _apply() -> void:
	_cam.zoom = Vector2(_shots[_step][1], _shots[_step][1])
	_cam.position = _shots[_step][2]
	_frame = 0


func _process(_d: float) -> bool:
	if _step < 0:
		return false
	_frame += 1
	if _frame < 8:
		return false
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, _shots[_step][0]])
	print("SHOT ", _shots[_step][0])
	_step += 1
	if _step >= _shots.size():
		quit()
		return false
	_apply()
	return false
