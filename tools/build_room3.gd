## Generates res://scenes/levels/room3.tscn (Room 3, "The Stacks"); its exit leads to
## res://scenes/levels/room4.tscn. Run:
##   godot --headless --path . --script res://tools/build_room3.gd
##
## Sizes come from the measured reach (tools/audit/reach.gd), centre travel and
## rise (px above takeoff):
##                    single   double jump          rise: single   double
##   plain              122 px   223 px                   95 (3.0)   171 (5.3 tiles)
##   Surge              182 px   334 px
##   Spring             160 px   297 px                  158 (4.9)   284 (8.9 tiles)
## (Spring's first jump is now 211 px, 6.6 tiles; its air jump is the plain one, so the
## double jump numbers below are unchanged.)
## Every climb is 6 tiles (192 px): past a plain double jump (21 px short), 19 px
## inside a held Spring single jump, 92 px inside a Spring double jump. The gallery roof is 12 tiles up, out of Spring's reach.
## The long gap is 9 tiles (288 px, needs 266): Surge double jump 334 (68 spare),
## Spring double jump 255 (11 short: Spring's air jump is a small extra, 0.6), plain 223.
## (At 10 tiles the Surge double jump had 36 spare and landed in 45% of the human
## sweep, tools/audit/margins.gd; Spring's double jump then had to be a pixel short.)
##
## The room is tall (rows 0-39, ground surface at row 36) and climbs to the right:
##   A     0-33   arrival on the yard floor in the easing rain; Bot1 walks the lane
##   B1   33-34   SPRING 1, discovery: a pad at the foot of a 6-tile wall, the ledge above
##   B2   34-54   SPRING 2, use it: checkpoint A, a pad, a floating ledge (row 24), the long
##                roof (row 18): two Spring jumps chained inside one 10 s charge
##   C    54-66   the long roof, checkpoint B, the gallery mouth
##   D    66-73   the conduit tunnel (2 tiles high): the sparking panel grants the shockwave
##   E    73-101  the shockwave lessons in a covered gallery: 3x2 crates to break (3 tiles high),
##                a patrol bot in a 4-tile corridor (the shockwave stuns it), a shock switch
##                that opens a shutter
##   F   101-129  the machine bay: a catwalk over the loader bot's track. The bot wakes as the
##                augmented cat arrives and copies its steps; walk it onto its plate at the end of
##                the track and the shutter at the catwalk's end opens
##   G   130-170  SPRING 3 + SURGE: checkpoint C, a pad at the foot of a 6-tile tower, Spring up it,
##                a Surge pad on top, a 9-tile gap, the exit roof (checkpoint D), the way
##                toward the security perimeter. Under the gap: stairs down the tower's right
##                side to a pit floor 12 tiles under the exit roof, so a fall is never a trap
##                and the far tower cannot be climbed from the pit
extends SceneTree

const T := 32
const ROWS := 40
const COLS := 170
const G := 36          ## yard floor surface row (y = 1152)
const S1 := 30         ## shed roof
const S2 := 24         ## floating ledge
const S3 := 18         ## long roof, gallery floor
const S4 := 12         ## tower tops, exit roof
const GROOF := 6       ## gallery roof surface: 12 tiles over the long roof (out of Spring's reach)
const BAY_FLOOR := 22
const PIT := 24        ## the pit floor under the gap: 12 tiles under the exit roof (a boosted Spring double jump rises up to 340 px, 10.6 tiles)

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
const PAD1_COL := 33              ## Spring, at the foot of the first wall (col 34)
const SHED := [34, 53]
const PAD2_COL := 41
const LEDGE := [45, 52]            ## the floating ledge: ends one tile short of the long roof (col 54)
const LONG := [54, 101]           ## the long roof building (gallery floor)
const GALLERY := [66, 101]
const CONDUIT_COL := 69
const CRATE_COLS := [77, 78]
const BOT_RANGE := [83, 94]
const SWITCH_COL := 96
const GATE_COL := 99
const BAY := [102, 125]
const BAY_WALL := 126             ## first solid column after the bay (its face stops the bot)
const BAY_GATE_COL := 127
const PLATE_X := 4004.0           ## the plate (56 px), flush with the bay wall: the pinned bot stands on it
const MIRROR_COL := 105
const PAD3_COL := 137             ## Spring, at the foot of the tower (col 138)
const TOWER := [138, 149]       ## the tower, with stairs down its right side to the pit floor
const SURGE_COL := 142            ## Surge, inside the 1-tile-headroom tunnel (cols 142-144): it cannot be hopped over
const TUNNEL := [142, 144]
const TOP_FLAT_END := 145         ## last full-height column of the tower top
const GAP := [146, 154]           ## nine tiles; the stairs (146-150) and the pit floor (151-154) lie under it
const LAND := [155, 169]
const EXIT_COL := 167

