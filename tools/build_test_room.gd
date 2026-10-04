## Generates res://scenes/levels/test_room.tscn (geometry on the warehouse TileSet
## plus every actor from scenes/actors). Run:
##   godot --headless --path . --script res://tools/build_test_room.gd
extends SceneTree

const T := 18
const G := 12  # ground surface row
const ROWS := 16
const COLS := 151

var room: Node2D
var tiles: TileMapLayer
var gaps := {}  # columns with no ground


func _initialize() -> void:
	room = Node2D.new()
	room.name = "TestRoom"
	room.set_script(load("res://scripts/systems/test_room.gd"))
	room.set("limits", Rect2i(0, 0, COLS * T, ROWS * T))

	var bg := CanvasLayer.new()
	bg.name = "Background"
	bg.set_script(load("res://scripts/systems/parallax_bg.gd"))
	_own(bg)

	tiles = TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = load("res://assets/tiles/warehouse_tileset.tres")
	_own(tiles)
	_build_geometry()

	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = _p(2, G)
	_own(start)

	# --- Section A: wake-up, continue pad, checkpoint ---
	_put("res://scenes/actors/continue_pad.tscn", "ContinuePad", 5, G)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointA", 9, G, {"checkpoint_id": "cp_a"})
	_put("res://scenes/actors/gem.tscn", "GemA1", 13, G - 2)
	_put("res://scenes/actors/gem.tscn", "GemA2", 14, G - 3)
	# --- B: double jump over the pit, shockwave unlock, crate corridor ---
	_put("res://scenes/actors/gem.tscn", "GemPit", 19, G - 4)
	_put("res://scenes/actors/pad.tscn", "PadShockwave", 24, G, {"power": 99})
	_put("res://scenes/actors/letter.tscn", "LetterC", 26, G - 3, {"letter_index": 0})
	for i in 3:
		_put("res://scenes/actors/crate_breakable.tscn", "CrateStack%d" % i, 32, G - i,
			{"drop": 1 if i == 2 else (2 if i == 1 else 0)})
	# --- C: surge pad, wide pit ---
	_put("res://scenes/actors/pad.tscn", "PadSurge", 38, G, {"power": 1})
	_put("res://scenes/actors/gem.tscn", "GemWide", 45, G - 4)
	# --- D: spring pad and the tall wall ---
	_put("res://scenes/actors/pad.tscn", "PadSpring", 52, G, {"power": 2})
	_put("res://scenes/actors/gem.tscn", "GemTop", 57, G - 7)
	# --- E: crawl tunnel ---
	_put("res://scenes/actors/letter.tscn", "LetterA", 66, G, {"letter_index": 1})
	_put("res://scenes/actors/fish.tscn", "FishTunnel", 68, G)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointB", 71, G, {"checkpoint_id": "cp_b"})
	# --- F: push the crate onto the plate to switch off the fence ---
	_put("res://scenes/actors/crate_pushable.tscn", "PushCrate", 74, G)
	_put("res://scenes/actors/floor_plate.tscn", "PlateA", 79, G)
	_put("res://scenes/actors/laser_fence.tscn", "FenceA", 84, G,
		{"height_tiles": 3, "timed": false, "controller": NodePath("../PlateA")})
	# --- G: shock switch + timed fence ---
	_put("res://scenes/actors/laser_fence.tscn", "FenceTimed", 90, G,
		{"height_tiles": 3, "timed": true, "on_time": 1.4, "off_time": 1.8})
	_put("res://scenes/actors/shock_switch.tscn", "SwitchA", 95, G - 1, {"auto_off": 6.0, "_dy": -9.0})
	_put("res://scenes/actors/laser_fence.tscn", "FenceB", 99, G,
		{"height_tiles": 3, "timed": false, "controller": NodePath("../SwitchA")})
	# --- H: phase pad + dash through a timed fence, then key and door ---
	_put("res://scenes/actors/pad.tscn", "PadPhase", 103, G, {"power": 3})
	_put("res://scenes/actors/laser_fence.tscn", "FenceDash", 108, G,
		{"height_tiles": 3, "timed": true, "on_time": 2.0, "off_time": 0.6})
	_put("res://scenes/actors/key.tscn", "KeyRed", 113, G - 3, {"key_color": "red"})
	_put("res://scenes/actors/locked_door.tscn", "DoorRed", 120, G, {"key_color": "red"})
	# --- I: bot, spikes, impact pad, cracked floor over the T chamber ---
	_put("res://scenes/actors/patrol_bot.tscn", "Bot", 126, G)
	_put("res://scenes/actors/spikes.tscn", "Spikes1", 134, G)
	_put("res://scenes/actors/spikes.tscn", "Spikes2", 135, G)
	_put("res://scenes/actors/pad.tscn", "PadImpact", 138, G, {"power": 4})
	_put("res://scenes/actors/cracked_floor.tscn", "Cracked1", 142, G)
	_put("res://scenes/actors/cracked_floor.tscn", "Cracked2", 143, G)
	_put("res://scenes/actors/letter.tscn", "LetterT", 142, G + 3, {"letter_index": 2})
	_put("res://scenes/actors/fish.tscn", "FishChamber", 143, G + 3)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointC", 148, G, {"checkpoint_id": "cp_c"})

	# Low beam for the crawl tunnel (10 px gap above the floor).
	var beam := StaticBody2D.new()
	beam.name = "LowBeam"
	beam.position = Vector2(66 * T, (G - 1) * T)
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(4 * T, 8)
	shape.shape = rs
	shape.name = "Shape"
	shape.position = Vector2(0, 4)
	beam.add_child(shape)
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/tiles/kenney-metal-expansion/tilemap_packed.png")
	spr.region_enabled = true
	spr.region_rect = Rect2(18, 72, 18, 8)
	# Stretch the plate across the beam by tiling four sprites.
	for i in 4:
		var s := spr.duplicate()
		s.position = Vector2(-1.5 * T + i * T, 4)
		s.name = "Plate%d" % i
		beam.add_child(s)
	_own(beam)
	for c in beam.get_children():
		c.owner = room

	var cat: Node = load("res://scenes/player/cat.tscn").instantiate()
	cat.name = "Cat"
	_own(cat)
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	_own(hud)

	var packed := PackedScene.new()
	print("pack: ", packed.pack(room))
	print("save: ", ResourceSaver.save(packed, "res://scenes/levels/test_room.tscn"))
	quit()


