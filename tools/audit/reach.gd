## Measures the cat's real jump reach with the real Cat scene on a synthetic
## flat world, so pits and walls are sized against the actual arcs.
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/reach.gd
##
## Gap: the cat runs at a ledge, jumps from the last pixel it can (the collider
## still overlaps the ledge up to half its width past the edge), optionally
## double-jumps at the best moment, and the landing x is where its feet cross
## the takeoff height. A gap of G px is crossable when travel >= G - width.
## Height: the cat jumps (and double-jumps) next to a wall; the highest feet
## position reached is reported.
extends SceneTree

const FLOOR_Y := 400.0
const EDGE_X := 600.0

var world: Node2D
var cat: CharacterBody2D


func gs() -> Node:
	return root.get_node("GameState")


func _initialize() -> void:
	_run.call_deferred()


func _make_world(with_wall := false, wall_x := 0.0) -> void:
	if world:
		world.queue_free()
	world = Node2D.new()
	root.add_child(world)
	var sb := StaticBody2D.new()
	sb.collision_layer = 1
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(EDGE_X + 200.0, 200.0)
	cs.shape = r
	cs.position = Vector2((EDGE_X - 200.0) * 0.5 + 0.0, FLOOR_Y + 100.0)
	sb.add_child(cs)
	world.add_child(sb)
	# Floor spans x in [-300, EDGE_X] (centre (EDGE_X-200)/2 = 200, half width 400).
	if with_wall:
		var w := StaticBody2D.new()
		w.collision_layer = 1
		var wc := CollisionShape2D.new()
		var wr := RectangleShape2D.new()
		wr.size = Vector2(40.0, 1200.0)
		wc.shape = wr
		wc.position = Vector2(wall_x + 20.0, FLOOR_Y - 600.0)
		w.add_child(wc)
		world.add_child(w)
	cat = load("res://scenes/player/cat.tscn").instantiate()
	world.add_child(cat)
	cat.death_y = 100000.0
	cat.global_position = Vector2(100.0, FLOOR_Y)


func _hold(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _gap_run(power: int, double_jump: bool, dj_delay: int, dx_past_edge: float) -> float:
	_make_world()
	gs().clear_power()
	if power != 0:
		gs().grant_power(power, 999.0)
	await _frames(3)
	Input.action_release("jump")
	_hold("move_right", true)
	# Run until the cat's centre is dx_past_edge past the edge, then jump.
	while cat.global_position.x < EDGE_X + dx_past_edge:
		await physics_frame
	var x0 := cat.global_position.x
	_hold("jump", true)
	await physics_frame
	var t := 0
	var dj_done := false
	var landed_x := -1.0
	var was_air := false
	while t < 240:
		await physics_frame
		t += 1
		if t > 3:
			_hold("jump", true if not dj_done else true)
		if double_jump and not dj_done and t == dj_delay:
			Input.action_release("jump")
			await physics_frame
			_hold("jump", true)
			dj_done = true
		if cat.global_position.y >= FLOOR_Y and t > 10 and cat.velocity.y > 0.0:
			landed_x = cat.global_position.x
			break
	_hold("move_right", false)
	_hold("jump", false)
	return (landed_x - x0) if landed_x > 0.0 else -1.0


func _best_gap(power: int, double_jump: bool) -> Array:
	var best := 0.0
	var best_dj := 0
	var delays := range(8, 60, 2) if double_jump else [0]
	for d in delays:
		var travel: float = await _gap_run(power, double_jump, d, 8.0)
		if travel > best:
			best = travel
			best_dj = d
	return [best, best_dj]


func _height(power: int, double_jump: bool) -> float:
	## Highest rise above the floor (px) with a jump and optional double jump.
	_make_world()
	gs().clear_power()
	if power != 0:
		gs().grant_power(power, 999.0)
	await _frames(3)
	var apex := 0.0
	var best := 0.0
	for d in ([0] if not double_jump else range(10, 50, 2)):
		_make_world()
		if power != 0:
			gs().grant_power(power, 999.0)
		await _frames(3)
		_hold("jump", true)
		var t := 0
		var rise := 0.0
		var dj := false
		while t < 200:
			await physics_frame
			t += 1
			rise = maxf(rise, FLOOR_Y - cat.global_position.y)
			if double_jump and not dj and t == d:
				Input.action_release("jump")
				await physics_frame
				_hold("jump", true)
				dj = true
			if t > 10 and cat.global_position.y >= FLOOR_Y:
				break
		_hold("jump", false)
		best = maxf(best, rise)
	return best


func _run() -> void:
	var pw := {"none": 0, "surge": 1, "spring": 2}
	print("== horizontal reach (centre travel from takeoff to landing, px)")
	for name in pw:
		var single: Array = await _best_gap(pw[name], false)
		var dbl: Array = await _best_gap(pw[name], true)
		print("%-7s single %.0f px   double %.0f px (double jump at frame %d)" % [name, single[0], dbl[0], dbl[1]])
	print("== height (px above takeoff)")
	for name in ["none", "spring"]:
		var s: float = await _height(pw[name], false)
		var d: float = await _height(pw[name], true)
		print("%-7s single %.1f px (%.2f tiles)   double %.1f px (%.2f tiles)" % [name, s, s / 32.0, d, d / 32.0])
	quit()