var room: Node2D
var tiles: TileMapLayer
var back_tiles: TileMapLayer


func _initialize() -> void:
	_build_room3()
	quit()


# ---- helpers ------------------------------------------------------------------

func _save(root: Node, path: String) -> void:
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


func _cell(x: int, y: int, mat: int, tile: Vector2i, layer: TileMapLayer = null) -> void:
	var l := layer if layer else tiles
	l.set_cell(Vector2i(x, y), 0, Vector2i(tile.x, tile.y + mat * 10))


func _course_mat(x: int, y: int) -> int:
	var mats := [RUST, TEAL, MAROON]
	return mats[((x / 5) + (y / 2) * 2) % 3]


## Solid container courses from row y0 to y1 inclusive, courses anchored to the
## bottom row. `cap`: the top row is a roof surface (steel bevel).
func _mass(x0: int, x1: int, y0: int, y1: int, cap := true) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			if cap and y == y0:
				_cell(x, y, STEEL, BEVEL)
				continue
			var k := y1 - y
			_cell(x, y, _course_mat(x, y1 - k - k % 2), Vector2i(11, 6 if k % 2 == 0 else 5))


## A column of solid with its own top row (a stepped or sloped roof edge).
func _column(x: int, top: int, bottom: int) -> void:
	_mass(x, x, top, bottom)


func _lip(x: int, y: int) -> void:
	_cell(x, y, HAZARD, BEVEL)


func _ground() -> void:
	for x in range(0, SHED[0]):  # the yard floor, up to the foot of the first wall
		_cell(x, G, STEEL, BEVEL)
		_cell(x, G + 1, MAROON, GIRDER_H)
		_cell(x, G + 2, MAROON, FLAT if x % 2 == 0 else RIVET)
		_cell(x, G + 3, MAROON, RIVET if x % 2 == 0 else FLAT)


func _crates(x0: int, x1: int, h: int) -> void:
	for x in range(x0, x1 + 1):
		for k in range(h):
			_cell(x, G - 1 - k, MAROON, FRAMED if (x + k) % 2 == 0 else CROSS)


## A catwalk: a steel deck 1 or 2 rows thick, `rows` below the top bevel.
func _deck(x0: int, x1: int, top: int, rows: int) -> void:
	for x in range(x0, x1 + 1):
		_cell(x, top, STEEL, BEVEL)
		for k in range(1, rows):
			_cell(x, top + k, MAROON, FLAT if x % 2 == 0 else RIVET)


func _back_container(x0: int, x1: int, top: int, mat: int) -> void:
	for x in range(x0, x1 + 1):
		var c := 10 + (x - x0) % 3
		_cell(x, top, mat, Vector2i(c, 5), back_tiles)
		_cell(x, top + 1, mat, Vector2i(c, 6), back_tiles)


func _back_stack(x0: int, x1: int, base_row: int, courses: int, mat: int) -> void:
	for k in range(courses):
		_back_container(x0, x1, base_row - 2 - 2 * k, mat if k % 2 == 0 else (mat + 1) % 3 + 2)


