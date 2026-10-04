## Render harness (needs a display or xvfb): xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 --script res://tools/audit/shoot.gd -- <scene> <outprefix> <frames,comma> [calls]
## calls: "frame:node_path:method[:arg]" separated by ';'
extends SceneTree

var _frames: Array = []
var _prefix := ""
var _calls: Array = []
var _n := 0
var _scene: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0]
	_prefix = args[1]
	for f in args[2].split(","):
		_frames.append(int(f))
	if args.size() > 3 and args[3] != "":
		for c in args[3].split(";"):
			_calls.append(c.split(":"))
	var sz := OS.get_environment("SHOOT_SIZE")
	if sz != "":
		var parts := sz.split("x")
		root.content_scale_size = Vector2i(int(parts[0]), int(parts[1]))
	_scene = load(scene_path).instantiate()
	root.add_child(_scene)
	current_scene = _scene

func _process(_d: float) -> bool:
	_n += 1
	for c in _calls:
		if int(c[0]) == _n:
			var node := _scene.get_node(c[1]) if c[1] != "." else _scene
			var a := []
			for i in range(3, c.size()):
				a.append(str_to_var(c[i]))
			node.callv(c[2], a)
	if _n in _frames:
		var img := root.get_texture().get_image()
		img.save_png("%s_%04d.png" % [_prefix, _n])
		print("SHOT ", _n)
	if _n >= _frames.max():
		quit()
	return false
