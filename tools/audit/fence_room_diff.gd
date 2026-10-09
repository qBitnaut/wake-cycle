## The real Room 2 / Room 4 scene rendered with the old YardFence script and with the chunked one
## (same seed, rain and lightning off), pixel compared at a few camera spots, with an old-vs-old
## control for the scene's own noise.
##   godot --path . --fixed-fps 60 --rendering-driver opengl3 --script res://tools/audit/fence_room_diff.gd
extends SceneTree

const Old := preload("res://tools/audit/_fence_old.gd")
const ROOMS := {"room2": [1500.0, 3600.0, 6300.0], "room4": [600.0, 5000.0, 10600.0]}
var _bad := 0


func _initialize() -> void:
	_run.call_deferred()


func _shot(room_id: String, old: bool, x: float) -> Image:
	seed(7)
	root.get_node("GameState").intelligence = true
	var room: Node2D = load("res://scenes/levels/%s.tscn" % room_id).instantiate()
	var fence := room.get_node("Fence")
	if old:
		var props := {"length": fence.length, "fence_height": fence.fence_height, "post_spacing": fence.post_spacing, "mesh_step": fence.mesh_step, "gaps": fence.gaps.duplicate()}
		fence.set_script(Old)
		for k in props:
			fence.set(k, props[k])
	for n in ["RainFar", "RainNear"]:
		var r := room.get_node_or_null(n)
		if r:
			r.queue_free()
	var l := room.get_node_or_null("LightningFX")
	if l:
		l.auto = false
	root.add_child(room)
	current_scene = room
	var cat := room.get_node("Cat")
	cat.global_position = Vector2(x, fence.global_position.y - 40.0)
	cat.velocity = Vector2.ZERO
	for i in 40:
		await process_frame
	var img := root.get_texture().get_image()
	room.queue_free()
	await process_frame
	await process_frame
	return img


func _same(a: Image, b: Image) -> int:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				n += 1
	return n


func _run() -> void:
	for room_id in ROOMS:
		for x in ROOMS[room_id]:
			var o1: Image = await _shot(room_id, true, x)
			var o2: Image = await _shot(room_id, true, x)
			var nw: Image = await _shot(room_id, false, x)
			print(room_id, " x=", x, " old-vs-old control diff px: ", _same(o1, o2), "  old-vs-new diff px: ", _same(o1, nw))
	quit()
