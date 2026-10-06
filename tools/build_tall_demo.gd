## Generates res://scenes/levels/tall_demo.tscn: a minimal TALL room (20 x 34 tiles, 640 x 1088
## px, three screens high) that shows the level framework: camera_follow = TIERS, a vertical
## stair of one-way girders, a basement under the floor, a CameraZone that locks the top screen,
## NightBackdrop.extend_vertically and a camera-following RainFX. It is a template for the
## redesigns and the fixture for tools/audit/camera_audit.gd. Run:
##   godot --headless --path . res://tools/build_runner.tscn -- --builder=res://tools/build_tall_demo.gd
## See docs/LEVELS.md.
extends RefCounted

const T := 32
const COLS := 20
const ROWS := 34
const G := 30          ## ground surface row (y = 960); rows 31-33 are the basement floor

const STEEL := 0
const BULKHEAD := 1
const FLAT := Vector2i(4, 3)
const BEVEL := Vector2i(0, 2)
const GIRDER_H := Vector2i(13, 4)

var errors := 0
var room: Node2D
var tiles: TileMapLayer


func build() -> void:
	room = Node2D.new()
	room.name = "TallDemo"
	room.set_script(load("res://scripts/systems/level.gd"))
	# The camera rectangle is the room's tile bounds.
	room.set("limits", Rect2i(0, 0, COLS * T, ROWS * T))
	room.set("camera_follow", Level.CameraFollow.TIERS)

	var sky := ColorRect.new()
	sky.name = "SkyFill"
	sky.color = Color("0c1030")
	sky.position = Vector2(-64, -64)
	sky.size = Vector2(COLS * T + 128, ROWS * T + 128)
	_own(sky)

	var backdrop := NightBackdrop.new()
	backdrop.name = "Exterior"
	backdrop.position = Vector2(0, G * T)
	backdrop.extend_vertically = true
	_own(backdrop)

	tiles = TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	_own(tiles)
	_geometry()

	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = Vector2(3 * T + 16, G * T)
	_own(start)

	var cp: Node2D = load("res://scenes/actors/checkpoint.tscn").instantiate()
	cp.name = "CheckpointA"
	cp.set("checkpoint_id", "cp_a")
	cp.position = Vector2(9 * T + 16, G * T)
	_own(cp)

	# The top screen (rows 0-11) is a locked single-screen frame.
	var zone := CameraZone.new()
	zone.name = "TopScreenLock"
	zone.position = Vector2(0, 0)
	zone.size = Vector2(COLS * T, 12 * T)
	zone.lock_framing = true
	_own(zone)

	var cat: Node = load("res://scenes/player/cat.tscn").instantiate()
	cat.name = "Cat"
	_own(cat)

	var rain := RainFX.new()
	rain.name = "Rain"
	rain.follow_camera = true
	rain.density = 40.0
	_own(rain)

	var rig := LightingRig.new()
	rig.name = "LightingRig"
	rig.night_tint = Color(0.38, 0.42, 0.60)
	var solid: Array[TileMapLayer] = [tiles]
	rig.solid_layers = solid
	_own(rig)

	_save(room, "res://scenes/levels/tall_demo.tscn")


func _geometry() -> void:
	for x in range(0, COLS):
		_cell(x, G, STEEL, BEVEL)
		for y in range(G + 1, ROWS):
			_cell(x, y, BULKHEAD, FLAT)
		_cell(x, 0, BULKHEAD, FLAT)
	for y in range(0, ROWS):
		_cell(-1, y, BULKHEAD, FLAT)
		_cell(COLS, y, BULKHEAD, FLAT)
	# A stair of one-way girders every 2 rows (inside a plain jump), left then right.
	var i := 0
	var row := G - 2
	while row >= 4:
		var x0 := 1 if i % 2 == 0 else 8
		for x in range(x0, x0 + 11):
			_cell(x, row, STEEL, GIRDER_H)
		row -= 2
		i += 1


func _cell(x: int, y: int, mat: int, tile: Vector2i) -> void:
	tiles.set_cell(Vector2i(x, y), 0, Vector2i(tile.x, tile.y + mat * 10))


func _own(n: Node) -> Node:
	room.add_child(n)
	n.owner = room
	return n


func _save(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	var e1 := packed.pack(root)
	var e2 := ResourceSaver.save(packed, path) if e1 == OK else e1
	print("save ", path, ": ", e2)
	errors += 0 if e2 == OK else 1
