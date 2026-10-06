## Generates res://scenes/levels/room1.tscn (Warehouse Room 1, the opening level), a TALL
## multi-tier Secret Agent / Duke Nukem 1 style level. Room 2 and the Room 3 stub come from
## tools/build_room2.gd. Run:
##   godot --headless --path . res://tools/build_runner.tscn -- --builder=res://tools/build_room1.gd
##
## No powers: plain run, jump (95 px = 2.97 tiles), double jump (171 px), crawl. Every required
## single-jump rise is at most 2 tiles, every required gap at most 3 tiles. Enemies avoid-only.
##
## The room is 133 x 36 tiles (4256 x 1152 px, 3.2 screens tall), camera_follow = TIERS.
## Tiers (surface rows, y = 32 row):
##   R  8  roof girders under the skylights          (y 256)
##   M 16  the mezzanine catwalk                      (y 512)
##   G 24  the receiving floor / the machine corridor (y 768)
##   B 33  the flooded basement                       (y 1056)
##
## The route, up and then down:
##   1 G west  (cols 0-57)   the nook (start, continue pad), a bot patrolling under a deck, a
##                           conveyor and a spike trap, then pallet racking up (rack steps);
##                           the floor east is blocked by a collapsed rack
##   2 M       (cols 12-57)  the mezzanine, walked WEST: a camera + shutter (detour: the service
##                           deck below the hole), a bot lane, to the freight lift at the west end
##   3 R       (cols 12-59)  up the freight lift to the roof girders, walked EAST under moonbeams:
##                           falling platform, a hover drone over a crossing, a ride across a
##                           gap, through the doorway into the vent shaft
##   4 shaft   (cols 60-67)  a long drop. Left half: down to the basement. Right half: a ledge,
##                           then the machine corridor (optional, harder, better loot)
##   5 B       (cols 60-133) the flooded basement walked EAST: puddles and drips, a pipe crawl,
##                           electric floor puddles, steam vents in the goo storage lab, the pool
##                           (unavoidable, under a solid ceiling), the wrecked crate, the loading door
##   office    (cols 69-125)  an optional upper tier in the east block: reached by a moving platform
##                           across the shaft from the roof doorway. A deck (barrels to push under a
##                           high ledge, the brass key), the floor below (a locked vault door, a crate
##                           to push onto a pressure plate that opens the shutter to the exit hatch)
##   G east    (cols 64-105) the optional machine corridor: electric floor, crusher, a bot, spikes;
##                           a hatch drops into the lab (rejoins before the pool)
##   B west    (cols 3-59)   the drain tunnel under the racks: the fake dead end with a crawl gap
##
## Secrets (no breakable walls): the crawl slit in the collapsed rack (letter C), the high ledge
## above the lift station (letter T), the roof loft in the girders (golden bone), and the drain
## tunnel's fake dead end with a crawl gap (the memory fragment).
##
## Builder for tools/build_runner.gd (autoloads are live there; --script mode lacks them).
## Rebuilds are deterministic: names are fixed and the runner re-uses the committed
## scene's unique_ids (see build_runner.gd).
extends RefCounted

## Set by _save on a pack or save failure; the runner turns it into the exit code.
var errors := 0


const T := 32
const COLS := 133
const ROWS := 36
const R := 8
const M := 16
const G := 24
const B := 33

# The pool (basement floor row B), cols inclusive.
const POOL := [116, 125]
const EXIT_COL := 131
const SHAFT0 := 60       ## shaft interior cols 60-67
const SHAFT1 := 67
const TOWER_WALL := 58   ## the tower's east wall: cols 58-59
const DOOR_COL := 126    ## the loading door's opening starts here

const STEEL := 0
const BULKHEAD := 1
const RUST := 2
const MAROON := 3
const TEAL := 4
const VIOLET := 5

const PIPE_V := [Vector2i(2, 0), Vector2i(2, 1)]
const BEVEL := Vector2i(0, 2)
const VENTBOX := Vector2i(1, 2)
const CROSS := Vector2i(2, 2)
const FRAMED := Vector2i(3, 2)
const FLAT := Vector2i(4, 3)
const RIVET := Vector2i(5, 3)
const PLATE_A := Vector2i(6, 3)
const GIRDER_V := Vector2i(12, 4)
const GIRDER_H := Vector2i(13, 4)

const SHAFT_ANGLE := 16.0

## Roof openings (cols, width in tiles): the nook, the tower, the vent shaft.
const SKYLIGHTS := [[1, 1], [14, 2], [26, 2], [38, 2], [50, 2], [62, 4]]
## Clerestory windows in the tower's back wall (x col; 88 x 108 at y 88).
const WINDOW_COLS := [6, 20, 32, 44]
## Steam vents in the lab: cols (each under a low ceiling block).
const LAB_VENTS := [94, 103, 108]

var room: Node2D
var tiles: TileMapLayer


func build() -> void:
	_build_room1()


# ---- Room 1 -----------------------------------------------------------------

