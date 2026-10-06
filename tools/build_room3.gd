## Generates res://scenes/levels/room3.tscn (Room 3, "The Stacks"); its exit leads to
## res://scenes/ui/world_map.tscn. Run:
##   godot --headless --path . res://tools/build_runner.tscn -- --builder=res://tools/build_room3.gd
##
## The Stacks is the tall room: 48 rows (1536 px, four screens), 172 columns. It climbs
## from the yard floor through container towers and a warehouse of stacked corridors to the
## crane girders and the exit roof, and the route turns back on itself so the tiers overlap:
##
##   rows   44  yard floor      A   arrival, a walker, crates                  east
##          38  shed roof       B1  SPRING 1: pad at the foot of a 6-tile wall
##          32  floating ledge  B2  SPRING 2: pad, ledge, long roof in one charge
##          26  long roof / C   C   the underfloor run (east): an electric strip, two ceiling
##                                  crawlers, a moving platform over a pit, a hopper, three
##                                  falling platforms over a pit (a Spring pad in each pit),
##                                  then a LIFT up through the floor above
##          20  D, the gallery  D   the conduit tunnel (the shockwave), crates, a patrol bot,
##                                  a shock switch and a shutter (west); the light well and its
##                                  girder ladder lead out onto the roof
##          14  E, the roof     E   (east) a crawlspace behind a cracked wall, a turret, an
##                                  explosive barrel chain and the sealed door of the VENT TOWER
##                                  (the high route: Spring, falling platforms, steam, the golden
##                                  bone and the memory fragment on the crane girders at the top),
##                                  a patrol bot, the mirror bay, a gate
##   (under the bay)  U   the UNDERCROFT, optional: a cracked wall at the foot of the lift, a corridor
##                         (crawlers, an electric strip), a 12-deep shaft with a pillar and four
##                         Spring pads, the loot (mice, bells, a fish) on the far landing
##           8  exit roof       G   SPRING 3: the tower, falling platforms over a pit, the exit
##
## Sizes come from the measured reach (tools/audit/reach.gd), centre travel and rise:
##                    single   double jump          rise: single   double
##   plain              122 px   223 px                   95 (3.0)   171 (5.3 tiles)
##   Spring             160 px   297 px                  211 (6.6)  284 (8.9 tiles)
## Every Spring wall is 6 tiles (192 px): past a plain double jump (21 px short), 19 px inside
## a held Spring single jump. Plain climbs are 2 tiles a step (a girder ladder, one-way).
## Builder for tools/build_runner.gd (autoloads are live there; --script mode lacks them).
## Rebuilds are deterministic: names are fixed and the runner re-uses the committed
## scene's unique_ids (see build_runner.gd).
extends RefCounted

## Set by _save on a pack or save failure; the runner turns it into the exit code.
var errors := 0


const T := 32
const ROWS := 48
const COLS := 172
const G := 44          ## yard floor surface row (y = 1408)
const R1 := 38         ## shed roof
const R2 := 32         ## floating ledge, the pit floors
const R3 := 26         ## long roof, the underfloor corridor C
const R4 := 20         ## the gallery D, the light well floor
const R5 := 14         ## the roof E, the bay deck
const R6 := 8          ## the tower top, the exit roof
const BAY_FLOOR := 18  ## the loader bot's track (4 under the deck)
const GROOF := 6       ## gate house roof

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

# ---- columns -----------------------------------------------------------------
const START_COL := 3
const PAD1_COL := 33              ## Spring, at the foot of the first wall (col 34)
const SHED := [34, 53]
const PAD2_COL := 41
const LEDGE := [45, 52]           ## the floating ledge: ends one tile short of the long roof wall
const LONG := [54, 65]            ## the long roof (open air)
const WELL_WALL := 66             ## the west wall of the light well (rows 14-21)
const WELL := [67, 70]            ## the light well: floor row 20, girder ladder to the roof
const BLD_E := 119                ## the east wall of the building
const PIT1 := [85, 92]            ## corridor C: pit with a moving platform
const PIT2 := [102, 109]          ## corridor C: pit with three falling platforms
const LIFT := [117, 118]          ## the lift up through the gallery floor
const STRIP := [59, 61]           ## the electric strip on the long roof
const CRAWLER_COLS := [74, 79]
const HOPPER_COL := 99
const CONDUIT_COL := 110
const TUNNEL := [107, 112]        ## 2 tiles high
const CRATE_COLS := [101, 102]
const CRATE_CEIL := [97, 106]     ## 3 tiles high
const BOT_RANGE := [82, 95]       ## stopper columns of the patrol bot's 4-tile corridor
const SWITCH_COL := 78
const GATE_COL := 75
const GATE_CEIL := [71, 79]       ## 3 tiles high
const PUMP := [76, 82]            ## the pump house on the roof, the crawlspace behind its cracked wall
const TURRET_COL := 81            ## on the pump house top
const BARRELS := [92, 93, 94]
const TOWER_W := 96               ## the vent tower: west wall (the blast door at its foot)
const VENT := [96, 107]
const VENT_PAD_COL := 99
const PILLAR := [100, 104]
const BAY := [120, 143]
const BAY_WALL := 144
const BAY_GATE_COL := 145
const PLATE_X := 144.0 * 32.0 - 28.0   ## the plate (56 px), flush with the bay wall: the pinned bot stands on it
const MIRROR_COL := 123
const PAD3_COL := 151             ## Spring, at the foot of the exit tower (col 152)
const UNDER_WALL := 119           ## the cracked wall at the east end of corridor C (the undercroft)
const UNDER := [120, 133]         ## the undercroft's corridor under the bay (row 26 floor, 4 tall)
const USHAFT := [134, 141]        ## the shaft: 12 deep, a pillar in it, a Spring pad on each side
const UPILLAR := [136, 139]       ## the pillar's top is row 32 (6 under the corridor)
const ULAND := [142, 143]         ## the far landing, the loot
const TOWER := [152, 156]
const XPIT := [157, 164]          ## the exit pit: two falling platforms, a pad in the pit
const LAND := [165, 171]
const EXIT_COL := 170

