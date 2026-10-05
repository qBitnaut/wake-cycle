## Generates res://scenes/levels/room4.tscn (Room 4, "The Perimeter") and the stub
## res://scenes/levels/stubs/after_room4.tscn ("Home - coming soon"). Run:
##   godot --headless --path . --script res://tools/build_room4.gd
##
## Reach (tools/audit/reach.gd, centre travel; vertical rise is v^2/2g):
##   plain single jump 100 px, plain double jump 180 px up
##   Spring single 163 px, Spring double jump about 295 px up
## So a ledge 7 rows (224 px) up needs Spring (180 < 224 < 295), and a pound
## needs air: the cat jumps (or steps off a ledge) and presses Down.
## Phase: a dash is 0.2 s at 409 px/s = 82 px, cooldown 0.45 s. A laser fence
## is 6 px of beam; the cat is 22 px wide, so a dash started 14..68 px before
## the fence centre goes through it clean. Fences are floor to ceiling.
##
## Beats, left to right (column numbers; 32 px tiles, floor surface at row 10):
##   A    0-30    arrival: guard tower, the perimeter sign, a walker
##   P1  31-53    PHASE 1, discovery: gatehouse corridor, pad (36), one fence (47)
##   P2  54-114   PHASE 2, use: checkpoint A, a corridor of three fences and two
##                guard drones (pads 60, 78, 96), then a laser turret (112)
##   P3 114-136   PHASE 3, combine: Spring pad (114), the guardhouse roof 7 rows
##                up, Phase pad (120), fence (127) under a ceiling
##   I1 138-153   IMPACT 1, discovery: checkpoint B, pad on a ledge (143), the
##                hatch H1 (147-149) in the floor, a closed gate wall (152)
##   I2 141-173   IMPACT 2, use: tunnel L1 (checkpoint C), pad (155), an armoured
##                bot in a 2-tile corridor (158-167), pad (168), hatch H2 (170-172)
##   I3 164-193   IMPACT 3, combine: tunnel L2 (checkpoint D), shield wall (174,
##                the shockwave), pad (177) and fence (182, Phase), pad (184),
##                hatch H3 (187-189); L3 (checkpoint E); a stair out (194-207)
##   F   208-346  the Master Gate: checkpoint F, relay 1 (Spring, tower 222-229),
##                a searchlight drone, relay 2 (Phase maze 243-285), relay 3
##                (Impact hatch 299-301, shield wall 305, vault 293-312), the
##                scanner (330) and the gate (342)
##   G   347-374  the dawn road, exit at 368
extends SceneTree

const T := 32
const G := 10          ## ground surface row (y = 320)
const ROWS := 26       ## 832 px: the deepest tunnel floor is row 22
const COLS := 374

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
const GATE_COL := 342      ## the gate straddles cols 341-342
const SCANNER_COL := 330
const EXIT_COL := 368

const SCENE_ROOM := "res://scenes/levels/room4.tscn"
const SCENE_STUB := "res://scenes/levels/stubs/after_room4.tscn"

var room: Node2D
var tiles: TileMapLayer
var back_tiles: TileMapLayer
var _mats := {}


func _initialize() -> void:
	_build_room4()
	_build_stub()
	quit()


# ---- helpers ------------------------------------------------------------------