func _build_room1() -> void:
	room = Node2D.new()
	room.name = "Room1"
	room.set_script(load("res://scripts/systems/room1.gd"))
	room.set("limits", Rect2i(0, 0, COLS * T, ROWS * T))
	room.set("camera_follow", Level.CameraFollow.TIERS)
	room.set("pool_trigger_x", float(POOL[0] * T + 56))
	var w := COLS * T

	var sky := ColorRect.new()
	sky.name = "SkyFill"
	sky.color = Color("0c1030")
	sky.position = Vector2(-64, -200)
	sky.size = Vector2(w + 128, ROWS * T + 400)
	_own(sky)

	var exterior := NightBackdrop.new()
	exterior.name = "Exterior"
	exterior.position = Vector2(0, 340)
	exterior.moon_position = Vector2(-210, -141)
	exterior.extend_vertically = true
	_own(exterior)

	var skylights: Array[Rect2] = []
	for s in SKYLIGHTS:
		skylights.append(Rect2(s[0] * T, 0, s[1] * T, 2 * T))
	_build_walls(skylights)
	_build_props()
	for sk in skylights:
		_shaft(sk)
	# Rain through the vent shaft's roof opening, visible only in the beam.
	_light_rain("HoleRain", Rect2(62 * T, 0, 4 * T, 0), 14.0 * T)

	tiles = TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	_own(tiles)
	_build_geometry(skylights)

	var nook := NookProp.new()
	nook.name = "Nook"
	nook.position = Vector2(2 * T, G * T)
	nook.z_index = 1
	_own(nook)

	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = _p(4, G)
	_own(start)

	_place_actors()
	_puddles()
	_pool()
	_low_beams()
	_stoppers()
	_lamps()
	_nanofluid_crate()
	_hints()

	var exit_area := RoomExit.new()
	exit_area.name = "RoomExit"
	exit_area.next_scene = "res://scenes/ui/world_map.tscn"
	exit_area.position = _p(EXIT_COL, B)
	_own(exit_area)

	var cat: Node = load("res://scenes/player/cat.tscn").instantiate()
	cat.name = "Cat"
	_own(cat)

	var rig := LightingRig.new()
	rig.name = "LightingRig"
	rig.night_tint = Color(0.36, 0.40, 0.58)
	rig.moon_angle = SHAFT_ANGLE
	rig.moon_energy = 0.85
	rig.glow_intensity = 0.8
	rig.vignette = 0.30
	var solid: Array[TileMapLayer] = [tiles]
	rig.solid_layers = solid
	_own(rig)

	_roof_extensions(w)

	var amb := Ambience.new()
	amb.name = "Ambience"
	amb.bed = "amb_warehouse"
	amb.surface = "step_metal"
	_own(amb)

	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	_own(hud)

	_save(room, "res://scenes/levels/room1.tscn")


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


func _mid(c0: int, c1: int) -> float:
	## The x of the middle of cols c0..c1 inclusive.
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
		if k != "_dy" and k != "_dx":
			n.set(k, props[k])
	n.position = _p(cx, cy) + Vector2(props.get("_dx", 0.0), props.get("_dy", 0.0))
	_own(n)
	return n


## Place a kit scene at an absolute pixel position.
func _kitx(id: String, node_name: String, x: float, y: float, props := {}) -> Node:
	var n: Node2D = load("res://scenes/kit/%s.tscn" % id).instantiate()
	n.name = node_name
	for k in props:
		n.set(k, props[k])
	n.position = Vector2(x, y)
	_own(n)
	return n


func _kit(id: String, node_name: String, cx: int, cy: int, props := {}) -> Node:
	return _put("res://scenes/kit/%s.tscn" % id, node_name, cx, cy, props)


## A collectible resting on surface row `row` at col `cx` (`up` px higher than the floor
## position). Named Gem*: the world map counts those.
func _gem(node_name: String, id: String, cx: int, row: int, up := 0.0, props := {}) -> Node:
	var p := props.duplicate()
	p["_dy"] = -8.0 - up
	return _kit("pickup_" + id, node_name, cx, row, p)


func _cell(x: int, y: int, mat: int, tile: Vector2i) -> void:
	tiles.set_cell(Vector2i(x, y), 0, Vector2i(tile.x, tile.y + mat * 10))


func _shaft(sk: Rect2) -> void:
	var shaft := MoonShaft.new()
	shaft.name = "MoonShaft%d" % int(sk.position.x / T)
	shaft.position = Vector2(sk.position.x + sk.size.x * 0.5, 40)
	shaft.angle = SHAFT_ANGLE
	# The nook's shaft reaches the floor; the roof skylights fall on the girders; the vent
	# shaft's wide opening lights the way down.
	var col := int(sk.position.x / T)
	shaft.length = float(G * T) - 40.0 if col == 1 else (14.0 * T if col == 62 else 8.0 * T - 20.0)
	shaft.top_width = sk.size.x - 4.0
	shaft.bottom_width = sk.size.x * 1.7
	shaft.ray_intensity = 0.10 if sk.size.x > T else 0.13
	shaft.ray_start = 2.0 * T - shaft.position.y
	shaft.light_energy = 1.0
	shaft.floor_glow = 0.30
	shaft.dust_amount = 60 if sk.size.x > T else 30
	shaft.dust_px = 1
	_own(shaft)


func _window_rain(node_name: String, r: Rect2, intensity: float) -> void:
	var wr := WindowRain.new()
	wr.name = node_name
	wr.position = r.position
	wr.size = r.size
	wr.intensity = intensity
	_own(wr)


func _light_rain(node_name: String, r: Rect2, floor_y: float) -> void:
	var rain := RainFX.new()
	rain.name = node_name
	rain.position = Vector2(r.position.x + 32.0, 40)
	rain.width = 48.0
	rain.floor_y = floor_y - 40.0
	rain.wind = 75.0
	rain.density = 70.0
	rain.lighting = RainFX.Lighting.LIGHT_ONLY
	rain.splash = false
	_own(rain)


