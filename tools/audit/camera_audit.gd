## Camera and tall-room audit: the level framework (scripts/systems/level.gd, level_camera.gd,
## camera_zone.gd) on the tall demo room (scenes/levels/tall_demo.tscn, three screens high),
## plus a check that the 360 px rooms keep the old centred camera untouched.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/camera_audit.gd
## Checks: limits come from the room bounds; a plain hop does not scroll the view; a long
## fall keeps the cat on screen, looks ahead, moves smoothly, lands settled within the rest band;
## the view centre is whole pixels at every frame; a locking CameraZone holds the screen and
## releases it; a CineZoom-style limit lift leaves the camera alone and the driver resumes;
## rooms 1-4, home and the test room are not driven (managed == false, offset unchanged).
## Exit code 1 if a check fails. Deletes user://save.json.
extends SceneTree

var results: Array = []
var room: Node2D
var cat


func _initialize() -> void:
	_main.call_deferred()


func note(label: String, ok: bool, detail := "") -> void:
	results.append([label, ok, detail])
	print("%s  %-70s %s" % ["PASS" if ok else "FAIL", label, detail])


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func centre() -> Vector2:
	return cat.camera.get_screen_center_position()


func place(p: Vector2) -> void:
	cat.global_position = p
	cat.velocity = Vector2.ZERO


func load_room(path: String) -> void:
	if room != null and is_instance_valid(room):
		room.free()
	root.get_node("SaveSystem").delete_save()
	root.get_node("GameState").new_game()
	room = load(path).instantiate()
	root.add_child(room)
	cat = room.get_node("Cat")  # untyped: --script mode cannot compile autoload-using classes
	await ticks(5)


func _main() -> void:
	print("viewport ", root.get_visible_rect().size)
	await load_room("res://scenes/levels/tall_demo.tscn")
	var rig = room.camera_rig
	note("tall room: the driver is active", rig != null and rig.managed)
	note("tall room: limits are the tile bounds", room.limits == Rect2i(0, 0, 640, 1088), str(room.limits))
	note("tall room: the cat dies below the room", cat.death_y > 1088.0, str(cat.death_y))

	# A plain hop on the floor does not scroll.
	place(Vector2(15 * 32 + 16, 30 * 32))   # clear of the girders overhead
	await ticks(90)
	var y0 := centre().y
	var worst := 0.0
	for i in 90:
		if i == 10:
			Input.action_press("jump")
		if i == 20:
			Input.action_release("jump")
		await physics_frame
		worst = maxf(worst, absf(centre().y - y0))
	note("a plain jump does not scroll the view", worst == 0.0, "max shift %.1f px" % worst)

	# A long fall from the top of the shaft: the cat stays on screen, the view moves smoothly.
	room.zone_ease_px = 12.0
	place(Vector2(13 * 32, 14 * 32))   # standing on the row-14 girder
	await ticks(150)
	place(Vector2(19 * 32 + 16, 14 * 32))   # one step off its end: a 16-row fall
	var prev := centre().y
	var max_step := 0.0
	var min_margin := 999.0
	var max_look := 0.0
	var whole := true
	for i in 240:
		await physics_frame
		var c := centre()
		max_step = maxf(max_step, absf(c.y - prev))
		prev = c.y
		whole = whole and is_equal_approx(c.y, roundf(c.y))
		var sy: float = cat.global_position.y - (c.y - 180.0)   # the cat's screen y
		min_margin = minf(min_margin, minf(sy, 360.0 - sy))
		max_look = maxf(max_look, sy)
		if cat.is_on_floor() and i > 20:
			break
	note("a long fall keeps the cat on screen", min_margin > 12.0, "min edge margin %.0f px" % min_margin)
	note("the view moves smoothly (at most 24 px a frame)", max_step <= 24.0, "max step %.1f px" % max_step)
	note("the view centre is whole pixels every frame", whole)
	note("a fall looks ahead (the cat never sinks below screen y 300)", max_look < 300.0, "lowest screen y %.0f" % max_look)
	await ticks(240)
	var settle: float = absf((cat.global_position.y - 25.0) - centre().y)
	note("standing on the new tier the view settles within the rest band", settle <= 17.0 or centre().y >= 907.5, "%.1f px off (the view may sit at the room floor)" % settle)

	# The lock zone: the top screen is held still.
	place(Vector2(10 * 32 + 16, 8 * 32))
	await ticks(120)
	var lc := centre()
	note("a locking CameraZone holds the frame on its centre", lc.distance_to(Vector2(320, 192)) < 2.0, str(lc))
	place(Vector2(3 * 32 + 16, 6 * 32))
	await ticks(30)
	note("the locked frame does not follow the cat", centre().distance_to(lc) < 1.5, str(centre()))
	place(Vector2(3 * 32 + 16, 20 * 32))   # out of the zone
	await ticks(90)
	var released := centre()
	note("leaving the zone releases the camera", released.y > 300.0 and absf(released.y - (cat.global_position.y - 25.0)) < 90.0, str(released))

	# CineZoom lifts the limits and restores them: the driver stays out of the way.
	var cam = cat.camera
	var saved = [cam.limit_left, cam.limit_top, cam.limit_right, cam.limit_bottom]
	var off = cam.offset
	cam.limit_top = -10000000
	cam.limit_bottom = 10000000
	await ticks(30)
	note("a lifted-limit cutscene keeps its camera offset", cam.offset == off, str(cam.offset))
	cam.limit_top = saved[1]
	cam.limit_bottom = saved[3]
	await ticks(60)
	note("the driver resumes after the cutscene", cam.limit_top == saved[1] and absf(centre().y - (cat.global_position.y - 25.0)) < 90.0, str(centre()))

	# A camera shake (a pound, an explosion) must not freeze the tier camera: ScreenShake restores a base offset
	# every frame, and the driver keeps that base on its own view.
	await load_room("res://scenes/levels/tall_demo.tscn")
	place(Vector2(3 * 32 + 16, 30 * 32))
	await ticks(60)
	ScreenShake.shake_at(room, 0.6, 0.3)
	await ticks(40)
	var y_before := centre().y
	place(Vector2(3 * 32 + 16, 20 * 32))
	await ticks(150)
	note("after a camera shake the tier camera still follows the cat", absf(centre().y - y_before) > 100.0 and absf(centre().y - (cat.global_position.y - 25.0)) < 60.0, "view y %.0f -> %.0f, cat y %.0f" % [y_before, centre().y, cat.global_position.y])

	# The rooms that keep the old centred camera are untouched; a redesigned tall room (TIERS) is driven.
	for id in ["room1", "room2", "room3", "room4", "home", "test_room"]:
		await load_room("res://scenes/levels/%s.tscn" % id)
		await ticks(30)
		var r = room.camera_rig
		if room.get("camera_follow") == 1:
			note("%s: a tall room, the tier driver is active, limits are the tile rect" % id, r.managed and room.limits.position == Vector2i.ZERO, "managed %s limits %s" % [r.managed, room.limits])
		else:
			note("%s: camera driver idle, vertical offset unchanged" % id, not r.managed and cat.camera.offset.y == -25.0, "managed %s offset %s" % [r.managed, cat.camera.offset])
	_finish()


func _finish() -> void:
	var ok_all := true
	for r in results:
		ok_all = ok_all and r[1]
	print("== %d checks, %s" % [results.size(), "ALL PASS" if ok_all else "FAILURES"])
	root.get_node("SaveSystem").delete_save()
	quit(0 if ok_all else 1)