func _truss(x: int, y0: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		_cell(x, y, STEEL, GIRDER_V, back_tiles)


func _beam(x0: int, x1: int, y: int) -> void:
	for x in range(x0, x1 + 1):
		_cell(x, y, STEEL, GIRDER_H, back_tiles)


# ---- the room -----------------------------------------------------------------

func _build_room3() -> void:
	room = Node2D.new()
	room.name = "Room3"
	room.set_script(load("res://scripts/systems/room3.gd"))
	room.set("limits", Rect2i(0, 0, COLS * T, ROWS * T))
	var w := COLS * T

	var sky := ColorRect.new()
	sky.name = "SkyFill"
	sky.color = Color("0c1030")
	sky.position = Vector2(-64, -400)
	sky.size = Vector2(w + 128, ROWS * T + 800)
	sky.z_index = -10
	_own(sky)

	var exterior := NightBackdrop.new()
	exterior.name = "Exterior"
	exterior.position = Vector2(0, 700)
	exterior.moon_position = Vector2(-120, -141)
	exterior.z_index = -9
	_own(exterior)

	var suburbs := SuburbBackdrop.new()
	suburbs.name = "Suburbs"
	suburbs.position = Vector2(0, 700)
	_own(suburbs)

	back_tiles = TileMapLayer.new()
	back_tiles.name = "BackTiles"
	back_tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	back_tiles.collision_enabled = false
	back_tiles.occlusion_enabled = false
	back_tiles.z_index = -4
	back_tiles.self_modulate = Color(0.5, 0.52, 0.62)
	_own(back_tiles)
	_back_decor()

	tiles = TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	_own(tiles)
	_build_geometry()
	_interiors()

	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = _p(START_COL, G)
	_own(start)

	_place_actors()
	_stoppers()
	_puddles()
	_poles()
	_lamps()

	# Rain, easing: two RainFX layers that follow the camera in both axes (Room3
	# moves them), one behind the foreground and a sparser one in front.
	_rain("RainFar", -2, 22.0, 0.0, 30.0)
	_rain("RainNear", 7, 14.0, 0.0, 70.0)

	var exit_area: Area2D = load("res://scripts/systems/room_exit.gd").new()
	exit_area.name = "RoomExit"
	exit_area.set("next_scene", "res://scenes/ui/world_map.tscn")
	exit_area.position = _p(EXIT_COL, S4)
	_own(exit_area)

	var cat: Node = load("res://scenes/player/cat.tscn").instantiate()
	cat.name = "Cat"
	_own(cat)

	var rig := LightingRig.new()
	rig.name = "LightingRig"
	rig.night_tint = Color(0.38, 0.42, 0.60)
	rig.moon_angle = 14.0
	rig.moon_energy = 0.9
	rig.glow_intensity = 0.8
	rig.vignette = 0.28
	var solid: Array[TileMapLayer] = [tiles]
	rig.solid_layers = solid
	_own(rig)

	var amb := Ambience.new()
	amb.name = "Ambience"
	_own(amb)

	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	_own(hud)

	var covered: Array[Rect2] = [
		Rect2(GALLERY[0] * T, (GROOF + 1) * T, (GALLERY[1] + 1 - GALLERY[0]) * T, (S3 - GROOF - 1) * T),
		Rect2(BAY_WALL * T, (GROOF + 1) * T, 4 * T, (S3 - GROOF - 1) * T),
	]
	room.set("covered", covered)

	_save(room, "res://scenes/levels/room3.tscn")


func _rain(node_name: String, z: int, density: float, wind_extra: float, speed_extra: float) -> void:
	var r := RainFX.new()
	r.name = node_name
	r.position = Vector2(320, 0)
	r.width = 760.0
	r.floor_y = 410.0
	r.wind = 55.0 + wind_extra
	r.speed = 230.0 + speed_extra
	r.density = density
	r.splash = false
	r.z_index = z
	_own(r)


func _build_geometry() -> void:
	_ground()
	for y in range(0, ROWS):
		_cell(-1, y, BULKHEAD, FLAT)
		_cell(COLS, y, BULKHEAD, FLAT)
	# Arrival: crates to hop on the way.
	_crates(11, 12, 1)
	_crates(15, 16, 2)
	# B1/B2: the shed (the wall the first pad stands at) and the floating ledge.
	_mass(SHED[0], SHED[1], S1, ROWS - 1)
	for x in range(SHED[0], SHED[0] + 3):
		_lip(x, S1)
	_deck(LEDGE[0], LEDGE[1], S2, 2)
	# A strut under the ledge's left end: its face is a wall from the shed roof up, so a
	# cat rising beside it never bangs its head on an overhang (a floating edge ate every
	# jump that started closer than 42 px).
	_mass(LEDGE[0], LEDGE[0] + 1, S2 + 2, S1 - 1, false)
	# ...and the ledge is a full column from the deck down to the shed roof, right up to the
	# one-tile slot beside the long roof (col 53): the open space under the deck was a vault
	# a cat dropped into through that slot and could not leave (no pad inside, 6 tiles to the
	# deck, the strut a wall on the left). Now the slot is two tiles deep: a plain jump out.
	_mass(LEDGE[0] + 2, LEDGE[1] + 1, S2 + 2, S1 - 1, false)
	# C-F: the long roof building: gallery and its ceilings, the bay.
	_mass(LONG[0], GALLERY[0] - 1, S3, ROWS - 1)
	_mass(GALLERY[0], GALLERY[1], S3, ROWS - 1, false)
	_cell_row_cap(GALLERY[0], GALLERY[1], S3)
	# Gallery ceilings (solid down to the headroom): conduit 2 tiles, crates 3, bot corridor 4, shutter 3.
	_mass(GALLERY[0], 72, GROOF, S3 - 3)
	_mass(73, 81, GROOF, S3 - 4)
	_mass(82, 94, GROOF, S3 - 5)
	_mass(95, GALLERY[1], GROOF, S3 - 4)
	# Bay: a deck over the machine's track, its floor 4 tiles under, walls both ends.
	_deck(BAY[0], BAY[1], S3, 1)
	_mass(BAY[0], BAY[1], BAY_FLOOR, ROWS - 1)
	# After the bay: the roof run, the gate house (a ceiling over the shutter), the tower.
	_mass(BAY_WALL, TOWER[0] - 1, S3, ROWS - 1)
	_mass(BAY_WALL, BAY_WALL + 3, GROOF, S3 - 4)
	for x in range(TOWER[0], TOP_FLAT_END + 1):
		_column(x, S4, ROWS - 1)
	for i in range(5):  # the stairs: 2 tiles a step, a single jump each
		_column(146 + i, S4 + 2 + 2 * i, ROWS - 1)
	_mass(151, GAP[1], PIT, ROWS - 1)
	_mass(LAND[0], LAND[1], S4, ROWS - 1)
	_lip(TOP_FLAT_END, S4)
	# The Surge pad sits in a low tunnel (32 px of headroom under a block that reaches the
	# roof): whoever climbed the tower on Spring walks through it, the pad replaces Spring
	# with Surge, and only then comes the lip. Spring's double jump (297 px) would cross the
	# nine-tile gap too (266 needed), and Surge's (334) is not far ahead of it, so the pad is
	# made unavoidable instead of the gap wider.
	_mass(TUNNEL[0], TUNNEL[1], 0, S4 - 2, false)
	_lip(LAND[0], S4)
	# The exit: a parapet on the last tile, then the bulkhead.
	for y in range(S4 - 4, S4):
		_cell(COLS - 1, y, BULKHEAD, FLAT)


func _cell_row_cap(x0: int, x1: int, y: int) -> void:
	## The gallery floor surface (the gallery mass is built without a cap).
	for x in range(x0, x1 + 1):
		_cell(x, y, STEEL, BEVEL)


func _interiors() -> void:
	## Dark back walls behind the covered spaces (so the sky does not show through them).
	var gal := Rect2(GALLERY[0] * T, (S3 - 4) * T, (GALLERY[1] + 1 - GALLERY[0]) * T, 4 * T)
	_interior("GalleryInterior", gal, Color("10121f"))
	_interior("GatehouseInterior", Rect2(BAY_WALL * T, (S3 - 3) * T, 4 * T, 3 * T), Color("10121f"))
	var bay := Rect2(BAY[0] * T, (S3 + 1) * T, (BAY[1] + 1 - BAY[0]) * T, (BAY_FLOOR - S3 - 1) * T)
	_interior("BayInterior", bay, Color("141a2c"))
	# Bay detail: ribs and a pipe along the back wall, the track on the floor.
	for i in range(BAY[0] + 2, BAY[1], 4):
		var rib := ColorRect.new()
		rib.name = "BayRib%d" % i
		rib.color = Color("1c2c3b")
		rib.position = Vector2(i * T, bay.position.y)
		rib.size = Vector2(6, bay.size.y)
		rib.z_index = -1
		_own(rib)
	var pipe := ColorRect.new()
	pipe.name = "BayPipe"
	pipe.color = Color("2a4658")
	pipe.position = Vector2(bay.position.x, bay.position.y + 24)
	pipe.size = Vector2(bay.size.x, 8)
	pipe.z_index = -1
	_own(pipe)
	var rail := ColorRect.new()
	rail.name = "BayRail"
	rail.color = Color("d07a26")
	rail.position = Vector2(bay.position.x + 4, BAY_FLOOR * T - 3)
	rail.size = Vector2(bay.size.x - 8, 3)
	rail.z_index = 1
	_own(rail)
	# The gallery's wiring.
	var cable := ColorRect.new()
	cable.name = "GalleryConduitPipe"
	cable.color = Color("2a4658")
	cable.position = Vector2(gal.position.x, gal.position.y + 6)
	cable.size = Vector2(gal.size.x, 6)
	cable.z_index = -1
	_own(cable)


func _interior(node_name: String, r: Rect2, c: Color) -> void:
	var cr := ColorRect.new()
	cr.name = node_name
	cr.color = c
	cr.position = r.position
	cr.size = r.size
	cr.z_index = -1
	_own(cr)


func _back_decor() -> void:
	# Far container stacks behind the yard floor and the roofs, and the gantry crane.
	for d in [[0, 8, G, 2, TEAL], [10, 17, G, 1, RUST], [19, 25, G, 2, MAROON], [26, 32, G, 3, TEAL]]:
		_back_stack(d[0], d[1], d[2], d[3], d[4])
	for d in [[36, 43, S1, 2, RUST], [44, 52, S1, 1, TEAL], [56, 64, S3, 2, TEAL], [58, 63, S3 - 4, 1, MAROON]]:
		_back_stack(d[0], d[1], d[2], d[3], d[4])
	for d in [[130, 136, S3, 2, RUST], [152, 155, PIT, 2, TEAL], [158, 164, S4, 2, TEAL], [165, 169, S4, 3, RUST]]:
		_back_stack(d[0], d[1], d[2], d[3], d[4])
	# The gantry crane: two posts, a jib and a hanging cable with its hook block.
	_truss(24, 12, G - 1)
	_truss(26, 12, G - 1)
	_beam(24, 48, 11)
	_beam(24, 48, 12)
	for y in range(13, 24):
		_cell(41, y, STEEL, Vector2i(12, 4), back_tiles)
	_cell(41, 24, STEEL, Vector2i(3, 2), back_tiles)
	# A second, lower crane over the long roof, and a lattice mast by the tower.
	_truss(60, 8, S3 - 1)
	_beam(52, 64, 8)
	_truss(133, 6, S3 - 1)
	_beam(126, 134, 6)
	_truss(161, 3, S4 - 1)
	_truss(163, 3, S4 - 1)
	_beam(161, 163, 3)


func _place_actors() -> void:
	# --- A: arrival ---
	_mono("StacksArrival", "stacks_arrival", Vector2(START_COL * T + 16, G * T), Vector2(192, 96))
	_put("res://scenes/actors/gem.tscn", "GemA1", 11, G - 2)
	_put("res://scenes/actors/gem.tscn", "GemA2", 16, G - 3)
	var bot1 := _put("res://scenes/actors/patrol_bot.tscn", "Bot1", 23, G, {"stomps_to_befriend": 99})
	bot1.set("dir", -1)
	_put("res://scenes/actors/gem.tscn", "GemA3", 21, G - 1)
	_put("res://scenes/actors/gem.tscn", "GemA4", 26, G - 1)
	_put("res://scenes/actors/gem.tscn", "GemA5", 30, G - 1)

	# --- B1: Spring, discovery: the pad at the foot of the wall ---
	_mono("SpringHint", "spring_hint", _p(PAD1_COL - 5, G), Vector2(96, 96))
	_pad("PadSpring1", PAD1_COL, G, 2)
	_mono("SpringFirst", "spring_first", _p(PAD1_COL, G), Vector2(44, 40))

	# --- B2: use it ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointA", 36, S1, {"checkpoint_id": "cp_a"})
	_put("res://scenes/actors/gem.tscn", "GemShed1", 38, S1 - 1)
	_mono("SpringHintLedge", "spring_hint_ledge", _p(PAD2_COL - 3, S1), Vector2(64, 96))
	_pad("PadSpring2", PAD2_COL, S1, 2)
	_put("res://scenes/actors/gem.tscn", "GemLedge1", 46, S2 - 1)
	_put("res://scenes/actors/gem.tscn", "GemLedge2", 49, S2 - 1)

	# --- C: the long roof ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointB", 57, S3, {"checkpoint_id": "cp_b"})
	_put("res://scenes/actors/gem.tscn", "GemRoof1", 60, S3 - 1)
	_put("res://scenes/actors/gem.tscn", "GemRoof2", 63, S3 - 1)

	# --- D: the conduit ---
	var conduit: Area2D = load("res://scripts/actors/conduit.gd").new()
	conduit.name = "Conduit"
	conduit.position = _p(CONDUIT_COL, S3)
	conduit.set("size", Vector2(96, 64))
	conduit.set("cable_anchor", Vector2(0, -64))
	_own(conduit)
	var line: Area2D = load("res://scripts/actors/shock_line_trigger.gd").new()
	line.name = "ConduitLine"
	line.set("line_id", "conduit")
	line.set("size", Vector2(192, 64))
	line.position = _p(CONDUIT_COL + 1, S3)
	_own(line)

	# --- E: the shockwave lessons ---
	var n := 0
	for x in CRATE_COLS:
		for k in range(3):
			var drop := 2 if (x == CRATE_COLS[1] and k == 0) else 0
			_put("res://scenes/actors/crate_breakable.tscn", "Crate%d" % n, x, S3 - k, {"drop": drop})
			n += 1
	var stack_bot := _put("res://scenes/actors/patrol_bot.tscn", "StackBot", 91, S3, {"stomps_to_befriend": 99})
	stack_bot.set("dir", -1)
	var sw := _put("res://scenes/actors/shock_switch.tscn", "ShockSwitch", SWITCH_COL, S3, {"auto_off": 6.0})
	sw.position = Vector2(SWITCH_COL * T + 16, S3 * T - 52)
	sw.z_index = -1
	_put("res://scenes/actors/shutter.tscn", "GalleryShutter", GATE_COL, S3, {
		"height_tiles": 3, "controller": NodePath("../ShockSwitch")})
	_put("res://scenes/actors/gem.tscn", "GemGallery1", 75, S3 - 1)
	_put("res://scenes/actors/gem.tscn", "GemGallery2", 86, S3 - 1)
	_put("res://scenes/actors/gem.tscn", "GemGallery3", 97, S3 - 1)

	# --- F: the machine bay ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointBay", 101, S3, {"checkpoint_id": "cp_bay"})
	_mono("MirrorLine", "mirror_bot", _p(BAY[0] + 1, S3), Vector2(96, 96))
	var bot: Node2D = load("res://scripts/actors/mirror_bot.gd").new()
	bot.name = "MirrorBot"
	bot.position = _p(MIRROR_COL, BAY_FLOOR)
	_own(bot)
	var plate := _put("res://scenes/actors/floor_plate.tscn", "BayPlate", 0, BAY_FLOOR, {"width": 56.0})
	plate.position = Vector2(PLATE_X, BAY_FLOOR * T)
	_put("res://scenes/actors/shutter.tscn", "BayShutter", BAY_GATE_COL, S3, {
		"height_tiles": 3, "controller": NodePath("../BayPlate")})
	for c in range(106, 124, 4):
		_put("res://scenes/actors/gem.tscn", "GemBay%d" % c, c, S3 - 1)

	# --- G: Spring up the tower, Surge across the gap ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointC", 131, S3, {"checkpoint_id": "cp_c"})
	_put("res://scenes/actors/gem.tscn", "GemTower1", 133, S3 - 1)
	_put("res://scenes/actors/gem.tscn", "GemTower2", 135, S3 - 1)
	_mono("SpringHintCombine", "spring_hint_combine", _p(PAD3_COL - 4, S3), Vector2(96, 96))
	_pad("PadSpring3", PAD3_COL, S3, 2)
	_pad("PadSurge1", SURGE_COL, S4, 1)
	_put("res://scenes/actors/gem.tscn", "GemTop1", 142, S4 - 1)
	_put("res://scenes/actors/gem.tscn", "GemTop2", 144, S4 - 1)
	for c in [152, 154]:
		_put("res://scenes/actors/gem.tscn", "GemPit%d" % c, c, PIT - 1)
	# The gap: a trail of gems in the arc of the Surge jump.
	for c in range(148, 154, 2):
		_put("res://scenes/actors/gem.tscn", "GemArc%d" % c, c, S4 - 3)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointD", 158, S4, {"checkpoint_id": "cp_d"})
	_mono("StacksExit", "stacks_exit", _p(161, S4), Vector2(128, 96))
	_put("res://scenes/actors/gem.tscn", "GemExit1", 162, S4 - 1)
	_put("res://scenes/actors/gem.tscn", "GemExit2", 164, S4 - 1)


func _pad(node_name: String, col: int, row: int, power: int) -> void:
	_put("res://scenes/actors/pad.tscn", node_name, col, row, {"power": power, "duration": 10.0, "cooldown": 3.0})


func _mono(node_name: String, line_id: String, pos: Vector2, size: Vector2) -> void:
	var t: Area2D = load("res://scripts/actors/monologue_trigger.gd").new()
	t.name = node_name
	t.set("line_id", line_id)
	t.set("require_mind", true)
	t.set("size", size)
	t.position = pos
	_own(t)


func _stoppers() -> void:
	## Invisible bot walls (physics layer 7): Bot1 walks cols 20-27, the gallery bot cols 84-93.
	for col in [19, 28, BOT_RANGE[0], BOT_RANGE[1]]:
		var floor_row := G if col < 40 else S3
		var sb := StaticBody2D.new()
		sb.name = "Stopper%d" % col
		sb.collision_layer = 64
		sb.collision_mask = 0
		sb.position = Vector2(col * T + T / 2.0, floor_row * T)
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = Vector2(T, 3 * T)
		cs.shape = r
		cs.position = Vector2(0, -1.5 * T)
		cs.name = "Shape"
		sb.add_child(cs)
		_own(sb)
		cs.owner = room


func _puddles() -> void:
	## [name, centre col, row, width px]
	var defs := [
		["PuddleA1", 9.0, G, 128.0], ["PuddleA2", 25.0, G, 160.0], ["PuddleShed", 47.0, S1, 128.0],
		["PuddleRoof", 61.0, S3, 160.0], ["PuddleRun", 133.0, S3, 128.0], ["PuddleTop", 143.0, S4, 96.0],
		["PuddleLand", 160.0, S4, 128.0],
	]
	for d in defs:
		var z := PuddleZone.new()
		z.name = d[0]
		z.width = d[3]
		z.position = Vector2(d[1] * T, d[2] * T)
		_own(z)


func _poles() -> void:
	## Floodlights on poles. [col, base row, flicker, energy, height px]
	var defs := [
		[8, G, false, 1.5, 170], [30, G, true, 1.6, 150], [35, S1, false, 1.6, 120], [52, S1, true, 1.5, 150],
		[62, S3, false, 1.5, 170], [131, S3, false, 1.4, 150], [136, S3, true, 1.5, 120], [141, S4, false, 1.5, 150],
		[157, S4, false, 1.4, 170], [165, S4, true, 1.6, 150],
	]
	var i := 0
	for d in defs:
		var pole := Node2D.new()
		pole.name = "Pole%d" % i
		pole.position = Vector2(d[0] * T + 16, d[1] * T)
		pole.z_index = -1
		_own(pole)
		var shaft := ColorRect.new()
		shaft.name = "Shaft"
		shaft.color = Color("2a4658")
		shaft.position = Vector2(-2, -d[4])
		shaft.size = Vector2(4, d[4])
		_own_under(pole, shaft)
		var hi := ColorRect.new()
		hi.name = "ShaftHi"
		hi.color = Color("5b7280")
		hi.position = Vector2(-2, -d[4])
		hi.size = Vector2(1, d[4])
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
		lamp.mode = WarningLight.Mode.FLICKER if d[2] else WarningLight.Mode.STEADY
		lamp.energy = d[3]
		lamp.light_radius_scale = 3.4
		lamp.halo_strength = 0.4
		lamp.shadows = d[2]
		lamp.position = Vector2(0, -d[4] - 8)
		lamp.z_index = 1
		_own_under(pole, lamp)
		i += 1


func _lamps() -> void:
	## Lamps inside the gallery and the bay, and the rotating beacons on the perimeter side.
	var defs := [
		["LampConduit", 67, S3 - 2, 1.5, WarningLight.Mode.FLICKER], ["LampCrates", 75, S3 - 3, 1.4, WarningLight.Mode.STEADY],
		["LampBot", 88, S3 - 4, 1.5, WarningLight.Mode.STEADY], ["LampShutter", 97, S3 - 3, 1.4, WarningLight.Mode.STEADY],
		["LampBay1", 108, S3 + 1, 1.6, WarningLight.Mode.STEADY], ["LampBay2", 120, S3 + 1, 1.6, WarningLight.Mode.STEADY],
		["LampGate", 127, S3 - 3, 1.4, WarningLight.Mode.STEADY],
		["BeaconA", 168, S4 - 5, 1.2, WarningLight.Mode.ROTATE],
	]
	for d in defs:
		var lamp := WarningLight.new()
		lamp.name = d[0]
		lamp.art_scale = 1
		lamp.mode = d[4]
		lamp.energy = d[3]
		lamp.light_radius_scale = 3.0
		lamp.halo_strength = 0.4
		lamp.shadows = false
		lamp.position = Vector2(d[1] * T + 16, d[2] * T + 8)
		lamp.z_index = 1
		_own(lamp)