func _lamp(node_name: String, pos: Vector2, shadows: bool, energy := 1.7) -> void:
	var lamp := WarningLight.new()
	lamp.name = node_name
	lamp.art_scale = 1
	lamp.mode = WarningLight.Mode.FLICKER if shadows else WarningLight.Mode.STEADY
	lamp.energy = energy
	lamp.light_radius_scale = 3.0
	lamp.halo_strength = 0.4
	lamp.shadows = shadows
	lamp.position = pos
	_own(lamp)


func _lamps() -> void:
	# Open truss (no shadows) on the decks, warning lamps at the tough spots.
	_lamp("LampDeck", Vector2(23 * T + 16, (G - 3) * T + 4 - 7), false)
	_lamp("LampRacks", Vector2(49 * T + 16, (G - 4) * T - 7), false, 1.5)
	_lamp("LampMezz", Vector2(33 * T + 16, M * T - 7), false, 1.6)
	_lamp("LampLift", Vector2(11 * T, M * T - 7), false, 1.5)
	_lamp("LampRoof", Vector2(30 * T + 16, R * T - 7), false, 1.4)
	_lamp("LampShaft", Vector2(66 * T + 16, 13 * T - 7), false, 1.5)
	_lamp("LampDrop", Vector2(62 * T, (B - 4) * T), false, 1.4)
	_lamp("LampDrain", Vector2(70 * T + 16, B * T - 7), true, 1.4)
	_lamp("LampMachine", Vector2(75 * T + 16, G * T - 7), true, 1.4)
	_lamp("LampLab", Vector2(98 * T + 16, B * T - 7), false, 1.5)
	_lamp("LampPool", Vector2((POOL[0] - 2) * T + 16, (B - 1) * T - 7), true, 1.4)  # on the near sill
	_lamp("LampOffice", Vector2(80 * T, R * T - 7), false, 1.5)
	_lamp("LampOfficeFloor", Vector2(100 * T, 17 * T - 7), false, 1.4)
	_lamp("LampVault", Vector2(118 * T, 17 * T - 7), false, 1.6)
	_lamp("LampTunnel", Vector2(30 * T + 16, (B - 1) * T), false, 1.2)


func _build_walls(skylights: Array[Rect2]) -> void:
	## Stacked back walls (the machinery band sits on each tier's floor).
	var windows: Array[Rect2] = []
	var holes: Array[Rect2] = []
	for c in WINDOW_COLS:
		var r := Rect2(c * T + 4, 88, 88, 108)
		windows.append(r)
		holes.append(r)
	for sk in skylights:
		if sk.position.x < SHAFT0 * T:
			holes.append(sk)
	var wall := BackWall.new()
	wall.name = "BackWall"
	wall.size = Vector2(SHAFT0 * T, G * T)
	wall.floor_y = G * T
	wall.holes = holes
	wall.windows = windows
	_own(wall)
	for r in windows:
		_window_rain("WindowRain%d" % int(r.position.x / T), r, 0.45)

	# The vent shaft: a tall wall with the roof opening at its top (no band).
	var shaft := BackWall.new()
	shaft.name = "BackWallShaft"
	shaft.position = Vector2(SHAFT0 * T, 0)
	shaft.size = Vector2((SHAFT1 - SHAFT0 + 1) * T, B * T)
	shaft.floor_y = B * T
	shaft.band_gaps = [Vector2(0, (SHAFT1 - SHAFT0 + 1) * T)]
	shaft.holes = [Rect2(2 * T, 0, 4 * T, 2 * T)]
	_own(shaft)

	# The machine corridor (rows 18-23, cols 68-105).
	var mach := BackWall.new()
	mach.name = "BackWallMachine"
	mach.position = Vector2((SHAFT1 + 1) * T, 17 * T)
	mach.size = Vector2((106 - SHAFT1 - 1) * T, 7 * T)
	mach.floor_y = 7 * T
	_own(mach)

	# The office tier (rows 3-17): windows on the night, a band at its floor.
	var off := BackWall.new()
	off.name = "BackWallOffice"
	off.position = Vector2(68 * T, 3 * T)
	off.size = Vector2((126 - 68) * T, 14 * T)
	off.floor_y = 14.0 * T
	var ow: Array[Rect2] = []
	for c in [74, 94, 104]:
		ow.append(Rect2((c - 68) * T + 4, 36, 88, 100))
	off.holes = ow
	off.windows = ow
	_own(off)
	for r in ow:
		_window_rain("OfficeRain%d" % int((r.position.x + off.position.x) / T), Rect2(r.position + off.position, r.size), 0.45)

	# The basement and the drain tunnel (rows 27-33), with the loading door at the east end.
	var base := BackWall.new()
	base.name = "BackWallBase"
	base.position = Vector2(0, 27 * T)
	base.size = Vector2(COLS * T, 7 * T)
	base.floor_y = float(B - 27) * T
	var door := Rect2(DOOR_COL * T, 1 * T, (COLS - DOOR_COL) * T, 5 * T)
	base.holes = [door]
	base.band_gaps = [Vector2(DOOR_COL * T, COLS * T)]
	_own(base)
	_window_rain("DoorRain", Rect2(door.position + base.position, door.size), 0.5)