func _save(root: Node, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var packed := PackedScene.new()
	print("pack ", path, ": ", packed.pack(root))
	print("save ", path, ": ", ResourceSaver.save(packed, path))


func _p(cx: int, cy: int) -> Vector2:
	## Bottom-centre of cell (cx, cy-1): standing on the top edge of row cy.
	return Vector2(cx * T + T / 2.0, cy * T)


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
		if k != "_dy" and k != "_dx":
			n.set(k, props[k])
	n.position = _p(cx, cy) + Vector2(props.get("_dx", 0.0), props.get("_dy", 0.0))
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


# ---- tile grid: fill and carve, then style by exposure -----------------------------

func _fill(x0: int, y0: int, x1: int, y1: int, mat: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			_mats[Vector2i(x, y)] = mat


func _clear(x0: int, y0: int, x1: int, y1: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			_mats.erase(Vector2i(x, y))


func _cell(x: int, y: int, mat: int, tile: Vector2i, layer: TileMapLayer = null) -> void:
	var l := layer if layer else tiles
	l.set_cell(Vector2i(x, y), 0, Vector2i(tile.x, tile.y + mat * 10))


## Every filled cell gets a tile by what it touches: a bevelled top where the cell
## above is open, a girder under an open bottom, plain plates elsewhere.
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
			tile = GIRDER_H
		elif m == BULKHEAD or m == TEAL or m == RUST:
			tile = FRAMED if (c.x * 3 + c.y) % 7 == 0 else (CROSS if (c.x + c.y * 5) % 11 == 0 else tile)
		_cell(c.x, c.y, m, tile)


# ---- the room -----------------------------------------------------------------

func _build_room4() -> void:
	room = Node2D.new()
	room.name = "Room4"
	room.set_script(load("res://scripts/systems/room4.gd"))
	room.set("limits", Rect2i(0, 24, COLS * T, 360))
	room.set("deep_bottom", ROWS * T)
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
	exterior.position = Vector2(0, 250)
	exterior.moon_position = Vector2(-120, -141)
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
	fence.length = float(341 * T - 5 * T)
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

	_place_actors()
	_signs()
	_towers()
	_stoppers()
	_puddles()
	_lamps()

	_rain("RainFar", -2, 40.0, 0.0, 60.0)
	_rain("RainNear", 7, 34.0, 0.0, 110.0)

	var exit_area: Area2D = load("res://scripts/systems/room_exit.gd").new()
	exit_area.name = "RoomExit"
	exit_area.set("next_scene", SCENE_STUB)
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
	sp.horizon_y = 250.0
	_own(sp)

	_script_node("res://scripts/systems/perimeter_finale.gd", "Finale", Vector2.ZERO)

	var amb := Ambience.new()
	amb.name = "Ambience"
	_own(amb)

	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	_own(hud)

	_save(room, SCENE_ROOM)


func _rain(node_name: String, z: int, density: float, wind_extra: float, speed_extra: float) -> void:
	var r := RainFX.new()
	r.name = node_name
	r.position = Vector2(320, 4)
	r.width = 760.0
	r.floor_y = G * T - 4.0
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
	s.position = Vector2(347 * T, G * T - 14)
	s.z_index = -8
	_own(s)


func _back_decor() -> void:
	## Dim stacks and guardhouse blocks behind the route: [x0, x1, courses, material].
	var defs := [
		[8, 14, 1, TEAL], [24, 30, 2, RUST], [54, 57, 1, MAROON], [103, 111, 1, TEAL], [136, 140, 2, RUST],
		[209, 215, 2, TEAL], [230, 238, 1, MAROON], [286, 292, 2, RUST], [318, 326, 1, TEAL],
		[349, 353, 1, MAROON],
	]
	for d in defs:
		for k in range(d[2]):
			for x in range(d[0], d[1] + 1):
				var c: int = 10 + (x - d[0]) % 3
				_cell(x, G - 2 - 2 * k, d[3], Vector2i(c, 5), back_tiles)
				_cell(x, G - 1 - 2 * k, d[3], Vector2i(c, 6), back_tiles)
	# Truss posts under the gatehouse corridors.
	for x in [32, 36, 41, 46, 52, 58, 66, 74, 82, 90, 98, 106]:
		for y in range(6, G):
			_cell(x, y, STEEL, GIRDER_V, back_tiles)
	for x in [243, 249, 255, 261, 267, 273, 279, 285]:
		for y in range(6, G):
			_cell(x, y, STEEL, GIRDER_V, back_tiles)
	# The gatehouse behind the Master Gate: panelled walls under the lintel.
	for x in range(336, 348):
		for y in range(3, G):
			_cell(x, y, MAROON, FLAT if (x + y) % 2 == 0 else RIVET, back_tiles)
	# Pillars behind the guardhouse ceiling.
	for y in range(1, 3):
		_cell(134, y, STEEL, GIRDER_V, back_tiles)
		_cell(125, y, STEEL, GIRDER_V, back_tiles)


func _build_geometry() -> void:
	# Ground everywhere, and deep rock under the Impact complex and the plaza so the
	# camera never sees void when it drops into a tunnel.
	_fill(0, G, COLS - 1, G + 3, MAROON)
	_fill(118, G + 4, 346, ROWS - 1, MAROON)
	for y in range(-4, ROWS):
		_mats[Vector2i(-1, y)] = BULKHEAD
		_mats[Vector2i(COLS, y)] = BULKHEAD

	# P1: the gatehouse corridor, 4 tiles clear (rows 6-9), a roof over it.
	_fill(32, -3, 52, 5, STEEL)
	# P2: the long corridor of fences.
	_fill(58, -3, 106, 5, STEEL)
	# P3: the guardhouse (roof 7 rows up) and the ceiling over its fence.
	_fill(118, 3, 134, 9, TEAL)
	_fill(124, -3, 134, 0, STEEL)

	# I1: the pad's ledge, the closed gate wall.
	_fill(141, 8, 145, 9, RUST)
	_fill(152, -3, 153, 9, BULKHEAD)
	# The tunnels. L1: rows 11-13, floor row 14. The hatch H1 opens the deck over it.
	_clear(141, 11, 173, 13)
	_clear(147, 10, 149, 10)
	_fill(158, 11, 167, 11, STEEL)          # the armoured bot's 2-tile corridor
	# L2: rows 15-17, floor row 18. H2 (168-170) in L1's floor.
	_clear(164, 15, 192, 17)
	_clear(170, 14, 172, 14)
	# L3: rows 19-21, floor row 22. H3 (187-189) in L2's floor.
	_clear(183, 19, 193, 21)
	_clear(187, 18, 189, 18)
	# The stair out: a trench open to the sky, steps rising to the surface at col 208.
	_clear(194, 10, 207, 21)
	var tops := [21, 19, 17, 15, 13, 11, 10]
	for k in range(7):
		_fill(194 + 2 * k, tops[k], 195 + 2 * k, 21, STEEL)

	# R1: the tower (top row 3 = 7 rows above the floor).
	_fill(222, 3, 229, 9, TEAL)
	# R2: the maze corridor.
	_fill(243, -3, 285, 5, STEEL)
	# R3: the vault under the surface (rows 11-13, floor row 14), hatch H4 and a stair out.
	_clear(293, 11, 312, 13)
	_clear(299, 10, 301, 10)
	_clear(313, 10, 314, 11)

	# The gatehouse lintel over the Master Gate.
	_fill(336, -3, 347, 2, TEAL)
	# Right end of the road: a bulkhead.
	for y in range(2, G):
		_mats[Vector2i(COLS - 1, y)] = BULKHEAD


func _back_walls() -> void:
	## Panelled back walls behind every tunnel so the sky never shows through.
	var defs := [
		["WallL1", 141, 11, 33, 3], ["WallL2", 164, 15, 29, 3], ["WallL3", 183, 19, 11, 3],
		["WallTrench", 194, 10, 14, 12], ["WallVault", 293, 11, 20, 3], ["WallVaultStep", 313, 10, 2, 2],
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
	_sign(board, "PlacardSpring", 112, G, PackedStringArray(["GUARDHOUSE ROOF", "NO GROUND ROUTE"]), amber, 18.0)
	_sign(board, "PlacardImpact", 139, G, PackedStringArray(["IMPACT", "DOWN IN MID-AIR: GROUND POUND"]), FXPalette.IMPACT, 18.0)
	_sign(board, "SignGateClosed", 150, G, PackedStringArray(["GATE CLOSED", "CRACKED FLOOR: SERVICE DUCT"]), amber, 18.0)
	_sign(board, "PlacardArmour", 156, 14, PackedStringArray(["ARMOURED UNIT", "STUN FROM ABOVE"]), amber, 10.0)
	_sign(board, "PlacardShield", 169, 18, PackedStringArray(["SHIELD", "DOUBLE JUMP BURST"]), FXPalette.SHOCKWAVE, 8.0)
	_sign(board, "SignRelays", 213, G, PackedStringArray(["MASTER GATE", "3 RELAYS REQUIRED"]), amber, 22.0)
	_sign(board, "SignRelay1", 218, G, PackedStringArray(["RELAY 1: TOWER"]), aqua, 18.0)
	_sign(board, "SignRelay2", 240, G, PackedStringArray(["RELAY 2: LASER MAZE"]), aqua, 18.0)
	_sign(board, "SignRelay3", 296, G, PackedStringArray(["RELAY 3: LOWER VAULT"]), aqua, 18.0)
	_sign(board, "SignScanner", 325, G, PackedStringArray(["SUPERVISORS ONLY", "SCAN ON APPROACH"]), amber, 18.0)
	_sign(board, "SignRoad", 352, G, PackedStringArray(["SUBURBAN DISTRICT", "2 KM"]), aqua, 22.0)


func _sign(path: String, node_name: String, col: int, row: int, lines: PackedStringArray, accent: Color, legs: float) -> void:
	var s: Node2D = load(path).new()
	s.name = node_name
	s.set("lines", lines)
	s.set("accent", accent)
	s.set("legs", legs)
	s.position = _p(col, row)
	_own(s)


func _towers() -> void:
	## Guard towers behind the route: [col, height px, phase].
	var defs := [[12, 210.0, 0.0], [44, 150.0, 2.0], [109, 230.0, 1.0], [206, 220.0, 3.0], [233, 230.0, 0.5],
		[291, 220.0, 2.5], [323, 230.0, 1.5], [338, 200.0, 4.0]]
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


func _place_actors() -> void:
	var gem := "res://scenes/actors/gem.tscn"
	var fish := "res://scenes/actors/fish.tscn"
	var pad := "res://scenes/actors/pad.tscn"
	var cp := "res://scenes/actors/checkpoint.tscn"
	var fence := "res://scenes/actors/laser_fence.tscn"
	var crack := "res://scenes/actors/cracked_floor.tscn"
	var bot := "res://scenes/actors/patrol_bot.tscn"

	# --- A: arrival ---
	_mono("PerimeterArrival", "perimeter_arrival", Vector2(START_COL * T + 16, G * T), Vector2(224, 96))
	var bot1 := _put(bot, "Bot1", 24, G, {"stomps_to_befriend": 99})
	bot1.set("dir", -1)
	_put(gem, "GemA1", 9, G - 1)
	_put(gem, "GemA2", 14, G - 2)
	_put(gem, "GemA3", 18, G - 1)
	_put(gem, "GemA4", 27, G - 1)

	# --- P1: Phase discovery. A pad, ten tiles of run-up, one fence; walls and a roof on both sides. ---
	_put(pad, "PadPhase1", 36, G, {"power": 3, "duration": 12.0, "cooldown": 3.0})
	_put(fence, "FenceP1", 47, G, {"height_tiles": 4, "timed": false})
	_mono("PhaseFirst", "phase_first", _p(50, G), Vector2(96, 96))
	_put(gem, "GemP1a", 41, G - 1)
	_put(gem, "GemP1b", 43, G - 1)
	_put(gem, "GemP1c", 51, G - 1)

	# --- P2: Phase use. Five fences, two drones, a turret. ---
	_put(cp, "CheckpointA", 55, G, {"checkpoint_id": "cp_a"})
	_put(pad, "PadPhase2a", 60, G, {"power": 3, "duration": 12.0, "cooldown": 3.0})
	_put(fence, "FenceP2a", 68, G, {"height_tiles": 4, "timed": false})
	_put(fence, "FenceP2b", 74, G, {"height_tiles": 4, "timed": false})
	_put(pad, "PadPhase2b", 78, G, {"power": 3, "duration": 12.0, "cooldown": 3.0})
	_drone("DroneP2a", 84, G - 2, 48.0, 0.0)
	_put(fence, "FenceP2c", 92, G, {"height_tiles": 4, "timed": false})
	_put(pad, "PadPhase2c", 96, G, {"power": 3, "duration": 12.0, "cooldown": 3.0})
	_drone("DroneP2b", 102, G - 2, 40.0, 1.7)
	_turret("TurretP2", 112, G, -1, 288.0, 0.0)
	_put(gem, "GemP2a", 64, G - 1)
	_put(gem, "GemP2b", 71, G - 3)
	_put(gem, "GemP2c", 88, G - 1)
	_put(gem, "GemP2d", 108, G - 1)

	# --- P3: Spring up the guardhouse, Phase through the fence on the roof. ---
	_put(pad, "PadSpring1", 114, G, {"power": 2, "duration": 10.0, "cooldown": 3.0})
	_put(pad, "PadPhase3", 120, 3, {"power": 3, "duration": 10.0, "cooldown": 3.0})
	_put(fence, "FenceP3", 127, 3, {"height_tiles": 2, "timed": false})
	_put(gem, "GemP3a", 117, G - 5)
	_put(gem, "GemP3b", 122, 2)
	_put(gem, "GemP3c", 131, 2)

	# --- I1: Impact discovery. ---
	_put(cp, "CheckpointB", 138, G, {"checkpoint_id": "cp_b"})
	_put(pad, "PadImpact1", 143, 8, {"power": 4, "duration": 12.0, "cooldown": 3.0})
	_put(crack, "HatchH1a", 147, G + 1)
	_put(crack, "HatchH1b", 148, G + 1)
	_put(crack, "HatchH1c", 149, G + 1)
	_put(gem, "GemI1", 146, 5)

	# --- I2: tunnel L1. ---
	_mono("ImpactFirst", "impact_first", _p(148, 14), Vector2(96, 96))
	_put(cp, "CheckpointC", 152, 14, {"checkpoint_id": "cp_c"})
	_put(pad, "PadImpact2", 155, 14, {"power": 4, "duration": 12.0, "cooldown": 3.0})
	var armoured := _put(bot, "BotArmoured", 162, 14, {"shielded": true, "stun_time": 4.0, "speed": 38.0, "stomps_to_befriend": 99})
	armoured.set("dir", -1)
	_put(pad, "PadImpact2b", 168, 14, {"power": 4, "duration": 12.0, "cooldown": 3.0})
	for c in [170, 171, 172]:
		_put(crack, "HatchH2%d" % c, c, 15)
	_put(fish, "FishL1", 145, 12)
	_put(gem, "GemL1a", 143, 13)

	# --- I3: tunnel L2, the shield, the fence, the last hatch (landing at col 171). ---
	_put(cp, "CheckpointD", 166, 18, {"checkpoint_id": "cp_d"})
	_put_script("res://scripts/actors/shield_panel.gd", "ShieldS1", 174, 18)
	_put(pad, "PadPhase4", 177, 18, {"power": 3, "duration": 10.0, "cooldown": 3.0})
	_put(fence, "FenceI3", 182, 18, {"height_tiles": 3, "timed": false})
	_put(pad, "PadImpact3", 184, 18, {"power": 4, "duration": 12.0, "cooldown": 3.0})
	for c in [187, 188, 189]:
		_put(crack, "HatchH3%d" % c, c, 19)
	_put(gem, "GemL2a", 179, 17)
	_put(gem, "GemL2b", 191, 17)

	# --- L3 and the stair. ---
	_put(cp, "CheckpointE", 191, 22, {"checkpoint_id": "cp_e"})
	_put(gem, "GemL3", 185, 21)

	# --- F: the plaza and its three relays. ---
	_put(cp, "CheckpointF", 211, G, {"checkpoint_id": "cp_f"})
	_mono("RelaysIntro", "relays_intro", _p(213, G), Vector2(96, 96))
	_put(pad, "PadSpring2", 217, G, {"power": 2, "duration": 10.0, "cooldown": 3.0})
	_put_script("res://scripts/actors/power_relay.gd", "Relay1", 226, 3, {"index": 1})
	_put(cp, "CheckpointG", 233, G, {"checkpoint_id": "cp_g"})
	var drone: Node = load("res://scripts/actors/search_drone.gd").new()
	drone.name = "SearchDrone"
	drone.set("trigger_x", float(236 * T))
	drone.set("start_x", float(229 * T))
	drone.set("end_x", float(241 * T))
	drone.set("speed", 120.0)
	drone.set("height", 160.0)
	drone.set("beam_length", 230.0)
	drone.set("half_angle", 12.0)
	drone.set("sway", 8.0)
	_own(drone)
	# R2: the maze: three fences and a drone, a pad before each stretch.
	_put(pad, "PadPhase5a", 245, G, {"power": 3, "duration": 12.0, "cooldown": 3.0})
	_put(fence, "FenceR2a", 251, G, {"height_tiles": 4, "timed": false})
	_put(fence, "FenceR2b", 257, G, {"height_tiles": 4, "timed": false})
	_put(pad, "PadPhase5b", 261, G, {"power": 3, "duration": 12.0, "cooldown": 3.0})
	_drone("DroneR2a", 267, G - 2, 40.0, 0.9)
	_put(fence, "FenceR2c", 274, G, {"height_tiles": 4, "timed": false})
	_put(pad, "PadPhase5c", 277, G, {"power": 3, "duration": 12.0, "cooldown": 3.0})
	_put_script("res://scripts/actors/power_relay.gd", "Relay2", 282, G, {"index": 2})
	_put(cp, "CheckpointH", 289, G, {"checkpoint_id": "cp_h"})
	# R3: Impact, the vault, the shockwave shield.
	_put(pad, "PadImpact4", 295, G, {"power": 4, "duration": 12.0, "cooldown": 3.0})
	for c in [299, 300, 301]:
		_put(crack, "HatchH4%d" % c, c, G + 1)
	_put_script("res://scripts/actors/shield_panel.gd", "ShieldS2", 305, 14)
	_put_script("res://scripts/actors/power_relay.gd", "Relay3", 309, 14, {"index": 3})
	_put(fish, "FishVault", 297, 14 - 0)
	_put(cp, "CheckpointI", 318, G, {"checkpoint_id": "cp_i"})
	var bot2 := _put(bot, "Bot2", 322, G, {"stomps_to_befriend": 99})
	bot2.set("dir", 1)
	# The scanner and the gate.
	var scanner := _script_node("res://scripts/actors/security_scanner.gd", "Scanner", _p(SCANNER_COL, G))
	scanner.set("z_index", 2)
	var gate := _script_node("res://scripts/actors/master_gate.gd", "MasterGate", Vector2(GATE_COL * T, G * T), {"width": 64.0, "height_tiles": 7})
	gate.set("width", 64.0)
	_put(cp, "CheckpointJ", 350, G, {"checkpoint_id": "cp_j"})
	_mono("PerimeterExit", "perimeter_exit", _p(358, G), Vector2(128, 96))
	for c in [354, 357, 361, 364]:
		_put(gem, "GemRoad%d" % c, c, G - 1)
	for c in [214, 238, 292, 306, 322]:
		_put(gem, "GemPlaza%d" % c, c, G - 1)


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


func _mono(node_name: String, line_id: String, pos: Vector2, size: Vector2) -> void:
	var t: Area2D = load("res://scripts/actors/monologue_trigger.gd").new()
	t.name = node_name
	t.set("line_id", line_id)
	t.set("require_mind", true)
	t.set("size", size)
	t.position = pos
	_own(t)


func _stoppers() -> void:
	## Invisible bot walls (physics layer 7): Bot1 walks cols 20-28, the armoured
	## bot cols 158-165 (left wall at col 157, right at col 166), Bot2 cols 321-326.
	for col in [19, 29, 157, 166, 320, 327]:
		var row := G
		var rows_tall := 4
		if col in [157, 166]:
			row = 14
			rows_tall = 3
		var sb := StaticBody2D.new()
		sb.name = "Stopper%d" % col
		sb.collision_layer = 64
		sb.collision_mask = 0
		sb.position = Vector2(col * T + T / 2.0, row * T)
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = Vector2(T, rows_tall * T)
		cs.shape = r
		cs.position = Vector2(0, -rows_tall * T / 2.0)
		cs.name = "Shape"
		sb.add_child(cs)
		_own(sb)
		cs.owner = room


func _puddles() -> void:
	var defs := [
		[10.0, 128.0], [26.0, 128.0], [40.0, 96.0], [56.0, 96.0], [104.0, 160.0], [116.0, 64.0], [136.0, 96.0],
		[210.0, 128.0], [219.0, 96.0], [231.0, 128.0], [291.0, 128.0], [316.0, 160.0], [335.0, 96.0],
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
	for d in [[352.0, 96.0], [362.0, 128.0]]:
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
	# Poles in the open: [col, flicker, energy, height px]. Ceiling lamps under corridors and in tunnels.
	var poles := [
		[6, false, 1.4, 170], [16, true, 1.6, 180], [28, false, 1.4, 170], [55, true, 1.6, 170], [106, false, 1.5, 170],
		[116, true, 1.5, 170], [137, false, 1.4, 160], [141, false, 1.2, 150], [210, false, 1.5, 170], [220, true, 1.6, 180],
		[234, false, 1.5, 170], [289, true, 1.6, 170], [296, false, 1.4, 170], [317, false, 1.5, 170], [327, true, 1.6, 180],
		[334, false, 1.6, 170],
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
	# Under the ceilings: corridors (y = 192 + 10 under the slab bottom), the guardhouse, the maze.
	var n := 0
	for c in [34, 40, 46, 51, 62, 71, 80, 88, 95, 103, 128, 132, 247, 254, 261, 268, 275, 282]:
		_lamp("CeilLamp%d" % n, c * T + 16, 6 * T + 6, n % 3 != 0, 1.2)
		n += 1
	# The guardhouse ceiling is lower: its lamps hang at row 1.
	for c in [127, 132]:
		_lamp("RoofLamp%d" % c, c * T + 16, 1 * T + 14, true, 1.2)
	# Tunnels: low ceilings (the deck/floor bottom edge + 8).
	var tun := [[143, 11], [150, 11], [156, 11], [162, 12], [171, 11], [167, 15], [175, 15], [181, 15], [186, 15], [190, 15],
		[185, 19], [190, 19], [297, 11], [303, 11], [309, 11], [201, 12], [199, 15], [195, 18]]
	for d in tun:
		_lamp("TunLamp%d_%d" % [d[0], d[1]], d[0] * T + 16, d[1] * T + 14, d[0] % 2 == 0, 1.1, Color(1.0, 0.62, 0.32))
	# The road: bright, warm pre-dawn lamps.
	for c in [349, 356, 363, 370]:
		_lamp("RoadLamp%d" % c, c * T + 16, (G - 5) * T, true, 1.5, Color(1.0, 0.8, 0.55))


# ---- the stub after Room 4 ---------------------------------------------------------

func _build_stub() -> void:
	_mats.clear()
	room = Node2D.new()
	room.name = "AfterRoom4"
	room.set_script(load("res://scripts/systems/after_room4.gd"))
	room.set("limits", Rect2i(0, 24, 20 * T, 360))
	var w := 20 * T

	var sky := ColorRect.new()
	sky.name = "SkyFill"
	sky.color = Color("1b2342")
	sky.position = Vector2(-64, -200)
	sky.size = Vector2(w + 128, 700)
	sky.z_index = -10
	_own(sky)
	var exterior := NightBackdrop.new()
	exterior.name = "Exterior"
	exterior.position = Vector2(0, 250)
	exterior.brightness = 2.3
	exterior.moon_visible = false
	exterior.z_index = -9
	_own(exterior)
	var subs: Node2D = load("res://scripts/fx/suburb_row.gd").new()
	subs.name = "Suburbs"
	subs.set("length", float(w))
	subs.position = Vector2(0, G * T - 14)
	subs.z_index = -8
	_own(subs)

	tiles = TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	_own(tiles)
	_fill(0, G, 19, G + 2, MAROON)
	for y in range(0, ROWS):
		_mats[Vector2i(-1, y)] = BULKHEAD
		_mats[Vector2i(20, y)] = BULKHEAD
	_paint()

	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = _p(3, G)
	_own(start)

	var label := Label.new()
	label.name = "ComingSoon"
	label.text = "Home - coming soon"
	label.add_theme_font_override("font", load("res://assets/fonts/monogram.ttf"))
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0) * 1.1)
	label.position = Vector2(7 * T, 4 * T)
	label.size = Vector2(12 * T, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_own(label)

	var cat: Node = load("res://scenes/player/cat.tscn").instantiate()
	cat.name = "Cat"
	_own(cat)
	var rig := LightingRig.new()
	rig.name = "LightingRig"
	rig.night_tint = Color(0.78, 0.82, 0.95)
	rig.moon_angle = 16.0
	rig.moon_energy = 0.3
	rig.glow_intensity = 0.8
	rig.vignette = 0.12
	var solid: Array[TileMapLayer] = [tiles]
	rig.solid_layers = solid
	_own(rig)
	var amb := Ambience.new()
	amb.name = "Ambience"
	_own(amb)
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	_own(hud)
	_save(room, SCENE_STUB)
