## Generates res://scenes/levels/room4.tscn (Room 4, "The Perimeter"); its exit leads to
## res://scenes/ui/world_map.tscn. Run:
##   godot --headless --path . res://tools/build_runner.tscn -- --builder=res://tools/build_room4.gd
##
## A tall, multi-tier level (docs/LEVELS.md: camera_follow = TIERS): 384 x 40 tiles (12288 x 1280 px,
## about 3.5 screens high). The surface perimeter (fences, guard towers, searchlights, a guardhouse
## and a roof catwalk) lies over a four-level underground network of service ducts, a bunker with
## a security-camera corridor and a flooded cistern. You go DOWN by ground-pounding through floors
## (Impact) and climb back UP through shafts (a ladder of girders; a lift).
##
## Rows (32 px tiles; y = 32 * row is the TOP of the row):
##   0-11   sky and the tops of towers (the surface is row 12, y = 384)
##   13-16  L1 service duct    floor row 17      (clear rows 13-16)
##   18-21  L2 lower duct      floor row 22      (clear rows 18-21)
##   23-26  L3 bunker          floor row 27      (clear rows 23-26)
##   28-34  L4 flooded cistern floor row 35      (clear rows 28-34), rock to row 39
## Reach (tools/audit/reach.gd): a plain jump rises 95 px (3 rows), a plain double jump 171 px (5.3),
## Spring 211 (6.6). Girders are one-way: the cat jumps up through them. Every plain step here is
## 2 rows (64 px) at most.
##
## Beats, west to east (columns):
##   A     0-30    arrival, a guard tower with a climbable interior (10-17)
##   P1   31-52    PHASE 1, discovery: gatehouse corridor, pad (36), one fence (47)
##   P2   53-106   PHASE 2, use: checkpoint A, a corridor of three fences and two guard drones, a turret
##                 (112); the corridor roof (cols 32-112, row 6) is the CATWALK, an optional harder
##                 route (bells, mice) reached from the guardhouse roof by a double jump across 113-117
##   P3  107-134   PHASE 3, combine: Spring pad (115), the guardhouse roof 6 rows up, Phase pad (120), fence (127)
##   I1  135-153   IMPACT 1, discovery: checkpoint B, pad (143), the hatch H1 (147-149), a shut gate (152-153)
##   UC  100-140   the undercroft: a secret duct behind a reinforced wall (col 140), loot and hazards
##   L1  141-173   IMPACT 2, use: service duct (checkpoint C), an armoured bot, hatch H2 (170-172)
##   L2  164-216   IMPACT 3, combine: lower duct (checkpoint D), shield (174, shockwave), fence (182, Phase),
##                 hatch H3 (187-189); beyond it the optional gauntlet and the sealed ARCHIVE (secret)
##   L3  183-237   bunker: checkpoint E, hatch H4 (193-195, to the cistern), the camera corridor, the press,
##                 the shaft S1 (224-237): a girder ladder and a lift up to the plaza
##   L4  190-235   flooded cistern: checkpoint G, acid pools, a falling platform, Phase fences, RELAY 2 (233),
##                 checkpoint H, the lift back up
##   F   238-340   the plaza: checkpoint F, RELAY 1 (a tower, Spring), the vault under the surface (H5 276-278,
##                 the HEAVY MECH, RELAY 3 behind it), the armoury (a blast-only floor, secret), the scanner
##                 (340) and the Master Gate (349-350)
##   G   351-383   the dawn road, exit at 376
## Builder for tools/build_runner.gd (autoloads are live there; --script mode lacks them).
## Rebuilds are deterministic: names are fixed and the runner re-uses the committed
## scene's unique_ids (see build_runner.gd).
extends RefCounted

## Set by _save on a pack or save failure; the runner turns it into the exit code.
var errors := 0


const T := 32
const G := 12          ## surface row (y = 384)
const F1 := 17         ## L1 floor row
const F2 := 22
const F3 := 27
const F4 := 35
const ROWS := 40
const COLS := 384

const STEEL := 0
const BULKHEAD := 1
const RUST := 2
const MAROON := 3
const TEAL := 4
const VIOLET := 5
const HAZARD := 6

const BEVEL := Vector2i(0, 2)
const FRAMED := Vector2i(3, 2)
const CROSS := Vector2i(2, 2)
const FLAT := Vector2i(4, 3)
const RIVET := Vector2i(5, 3)
const GIRDER_V := Vector2i(12, 4)
const GIRDER_H := Vector2i(13, 4)

const START_COL := 3
const GATE_COL := 350      ## the gate straddles cols 349-350
const SCANNER_COL := 340
const EXIT_COL := 376

const SCENE_ROOM := "res://scenes/levels/room4.tscn"
const SCENE_MAP := "res://scenes/ui/world_map.tscn"
const KIT := "res://scenes/kit/"
const ACT := "res://scenes/actors/"

var room: Node2D
var tiles: TileMapLayer
var back_tiles: TileMapLayer
var _mats := {}
var _ledges := {}       ## Vector2i -> material: one-way girders
var _item_n := 0


func build() -> void:
	_build_room4()


# ---- helpers ------------------------------------------------------------------