func _build_props() -> void:
	var props := Node2D.new()
	props.name = "Props"
	_own(props)
	# [sprite, x px, floor row]
	var defs := [
		["servers", 6 * T + 8, G],
		["terminal", 11 * T + 12, G],
		["big-computer", 34 * T, G],
		["servers", 42 * T, G],
		["terminal", 53 * T, G],
		["servers", 15 * T, M],
		["big-computer", 22 * T, M],
		["servers", 30 * T + 4, M],
		["terminal", 51 * T, M],
		["servers", 18 * T, R],
		["terminal", 40 * T, R],
		["servers", 52 * T, R],
		["big-computer", 70 * T, G],
		["servers", 77 * T, G],
		["terminal", 88 * T, G],
		["servers", 94 * T, G],
		["servers", 72 * T, 17],
		["terminal", 78 * T, 17],
		["big-computer", 84 * T, 17],
		["servers", 100 * T, 17],
		["servers", 114 * T, 17],
		["big-computer", 117 * T + 8, 17],
		["terminal", 122 * T, 17],
		["servers", 76 * T, R],
		["terminal", 93 * T, R],
		["servers", 66 * T, B],
		["terminal", 72 * T + 8, B],
		["servers", 89 * T, B],
		["cryo-pod", 94 * T, B],
		["cryo-pod", 98 * T + 20, B],
		["elevator", 111 * T, B],
		["cryo-pod", 112 * T + 4, B],
		["big-computer", 128 * T, B],
		["terminal", 120 * T, B],
		["servers", 28 * T, B],
		["big-computer", 40 * T, B],
	]
	var i := 0
	for d in defs:
		var s := Sprite2D.new()
		s.name = "Prop%d" % i
		s.texture = load("res://assets/art_hd/props/%s.png" % d[0])
		s.centered = false
		s.position = Vector2(d[1], d[2] * T - s.texture.get_height())
		s.self_modulate = Color(0.7, 0.7, 0.7)
		_own_under(props, s)
		i += 1


# ---- geometry -----------------------------------------------------------------

func _mass(x0: int, x1: int, y0: int, y1: int, mat := BULKHEAD) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			_cell(x, y, mat, [FLAT, RIVET, FLAT, PLATE_A][(x + y) % 4])


## A solid floor: a steel bevel row on top and maroon plates beneath (3 rows).
func _floor(x0: int, x1: int, row: int) -> void:
	for x in range(x0, x1 + 1):
		_cell(x, row, STEEL, BEVEL)
		_cell(x, row + 1, MAROON, CROSS)   # solid (a one-way strip here is a walkable slit at an exposed face)
		_cell(x, row + 2, MAROON, FLAT if x % 2 == 0 else RIVET)


func _crates(x0: int, x1: int, row: int, h: int) -> void:
	## A stack of crates h tiles high standing on the surface at `row`: top surface at row - h.
	for x in range(x0, x1 + 1):
		for k in range(h):
			_cell(x, row - 1 - k, MAROON, FRAMED if (x + k) % 2 == 0 else CROSS)


func _deck(x0: int, x1: int, row: int, foot := -1) -> void:
	## A one-way deck. `foot` > row: a truss post under each end down to that row (decor).
	for x in range(x0, x1 + 1):
		_cell(x, row, STEEL, GIRDER_H)
	if foot > row:
		for x in [x0, x1]:
			for y in range(row + 1, foot):
				_cell(x, y, STEEL, GIRDER_V)


func _hangers(xs: Array, row: int) -> void:
	## Truss hangers from the roof down to a girder (decor).
	for x in xs:
		for y in range(2, row):
			_cell(x, y, STEEL, GIRDER_V)


