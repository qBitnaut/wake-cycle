## Renders the whole of Room 3 in one image (needs a display or xvfb big enough for the room):
##   xvfb-run -a -s "-screen 0 5600x1600x24" godot --path . --rendering-driver opengl3 \
##     --script res://tools/audit/room3_map.gd -- <out.png>
## The window is made as large as the room (5504 x 1536 px), the content scale is switched off and
## a camera of its own looks at the whole level at 1:1. Not a test: a way to look at the level.
extends SceneTree

var _out := "/tmp/room3_map.png"
var _frame := 0
var _room: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	_start.call_deferred()


func _start() -> void:
	root.get_node("SaveSystem").delete_save()
	root.get_node("GameState").intelligence = true
	_room = load("res://scenes/levels/room3.tscn").instantiate()
	root.add_child(_room)
	current_scene = _room
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(5504, 1536)
	var cam := Camera2D.new()
	cam.position = Vector2(5504, 1536) * 0.5
	_room.add_child(cam)
	cam.make_current()
	var hud := _room.get_node_or_null("Hud")
	if hud:
		hud.visible = false
	for n in ["RainFar", "RainNear"]:
		var r := _room.get_node_or_null(n)
		if r:
			r.visible = false
	_room.get_node("Cat").global_position = Vector2(112, 1408)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 90:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("SAVED ", _out, " ", img.get_size())
		quit()
	return false