func _p(cx: int, cy: int) -> Vector2:
	## Bottom-centre of cell (cx, cy-1) i.e. standing on the top edge of row cy.
	return Vector2(cx * T + T / 2.0, cy * T)


func _own(n: Node) -> Node:
	room.add_child(n)
	n.owner = room
	return n


func _put(path: String, node_name: String, cx: int, cy: int, props := {}) -> Node:
	var n: Node2D = load(path).instantiate()
	n.name = node_name
	for k in props:
		if k != "_dy":
			n.set(k, props[k])
	n.position = _p(cx, cy) + Vector2(0, props.get("_dy", 0.0))
	_own(n)
	return n


func _cell(x: int, y: int, source: int, col: int, row: int) -> void:
	tiles.set_cell(Vector2i(x, y), source, Vector2i(col, row))


func _ground(x0: int, x1: int) -> void:
	for x in range(x0, x1 + 1):
		var top := 1 + (x % 2)
		if x == x0 or gaps.has(x - 1):
			top = 0
		elif x == x1 or gaps.has(x + 1):
			top = 3
		_cell(x, G, 1, top, 0)
		for y in range(G + 1, ROWS):
			_cell(x, y, 1, 1 + ((x + y) % 3), 2)


func _block(x0: int, x1: int, y0: int, y1: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			_cell(x, y, 2, 1 + ((x + y) % 3), 4)


func _catwalk(x0: int, x1: int, y: int) -> void:
	for x in range(x0, x1 + 1):
		_cell(x, y, 1, 4 + (x % 3), 0)


func _build_geometry() -> void:
	for x in range(17, 22):
		gaps[x] = true
	for x in range(41, 49):
		gaps[x] = true
	_ground(0, 16)
	_ground(22, 40)
	_ground(49, COLS - 2)
	# Chamber under the cracked floor: remove ground rows G (set by crates) and G+1..G+2.
	for x in [142, 143]:
		tiles.erase_cell(Vector2i(x, G))
		tiles.erase_cell(Vector2i(x, G + 1))
		tiles.erase_cell(Vector2i(x, G + 2))
	# Boundary walls.
	_block(-1, -1, 0, ROWS - 1)
	_block(COLS - 1, COLS - 1, 0, ROWS - 1)
	# B: catwalk and the crate corridor (ceiling leaves exactly 3 rows).
	_catwalk(24, 28, G - 3)
	_block(30, 34, 0, G - 4)
	# D: the tall wall (6 high) with a top slab.
	_block(55, 56, G - 6, G - 1)
	_block(55, 58, G - 6, G - 6)
	# E: crawl tunnel ceiling.
	_block(63, 69, 0, G - 2)
	# F/G/H: ceilings over every fence and the door so they cannot be jumped.
	_block(83, 85, 0, G - 4)
	_block(89, 91, 0, G - 4)
	_block(98, 100, 0, G - 4)
	_block(107, 109, 0, G - 4)
	_block(119, 121, 0, G - 3)
	# Switch pillar and the key catwalk.
	_block(95, 95, G - 1, G - 1)
	_catwalk(112, 114, G - 3)