func _build_geometry(skylights: Array[Rect2]) -> void:
	var sky_cols := {}
	for sk in skylights:
		for x in range(int(sk.position.x / T), int((sk.position.x + sk.size.x) / T)):
			sky_cols[x] = true
	# --- Roof (rows 0-1) over the whole room, minus the skylights ---
	for x in range(0, COLS):
		if sky_cols.has(x):
			continue
		_cell(x, 0, BULKHEAD, FLAT if x % 3 != 0 else RIVET)
		_cell(x, 1, BULKHEAD, BEVEL if x % 2 == 1 else VENTBOX)
	# --- Boundary walls ---
	for y in range(0, ROWS):
		_cell(-1, y, BULKHEAD, FLAT)
		_cell(COLS, y, BULKHEAD, FLAT)
	# (Solid and uniform: a pipe tile with gaps would be a ledge ladder up the wall.)
	for y in range(2, G):
		_cell(0, y, TEAL, FLAT)
	for y in range(2, B):
		_cell(COLS - 1, y, VIOLET, FLAT)

	# --- The tower: the ground slab (cols 0-59, rows 24-35) ---
	_floor(0, TOWER_WALL + 1, G)
	_mass(0, TOWER_WALL + 1, G + 3, ROWS - 1, MAROON)
	# The drain tunnel carved under it (rows 30-32, cols 3-59), then its floor.
	for x in range(3, TOWER_WALL + 2):
		for y in range(B - 3, B):
			tiles.erase_cell(Vector2i(x, y))
	# The fake dead end: cols 8-11 are a solid block over a crawl slit (the beam, _low_beams).
	_mass(8, 11, B - 3, B - 2, MAROON)
	# The tower's east wall (cols 58-59): solid, with the roof doorway (rows 4-7 open).
	_mass(TOWER_WALL, TOWER_WALL + 1, 2, 3)
	_mass(TOWER_WALL, TOWER_WALL + 1, R, G - 1)
	for x in [TOWER_WALL, TOWER_WALL + 1]:
		_cell(x, R, STEEL, GIRDER_H)   # the doorway's floor: a girder, level with the roof run (y 260)
		tiles.erase_cell(Vector2i(x, G - 1))   # the slit's pocket (the letter C)
	# The lift shaft's west wall (col 9, rows 2-15).
	for y in range(2, M):
		_cell(9, y, TEAL, FLAT)

	# --- G west: crates, the deck over the bot's lane, the rack steps, the collapsed rack ---
	_crates(13, 13, G, 1)
	_crates(15, 16, G, 2)
	_deck(17, 27, G - 3, G)
	_deck(44, 46, G - 2, G)
	_deck(48, 50, G - 4, G)
	_deck(52, 54, G - 6, G)
	# The collapsed rack across the floor (cols 56-57, crates rows 18-22); the slit at row 23
	# under them is the crawl (with the pocket at cols 58-59).
	_crates(56, 57, G - 1, 5)
	# Conveyor: the floor tiles under the belt are cut away (the belt is the floor).
	for x in range(35, 41):
		tiles.erase_cell(Vector2i(x, G))

	# --- M: the mezzanine catwalk (walked west), its hole, the service deck, the steps ---
	for x in range(12, 58):
		if x < 41 or x > 43:
			_cell(x, M, STEEL, GIRDER_H)
	for x in [12, 24, 40]:
		for y in range(M + 1, G):
			_cell(x, y, STEEL, GIRDER_V)
	_deck(29, 44, M + 4)               # the service deck (row 20) under the shutter (the detour)
	_deck(30, 32, M + 2, M + 4)        # steps up from the service deck (row 18) to the catwalk

	# --- R: the roof girders, hangers, the lofts ---
	_deck(12, 21, R)
	_deck(26, 33, R)
	_deck(37, 44, R)
	_deck(50, 57, R)
	_hangers([12, 21, 26, 33, 37, 44, 50, 57], R)
	_deck(12, 15, 4)    # the T ledge above the lift station
	_deck(38, 43, 4)    # the roof loft (golden bone)
	_hangers([15, 43], 4)

	# --- The vent shaft (cols 60-67) ---
	_deck(SHAFT0, SHAFT0 + 2, R)     # L0: the doorway's ledge
	_deck(64, 65, 13)                # L1: a ledge on the right half
	_mass(SHAFT1 + 1, COLS - 2, 2, 17)
	_office()
	_mass(106, COLS - 2, 18, 26)
	_deck(SHAFT0, SHAFT0 + 3, B - 5)   # L4: the catch ledge at the foot of the left half
	# The machine corridor's floor, cols 64-105 (row 24): a slab over the basement with a hatch.
	_floor(64, 105, G)
	for x in range(96, 100):
		for y in range(G, G + 3):
			tiles.erase_cell(Vector2i(x, y))
	# The corridor's crate bypass over the bot, and its far ledge.
	_crates(83, 83, G, 1)
	_crates(84, 84, G, 2)
	_deck(85, 92, G - 3)

	# --- The basement (floor row 33), cols 60-132 ---
	_floor(60, COLS - 1, B)
	for x in range(3, TOWER_WALL + 2):
		_cell(x, B, STEEL, BEVEL)
	# The pipe crawl: a ceiling block over cols 77-82 (rows 27-31) with the beam under it.
	_mass(77, 82, 27, B - 2)
	# Low ceilings over the steam vents (3 tiles of headroom = the steam column).
	for v in LAB_VENTS:
		_mass(v - 1, v + 1, 27, B - 4)
	# The pool: a sill (one tile) at each end, and a solid mass over it (3 tiles clearance).
	_mass(POOL[0] - 2, POOL[0] - 1, B - 1, B - 1, STEEL)
	_mass(POOL[1] + 1, POOL[1] + 2, B - 1, B - 1, STEEL)
	_mass(POOL[0] - 1, POOL[1] + 1, 27, B - 4)
	# The loading door's header (row 27); the opening below it, rows 28-32.
	_mass(DOOR_COL, COLS - 2, 27, 27)
	# Raised catwalks in the drain and over the electric floor (a bypass).
	_deck(70, 73, B - 2, B)
	_deck(87, 91, B - 2, B)


func _office() -> void:
	## The upper office tier: interior cols 69-125, rows 3-16, the doorway at col 68 (rows 3-7,
	## its floor the row-8 girder). The hatch (col 69, row 17) drops into the machine corridor.
	for x in range(69, 126):
		for y in range(3, 17):
			tiles.erase_cell(Vector2i(x, y))
	for y in range(3, 8):
		tiles.erase_cell(Vector2i(68, y))
	_cell(68, 8, STEEL, GIRDER_H)
	tiles.erase_cell(Vector2i(69, 17))
	_deck(69, 101, R)              # the upper deck, level with the roof run
	_deck(86, 90, 4)               # the high ledge: a pushed barrel is the step up
	_hangers_office([74, 84, 96], R)
	# The vault: a walled room (cols 111-125) with a 2-tile door at its foot, rows 15-16.
	# The way back up from the office floor (so the crate puzzle never traps anyone): zigzag
	# rack steps (rise 2, gap 1) at the east end, then a hop onto the deck.
	_deck(108, 110, 15, 17)
	_deck(104, 106, 13, 17)
	_deck(108, 110, 11, 15)
	_deck(104, 106, 9, 13)
	_mass(111, 111, 3, 14)
	_mass(112, 125, 3, 13)


func _hangers_office(xs: Array, row: int) -> void:
	for x in xs:
		for y in range(3, row):
			_cell(x, y, STEEL, GIRDER_V)


