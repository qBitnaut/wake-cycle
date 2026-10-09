## Renders the old single-item YardFence (tools/audit/_fence_old.gd) and the chunked one with the
## room's parameters, at several camera offsets, and compares the pixels.
##   godot --path . --script res://tools/audit/fence_diff.gd
extends SceneTree

const Old := preload("res://tools/audit/_fence_old.gd")
const CASES := [
	# [name, length, height, gaps]
	["room2", 6784.0, 144.0, [Vector2(6560, 6720)]],
	["room4", 11104.0, 176.0, []],
	["gapcase", 2000.0, 144.0, [Vector2(900, 1060)]],
	["exact", 1152.0, 144.0, []],
]
var _bad := 0


func _initialize() -> void:
	_run.call_deferred()


func _make(old: bool, c: Array) -> Node2D:
	var f: Node2D = (Old if old else YardFence).new()
	f.length = c[1]
	f.fence_height = c[2]
	var g: Array[Vector2] = []
	for v in c[3]:
		g.append(v)
	f.gaps = g
	f.self_modulate = Color(0.8, 0.84, 0.9)
	f.z_index = -3
	return f


func _shot(old: bool, c: Array, cam_x: float) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.2)
	bg.size = Vector2(640, 360)
	bg.z_index = -10
	vp.add_child(bg)
	var w := Node2D.new()
	w.position = Vector2(-cam_x, 300)
	vp.add_child(w)
	w.add_child(_make(old, c))
	await process_frame
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


func _run() -> void:
	for c in CASES:
		var len: float = c[1]
		var xs := [0.0, 300.0, 575.0, 576.0, 577.0, 1100.0, len * 0.5, len - 640.0, len - 300.0]
		if c[0] == "gapcase":
			xs.append_array([600.0, 700.0])
		for cx in xs:
			var a: Image = await _shot(true, c, cx)
			var b: Image = await _shot(false, c, cx)
			var same := a.get_data() == b.get_data()
			if not same:
				_bad += 1
				var n := 0
				for y in 360:
					for x in 640:
						if a.get_pixel(x, y) != b.get_pixel(x, y):
							n += 1
				print("DIFF ", c[0], " cam ", cx, " pixels ", n)
			else:
				var ink := 0
				var bgc := b.get_pixel(0, 0)
				for y in range(0, 360, 2):
					for x in range(0, 640, 2):
						if b.get_pixel(x, y) != bgc:
							ink += 1
				print("same ", c[0], " cam ", cx, " (non-background samples ", ink, ")")
	print("RESULT bad=", _bad)
	quit(1 if _bad else 0)