var room: Node2D
var tiles: TileMapLayer
var back_tiles: TileMapLayer


func build() -> void:
	_build_room3()


# ---- helpers ------------------------------------------------------------------

func _save(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	var e1 := packed.pack(root)
	var e2 := ResourceSaver.save(packed, path) if e1 == OK else e1
	print("save ", path, ": ", e2)
	errors += 0 if e2 == OK else 1


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


## A placed thing at an exact world position (platforms, hazards that are centred on their width).
func _putx(path: String, node_name: String, x: float, y: float, props := {}) -> Node:
	var n: Node2D = load(path).instantiate()
	n.name = node_name
	for k in props:
		n.set(k, props[k])
	n.position = Vector2(x, y)
	_own(n)
	return n


## A collectible: column `cx`, standing on surface row `row`, `dy` px above that surface.
## Yarn, bells and mice are all "Gem*" nodes (the world map counts them); the rest are named by the caller.
func _pick(kind: String, node_name: String, cx: int, row: int, dy := 16.0, props := {}) -> Node:
	var p := {"_dy": -dy}
	for k in props:
		p[k] = props[k]
	return _put("res://scenes/kit/pickup_%s.tscn" % kind, node_name, cx, row, p)


func _cell(x: int, y: int, mat: int, tile: Vector2i, layer: TileMapLayer = null) -> void:
	var l := layer if layer else tiles
	l.set_cell(Vector2i(x, y), 0, Vector2i(tile.x, tile.y + mat * 10))


func _clear(x0: int, x1: int, y0: int, y1: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			tiles.erase_cell(Vector2i(x, y))


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


func _lip(x: int, y: int) -> void:
	_cell(x, y, HAZARD, BEVEL)


## One-way girders: the cat jumps up through them and lands on top.
func _girder(x0: int, x1: int, y: int) -> void:
	for x in range(x0, x1 + 1):
		_cell(x, y, STEEL, GIRDER_H)


func _ground() -> void:
	for x in range(0, SHED[0]):  # the yard floor, up to the foot of the first wall
		_cell(x, G, STEEL, BEVEL)
		_cell(x, G + 1, MAROON, CROSS)   # solid: a one-way row here is a slit the cat can enter at an exposed face
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
	room.set("camera_follow", Level.CameraFollow.TIERS)
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
	exterior.extend_vertically = true
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
	exit_area.position = _p(EXIT_COL, R6)
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
	amb.bed = "amb_stacks"
	amb.surface = "step_concrete"
	_own(amb)

	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	_own(hud)

	# Under a roof the near rain stops: the underfloor corridor, the gallery, the gate house, the tower.
	var covered: Array[Rect2] = [
		Rect2(WELL_WALL * T, (R3 - 4) * T, (BLD_E - WELL_WALL) * T, 4 * T),
		Rect2(GATE_CEIL[0] * T, (R4 - 4) * T, (LIFT[1] + 1 - GATE_CEIL[0]) * T, 4 * T),
		Rect2(BAY_WALL * T, (R5 - 3) * T, 4 * T, 3 * T),
		Rect2((TOWER_W + 1) * T, 5 * T, 8 * T, 9 * T),
		Rect2(UNDER[0] * T, (R3 - 4) * T, (ULAND[1] + 1 - UNDER[0]) * T, 12 * T),
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
	# A: arrival crates to hop on the way.
	_crates(11, 12, 1)
	_crates(15, 16, 2)
	# B1/B2: the shed (the wall the first pad stands at) and the floating ledge.
	_mass(SHED[0], SHED[1], R1, ROWS - 1)
	for x in range(SHED[0], SHED[0] + 3):
		_lip(x, R1)
	_deck(LEDGE[0], LEDGE[1], R2, 2)
	# A strut under the ledge's left end: its face is a wall from the shed roof up, so a
	# cat rising beside it never bangs its head on an overhang.
	_mass(LEDGE[0], LEDGE[0] + 1, R2 + 2, R1 - 1, false)
	# ...and the ledge is a full column from the deck down to the shed roof, right up to the
	# one-tile slot beside the long roof (col 53): the slot is two tiles deep: a plain jump out.
	_mass(LEDGE[0] + 2, LEDGE[1] + 1, R2 + 2, R1 - 1, false)
	# C: the long roof, and the floor of the underfloor corridor: one surface from col 54 to the
	# east wall of the building.
	_mass(LONG[0], BLD_E, R3, ROWS - 1)
	# The light well's west wall (rows 14-21: a 12-tile wall from the long roof), the gallery
	# floor (the corridor's ceiling, 2 rows; open over the lift), the gallery roof (the roof run),
	# the building's east wall.
	_mass(WELL_WALL, WELL_WALL, R5, R4 + 1)
	_mass(WELL[0], LIFT[0] - 1, R4, R4 + 1)
	_mass(WELL[1] + 1, BLD_E, R5, R5 + 1)
	_mass(BLD_E, BLD_E, R5, ROWS - 1)
	# Gallery ceilings, lowered where the lessons need walls: conduit tunnel 2 tiles high,
	# crates 3 tiles, the shutter 3 tiles; the bot's corridor and the lift hall keep 4.
	_mass(TUNNEL[0], TUNNEL[1], R5 + 2, R5 + 3, false)
	_mass(CRATE_CEIL[0], CRATE_CEIL[1], R5 + 2, R5 + 2, false)
	_mass(GATE_CEIL[0], GATE_CEIL[1], R5 + 2, R5 + 2, false)
	# The pits in the corridor floor (6 deep): a Spring pad at the far wall of each, so a fall
	# is never a trap.
	for p in [PIT1, PIT2]:
		_clear(p[0], p[1], R3, R2 - 1)
		for x in range(p[0], p[1] + 1):
			_cell(x, R2, STEEL, BEVEL)
	# E: the pump house on the roof: a 2-tile block, a crawlspace in it behind a cracked wall.
	_mass(PUMP[0], PUMP[1], R5 - 2, R5 - 1)
	_clear(PUMP[0], PUMP[0] + 3, R5 - 1, R5 - 1)
	# The vent tower: a thin west wall with the sealed door at its foot, an east wall, a pillar
	# the Spring pad lifts the cat onto, and one-way girders across the top (the crane deck and
	# its skywalk).
	_mass(TOWER_W, TOWER_W, 5, R5 - 1)
	_clear(TOWER_W, TOWER_W, R5 - 2, R5 - 1)
	_mass(105, 107, 5, R5 - 1)
	_mass(PILLAR[0], PILLAR[1], R6, R5 - 1)
	_girder(TOWER_W, 112, 4)
	# F: the bay: a deck over the machine's track, its floor 4 tiles under, walls both ends.
	_deck(BAY[0], BAY[1], R5, 1)
	_mass(BAY[0], BAY[1], BAY_FLOOR, ROWS - 1)
	# After the bay: the gate house (a ceiling over the shutter, solid to the top so it cannot
	# be hopped), the roof run to the tower foot.
	_mass(BAY_WALL, PAD3_COL, R5, ROWS - 1)
	_mass(BAY_WALL, BAY_WALL + 3, GROOF, R5 - 4)
	# U: the undercroft, carved out of the bay's plinth: a corridor under the bay (4 tall), a shaft with
	# a pillar, the far landing. The corridor's west end is the east wall of the building (cracked).
	_clear(UNDER_WALL, UNDER_WALL, R3 - 2, R3 - 1)
	_clear(UNDER[0], ULAND[1], R3 - 4, R3 - 1)
	_clear(USHAFT[0], USHAFT[1], R3, 37)
	for x in range(UNDER[0], UNDER[1] + 1):
		_cell(x, R3, STEEL, BEVEL)
	for x in range(ULAND[0], ULAND[1] + 1):
		_cell(x, R3, STEEL, BEVEL)
	for x in range(USHAFT[0], USHAFT[1] + 1):
		_cell(x, 38, STEEL, BEVEL)
	_mass(UPILLAR[0], UPILLAR[1], R2, 37)
	# G: the exit tower, the pit with two falling platforms, the exit roof.
	_mass(TOWER[0], TOWER[1], R6, ROWS - 1)
	_mass(XPIT[0], XPIT[1], R5, ROWS - 1)
	_mass(LAND[0], LAND[1], R6, ROWS - 1)
	for y in range(R6 - 4, R6):
		_cell(COLS - 1, y, BULKHEAD, FLAT)


func _interiors() -> void:
	## Dark back walls behind the covered spaces (so the sky does not show through them).
	var corr := Rect2(WELL_WALL * T, (R3 - 4) * T, (BLD_E - WELL_WALL) * T, 4 * T)
	_interior("CorridorInterior", corr, Color("0f111e"))
	for p in [PIT1, PIT2]:
		_interior("PitInterior%d" % p[0], Rect2(p[0] * T, R3 * T, (p[1] + 1 - p[0]) * T, (R2 - R3) * T), Color("0b0d19"))
	_interior("UndercroftInterior", Rect2(UNDER[0] * T, (R3 - 4) * T, (ULAND[1] + 1 - UNDER[0]) * T, 4 * T), Color("0b0d19"))
	_interior("UndercroftShaft", Rect2(USHAFT[0] * T, R3 * T, (USHAFT[1] + 1 - USHAFT[0]) * T, (38 - R3) * T), Color("080a14"))
	var gal := Rect2((WELL[1] + 1) * T, (R4 - 4) * T, (LIFT[1] + 1 - WELL[1] - 1) * T, 4 * T)
	_interior("GalleryInterior", gal, Color("10121f"))
	_interior("ClosetInterior", Rect2((PUMP[0] + 1) * T, (R5 - 1) * T, 3 * T, T), Color("0b0d19"))
	_interior("TowerInterior", Rect2((TOWER_W + 1) * T, 5 * T, 8 * T, 9 * T), Color("0d1020"))
	_interior("GatehouseInterior", Rect2(BAY_WALL * T, (R5 - 3) * T, 4 * T, 3 * T), Color("10121f"))
	var bay := Rect2(BAY[0] * T, (R5 + 1) * T, (BAY[1] + 1 - BAY[0]) * T, (BAY_FLOOR - R5 - 1) * T)
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
	# The gallery's wiring and the corridor's pipe run.
	var cable := ColorRect.new()
	cable.name = "GalleryConduitPipe"
	cable.color = Color("2a4658")
	cable.position = Vector2(gal.position.x, gal.position.y + 6)
	cable.size = Vector2(gal.size.x, 6)
	cable.z_index = -1
	_own(cable)
	var cpipe := ColorRect.new()
	cpipe.name = "CorridorPipe"
	cpipe.color = Color("26404f")
	cpipe.position = Vector2(corr.position.x, corr.position.y + 10)
	cpipe.size = Vector2(corr.size.x, 5)
	cpipe.z_index = -1
	_own(cpipe)
	# Tower ladder rungs of light: a vertical conduit up the tower's back wall.
	var vent := ColorRect.new()
	vent.name = "TowerVentPipe"
	vent.color = Color("2a4658")
	vent.position = Vector2(97 * T + 10, 5 * T)
	vent.size = Vector2(6, 9 * T)
	vent.z_index = -1
	_own(vent)


func _interior(node_name: String, r: Rect2, c: Color) -> void:
	var cr := ColorRect.new()
	cr.name = node_name
	cr.color = c
	cr.position = r.position
	cr.size = r.size
	cr.z_index = -1
	_own(cr)


func _back_decor() -> void:
	# Far container stacks behind the yard floor and the roofs, and the gantry cranes.
	for d in [[0, 8, G, 2, TEAL], [10, 17, G, 1, RUST], [19, 25, G, 2, MAROON], [26, 32, G, 3, TEAL]]:
		_back_stack(d[0], d[1], d[2], d[3], d[4])
	for d in [[36, 43, R1, 3, RUST], [44, 52, R1, 2, TEAL], [54, 64, R3, 3, TEAL], [57, 63, R3 - 6, 1, MAROON]]:
		_back_stack(d[0], d[1], d[2], d[3], d[4])
	for d in [[72, 90, R5, 2, RUST], [108, 118, R5, 3, TEAL], [146, 151, R5, 2, MAROON], [158, 164, R5, 3, TEAL], [165, 171, R6, 3, RUST]]:
		_back_stack(d[0], d[1], d[2], d[3], d[4])
	# The gantry crane over the yard: two posts, a jib and a hanging cable with its hook block.
	_truss(24, 19, G - 1)
	_truss(26, 19, G - 1)
	_beam(24, 48, 18)
	_beam(24, 48, 19)
	for y in range(20, 31):
		_cell(41, y, STEEL, Vector2i(12, 4), back_tiles)
	_cell(41, 31, STEEL, Vector2i(3, 2), back_tiles)
	# A second crane over the long roof, a mast by the tower, and the crane over the vent tower's skywalk.
	_truss(60, 12, R3 - 1)
	_beam(52, 64, 12)
	_truss(114, 2, R5 - 1)
	_beam(106, 120, 2)
	_truss(160, 0, R6 - 1)
	_truss(162, 0, R6 - 1)
	_beam(160, 162, 0)


func _place_actors() -> void:
	var yarn := "yarn"
	# --- A: arrival ---
	_mono("StacksArrival", "stacks_arrival", Vector2(START_COL * T + 16, G * T), Vector2(192, 96))
	_pick(yarn, "GemA1", 11, G, 62)
	_pick("bell", "GemBellA2", 16, G, 94)
	var bot1 := _put("res://scenes/actors/patrol_bot.tscn", "Bot1", 23, G, {"stomps_to_befriend": 99})
	bot1.set("dir", -1)
	_pick(yarn, "GemA3", 21, G)
	_pick(yarn, "GemA4", 26, G)
	_pick(yarn, "GemA5", 30, G)

	# --- B1: Spring, discovery: the pad at the foot of the wall ---
	_mono("SpringHint", "spring_hint", _p(PAD1_COL - 5, G), Vector2(96, 96))
	_pad("PadSpring1", PAD1_COL, G, 2)
	_mono("SpringFirst", "spring_first", _p(PAD1_COL, G), Vector2(44, 40))

	# --- B2: use it ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointA", 36, R1, {"checkpoint_id": "cp_a"})
	_pick(yarn, "GemShed1", 38, R1)
	_mono("SpringHintLedge", "spring_hint_ledge", _p(PAD2_COL - 3, R1), Vector2(64, 96))
	_pad("PadSpring2", PAD2_COL, R1, 2)
	_pick(yarn, "GemLedge1", 46, R2)
	_pick(yarn, "GemLedge2", 49, R2)

	# --- C: the long roof: an electric strip, the underfloor corridor ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointB", 57, R3, {"checkpoint_id": "cp_b"})
	_putx("res://scenes/kit/electric_floor.tscn", "StripFloor", (STRIP[0] + 1.5) * T, R3 * T, {"width_tiles": 3})
	_pick("mouse", "GemMouseStrip", STRIP[0] + 1, R3, 76)
	_pick(yarn, "GemRoof2", 64, R3)
	_pick(yarn, "GemCorr1", 68, R3)
	_pick(yarn, "GemCorr2", 71, R3)
	for c in CRAWLER_COLS:
		_put("res://scenes/kit/crawler_bot.tscn", "Crawler%d" % c, c, R4 + 2, {"crawl_range": 30.0})
	_pick(yarn, "GemCrawl1", 77, R3)
	_pick(yarn, "GemCrawl2", 85 - 1, R3)
	_put("res://scenes/kit/pickup_fish.tscn", "FishC1", 83, R3, {"_dy": -16.0})
	# Pit 1: a moving platform across, a Spring pad at the far wall of the pit.
	_mono("SpringHintPit1", "spring_hint_roof", _p(PIT1[0] - 1, R3), Vector2(64, 96))
	_putx("res://scenes/kit/platform_horizontal.tscn", "MoverPit1", PIT1[0] * T + 48.0, R3 * T,
		{"width_tiles": 3, "travel": (PIT1[1] + 1 - PIT1[0]) * T - 96.0, "speed": 52.0, "pause": 0.8})
	_pad("PadSpringPit1", PIT1[1], R2, 2)
	_pick("bell", "GemBellPit1", 88, R3, 78)
	# The hopper's stretch.
	_put("res://scenes/kit/hopper_bot.tscn", "Hopper1", HOPPER_COL, R3, {"detect_range": 150.0})
	_pick(yarn, "GemHop1", 96, R3)
	_pick(yarn, "GemHop2", 101, R3)
	# Pit 2: three falling platforms across, a pad at the far wall.
	_mono("SpringHintPit2", "spring_hint_roof", _p(PIT2[0] - 1, R3), Vector2(64, 96))
	for k in 3:
		_putx("res://scenes/kit/platform_falling.tscn", "FallPit2%d" % k, (PIT2[0] + 1 + k * 3) * T, R3 * T,
			{"width_tiles": 2, "fall_delay": 0.9, "respawn_time": 3.0})
	_pad("PadSpringPit2", PIT2[1], R2, 2)
	_pick("bell", "GemBellPit2", 105, R3, 84)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointC", 112, R3, {"checkpoint_id": "cp_c"})
	_pick(yarn, "GemC3", 114, R3)
	# The lift up through the gallery floor.
	_mono("LiftLine", "stacks_lift", _p(LIFT[0] - 3, R3), Vector2(96, 96))
	_putx("res://scenes/kit/platform_vertical.tscn", "LiftC", (LIFT[0] + 1) * T, R4 * T,
		{"width_tiles": 2, "travel": (R3 - R4) * T, "speed": 56.0, "pause": 0.8})

	# --- D: the gallery: the conduit, the crates, the patrol bot, the switch ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointD", 114, R4, {"checkpoint_id": "cp_d"})
	_pick(yarn, "GemD1", 113, R4)
	var conduit: Area2D = load("res://scripts/actors/conduit.gd").new()
	conduit.name = "Conduit"
	conduit.position = _p(CONDUIT_COL, R4)
	conduit.set("size", Vector2(96, 64))
	conduit.set("cable_anchor", Vector2(0, -64))
	_own(conduit)
	var line: Area2D = load("res://scripts/actors/shock_line_trigger.gd").new()
	line.name = "ConduitLine"
	line.set("line_id", "conduit")
	line.set("size", Vector2(192, 64))
	line.position = _p(CONDUIT_COL - 1, R4)
	_own(line)
	_pick(yarn, "GemD2", 107, R4)
	# E-lessons: the shockwave breaks the crates (3 tall, 2 wide, filling the 3-tile corridor).
	var n := 0
	for x in CRATE_COLS:
		for k in range(3):
			var drop := 2 if (x == CRATE_COLS[0] and k == 0) else 0
			_put("res://scenes/actors/crate_breakable.tscn", "Crate%d" % n, x, R4 - k, {"drop": drop})
			n += 1
	_put("res://scenes/kit/pickup_fish.tscn", "FishD1", 98, R4, {"_dy": -16.0})
	_pick(yarn, "GemD3", 104, R4)
	var stack_bot := _put("res://scenes/actors/patrol_bot.tscn", "StackBot", 90, R4, {"stomps_to_befriend": 99})
	stack_bot.set("dir", -1)
	_pick(yarn, "GemD4", 92, R4)
	_pick(yarn, "GemD5", 86, R4)
	var sw := _put("res://scenes/actors/shock_switch.tscn", "ShockSwitch", SWITCH_COL, R4, {"auto_off": 6.0})
	sw.position = Vector2(SWITCH_COL * T + 16, R4 * T - 52)
	sw.z_index = -1
	_put("res://scenes/actors/shutter.tscn", "GalleryShutter", GATE_COL, R4, {
		"height_tiles": 3, "controller": NodePath("../ShockSwitch")})
	_pick(yarn, "GemD6", 80, R4)
	# The light well: the girder ladder out onto the roof.
	_girder(WELL[0], WELL[0] + 1, R4 - 2)
	_girder(WELL[0] + 2, WELL[1], R4 - 4)
	_pick(yarn, "GemWell1", WELL[0], R4 - 2)
	_pick(yarn, "GemWell2", WELL[0] + 2, R4 - 4)

	# --- E: the roof ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointRoof", 73, R5, {"checkpoint_id": "cp_roof"})
	_pick(yarn, "GemE1", 74, R5)
	# The pump house: a crawlspace behind a cracked wall, taught by the crates.
	_mono("CrackLine", "stacks_crack", _p(PUMP[0] - 2, R5), Vector2(96, 96))
	_put("res://scenes/kit/wall_cracked.tscn", "CrackedWall1", PUMP[0], R5, {"size_tiles": Vector2i(1, 1)})
	_pick("mouse", "GemMouseCloset", PUMP[0] + 3, R5, 16)
	_pick("bell", "GemBellCloset", PUMP[0] + 2, R5, 16)
	_put("res://scenes/kit/pickup_fish.tscn", "FishCloset", PUMP[0] + 1, R5, {"_dy": -16.0})
	_pick(yarn, "GemPump", PUMP[0] + 4, R5 - 2)
	# The turret on the pump house roof: the shockwave stuns it.
	_put("res://scenes/kit/sentry_turret.tscn", "Turret1", TURRET_COL, R5 - 2, {"detect_range": 220.0})
	_pick(yarn, "GemE3", 85, R5)
	_pick(yarn, "GemE4", 89, R5)
	# The barrel chain and the sealed door of the vent tower.
	_mono("BarrelLine", "stacks_barrels", _p(BARRELS[0] - 4, R5), Vector2(96, 96))
	for b in BARRELS:
		_put("res://scenes/kit/barrel_explosive.tscn", "Barrel%d" % b, b, R5, {"fuse": 1.0, "persist": true})
	_put("res://scenes/kit/wall_blast.tscn", "BlastDoor", TOWER_W, R5, {"size_tiles": Vector2i(1, 2)})
	_pick("bell", "GemBellBarrels", BARRELS[1], R5, 92)
	# The vent tower: Spring up the pillar, steam on the pillar top, a falling platform to the
	# crane deck, a flame vent between the arrival and the treasure.
	_mono("VentLine", "spring_hint_tower", _p(VENT_PAD_COL - 1, R5), Vector2(64, 96))
	_pad("PadSpringVent", VENT_PAD_COL, R5, 2)
	_pick("bell", "GemBellVent1", 101, R6, 16)
	_putx("res://scenes/kit/vent_steam.tscn", "VentSteam1", 102 * T + 16.0, R6 * T)
	_put("res://scenes/kit/pickup_fish.tscn", "FishVent", 100, R6, {"_dy": -16.0})
	_putx("res://scenes/kit/platform_falling.tscn", "FallVent", 104 * T, 6 * T, {"width_tiles": 2, "fall_delay": 0.9, "respawn_time": 3.0})
	_putx("res://scenes/kit/vent_flame.tscn", "VentFlame1", 101 * T + 16.0, 4 * T + 4.0, {"idle_time": 1.8})
	_mono("VentTopLine", "stacks_vent_top", _p(103, 4), Vector2(96, 96))
	_pick("bone", "GemBoneStacks", 98, 4, 14, {"_dy": -14.0})
	_pick("memory", "MemoryStacks", 97, 4, 18, {"memory_id": "memory_stacks"})
	_pick(yarn, "GemSky1", 109, 4, 12)
	_pick(yarn, "GemSky2", 111, 4, 12)
	_pick("bell", "GemBellSky", 106, 4, 40)
	# The patrol bot with a laser, between the turret and the barrels (the barrel chain can catch it too).
	_put("res://scenes/kit/kit_patrol_bot.tscn", "RoofBot", 85, R5)
	_pick(yarn, "GemE5", 109, R5)
	_pick(yarn, "GemE6", 116, R5)

	# --- F: the machine bay ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointBay", BAY[0] - 1, R5, {"checkpoint_id": "cp_bay"})
	_mono("MirrorLine", "mirror_bot", _p(BAY[0] + 1, R5), Vector2(96, 96))
	var bot: Node2D = load("res://scripts/actors/mirror_bot.gd").new()
	bot.name = "MirrorBot"
	bot.set("wake_dy", 150.0)   # it wakes for a cat on the catwalk, not for one in the undercroft below
	bot.position = _p(MIRROR_COL, BAY_FLOOR)
	_own(bot)
	var plate := _put("res://scenes/actors/floor_plate.tscn", "BayPlate", 0, BAY_FLOOR, {"width": 56.0})
	plate.position = Vector2(PLATE_X, BAY_FLOOR * T)
	_put("res://scenes/actors/shutter.tscn", "BayShutter", BAY_GATE_COL, R5, {
		"height_tiles": 3, "controller": NodePath("../BayPlate")})
	for c in range(124, 142, 4):
		_pick(yarn, "GemBay%d" % c, c, R5)

	# --- U: the undercroft (optional): through the cracked wall at the foot of the lift ---
	_put("res://scenes/kit/wall_cracked.tscn", "CrackedWall2", UNDER_WALL, R3, {"size_tiles": Vector2i(1, 2)})
	_pick("bell", "GemBellLiftFoot", 116, R3, 40)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointUnder", 122, R3, {"checkpoint_id": "cp_under"})
	_put("res://scenes/kit/pickup_fish.tscn", "FishUnder", 121, R3, {"_dy": -16.0})
	for c in [124, 126]:
		# a short roll (90 px/s for 2.5 s = 225 px): a ball burns out before it can reach the shaft's edge at col 134
		_put("res://scenes/kit/crawler_bot.tscn", "UnderCrawler%d" % c, c, R3 - 4, {"crawl_range": 20.0, "roll_speed": 90.0, "roll_time": 2.5})
	_putx("res://scenes/kit/electric_floor.tscn", "StripUnder", 128.0 * T + 16.0, R3 * T, {"width_tiles": 3, "start_offset": 0.7})
	_pick(yarn, "GemUnder1", 124, R3)
	_pick(yarn, "GemUnder2", 133, R3)
	_pick("mouse", "GemMouseUnder1", 128, R3, 76)
	_pad("PadSpringU1", 135, 38, 2)
	_pad("PadSpringU2", 140, 38, 2)
	_pad("PadSpringU3", 136, R2, 2)
	_pad("PadSpringU4", 139, R2, 2)
	_pick("bell", "GemBellUnderPillar", 137, R2, 16)
	_put("res://scenes/kit/sentry_turret.tscn", "TurretUnder", 143, R3, {"detect_range": 190.0})
	_pick("mouse", "GemMouseUnder2", 142, R3, 16)
	_pick("bell", "GemBellUnder", 142, R3, 62)
	_put("res://scenes/kit/pickup_fish.tscn", "FishUnder2", 139, R2, {"_dy": -16.0})

	# --- G: Spring up the exit tower, falling platforms over the pit, the exit ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointGate", 149, R5, {"checkpoint_id": "cp_gate"})
	_mono("SpringHintCombine", "spring_hint_combine", _p(PAD3_COL - 3, R5), Vector2(96, 96))
	_pad("PadSpring3", PAD3_COL, R5, 2)
	_pick(yarn, "GemTower1", 153, R6)
	_pick(yarn, "GemTower2", 155, R6)
	for k in 2:
		_putx("res://scenes/kit/platform_falling.tscn", "FallExit%d" % k, (XPIT[0] + 2 + k * 4) * T, R6 * T,
			{"width_tiles": 2, "fall_delay": 0.9, "respawn_time": 3.0})
	_pad("PadSpringExit", XPIT[1], R5, 2)
	_pick("bell", "GemBellExit", 160, R6, 70)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointExit", 166, R6, {"checkpoint_id": "cp_exit"})
	_mono("StacksExit", "stacks_exit", _p(167, R6), Vector2(128, 96))
	_pick(yarn, "GemExit1", 168, R6)
	_pick(yarn, "GemExit2", 169, R6)


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
	## Invisible bot walls (physics layer 7): Bot1 walks cols 20-27, the gallery bot cols 83-94,
	## the hopper cols 95-100 (so it cannot hop into a pit), the roof bot cols 84-87.
	for d in [[19, G], [28, G], [94, R3], [101, R3], [BOT_RANGE[0], R4], [BOT_RANGE[1], R4], [83, R5], [88, R5]]:
		var col: int = d[0]
		var sb := StaticBody2D.new()
		sb.name = "Stopper%d" % col
		sb.collision_layer = 64
		sb.collision_mask = 0
		sb.position = Vector2(col * T + T / 2.0, d[1] * T)
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
		["PuddleA1", 9.0, G, 128.0], ["PuddleA2", 25.0, G, 160.0], ["PuddleShed", 47.0, R1, 128.0],
		["PuddleRoof", 64.0, R3, 96.0], ["PuddleRoofE1", 83.0, R5, 128.0], ["PuddleRoofE2", 111.0, R5, 160.0],
		["PuddleRun", 149.0, R5, 96.0], ["PuddleTop", 154.0, R6, 96.0], ["PuddleLand", 168.0, R6, 128.0],
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
		[8, G, false, 1.5, 170], [30, G, true, 1.6, 150], [35, R1, false, 1.6, 120], [52, R1, true, 1.5, 150],
		[62, R3, false, 1.5, 170], [72, R5, false, 1.5, 150], [89, R5, true, 1.5, 150], [115, R5, false, 1.4, 150],
		[150, R5, false, 1.4, 140], [153, R6, true, 1.5, 120], [165, R6, false, 1.4, 170], [168, R6, true, 1.6, 150],
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
	## Lamps inside the corridor, the gallery, the tower and the bay, and the rotating beacon at the exit.
	var defs := [
		["LampCorr1", 74, R3 - 3, 1.4, WarningLight.Mode.STEADY], ["LampCorr2", 96, R3 - 3, 1.4, WarningLight.Mode.STEADY],
		["LampCorr3", 113, R3 - 3, 1.4, WarningLight.Mode.STEADY],
		["LampConduit", 109, R4 - 2, 1.5, WarningLight.Mode.FLICKER], ["LampCrates", 100, R4 - 3, 1.4, WarningLight.Mode.STEADY],
		["LampBot", 88, R4 - 4, 1.5, WarningLight.Mode.STEADY], ["LampShutter", 77, R4 - 3, 1.4, WarningLight.Mode.STEADY],
		["LampTower", 100, 7, 1.4, WarningLight.Mode.STEADY], ["LampTop", 100, 6, 1.3, WarningLight.Mode.FLICKER],
		["LampUnder1", 124, R3 - 3, 1.3, WarningLight.Mode.STEADY], ["LampUnder2", 131, R3 - 3, 1.3, WarningLight.Mode.FLICKER],
		["LampUnder3", 137, 29, 1.4, WarningLight.Mode.STEADY], ["LampUnder4", 137, 35, 1.3, WarningLight.Mode.STEADY],
		["LampBay1", 126, R5 + 1, 1.6, WarningLight.Mode.STEADY], ["LampBay2", 138, R5 + 1, 1.6, WarningLight.Mode.STEADY],
		["LampGate", 145, R5 - 3, 1.4, WarningLight.Mode.STEADY],
		["BeaconA", 171, R6 - 5, 1.2, WarningLight.Mode.ROTATE],
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