func _place_actors() -> void:
	var shut: Array[NodePath] = [NodePath("../ShutterMezz")]
	# ==== G west ====
	_put("res://scenes/actors/continue_pad.tscn", "ContinuePad", 9, G)
	_gem("GemA", "yarn", 7, G)
	_put("res://scenes/actors/letter.tscn", "LetterA", 3, G, {"letter_index": 1, "_dx": -2.0})
	_gem("GemCrate", "yarn", 15, G - 2)
	for i in 3:
		_gem("GemDeck%d" % (i + 1), "yarn", 19 + i * 3, G - 3)
	_kit("kit_patrol_bot", "BotDeck", 21, G, {"speed": 36.0, "laser_range": 140.0})
	_gem("GemBellLane", "bell", 23, G)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointA", 33, G, {"checkpoint_id": "cp_a"})
	_kitx("conveyor", "Belt1", _mid(35, 40), G * T, {"width_tiles": 6, "speed": -55.0})
	_gem("GemBelt", "yarn", 37, G)
	_kitx("spike_trap", "SpikesG", _mid(42, 43), G * T, {"width_tiles": 2, "idle_time": 1.6, "warn_time": 0.9, "live_time": 0.8})
	_gem("GemBellSpikes", "bell", 42, G, 70.0)
	_kit("pickup_fish", "FishRack", 47, G)
	_gem("GemRack1", "yarn", 45, G - 2)
	_gem("GemRack2", "yarn", 49, G - 4)
	_gem("GemRack3", "yarn", 53, G - 6)
	_gem("GemSlit", "yarn", 55, G)
	_put("res://scenes/actors/letter.tscn", "LetterC", 59, G, {"letter_index": 0})
	# ==== M (walked west) ====
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointB", 55, M, {"checkpoint_id": "cp_b"})
	_kit("pickup_fish", "FishMezz", 52, M)
	_gem("GemMezz1", "yarn", 50, M)
	_gem("GemMezz2", "yarn", 47, M)
	_kit("security_camera", "Camera1", 47, 9, {"sweep_min": 50.0, "sweep_max": 130.0, "sweep_speed": 22.0,
		"view_range": 260.0, "half_angle": 16.0, "spot_time": 0.9, "alarm_time": 6.0, "shutters": shut})
	_kit("kit_shutter", "ShutterMezz", 36, M, {"height_tiles": 3})
	_gem("GemMezz3", "yarn", 38, M)
	_gem("GemDetour", "bell", 42, M + 4)
	_gem("GemDetour2", "yarn", 30, M + 4)
	_gem("GemMezz4", "yarn", 26, M)
	_kit("kit_patrol_bot", "BotMezz", 38, M + 4, {"speed": 32.0, "laser_range": 150.0})
	_gem("GemMezzMouse", "mouse", 33, M + 4)
	_gem("GemDeckWest", "yarn", 20, M)
	_gem("GemDeckWest2", "yarn", 15, M)
	# ==== R (walked east) ====
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointC", 17, R, {"checkpoint_id": "cp_c"})
	_kitx("platform_vertical", "FreightLift", 11 * T, R * T + 4, {"width_tiles": 2, "travel": float((M - R) * T), "speed": 64.0, "pause": 1.4})
	_put("res://scenes/actors/letter.tscn", "LetterT", 13, 4, {"letter_index": 2})
	_gem("GemRoof1", "yarn", 14, R)
	_gem("GemRoof2", "yarn", 20, R)
	_kitx("platform_falling", "FallA", _mid(23, 24), R * T + 4, {"width_tiles": 2, "fall_delay": 0.9, "respawn_time": 3.0})
	_gem("GemFallBell", "bell", 23, R, 40.0)
	_kit("hover_drone", "Drone1", 30, R, {"patrol_range": 100.0, "drop_kind": HoverDrone.Drop.SPARK, "_dy": -150.0,
		"drop_range": 190.0, "cooldown": 2.6})
	_gem("GemRoof3", "yarn", 28, R)
	_gem("GemRoof4", "yarn", 32, R)
	_gem("GemRoof5", "yarn", 38, R)
	_gem("GemLoftBone", "bone", 40, 4)
	_kitx("platform_horizontal", "RideA", 46 * T, R * T + 4, {"width_tiles": 2, "travel": 96.0, "speed": 44.0, "pause": 0.7})
	_gem("GemRideBell", "bell", 47, R, 50.0)
	_gem("GemRoof6", "yarn", 54, R)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointD", 61, R, {"checkpoint_id": "cp_d"})
	# ==== The shaft ====
	_gem("GemShaftL1", "bell", 64, 13)
	# ==== Basement (walked east) ====
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointE", 66, B, {"checkpoint_id": "cp_e"})
	_kit("pickup_fish", "FishDrain", 64, B)
	_gem("GemDrain1", "yarn", 69, B)
	_gem("GemDrain2", "yarn", 75, B)
	_gem("GemDrainDeck", "yarn", 71, B - 2)
	_gem("GemCrawl", "mouse", 79, B)
	_kitx("electric_floor", "Electric1", _mid(88, 90), B * T, {"width_tiles": 3, "idle_time": 1.6, "warn_time": 0.9, "live_time": 1.1})
	_gem("GemElecBell", "bell", 89, B - 2)
	_gem("GemDrain3", "yarn", 84, B)
	_kit("pickup_fish", "FishLab", 85, B)
	var i := 0
	for v in LAB_VENTS:
		_kit("vent_steam", "Steam%d" % (i + 1), v, B, {"idle_time": 2.0, "warn_time": 0.8, "live_time": 1.2,
			"start_offset": i * 1.1, "column_height": 90.0})
		i += 1
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointF", 100, B, {"checkpoint_id": "cp_f"})
	_gem("GemLab1", "yarn", 97, B)
	_gem("GemLab2", "yarn", 105, B)
	_gem("GemLab3", "yarn", 111, B)
	# ==== The drain tunnel's closet: the memory fragment ====
	_gem("GemTunnel1", "yarn", 20, B)
	_gem("GemTunnel2", "yarn", 33, B)
	_gem("GemTunnelBell", "bell", 45, B)
	_gem("GemSlitYarn", "yarn", 12, B)
	_kit("pickup_fish", "FishCloset", 4, B)
	_gem("GemMemory", "memory", 6, B, 6.0, {"memory_id": "memory_warehouse"})
	# ==== The machine corridor (optional) ====
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointG", 66, G, {"checkpoint_id": "cp_g"})
	_kit("pickup_fish", "FishMachine", 68, G)
	_kitx("electric_floor", "Electric2", _mid(71, 73), G * T, {"width_tiles": 3, "idle_time": 1.5, "warn_time": 0.9, "live_time": 1.0})
	_gem("GemMachineBell1", "bell", 72, G, 100.0)
	_kitx("conveyor", "Belt2", _mid(74, 77), G * T, {"width_tiles": 4, "speed": 55.0})
	_kitx("crusher", "Crusher1", _mid(79, 80), 18 * T, {"width_tiles": 2, "stroke": 164.0})
	_gem("GemMachineMouse1", "mouse", 82, G)
	_kit("kit_patrol_bot", "BotMachine", 88, G, {"speed": 30.0, "laser_range": 170.0})
	_gem("GemMachineYarn1", "yarn", 87, G - 3)
	_gem("GemMachineYarn2", "yarn", 90, G - 3)
	_kitx("spike_trap", "SpikesMachine", _mid(94, 95), G * T, {"width_tiles": 2})
	_gem("GemMachineBell2", "bell", 94, G, 70.0)
	_gem("GemMachineMouse2", "mouse", 102, G)
	_place_office()