func _save(root: Node, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var packed := PackedScene.new()
	var e1 := packed.pack(root)
	var e2 := ResourceSaver.save(packed, path) if e1 == OK else e1
	print("save ", path, ": ", e2)
	errors += 0 if e2 == OK else 1


func _p(cx: int, cy: int) -> Vector2:
	## Bottom-centre of cell (cx, cy-1): standing on the top edge of row cy.
	return Vector2(cx * T + T / 2.0, cy * T)


## x of the middle of columns c0..c1 (for an even-width hazard).
func _mid(c0: int, c1: int) -> float:
	return (c0 + c1 + 1) * T / 2.0


func _own(n: Node) -> Node:
	room.add_child(n)
	n.owner = room
	return n


func _own_under(parent: Node, n: Node) -> Node:
	parent.add_child(n)
	n.owner = room
	return n


func _put(path: String, node_name: String, cx: int, cy: int, props := {}) -> Node:
	var n: Node2D = load(path).instantiate()
	n.name = node_name
	for k in props:
		n.set(k, props[k])
	n.position = _p(cx, cy)
	_own(n)
	return n


## A kit actor at an exact world position.
func _kat(scene: String, node_name: String, pos: Vector2, props := {}) -> Node:
	var n: Node2D = load(KIT + scene + ".tscn").instantiate()
	n.name = node_name
	for k in props:
		n.set(k, props[k])
	n.position = pos
	_own(n)
	return n


## A node made from a script (not a scene), standing at (col, row).
func _put_script(path: String, node_name: String, cx: int, cy: int, props := {}) -> Node:
	return _script_node(path, node_name, _p(cx, cy), props)


func _script_node(path: String, node_name: String, pos: Vector2, props := {}) -> Node:
	var n: Node = load(path).new()
	n.name = node_name
	for k in props:
		n.set(k, props[k])
	n.set("position", pos)
	_own(n)
	return n


## A collectible. `col` in tiles (an integer is a tile's middle, 73.5 the line between 73 and 74), `row`
## the surface it floats over, `up` px above that surface. Placed ones are named Gem* so the map counts
## them (fish are Fish*: they heal, they are not collectibles).
func _item(kind: String, node_name: String, col: float, row: int, up := 0.0) -> Node:
	var n: Node2D = load(KIT + "pickup_" + kind + ".tscn").instantiate()
	n.name = ("Fish" if kind == "fish" else "Gem") + node_name
	n.position = Vector2(col * T + T / 2.0, row * T - 10.0 - up)
	_own(n)
	if kind != "fish":
		_item_n += 1
	return n


# ---- tile grid: fill and carve, then style by exposure -----------------------------

func _fill(x0: int, y0: int, x1: int, y1: int, mat: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			_mats[Vector2i(x, y)] = mat


func _clear(x0: int, y0: int, x1: int, y1: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			_mats.erase(Vector2i(x, y))
			_ledges.erase(Vector2i(x, y))


## A one-way girder: the cat jumps up through it and lands on it.
func _ledge(x0: int, x1: int, row: int, mat := STEEL) -> void:
	for x in range(x0, x1 + 1):
		_ledges[Vector2i(x, row)] = mat


func _cell(x: int, y: int, mat: int, tile: Vector2i, layer: TileMapLayer = null) -> void:
	var l := layer if layer else tiles
	l.set_cell(Vector2i(x, y), 0, Vector2i(tile.x, tile.y + mat * 10))


## Every filled cell gets a tile by what it touches: a bevelled top where the cell
## above is open, plain plates elsewhere (one-way girders are only the explicit ledges).
func _paint() -> void:
	for c in _mats:
		var m: int = _mats[c]
		var up_open := not _mats.has(c + Vector2i(0, -1))
		var down_open := not _mats.has(c + Vector2i(0, 1))
		var tile := FLAT if (c.x + c.y) % 2 == 0 else RIVET
		if up_open:
			tile = BEVEL
			if m == MAROON:
				m = STEEL
		elif down_open:
			# (A solid plate, never the one-way girder tile: a girder in a slab's bottom row becomes a
			# walkable slit at a shaft's or tunnel mouth's vertical face.)
			tile = FLAT if (c.x + c.y) % 2 == 0 else RIVET
		elif m == BULKHEAD or m == TEAL or m == RUST:
			tile = FRAMED if (c.x * 3 + c.y) % 7 == 0 else (CROSS if (c.x + c.y * 5) % 11 == 0 else tile)
		_cell(c.x, c.y, m, tile)
	for c in _ledges:
		_cell(c.x, c.y, _ledges[c], GIRDER_H)


# ---- the room -----------------------------------------------------------------

func _build_room4() -> void:
	room = Node2D.new()
	room.name = "Room4"
	room.set_script(load("res://scripts/systems/room4.gd"))
	room.set("limits", Rect2i(0, 0, COLS * T, ROWS * T))
	room.set("camera_follow", Level.CameraFollow.TIERS)
	var w := COLS * T

	var sky := ColorRect.new()
	sky.name = "SkyFill"
	sky.color = Color("0c1030")
	sky.position = Vector2(-64, -300)
	sky.size = Vector2(w + 128, ROWS * T + 500)
	sky.z_index = -10
	_own(sky)

	var exterior := NightBackdrop.new()
	exterior.name = "Exterior"
	exterior.position = Vector2(0, G * T - 70)
	exterior.moon_position = Vector2(-120, -141)
	exterior.extend_vertically = true
	exterior.z_index = -9
	_own(exterior)

	_suburbs()

	# Far side of the perimeter: dim container stacks and guard buildings.
	back_tiles = TileMapLayer.new()
	back_tiles.name = "BackTiles"
	back_tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	back_tiles.collision_enabled = false
	back_tiles.occlusion_enabled = false
	back_tiles.z_index = -4
	back_tiles.self_modulate = Color(0.5, 0.52, 0.62)
	_own(back_tiles)
	_back_decor()

	var fence := YardFence.new()
	fence.name = "Fence"
	fence.position = Vector2(5 * T, G * T)
	fence.length = float((GATE_COL - 9) * T - 5 * T)
	fence.fence_height = 176.0
	fence.z_index = -3
	fence.self_modulate = Color(0.8, 0.84, 0.9)
	_own(fence)

	tiles = TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	_own(tiles)
	_build_geometry()
	_paint()
	_back_walls()

	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = _p(START_COL, G)
	_own(start)

	_actors_surface_west()
	_actors_underground()
	_actors_cistern()
	_actors_plaza()
	_signs()
	_towers()
	_stoppers()
	_puddles()
	_lamps()

	_rain("RainFar", -2, 40.0, 0.0, 60.0)
	_rain("RainNear", 7, 34.0, 0.0, 110.0)

	var exit_area: Area2D = load("res://scripts/systems/room_exit.gd").new()
	exit_area.name = "RoomExit"
	exit_area.set("next_scene", SCENE_MAP)
	exit_area.set("enabled", false)
	exit_area.position = _p(EXIT_COL, G)
	_own(exit_area)

	var cat: Node = load("res://scenes/player/cat.tscn").instantiate()
	cat.name = "Cat"
	_own(cat)

	var rig := LightingRig.new()
	rig.name = "LightingRig"
	rig.night_tint = Color(0.36, 0.40, 0.58)
	rig.moon_angle = 16.0
	rig.moon_energy = 0.85
	rig.glow_intensity = 0.8
	rig.vignette = 0.30
	var solid: Array[TileMapLayer] = [tiles]
	rig.solid_layers = solid
	_own(rig)

	var lightning := LightningFX.new()
	lightning.name = "Lightning"
	lightning.rig = rig
	lightning.backdrop = exterior
	lightning.interval_min = 10.0
	lightning.interval_max = 22.0
	lightning.light_shadows = false
	_own(lightning)

	var sp := SkyProgress.new()
	sp.name = "SkyProgress"
	sp.rig = rig
	sp.backdrop = exterior
	sp.lightning = lightning
	var rains: Array[RainFX] = [room.get_node("RainFar") as RainFX, room.get_node("RainNear") as RainFX]
	sp.rains = rains
	sp.x_from = 6.0 * T
	sp.x_to = float(GATE_COL * T)
	sp.horizon_y = G * T - 70.0
	_own(sp)

	_script_node("res://scripts/systems/perimeter_finale.gd", "Finale", Vector2.ZERO)

	var amb := Ambience.new()
	amb.name = "Ambience"
	amb.bed = "amb_perimeter"
	amb.surface = "step_wet"
	_own(amb)

	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	_own(hud)

	_save(room, SCENE_ROOM)
	print("collectibles placed (gems): ", _item_n)
	if OS.get_environment("R4_MAP") != "":
		_print_map(int(OS.get_environment("R4_MAP")))


## A text sketch of the tile grid (every `step`-th column): # solid, = one-way girder, . open.
func _print_map(step: int) -> void:
	var header := "     "
	for x in range(0, COLS, step * 10):
		header += ("%d" % x).rpad(10 * 1)
	print(header)
	for y in range(0, ROWS):
		var line := "%3d  " % y
		for x in range(0, COLS, step):
			var c := "."
			var best := 0
			for k in range(step):
				var v := Vector2i(x + k, y)
				if _mats.has(v):
					best = 2
				elif _ledges.has(v) and best < 1:
					best = 1
			c = "#" if best == 2 else ("=" if best == 1 else ".")
			line += c
		print(line)


func _rain(node_name: String, z: int, density: float, wind_extra: float, speed_extra: float) -> void:
	var r := RainFX.new()
	r.name = node_name
	r.follow_camera = true
	r.wind = 70.0 + wind_extra
	r.speed = 250.0 + speed_extra
	r.density = density
	r.splash_rate_scale = 0.35
	r.z_index = z
	_own(r)


func _suburbs() -> void:
	var s: Node2D = load("res://scripts/fx/suburb_row.gd").new()
	s.name = "Suburbs"
	s.set("length", 760.0)
	s.set("seed_value", 11)
	s.position = Vector2((GATE_COL + 5) * T, G * T - 14)
	s.z_index = -8
	_own(s)


func _back_decor() -> void:
	## Dim stacks and guardhouse blocks behind the route: [x0, x1, courses, material].
	var defs := [
		[20, 26, 1, TEAL], [36, 41, 2, RUST], [60, 63, 1, MAROON], [98, 106, 1, TEAL], [136, 140, 2, RUST],
		[238, 244, 2, TEAL], [262, 270, 1, MAROON], [305, 312, 2, RUST], [326, 333, 1, TEAL],
	]
	for d in defs:
		for k in range(d[2]):
			for x in range(d[0], d[1] + 1):
				var c: int = 10 + (x - d[0]) % 3
				_cell(x, G - 2 - 2 * k, d[3], Vector2i(c, 5), back_tiles)
				_cell(x, G - 1 - 2 * k, d[3], Vector2i(c, 6), back_tiles)
	# Truss posts under the gatehouse corridors and the catwalk.
	for x in [32, 36, 41, 46, 52, 58, 66, 74, 82, 90, 98, 106, 112]:
		for y in range(G - 4, G):
			_cell(x, y, STEEL, GIRDER_V, back_tiles)
	# The gatehouse behind the Master Gate: panelled walls under the lintel.
	for x in range(GATE_COL - 6, GATE_COL + 6):
		if x == GATE_COL - 1 or x == GATE_COL:
			continue  # the passage the door slides in: bare, the dawn shows through
		for y in range(G - 7, G):
			_cell(x, y, MAROON, FLAT if (x + y) % 2 == 0 else RIVET, back_tiles)
	# Pillars behind the guardhouse ceiling.
	for y in range(0, 4):
		_cell(134, y, STEEL, GIRDER_V, back_tiles)
		_cell(125, y, STEEL, GIRDER_V, back_tiles)


func _build_geometry() -> void:
	# Rock everywhere under the surface; rooms are carved out of it.
	_fill(0, G, COLS - 1, ROWS - 1, MAROON)
	for y in range(-4, ROWS):
		_mats[Vector2i(-1, y)] = BULKHEAD
		_mats[Vector2i(COLS, y)] = BULKHEAD

	# A: the guard tower with a climbable interior (a door at the foot, three girders, a roof).
	_fill(10, 5, 10, 9, TEAL)
	_fill(17, 5, 17, 9, TEAL)          # (the east door, rows 10-11, is open: the way on goes through the tower)
	_ledge(11, 13, 10)
	_ledge(14, 16, 8)
	_ledge(11, 13, 6)
	_ledge(10, 17, 4)

	# P1 and P2: the corridors, 4 tiles clear (rows 8-11); their roof is the catwalk (row 6).
	_fill(32, 6, 112, 7, STEEL)
	# P3: the guardhouse (roof 6 rows up: out of a plain double jump, inside a held Spring jump)
	# and the ceiling over its fence (64 px of headroom, as the fence).
	_fill(118, 6, 134, G - 1, TEAL)
	_fill(124, 0, 134, 3, STEEL)
	# The catwalk's west perch (a double jump up from the roof).
	_ledge(33, 35, 3)

	# I1: the pad's ledge, the shut gate wall, the hatch H1.
	_fill(141, G - 2, 145, G - 1, RUST)
	_fill(152, 0, 153, G - 1, BULKHEAD)
	_clear(147, G, 149, G)

	# L1: the service duct (rows 13-16, floor 17). The armoured bot's corridor is 2 tiles clear.
	_clear(141, 13, 173, 16)
	_fill(158, 13, 167, 14, STEEL)
	_clear(170, F1, 172, F1)          # hatch H2
	# The undercroft (a secret branch under the vestibule): a long duct west of the alcove, behind a reinforced wall (col 140).
	_clear(100, 13, 140, 16)
	# L2: the lower duct (rows 18-21, floor 22), the gauntlet to the archive wall (col 207) and the archive.
	_clear(164, 18, 216, 21)
	_clear(187, F2, 189, F2)          # hatch H3
	# L3: the bunker (rows 23-26, floor 27).
	_clear(183, 23, 237, 26)
	_clear(193, F3, 195, F3)          # hatch H4
	# The shaft S1, open to the sky: a girder ladder on the left, lifts on the right.
	_fill(223, 0, 223, G - 1, BULKHEAD)
	_clear(224, G, 237, 22)
	_clear(234, F3, 235, F3)
	_ledge(234, 235, F3)              # a one-way cap over the cistern's lift lane: nobody walks off the floor into the shaft
	var rows := [25, 23, 21, 19, 17, 15, 13]
	for i in rows.size():
		if i % 2 == 0:
			_ledge(229, 233, rows[i])
		else:
			_ledge(224, 228, rows[i])
	_ledge(229, 237, 13)              # the top girder runs on to the plaza (one row below the surface)
	# L4: the flooded cistern (rows 28-34, floor 35): entry hall, flooded hall with stones,
	# a low laser tunnel, and the relay chamber with the lift lane.
	_clear(190, 28, 222, 34)
	_fill(206, 34, 210, 34, STEEL)
	_fill(213, 34, 216, 34, STEEL)
	_fill(221, 34, 222, 34, STEEL)
	_ledge(221, 223, 32)
	_ledge(218, 220, 30)
	_clear(223, 31, 230, 34)
	_clear(231, 28, 235, 34)

	# F: relay tower 1 (interior climb: a door, two girders, the relay's roof, Spring from the second).
	_fill(252, 3, 252, 9, TEAL)
	_fill(261, 3, 261, G - 1, TEAL)
	_ledge(253, 256, 10)
	_ledge(257, 260, 8)
	_ledge(249, 264, 2)
	# The vault (rows 13-17, floor 18): the hatch H5 (276-278), the antechamber, the mech's hall, relay 3,
	# and the stair out to the surface.
	_clear(274, 13, 301, 17)
	_clear(276, G, 278, G)
	_clear(302, G, 309, 17)
	_fill(302, 17, 303, 17, STEEL)
	_fill(304, 16, 305, 17, STEEL)
	_fill(306, 15, 307, 17, STEEL)
	_fill(308, 14, 309, 17, STEEL)
	# The armoury (rows 13-16, floor 17): under a blast-only floor (318-320), a stair out east.
	_clear(314, 13, 327, 16)
	_clear(318, G, 320, G)
	_clear(328, G, 333, 16)
	_fill(328, 16, 329, 16, STEEL)
	_fill(330, 15, 331, 16, STEEL)
	_fill(332, 14, 333, 16, STEEL)
	# The gatehouse lintel over the Master Gate.
	_fill(GATE_COL - 6, 0, GATE_COL + 5, G - 8, TEAL)
	# Right end of the road: a bulkhead.
	for y in range(2, G):
		_mats[Vector2i(COLS - 1, y)] = BULKHEAD


func _back_walls() -> void:
	## Panelled back walls behind every carved room so the sky never shows through.
	var defs := [
		["WallTowerA", 11, 5, 6, 7], ["WallL1", 141, 13, 33, 4], ["WallL2", 164, 18, 53, 4],
		["WallL3", 183, 23, 55, 4], ["WallUndercroft", 100, 13, 41, 4], ["WallShaft", 224, 12, 14, 11], ["WallCisternA", 190, 28, 33, 7],
		["WallCisternB", 223, 28, 13, 7], ["WallTowerR1", 253, 3, 8, 9], ["WallVault", 274, 13, 28, 5],
		["WallVaultStair", 302, G, 8, 6], ["WallArmoury", 314, 13, 14, 4], ["WallArmouryStair", 328, G, 6, 5],
	]
	for d in defs:
		var wall := BackWall.new()
		wall.name = d[0]
		wall.position = Vector2(d[1] * T, d[2] * T)
		wall.size = Vector2(d[3] * T, d[4] * T)
		wall.floor_y = d[4] * T
		wall.z_index = -5
		_own(wall)


func _signs() -> void:
	var board := "res://scripts/actors/sign_board.gd"
	var amber := Color(1.0, 0.55, 0.16)
	var aqua := FXPalette.INDICATOR
	_sign(board, "SignPerimeter", 21, G, PackedStringArray(["SECURITY PERIMETER - AUTHORISED UNITS ONLY"]), amber, 30.0)
	_sign(board, "SignGateway", 29, G, PackedStringArray(["CHECKPOINT 7", "PRESENT CREDENTIAL"]), amber, 18.0)
	_sign(board, "PlacardPhase", 34, G, PackedStringArray(["PHASE", "SHIFT: DASH THROUGH BEAMS"]), FXPalette.PHASE, 18.0)
	_sign(board, "PlacardPhase2", 62, G, PackedStringArray(["BEAMS AHEAD", "DASH, DO NOT WALK"]), amber, 18.0)
	_sign(board, "PlacardSpring", 113, G, PackedStringArray(["GUARDHOUSE ROOF", "NO GROUND ROUTE"]), amber, 18.0)
	_sign(board, "PlacardImpact", 135, G, PackedStringArray(["IMPACT", "DOWN IN MID-AIR: GROUND POUND"]), FXPalette.IMPACT, 18.0)
	_sign(board, "SignGateClosed", 150, G, PackedStringArray(["GATE CLOSED", "SERVICE DUCT BELOW"]), amber, 18.0)
	_sign(board, "PlacardArmour", 156, F1, PackedStringArray(["ARMOURED UNIT", "STUN FROM ABOVE"]), amber, 10.0)
	_sign(board, "PlacardShield", 169, F2, PackedStringArray(["SHIELD", "DOUBLE JUMP BURST"]), FXPalette.SHOCKWAVE, 8.0)
	_sign(board, "SignCistern", 185, F3, PackedStringArray(["RELAY 2: CISTERN", "FLOOR HATCH, POUND"]), aqua, 8.0)
	_sign(board, "SignShaft", 222, F3, PackedStringArray(["SHAFT TO SURFACE", "LIFT OR CLIMB"]), amber, 8.0)
	_sign(board, "SignRelays", 244, G, PackedStringArray(["MASTER GATE", "3 RELAYS REQUIRED"]), amber, 22.0)
	_sign(board, "SignRelay1", 249, G, PackedStringArray(["RELAY 1: TOWER"]), aqua, 18.0)
	_sign(board, "SignRelay3", 272, G, PackedStringArray(["RELAY 3: VAULT", "ARMOURED UNIT"]), aqua, 18.0)
	_sign(board, "SignScanner", 341, G, PackedStringArray(["SUPERVISORS ONLY", "SCAN ON APPROACH"]), amber, 18.0)
	_sign(board, "SignRoad", 355, G, PackedStringArray(["SUBURBAN DISTRICT", "2 KM"]), aqua, 22.0)


func _sign(path: String, node_name: String, col: int, row: int, lines: PackedStringArray, accent: Color, legs: float) -> void:
	var s: Node2D = load(path).new()
	s.name = node_name
	s.set("lines", lines)
	s.set("accent", accent)
	s.set("legs", legs)
	s.position = _p(col, row)
	_own(s)


func _towers() -> void:
	## Guard towers behind the route (searchlights): [col, height px, phase].
	var defs := [[28, 210.0, 0.0], [44, 150.0, 2.0], [109, 230.0, 1.0], [145, 200.0, 3.0], [246, 220.0, 0.5],
		[300, 220.0, 2.5], [330, 230.0, 1.5], [345, 200.0, 4.0]]
	var i := 0
	for d in defs:
		var t: Node2D = load("res://scripts/fx/guard_tower.gd").new()
		t.name = "Tower%d" % i
		t.set("tower_height", d[1])
		t.set("phase", d[2])
		t.set("sweep_period", 4.6 + 0.7 * (i % 3))
		t.position = Vector2(d[0] * T + 16, G * T)
		_own(t)
		i += 1


# ---- actors ---------------------------------------------------------------------

func _mono(node_name: String, line_id: String, pos: Vector2, size: Vector2) -> void:
	var t: Area2D = load("res://scripts/actors/monologue_trigger.gd").new()
	t.name = node_name
	t.set("line_id", line_id)
	t.set("require_mind", true)
	t.set("size", size)
	t.position = pos
	_own(t)


func _pad(node_name: String, col: int, row: int, power: int, duration := 12.0) -> Node:
	return _put(ACT + "pad.tscn", node_name, col, row, {"power": power, "duration": duration, "cooldown": 3.0})


func _fence(node_name: String, col: int, row: int, tall: int) -> Node:
	return _put(ACT + "laser_fence.tscn", node_name, col, row, {"height_tiles": tall, "timed": false, "solid_when_on": true})


func _cp(node_name: String, col: int, row: int, id: String) -> Node:
	return _put(ACT + "checkpoint.tscn", node_name, col, row, {"checkpoint_id": id})


func _hatch(prefix: String, c0: int, c1: int, row: int) -> void:
	## Cracked floor tiles (the ground pound breaks them) standing in the floor cells of row `row`.
	for c in range(c0, c1 + 1):
		_put(ACT + "cracked_floor.tscn", "%s%d" % [prefix, c], c, row + 1)


func _drone(node_name: String, col: int, row: int, range_x: float, phase: float) -> void:
	var d: Node2D = load("res://scripts/actors/guard_drone.gd").new()
	d.name = node_name
	d.set("range_x", range_x)
	d.set("bob", 30.0)
	d.set("phase_offset", phase)
	d.position = _p(col, row) + Vector2(0, 12)
	_own(d)


func _turret(node_name: String, col: int, row: int, facing: int, reach: float, offset: float) -> void:
	var t: Node2D = load("res://scripts/actors/laser_turret.gd").new()
	t.name = node_name
	t.set("facing", facing)
	t.set("reach", reach)
	t.set("start_offset", offset)
	t.position = _p(col, row)
	_own(t)


func _actors_surface_west() -> void:
	var bot := ACT + "patrol_bot.tscn"

	# --- A: arrival, and the guard tower's interior ---
	_mono("PerimeterArrival", "perimeter_arrival", Vector2(START_COL * T + 16, G * T), Vector2(224, 96))
	var bot1 := _put(bot, "Bot1", 24, G, {"stomps_to_befriend": 99})
	bot1.set("dir", -1)
	_item("yarn", "YarnA1", 8, G)
	_item("yarn", "YarnA2", 20, G, 20.0)
	_item("yarn", "YarnA3", 27, G)
	_item("yarn", "YarnTA1", 12, 10)
	_item("yarn", "YarnTA3", 12, 6)
	_item("bell", "BellTA", 14, 4)

	# --- P1: Phase discovery. A pad, ten tiles of run-up, one fence; a roof over it. ---
	_pad("PadPhase1", 36, G, 3)
	_fence("FenceP1", 47, G, 4)
	_mono("PhaseFirst", "phase_first", _p(50, G), Vector2(96, 96))
	_item("yarn", "YarnP1a", 41, G)
	_item("yarn", "YarnP1b", 43, G)
	_item("yarn", "YarnP1c", 51, G)

	# --- P2: Phase use. Three fences, two drones, a turret. ---
	_cp("CheckpointA", 55, G, "cp_a")
	_pad("PadPhase2a", 60, G, 3)
	_fence("FenceP2a", 68, G, 4)
	_pad("PadPhase2ab", 71, G, 3)       # between two solid fences: never trapped without Phase
	_fence("FenceP2b", 74, G, 4)
	_pad("PadPhase2b", 78, G, 3)
	_drone("DroneP2a", 84, G - 2, 48.0, 0.0)
	_fence("FenceP2c", 92, G, 4)
	_pad("PadPhase2c", 96, G, 3)
	_drone("DroneP2b", 102, G - 2, 40.0, 1.7)
	_turret("TurretP2", 112, G, -1, 224.0, 0.0)
	_item("yarn", "YarnP2a", 64, G)
	_item("yarn", "YarnP2b", 71, G, 64.0)
	_item("yarn", "YarnP2d", 108, G)

	# --- P3: Spring up the guardhouse, Phase through the fence on the roof. ---
	# The pad stands 3 tiles from the wall face (col 118); the catwalk's end (col 112) is above
	# the corridor, the gap 113-117 above the pad is open sky. The turret (col 112) fires LEFT.
	_mono("SpringHintRoof", "spring_hint_roof", _p(113, G), Vector2(96, 96))
	_pad("PadSpring1", 115, G, 2, 10.0)
	_pad("PadPhase3", 120, 6, 3, 10.0)
	_fence("FenceP3", 127, 6, 2)
	_item("yarn", "YarnP3a", 117, G, 150.0)
	_item("yarn", "YarnP3b", 122, 6)
	_item("yarn", "YarnP3c", 131, 6)

	# --- The catwalk: the optional harder route over the corridors (cols 112 -> 32). The cat gets on it from
	# the guardhouse roof with a plain double jump across the gap. Robots here are avoided, not fought. ---
	_put(KIT + "sentry_turret.tscn", "TurretCat1", 103, 6, {"detect_range": 280.0})
	var cb1 := _put(KIT + "kit_patrol_bot.tscn", "BotCat1", 95, 6, {"speed": 34.0})
	cb1.set("dir", -1)
	_put(KIT + "electric_floor.tscn", "ElecCat1", 81, 6, {"width_tiles": 3, "start_offset": 0.6})
	_kat("spike_trap", "SpikeCat1", Vector2(_mid(73, 74), 6 * T), {"width_tiles": 2, "start_offset": 1.1})
	_kat("hover_drone", "DroneCat1", Vector2(66 * T, 3 * T + 8), {"patrol_range": 96.0})
	_put(KIT + "sentry_turret.tscn", "TurretCat2", 52, 6, {"detect_range": 260.0, "cooldown": 2.6})
	_item("bell", "BellCat1", 111, 6, 56.0)
	_item("yarn", "YarnCat1", 107, 6)
	_item("bell", "BellCat2", 81, 6, 70.0)
	_item("mouse", "MouseCat1", 73.5, 6, 66.0)
	_item("fish", "Cat1", 38, 6)
	_item("mouse", "MouseCat2", 34, 3)

	# --- I1: Impact discovery. ---
	_cp("CheckpointB", 138, G, "cp_b")
	_pad("PadImpact1", 143, G - 2, 4)
	_hatch("HatchH1", 147, 149, G)
	_item("yarn", "YarnI1", 148, G, 90.0)


func _actors_underground() -> void:
	var bot := ACT + "patrol_bot.tscn"

	# --- L1, I2: the first duct. ---
	_mono("PerimeterDepths", "perimeter_depths", _p(151, F1), Vector2(64, 96))
	_mono("ImpactFirst", "impact_first", _p(148, F1), Vector2(96, 96))
	_cp("CheckpointC", 152, F1, "cp_c")
	_pad("PadImpact2", 155, F1, 4)
	var armoured := _put(bot, "BotArmoured", 162, F1, {"shielded": true, "stun_time": 4.0, "speed": 38.0, "stomps_to_befriend": 99})
	armoured.set("dir", -1)
	_pad("PadImpact2b", 168, F1, 4)
	_hatch("HatchH2", 170, 172, F1)
	_item("fish", "L1", 145, F1)
	_item("bell", "BellUCh", 142, F1)   # a glint beside the pound-only wall
	# The undercroft: behind a pound-only wall. An Impact pad in the alcove, then a hazard run west with better loot.
	_pad("PadImpact1b", 144, F1, 4, 14.0)
	_kat("wall_reinforced", "SealUndercroft", Vector2(140 * T + 16, F1 * T), {"size_tiles": Vector2i(1, 4)})
	_kat("spike_trap", "SpikeUC1", Vector2(_mid(135, 136), F1 * T), {"width_tiles": 2})
	_item("bell", "BellUC1", 135.5, F1, 62.0)
	_kat("crawler_bot", "CrawlerUC", Vector2(128 * T + 16, 13 * T), {"crawl_range": 30.0})
	_kat("electric_floor", "ElecUC", Vector2(_mid(121, 122), F1 * T), {"width_tiles": 2, "start_offset": 0.4})
	_item("mouse", "MouseUC1", 121.5, F1, 56.0)
	_cp("CheckpointK", 117, F1, "cp_k")
	_item("fish", "UC", 119, F1)
	_put(KIT + "crusher.tscn", "CrusherUC", 113, 13, {"stroke": 104.0, "start_offset": 0.7})
	_kat("falling_debris", "DebrisUC", Vector2(108 * T + 16, 13 * T))
	_kat("spike_trap", "SpikeUC2", Vector2(_mid(105, 106), F1 * T), {"width_tiles": 2, "start_offset": 1.0})
	_item("bell", "BellUC2", 105.5, F1, 62.0)
	_item("mouse", "MouseUC2", 101, F1)
	_item("bell", "BellUC3", 103, F1)
	_item("yarn", "YarnUC1", 131, F1)
	_item("yarn", "YarnL1a", 143, F1)
	_item("yarn", "YarnL1b", 150, F1)
	_item("yarn", "YarnL1d", 171, F1, 70.0)

	# --- L2, I3: the lower duct. The shield is the shockwave's, the fence Phase's, the hatch Impact's. ---
	_cp("CheckpointD", 166, F2, "cp_d")
	_put_script("res://scripts/actors/shield_panel.gd", "ShieldS1", 174, F2, {"height_tiles": 4})
	_pad("PadPhase4", 177, F2, 3, 10.0)
	_fence("FenceI3", 182, F2, 4)
	_pad("PadImpact3", 184, F2, 4)
	_hatch("HatchH3", 187, 189, F2)
	_item("yarn", "YarnL2a", 179, F2)

	# --- The gauntlet east of H3 (optional): the way to the archive. ---
	_kat("spike_trap", "SpikeL2", Vector2(_mid(192, 193), F2 * T), {"width_tiles": 2})
	_item("bell", "BellL2a", 192.5, F2, 62.0)
	_kat("crawler_bot", "CrawlerL2", Vector2(197 * T + 16, 18 * T), {"crawl_range": 40.0})
	_kat("falling_debris", "DebrisL2", Vector2(200 * T + 16, 18 * T))
	_pad("PadImpact6", 202, F2, 4, 16.0)
	_put(KIT + "crusher.tscn", "CrusherL2", 204, 18, {"stroke": 104.0, "start_offset": 0.9})
	_kat("wall_reinforced", "SealArchive", Vector2(207 * T + 16, F2 * T), {"size_tiles": Vector2i(1, 4)})
	_mono("ArchiveHollow", "perimeter_hollow", _p(205, F2), Vector2(96, 96))
	_item("yarn", "YarnL2c", 195, F2)
	_item("yarn", "YarnL2d", 200, F2)
	_item("bell", "BellL2b", 206, F2)
	# The archive (the hardest secret): the memory fragment.
	_item("memory", "Memory", 212, F2).set("memory_id", "memory_perimeter")
	_item("yarn", "YarnArc1", 209, F2)
	_item("yarn", "YarnArc2", 214, F2)
	_item("yarn", "YarnArc3", 215, F2, 40.0)

	# --- L3: the bunker. ---
	_cp("CheckpointE", 190, F3, "cp_e")
	_pad("PadImpact7", 192, F3, 4, 14.0)
	_hatch("HatchH4", 193, 195, F3)
	# The camera corridor: the camera watches the floor, a dormant turret ahead wakes on the alarm.
	_put(KIT + "security_camera.tscn", "CameraU3a", 200, 23, {"sweep_min": 25.0, "sweep_max": 100.0, "view_range": 250.0, "alarm_time": 5.0, "alarm_radius": 300.0})
	_put(KIT + "sentry_turret.tscn", "TurretU3a", 208, F3, {"dormant": true, "detect_range": 380.0})
	_kat("crawler_bot", "CrawlerU3", Vector2(204 * T + 16, 23 * T), {"crawl_range": 30.0})
	_item("yarn", "YarnL3a", 197, F3)
	_item("yarn", "YarnL3c", 207, F3, 40.0)
	_item("fish", "L3", 211, F3)
	# The press: an electric floor, two crushers, spikes.
	_kat("electric_floor", "ElecU3", Vector2(_mid(212, 213), F3 * T), {"width_tiles": 2, "start_offset": 0.3})
	_item("mouse", "MouseU3", 212.5, F3, 56.0)
	_put(KIT + "crusher.tscn", "CrusherU3a", 216, 23, {"stroke": 104.0})
	_put(KIT + "crusher.tscn", "CrusherU3b", 219, 23, {"stroke": 104.0, "start_offset": 1.2})
	_kat("spike_trap", "SpikeU3", Vector2(_mid(221, 222), F3 * T), {"width_tiles": 2, "start_offset": 0.5})
	_item("bell", "BellU3", 221.5, F3, 66.0)
	_item("yarn", "YarnL3d", 214.5, F3)
	_item("yarn", "YarnL3e", 217.5, F3)
	# The shaft S1: yarn up the ladder, and the lift on the right (it rides 480 px up to the plaza).
	for i in 7:
		var row: int = [25, 23, 21, 19, 17, 15, 13][i]
		var col := 231 if i % 2 == 0 else 226
		if i % 2 == 0:
			_item("yarn", "YarnS1_%d" % i, col, row)
	_kat("platform_vertical", "LiftB", Vector2(237 * T, G * T), {"width_tiles": 2, "travel": float((F3 - G) * T), "speed": 110.0, "pause": 0.8})


func _actors_cistern() -> void:
	# --- L4: the flooded cistern (Relay 2). The hall A is dry; B is flooded; C is a laser tunnel. ---
	_cp("CheckpointG", 191, F4, "cp_g")
	_mono("CisternEnter", "perimeter_cistern", _p(195, F4), Vector2(160, 96))
	_item("fish", "L4", 192, F4)
	# Acid fills the floor between the stones: [first col, last col].
	for pool in [[205, 205], [211, 212], [217, 220]]:
		var c0: int = pool[0]
		var c1: int = pool[1]
		_kat("acid_pool", "Acid%d" % c0, Vector2(_mid(c0, c1), F4 * T), {"width": float((c1 - c0 + 1) * T), "spread_time": 0.0})
	_kat("platform_falling", "FallL4", Vector2(_mid(218, 219), 34 * T), {"width_tiles": 2, "fall_delay": 0.8, "respawn_time": 3.0})
	_item("yarn", "YarnL4c", 208, 34)
	_item("bell", "BellL4a", 222, 32)
	_item("yarn", "YarnL4d", 214.5, 34)
	_item("mouse", "MouseL4", 219, 30)
	_item("yarn", "YarnL4e", 222, 34)
	# The laser tunnel: pad, fence, a pad between, fence, then the relay.
	_pad("PadPhase5a", 223, F4, 3)
	_fence("FenceL4a", 225, F4, 4)
	_pad("PadPhase5b", 227, F4, 3)
	_fence("FenceL4b", 230, F4, 4)
	_cp("CheckpointH", 232, F4, "cp_h")
	_put_script("res://scripts/actors/power_relay.gd", "Relay2", 233, F4, {"index": 2})
	_kat("platform_vertical", "LiftA", Vector2(235 * T, F3 * T), {"width_tiles": 2, "travel": float((F4 - F3) * T), "speed": 70.0, "pause": 0.8})


func _actors_plaza() -> void:
	# --- F: the plaza. ---
	_cp("CheckpointF", 241, G, "cp_f")
	_mono("RelaysIntro", "relays_intro", _p(243, G), Vector2(96, 96))
	_kat("hover_drone", "DronePlaza", Vector2(246 * T, 8 * T), {"patrol_range": 80.0})
	_item("yarn", "YarnF2", 247, G)

	# R1: the tower. A door, a girder, the Spring pad on the second girder, the relay on the roof 6 rows above it.
	_mono("SpringHintTower", "spring_hint_tower", _p(250, G), Vector2(96, 96))
	_pad("PadSpring2", 258, 8, 2, 10.0)
	_put_script("res://scripts/actors/power_relay.gd", "Relay1", 256, 2, {"index": 1})
	_cp("CheckpointL", 263, 2, "cp_l")     # on the relay roof's east end: the way on goes over the tower
	_item("bell", "BellR1", 254, 10)
	_item("yarn", "YarnR1a", 255, G)

	# The way on: a patrolling armed bot, a pad, a fish before the arena, the hatch H5.
	var pb := _put(KIT + "kit_patrol_bot.tscn", "BotPlaza", 266, G, {"speed": 32.0})
	pb.set("dir", -1)
	_item("yarn", "YarnF3", 263, G)
	_pad("PadImpact4", 272, G, 4)
	_item("fish", "Vault", 274, G)
	_hatch("HatchH5", 276, 278, G)

	# R3: the vault. An antechamber (checkpoint, pad, yarn), the mech's hall (stoppers fence it in), the relay behind it.
	_cp("CheckpointI", 275, 18, "cp_i")
	_mono("VaultMech", "perimeter_mech", _p(280, 18), Vector2(96, 96))
	_pad("PadImpact5", 282, 18, 4, 14.0)
	_item("yarn", "YarnV1", 277, 18)
	var mech := _put(KIT + "heavy_mech.tscn", "Mech", 292, 18)
	mech.set("dir", -1)
	_put_script("res://scripts/actors/power_relay.gd", "Relay3", 300, 18, {"index": 3})

	# S-A: the armoury. A barrel stands on a blast-only floor; a turret ahead shoots at the cat, and the
	# bolt sets the barrel off from a safe distance. The pit drops into the armoury and its stair.
	_kat("wall_blast", "SealArmoury", Vector2(_mid(318, 320), (G + 1) * T), {"size_tiles": Vector2i(3, 1)})
	_put(KIT + "barrel_explosive.tscn", "BarrelArmoury", 319, G)
	_put(KIT + "sentry_turret.tscn", "TurretArmoury", 323, G, {"detect_range": 330.0, "cooldown": 3.0})
	_item("yarn", "YarnA4", 311, G)
	_item("bone", "Bone", 322, F1)
	_item("yarn", "YarnArm1", 316, F1)
	_item("yarn", "YarnArm3", 324, F1)
	_put(KIT + "barrel_explosive.tscn", "BarrelArm1", 315, F1)

	# The scanner and the gate.
	var scanner := _script_node("res://scripts/actors/security_scanner.gd", "Scanner", _p(SCANNER_COL, G))
	scanner.set("z_index", 2)
	var gate := _script_node("res://scripts/actors/master_gate.gd", "MasterGate", Vector2(GATE_COL * T, G * T), {"width": 64.0, "height_tiles": 7})
	gate.set("width", 64.0)
	_cp("CheckpointJ", 358, G, "cp_j")
	_mono("PerimeterExit", "perimeter_exit", _p(360, G), Vector2(128, 96))
	for c in [361, 370]:
		_item("yarn", "YarnRoad%d" % c, c, G)
	for c in [344]:
		_item("yarn", "YarnPlaza%d" % c, c, G)


func _stoppers() -> void:
	## Invisible bot walls (physics layer 7): [col, floor row, rows tall].
	var defs := [
		[19, G, 4], [29, G, 4],                       # Bot1
		[94, 6, 4], [99, 6, 4],                       # the catwalk bot (cols 95-98)
		[157, F1, 3], [166, F1, 3],                   # the armoured bot
		[263, G, 4], [270, G, 4],                     # the plaza bot (cols 264-269)
		[283, 18, 5], [297, 18, 5],                   # the mech's hall (cols 284-296)
	]
	for d in defs:
		var sb := StaticBody2D.new()
		sb.name = "Stopper%d_%d" % [d[0], d[1]]
		sb.collision_layer = 64
		sb.collision_mask = 0
		sb.position = Vector2(d[0] * T + T / 2.0, d[1] * T)
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = Vector2(T, d[2] * T)
		cs.shape = r
		cs.position = Vector2(0, -d[2] * T / 2.0)
		cs.name = "Shape"
		sb.add_child(cs)
		_own(sb)
		cs.owner = room


func _puddles() -> void:
	var defs := [
		[4.0, 96.0], [22.0, 128.0], [39.0, 96.0], [56.0, 96.0], [113.0, 64.0], [136.0, 96.0],
		[240.0, 128.0], [262.0, 128.0], [311.0, 96.0], [335.0, 96.0],
	]
	var i := 0
	for d in defs:
		var z := PuddleZone.new()
		z.name = "Puddle%d" % i
		z.width = d[1]
		z.position = Vector2(d[0] * T, G * T)
		_own(z)
		i += 1
	# Rain stops at the gate: fewer puddles beyond it.
	for d in [[354.0, 96.0], [366.0, 128.0]]:
		var z := PuddleZone.new()
		z.name = "PuddleRoad%d" % int(d[0])
		z.width = d[1]
		z.position = Vector2(d[0] * T, G * T)
		_own(z)


func _lamp(node_name: String, x: float, y: float, steady: bool, energy: float, color := FXPalette.SODIUM, shadows := false) -> void:
	var lamp := WarningLight.new()
	lamp.name = node_name
	lamp.art_scale = 1
	lamp.mode = WarningLight.Mode.STEADY if steady else WarningLight.Mode.FLICKER
	lamp.color = color
	lamp.energy = energy
	lamp.light_radius_scale = 3.2
	lamp.halo_strength = 0.4
	lamp.shadows = shadows
	lamp.position = Vector2(x, y)
	lamp.z_index = 1
	_own(lamp)


func _lamps() -> void:
	# Poles in the open: [col, flicker, energy, height px].
	var poles := [
		[6, false, 1.4, 170], [22, true, 1.6, 180], [29, false, 1.4, 170], [55, true, 1.6, 170], [116, true, 1.5, 170],
		[137, false, 1.4, 160], [141, false, 1.2, 150], [240, false, 1.5, 170], [250, true, 1.6, 180], [270, false, 1.4, 170],
		[290, true, 1.6, 170], [310, false, 1.5, 170], [330, true, 1.6, 180], [338, false, 1.6, 170],
	]
	var i := 0
	for d in poles:
		var pole := Node2D.new()
		pole.name = "Pole%d" % i
		pole.position = Vector2(d[0] * T + 16, G * T)
		pole.z_index = -1
		_own(pole)
		var shaft := ColorRect.new()
		shaft.name = "Shaft"
		shaft.color = Color("2a4658")
		shaft.position = Vector2(-2, -d[3])
		shaft.size = Vector2(4, d[3])
		_own_under(pole, shaft)
		var hi := ColorRect.new()
		hi.name = "ShaftHi"
		hi.color = Color("5b7280")
		hi.position = Vector2(-2, -d[3])
		hi.size = Vector2(1, d[3])
		_own_under(pole, hi)
		var foot := ColorRect.new()
		foot.name = "Foot"
		foot.color = Color("141a2c")
		foot.position = Vector2(-6, -6)
		foot.size = Vector2(12, 6)
		_own_under(pole, foot)
		var lamp := WarningLight.new()
		lamp.name = "Lamp%d" % i
		lamp.art_scale = 1
		lamp.mode = WarningLight.Mode.FLICKER if d[1] else WarningLight.Mode.STEADY
		lamp.energy = d[2]
		lamp.light_radius_scale = 3.4
		lamp.halo_strength = 0.4
		lamp.shadows = d[1]
		lamp.position = Vector2(0, -d[3] - 8)
		lamp.z_index = 1
		_own_under(pole, lamp)
		i += 1
	# Under the corridor roofs (the slab bottom is y = 256).
	var n := 0
	for c in [34, 40, 46, 51, 62, 71, 80, 88, 95, 103, 109]:
		_lamp("CeilLamp%d" % n, c * T + 16, 8 * T + 6, n % 3 != 0, 1.2)
		n += 1
	# Under the guardhouse roof's low ceiling and inside tower A and the relay tower.
	for c in [127, 132]:
		_lamp("RoofLamp%d" % c, c * T + 16, 4 * T + 14, true, 1.2)
	for d in [[12, 6], [15, 6], [254, 3], [259, 3]]:
		_lamp("TowerLamp%d" % d[0], d[0] * T + 16, d[1] * T + 14, true, 1.2, Color(1.0, 0.62, 0.32))
	# Tunnels: under each ceiling ([col, row of the first clear row]).
	var tun := [
		[102, 13], [110, 13], [118, 13], [126, 13], [134, 13],
		[143, 13], [150, 13], [156, 15], [162, 15], [171, 13], [166, 18], [175, 18], [181, 18], [186, 18], [192, 18],
		[198, 18], [204, 18], [210, 18], [214, 18], [187, 23], [195, 23], [203, 23], [211, 23], [219, 23], [228, 23],
		[196, 28], [208, 28], [217, 28], [226, 31], [233, 28], [277, 13], [286, 13], [294, 13], [300, 13], [316, 13],
		[323, 13],
	]
	for d in tun:
		_lamp("TunLamp%d_%d" % [d[0], d[1]], d[0] * T + 16, d[1] * T + 14, d[0] % 2 == 0, 1.1, Color(1.0, 0.62, 0.32))
	# The road: bright, warm pre-dawn lamps.
	for c in [352, 359, 366, 373]:
		_lamp("RoadLamp%d" % c, c * T + 16, (G - 5) * T, true, 1.5, Color(1.0, 0.8, 0.55))
