extends SceneTree
func _initialize() -> void:
	_m.call_deferred()
func _m() -> void:
	var gs := root.get_node("GameState")
	gs.new_game(); gs.awaken_mind()
	var room: Node = load("res://scenes/levels/room1.tscn").instantiate()
	root.add_child(room); current_scene = room
	for i in 6: await physics_frame
	var t: TileMapLayer = room.get_node("Tiles")
	for y in range(22, 34):
		var row := ""
		for x in range(56, 70):
			row += "#" if t.get_cell_source_id(Vector2i(x, y)) >= 0 else "."
		print(y, " ", row)
	var cat: CharacterBody2D = room.get_node("Cat")
	for steer in [45]:
		cat.global_position = Vector2(2000, 255); cat.velocity = Vector2.ZERO
		await physics_frame
		Input.action_press("move_right")
		var n := 0
		while cat.global_position.x < 2034: await physics_frame
		Input.action_release("move_right"); Input.action_press("move_left")
		for i in steer: await physics_frame
		Input.action_release("move_left")
		for i in 300:
			await physics_frame
			if i % 6 == 0: print(i, cat.global_position, cat.is_on_floor())
			if cat.is_on_floor() and i > 5: break
		print(steer, " landed ", cat.global_position)
	quit()