func _place_office() -> void:
	# The moving platform across the shaft, from the roof doorway ledge (L0) to the office doorway.
	_kitx("platform_horizontal", "RideB", 2048.0, R * T + 4, {"width_tiles": 2, "travel": 96.0, "speed": 44.0, "pause": 0.9})
	_gem("GemRideBBell", "bell", 65, R, 50.0)
	# The upper deck.
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointH", 71, R, {"checkpoint_id": "cp_h"})
	_gem("GemOffice1", "yarn", 74, R)
	_gem("GemOffice2", "yarn", 77, R)
	_put("res://scenes/kit/barrel_plain.tscn", "BarrelOffice1", 80, R, {"sprite_scale": 2.0})
	_put("res://scenes/kit/barrel_plain.tscn", "BarrelOffice2", 82, R, {"sprite_scale": 2.0})
	_gem("GemOfficeBell", "bell", 87, 4)
	_gem("GemOfficeMouse", "mouse", 89, 4)
	_put("res://scenes/actors/key.tscn", "KeyOffice", 99, R, {"key_color": "brass"})
	_gem("GemOffice3", "yarn", 95, R)
	# The floor below: fish, the crate and its plate, the shutter, the vault.
	_kit("pickup_fish", "FishOffice", 104, 17)
	_put("res://scenes/actors/crate_pushable.tscn", "CrateOffice", 102, 17)
	_put("res://scenes/actors/floor_plate.tscn", "PlateOffice", 98, 17)
	_put("res://scenes/actors/shutter.tscn", "ShutterOffice", 94, 17, {"height_tiles": 3, "controller": NodePath("../PlateOffice")})
	_put("res://scenes/actors/locked_door.tscn", "DoorOffice", 111, 17, {"key_color": "brass"})
	_gem("GemOffice4", "yarn", 90, 17)
	_gem("GemOfficeStep1", "yarn", 109, 15)
	_gem("GemOfficeStep2", "yarn", 105, 13)
	_gem("GemOffice5", "yarn", 80, 17)
	_gem("GemOfficeBell2", "bell", 72, 17)
	_gem("GemVault1", "mouse", 114, 17)
	_gem("GemVault2", "mouse", 122, 17)
	_gem("GemVault3", "bell", 118, 17)
	_gem("GemVault4", "bell", 124, 17)
	_gem("GemVault5", "yarn", 116, 17)
	_gem("GemVault6", "yarn", 120, 17)
	_kit("pickup_fish", "FishVault", 113, 17)


func _puddles() -> void:
	# [name, centre col (float ok), width px, drip, ceiling bottom y]
	var east := 27.0 * T
	var tunnel := 30.0 * T
	var defs := [
		["PuddleDrain1", 68.0, 96.0, true, east],
		["PuddleDrain2", 74.5, 96.0, false, east],
		["PuddleDrain3", 83.0, 64.0, false, east],
		["PuddleLab1", 91.0, 96.0, true, east],
		["PuddleLab2", 97.0, 128.0, true, east],
		["PuddleLab3", 111.0, 96.0, false, east],
		["PuddleTunnel1", 24.0, 128.0, true, tunnel],
		["PuddleTunnel2", 40.0, 96.0, true, tunnel],
		["PuddleTunnel3", 52.0, 96.0, false, tunnel],
		["PuddleBase", 62.0, 64.0, false, east],
	]
	for d in defs:
		var z := PuddleZone.new()
		z.name = d[0]
		z.width = d[2]
		z.position = Vector2(d[1] * T, B * T)
		_own(z)
		if d[3]:
			var drip := DripFX.new()
			drip.name = "Drip" + String(d[0]).trim_prefix("Puddle")
			var ceil_y: float = d[4] + 4.0
			drip.position = Vector2(d[1] * T, ceil_y)
			drip.fall_height = B * T - ceil_y
			drip.interval_min = 1.1
			drip.interval_max = 2.4
			_own(drip)
			drip.puddle = null  # set at runtime by Room1 wiring
			drip.set_meta("puddle_path", drip.get_path_to(z))


func _pool() -> void:
	var pool := GooPool.new()
	pool.name = "GooPool"
	pool.width = float((POOL[1] - POOL[0] + 1) * T)
	pool.depth = 36.0  # surface 4 px above the floor, covering the floor row
	pool.position = Vector2(POOL[0] * T, B * T - 4.0)
	pool.z_index = 6
	_own(pool)


func _nanofluid_crate() -> void:
	## The wrecked container past the pool (the floor between the far sill and the exit), with
	## the monologue triggers that read it. The cat walks in front of it; dressing only.
	var edge := float((POOL[1] + 3) * T)
	var crate := NanofluidCrate.new()
	crate.name = "NanofluidCrate"
	crate.position = Vector2(edge + 64.0, B * T)
	crate.z_index = 2
	_own(crate)
	var trigger_script: Script = load("res://scripts/actors/monologue_trigger.gd")
	var read: Area2D = trigger_script.new()
	read.name = "ReadContainer"
	read.set("line_id", "nanofluid_container")
	read.set("require_mind", true)
	read.set("size", Vector2(64, 96))
	read.position = Vector2(edge + 32.0, B * T)
	_own(read)
	var hint: Area2D = trigger_script.new()
	hint.name = "HintExit"
	hint.set("line_id", "exit_hint")
	hint.set("require_mind", true)
	hint.set("requires_played", "nanofluid_container")
	hint.set("size", Vector2(48, 96))
	hint.position = Vector2(edge + 80.0, B * T)
	_own(hint)


func _hints() -> void:
	## A few short text-only lines (no voice clip yet): see data/monologue.json "warehouse_*".
	var trigger_script: Script = load("res://scripts/actors/monologue_trigger.gd")
	var defs := [
		["HintClimb", "warehouse_climb", 50, G, Vector2(96, 96)],
		["HintRoof", "warehouse_roof", 24, R, Vector2(64, 96)],
		["HintShaft", "warehouse_shaft", 61, R, Vector2(64, 96)],
		["HintLab", "warehouse_lab", 96, B, Vector2(96, 96)],
	]
	for d in defs:
		var t: Area2D = trigger_script.new()
		t.name = d[0]
		t.set("line_id", d[1])
		t.set("size", d[4])
		t.position = _p(d[2], d[3])
		_own(t)


func _low_beams() -> void:
	## A beam hangs 12 px from a ceiling block's underside, leaving a 20 px gap above the floor:
	## the standing cat (26) cannot pass, the crouched cat (14) can.
	_low_beam("LowBeamPipe", 77, 82, B - 1)      # the basement's pipe crawl (required)
	_low_beam("LowBeamRack", 56, 59, G - 1)      # the slit at the foot of the collapsed rack (letter C)
	_low_beam("LowBeamDead", 8, 11, B - 1)       # the drain tunnel's crawl gap (the memory)


func _low_beam(node_name: String, c0: int, c1: int, row: int) -> void:
	var n := c1 - c0 + 1
	var beam := StaticBody2D.new()
	beam.name = node_name
	beam.position = Vector2((c0 + n / 2.0) * T, row * T)
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(n * T, 12)
	shape.shape = rs
	shape.name = "Shape"
	shape.position = Vector2(0, 6)
	beam.add_child(shape)
	for i in n:
		var s := TileArt.sprite("bulkhead", TileArt.FLAT, Rect2i(0, 0, T, 12))
		s.name = "Plate%d" % i
		s.position = Vector2((i - (n - 1) / 2.0) * T, 0)
		beam.add_child(s)
	_own(beam)
	for c in beam.get_children():
		c.owner = room


func _stopper(node_name: String, col: int, row: int) -> void:
	## An invisible wall on physics layer 7 ("bot_bounds"): solid only to bots.
	var sb := StaticBody2D.new()
	sb.name = node_name
	sb.collision_layer = 64
	sb.collision_mask = 0
	sb.position = Vector2(col * T + T / 2.0, row * T)
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(T, 2 * T)
	cs.shape = r
	cs.position = Vector2(0, -T)
	cs.name = "Shape"
	sb.add_child(cs)
	_own(sb)
	cs.owner = room


func _stoppers() -> void:
	# The deck bot keeps to its lane (cols 18-30); the mezzanine bot to cols 14-20 of the
	# catwalk; the machine bot to cols 85-92 (crates west, a stopper east).
	_stopper("Stopper17", 17, G)
	_stopper("Stopper25", 25, G)
	_stopper("StopperX93", 93, G)
	# The office: barrels stop short of the deck's end under the ledge; the crate rests on its plate
	# (west) and cannot be shoved into the vault wall (east): the puzzle can never be locked.
	_stopper("StopperOffice91", 91, R)
	_stopper("StopperOfficePlate", 97, 17)
	_stopper("StopperOfficeEast", 106, 17)


func _roof_extensions(w: int) -> void:
	var holder := Node2D.new()
	holder.name = "RoofExtensions"
	_own(holder)
	for r in [Rect2(-600, 0, 600, 2 * T), Rect2(w, 0, 600, 2 * T)]:
		var occ := LightOccluder2D.new()
		occ.name = "Roof%d" % int(r.position.x)
		var poly := OccluderPolygon2D.new()
		poly.polygon = PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0),
			r.end, r.position + Vector2(0, r.size.y)])
		poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
		occ.occluder = poly
		occ.occluder_light_mask = LightingRig.MASK_WORLD
		_own_under(holder, occ)
