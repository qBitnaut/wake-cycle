## Generates res://scenes/levels/room1.tscn (Warehouse Room 1, the opening
## level) and the stub res://scenes/levels/room2.tscn. Run:
##   godot --headless --path . --script res://tools/build_room1.gd
##
## Sizes come from the measured reach (tools/audit/reach.gd, plain movement):
##   single jump: 122 px of travel, 95 px (2.97 tiles) of rise
##   double jump: 223 px of travel, 171 px (5.3 tiles) of rise
## A gap of N px needs travel >= N - 22 (the cat is 22 px wide). So single
## jump gaps here are at most 3 tiles (96 px: needs 74, margin 48), the only
## double jump gap is 5 tiles, and single jump rises are at most 2 tiles.
##
## Beats, left to right (column numbers; 32 px tiles, floor surface at row 10):
##   A   0-13   the nook: asleep under a sliver of moonlight, wake-up, continue pad
##   B  14-40   crate stairs (1,2,3 high) up to a catwalk under two moon shafts,
##              a 3-tile gap, letter C on a perch, stairs down; checkpoint at 42
##   C  42-56   puddle hall: rain window, puddles to wade through, a patrol bot
##   D  57-69   crawl-under (low beam), wet, one drip
##   E  71-90   timed laser fence, then push the crate onto the plate: shutter
##   F  91-110  steps up to the key deck (letter A above it), brass door, checkpoint
##   G 111-123  three cycling steam vents under low ceilings
##   H 124-137  flooded lab hall: windows, puddles, drips, tanks (letter T on a perch)
##   I 136-149  the pool: a trough between two one-tile sills under a low ceiling,
##              10 tiles (cols 138-147) of dark water
##   J 148-153  the loading door, rain outside; the exit trigger at col 152
extends SceneTree

const T := 32
const G := 10          ## ground surface row (y = 320)
const ROWS := 14       ## 448 px: rows G+1..G+3 are the underfloor
const COLS := 155

# Pool: sunken floor, cols inclusive.
const POOL := [138, 147]
const EXIT_COL := 152

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

## Roof openings (cols, inclusive start, width in tiles).
const SKYLIGHTS := [[1, 1], [24, 2], [33, 2], [52, 2], [130, 2]]
## Windows (x, width px are 88 x 108 at y 88).
const WINDOW_COLS := [47, 124, 127]
## Steam vents: [col, cycle offset].
const VENTS := [[111, 0.0], [116, 2.0], [121, 1.0]]

var room: Node2D
var tiles: TileMapLayer


func _initialize() -> void:
	_build_room1()
	_build_room2()
	quit()


# ---- Room 1 -----------------------------------------------------------------

func _build_room1() -> void:
	room = Node2D.new()
	room.name = "Room1"
	room.set_script(load("res://scripts/systems/room1.gd"))
	room.set("limits", Rect2i(0, 24, COLS * T, 360))
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
	exterior.position = Vector2(0, 250)
	exterior.moon_position = Vector2(-210, -141)
	_own(exterior)

	var holes: Array[Rect2] = []
	var windows: Array[Rect2] = []
	for c in WINDOW_COLS:
		var r := Rect2(c * T + 4, 88, 88, 108)
		holes.append(r)
		windows.append(r)
	var skylights: Array[Rect2] = []
	for s in SKYLIGHTS:
		skylights.append(Rect2(s[0] * T, 0, s[1] * T, 2 * T))
	holes.append_array(skylights)
	# The loading door: a big opening in the back wall, the night outside.
	var door_hole := Rect2(148 * T, 5 * T, 7 * T, G * T - 5 * T)
	holes.append(door_hole)

	# Rain seen through the windows and the loading door (behind the wall art).
	var i := 0
	for r in windows:
		_window_rain("WindowRain%d" % i, r, 0.45)
		i += 1
	_window_rain("DoorRain", door_hole, 0.5)

	var wall := BackWall.new()
	wall.name = "BackWall"
	wall.size = Vector2(w, G * T)
	wall.floor_y = G * T
	wall.holes = holes
	wall.windows = windows
	wall.band_gaps = [Vector2(148 * T, 155 * T)]  # the loading door opens straight onto the night
	_own(wall)

	_build_props()

	for sk in skylights:
		_shaft(sk)
	# Rain through the roof hole over the puddle hall, visible only in the beam.
	_light_rain("HoleRain", Rect2(52 * T, 0, 2 * T, 0), 320.0)

	_underfloor()

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
	_steam()
	_pool()
	_low_beam()
	_stoppers()
	_lamps()

	var exit_area := RoomExit.new()
	exit_area.name = "RoomExit"
	exit_area.next_scene = "res://scenes/levels/room2.tscn"
	exit_area.position = _p(EXIT_COL, G)
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
	_own(amb)

	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	_own(hud)

	_save(room, "res://scenes/levels/room1.tscn")


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
		if k != "_dy":
			n.set(k, props[k])
	n.position = _p(cx, cy) + Vector2(0, props.get("_dy", 0.0))
	_own(n)
	return n


func _cell(x: int, y: int, mat: int, tile: Vector2i) -> void:
	tiles.set_cell(Vector2i(x, y), 0, Vector2i(tile.x, tile.y + mat * 10))


func _shaft(sk: Rect2) -> void:
	var shaft := MoonShaft.new()
	shaft.name = "MoonShaft%d" % int(sk.position.x / T)
	shaft.position = Vector2(sk.position.x + sk.size.x * 0.5, 40)
	shaft.angle = SHAFT_ANGLE
	shaft.length = float(G * T) - 40.0
	shaft.top_width = sk.size.x - 4.0
	shaft.bottom_width = sk.size.x * 1.7
	shaft.ray_intensity = 0.30 if sk.size.x > T else 0.42
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
	# On the catwalk deck (open truss: no shadows), above the key door, at the
	# last vent, and a warning lamp before the pool.
	_lamp("LampDeck", Vector2(23 * T + 16, (G - 3) * T + 4 - 7), false)
	_lamp("LampDoor", Vector2(101 * T + 16, G * T - 7), true, 1.5)
	_lamp("LampVent", Vector2(124 * T + 16, G * T - 7), false, 1.5)
	_lamp("LampPool", Vector2((POOL[0] - 2) * T + 16, (G - 1) * T - 7), true, 1.4)  # on the near sill


func _build_props() -> void:
	var props := Node2D.new()
	props.name = "Props"
	_own(props)
	var floor_y := float(G * T)
	var defs := [
		["servers", 6 * T + 8],
		["terminal", 11 * T + 12],
		["big-computer", 43 * T + 8],
		["servers", 55 * T],
		["terminal", 58 * T + 20],
		["servers", 71 * T + 10],
		["cryo-pod", 80 * T],
		["big-computer", 92 * T],
		["servers", 105 * T],
		["terminal", 109 * T],
		["servers", 113 * T + 8],
		["big-computer", 117 * T],
		["servers", 122 * T],
		["elevator", 132 * T],
		["cryo-pod", 133 * T + 20],
		["cryo-pod", 135 * T + 4],
		["big-computer", 144 * T],
		["terminal", 141 * T],
	]
	var i := 0
	for d in defs:
		var s := Sprite2D.new()
		s.name = "Prop%d" % i
		s.texture = load("res://assets/art_hd/props/%s.png" % d[0])
		s.centered = false
		s.position = Vector2(d[1], floor_y - s.texture.get_height())
		s.self_modulate = Color(0.7, 0.7, 0.7)
		_own_under(props, s)
		i += 1
	# The lab tanks glow faintly (set dressing hinting where the goo came from).


func _underfloor() -> void:
	var rect := ColorRect.new()
	rect.name = "Underfloor"
	rect.color = Color("1d1230")
	rect.position = Vector2(0, (G + 1) * T)
	rect.size = Vector2(COLS * T, (ROWS - G - 1) * T)
	_own(rect)


# ---- geometry -----------------------------------------------------------------

func _ground(x0: int, x1: int) -> void:
	for x in range(x0, x1 + 1):
		_cell(x, G, STEEL, BEVEL)
		_cell(x, G + 1, MAROON, GIRDER_H)
		_cell(x, G + 2, MAROON, FLAT if x % 2 == 0 else RIVET)
		_cell(x, G + 3, MAROON, RIVET if x % 2 == 0 else FLAT)


func _block(x0: int, x1: int, y0: int, y1: int, mat := BULKHEAD) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			_cell(x, y, mat, [FLAT, RIVET, FLAT, PLATE_A][(x + y) % 4])


func _crates(x0: int, x1: int, h: int) -> void:
	## A stack of crates h tiles high: top surface at row G - h.
	for x in range(x0, x1 + 1):
		for k in range(h):
			_cell(x, G - 1 - k, MAROON, FRAMED if (x + k) % 2 == 0 else CROSS)


func _girder(x0: int, x1: int, row: int, foot := G) -> void:
	## A one-way deck with a truss post under each end, down to row `foot`.
	for x in range(x0, x1 + 1):
		_cell(x, row, STEEL, GIRDER_H)
	for x in [x0, x1]:
		for y in range(row + 1, foot):
			_cell(x, y, STEEL, GIRDER_V)


func _build_geometry(skylights: Array[Rect2]) -> void:
	_ground(0, COLS - 1)
	# Vent grates in the floor.
	for v in VENTS:
		_cell(v[0], G, STEEL, VENTBOX)
	# Ceiling: bulkhead with the roof openings.
	var sky_cols := {}
	for sk in skylights:
		for x in range(int(sk.position.x / T), int((sk.position.x + sk.size.x) / T)):
			sky_cols[x] = true
	for x in range(0, COLS):
		if sky_cols.has(x):
			continue
		_cell(x, 0, BULKHEAD, FLAT if x % 3 != 0 else RIVET)
		_cell(x, 1, BULKHEAD, BEVEL if x % 2 == 1 else VENTBOX)
	# Boundary walls.
	for y in range(0, ROWS):
		_cell(-1, y, BULKHEAD, FLAT)
		_cell(COLS, y, BULKHEAD, FLAT)
	# Left wall: a teal riser.
	for y in range(2, G):
		_cell(0, y, TEAL, PIPE_V[y % 2])

	# B: crate stairs (1, 2, 3 high), a catwalk, the perch for letter C, stairs down.
	_crates(14, 15, 1)
	_crates(17, 18, 2)
	_crates(20, 21, 3)
	_girder(22, 27, G - 3)
	_girder(31, 35, G - 3)
	_girder(25, 26, G - 6, G - 3)   # perch (letter C): reached with the double jump
	_crates(36, 37, 2)
	_crates(39, 40, 1)
	# C: nothing solid: an open hall.
	# D: crawl tunnel ceiling (one tile of headroom).
	_block(60, 66, 2, G - 2)
	# E: ceilings over the timed fence and the shutter so neither can be jumped.
	_block(74, 76, 2, G - 4)
	_block(87, 89, 2, G - 4)
	# F: steps to the key deck, the deck, the perch for letter A, the door ceiling.
	_crates(93, 93, 1)
	_crates(94, 94, 2)
	_girder(95, 99, G - 3)
	_girder(96, 97, G - 6, G - 3)
	_block(103, 105, 2, G - 3)
	# G: ceilings over each vent (3 tiles of headroom = the steam column).
	for v in VENTS:
		_block(v[0] - 1, v[0] + 1, 2, G - 4)
	# H: the letter T perch over the flooded hall, with crates to climb from.
	_crates(128, 129, 2)
	_girder(130, 131, G - 5)
	# I: the pool trough: a raised sill (one tile) at each end, so the pool floor
	# reads as sunken between walls, and a low ceiling over it (3 tiles of headroom).
	_block(POOL[0] - 2, POOL[0] - 1, G - 1, G - 1, STEEL)
	_block(POOL[1] + 1, POOL[1] + 2, G - 1, G - 1, STEEL)
	_block(POOL[0] - 1, POOL[1] + 1, 5, G - 4)
	# J: the loading door header (rows 2-4), the opening below it.
	_block(148, 154, 2, 4)
	# Right end.
	for y in range(2, G):
		_cell(COLS - 1, y, VIOLET, PIPE_V[y % 2])


func _place_actors() -> void:
	# --- A ---
	_put("res://scenes/actors/continue_pad.tscn", "ContinuePad", 9, G)
	_put("res://scenes/actors/gem.tscn", "GemA", 7, G - 1)
	# --- B ---
	_put("res://scenes/actors/gem.tscn", "GemStep", 18, G - 3)
	_put("res://scenes/actors/letter.tscn", "LetterC", 25, G - 6, {"letter_index": 0})
	_put("res://scenes/actors/gem.tscn", "GemGap", 29, G - 5)
	_put("res://scenes/actors/gem.tscn", "GemDeck", 33, G - 3)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointA", 42, G, {"checkpoint_id": "cp_a"})
	# --- C ---
	_put("res://scenes/actors/patrol_bot.tscn", "Bot", 48, G)
	_put("res://scenes/actors/gem.tscn", "GemHall1", 46, G - 2)
	_put("res://scenes/actors/gem.tscn", "GemHall2", 53, G - 2)
	# --- D ---
	_put("res://scenes/actors/gem.tscn", "GemCrawl", 63, G)
	_put("res://scenes/actors/fish.tscn", "FishCrawl", 68, G)
	# --- E: the timed fence, the crate and the plate, the shutter ---
	_put("res://scenes/actors/laser_fence.tscn", "FenceTimed", 75, G,
		{"height_tiles": 3, "timed": true, "on_time": 1.4, "off_time": 1.8})
	_put("res://scenes/actors/crate_pushable.tscn", "PushCrate", 79, G)
	_put("res://scenes/actors/floor_plate.tscn", "PlateA", 84, G)
	_put("res://scenes/actors/shutter.tscn", "Shutter", 88, G,
		{"height_tiles": 3, "controller": NodePath("../PlateA")})
	# --- F: key deck, the door, checkpoint ---
	_put("res://scenes/actors/key.tscn", "KeyBrass", 97, G - 3, {"key_color": "brass"})
	_put("res://scenes/actors/letter.tscn", "LetterA", 96, G - 6, {"letter_index": 1})
	_put("res://scenes/actors/locked_door.tscn", "DoorBrass", 104, G, {"key_color": "brass"})
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointB", 108, G, {"checkpoint_id": "cp_b"})
	# --- H ---
	_put("res://scenes/actors/gem.tscn", "GemHall3", 126, G - 1)
	_put("res://scenes/actors/letter.tscn", "LetterT", 130, G - 5, {"letter_index": 2})


func _puddles() -> void:
	# [name, centre col (float ok), width px, drip x offset or null]
	var defs := [
		["PuddleHall1", 45.5, 112.0, false],
		["PuddleHall2", 53.0, 128.0, true],
		["PuddleCrawl", 63.5, 64.0, true],
		["PuddleFlood1", 125.0, 160.0, true],
		["PuddleFlood2", 129.5, 96.0, false],
		["PuddleFlood3", 135.0, 72.0, true],
		["PuddleVent", 113.5, 64.0, false],
	]
	for d in defs:
		var z := PuddleZone.new()
		z.name = d[0]
		z.width = d[2]
		z.position = Vector2(d[1] * T, G * T)
		_own(z)
		if d[3]:
			var drip := DripFX.new()
			drip.name = "Drip" + String(d[0]).trim_prefix("Puddle")
			var ceil_y := 64.0
			if d[0] == "PuddleCrawl":
				ceil_y = 9 * T + 12.0  # hangs from the low beam
			drip.position = Vector2(d[1] * T, ceil_y)
			drip.fall_height = G * T - ceil_y
			drip.interval_min = 1.1
			drip.interval_max = 2.4
			_own(drip)
			drip.puddle = null  # set at runtime by Room1 wiring below
			drip.set_meta("puddle_path", drip.get_path_to(z))


func _steam() -> void:
	var i := 1
	for v in VENTS:
		_put("res://scenes/actors/steam_hazard.tscn", "Steam%d" % i, v[0], G,
			{"cycle_on": 1.2, "cycle_off": 2.2, "cycle_offset": v[1], "column_height": 96.0})
		i += 1


func _pool() -> void:
	var pool := GooPool.new()
	pool.name = "GooPool"
	pool.width = float((POOL[1] - POOL[0] + 1) * T)
	pool.depth = 14.0
	pool.position = Vector2(POOL[0] * T, G * T - 12.0)
	pool.bubbles = false
	pool.trace_energy = 0.12
	pool.light_energy = 0.12
	pool.z_index = 6
	_own(pool)


func _low_beam() -> void:
	## Hangs 12 px from the tunnel ceiling over cols 61-65, leaving a 20 px gap
	## above the floor: the standing cat (26) cannot pass, the crouched cat (14) can.
	var beam := StaticBody2D.new()
	beam.name = "LowBeam"
	beam.position = Vector2(63 * T + T / 2.0, (G - 1) * T)
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(5 * T, 12)
	shape.shape = rs
	shape.name = "Shape"
	shape.position = Vector2(0, 6)
	beam.add_child(shape)
	for i in 5:
		var s := TileArt.sprite("bulkhead", TileArt.FLAT, Rect2i(0, 0, T, 12))
		s.name = "Plate%d" % i
		s.position = Vector2((i - 2.5) * T, 0)
		beam.add_child(s)
	_own(beam)
	for c in beam.get_children():
		c.owner = room


func _stoppers() -> void:
	## Invisible walls on physics layer 7 ("bot_bounds"): solid only to bots and
	## pushable crates. The bot patrols cols 44-55; col 85 stops the push crate
	## centred on the plate (col 84) so it can never be shoved past it.
	for col in [43, 56, 85]:
		var sb := StaticBody2D.new()
		sb.name = "Stopper%d" % col
		sb.collision_layer = 64
		sb.collision_mask = 0
		sb.position = Vector2(col * T + T / 2.0, G * T)
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = Vector2(T, 4 * T)
		cs.shape = r
		cs.position = Vector2(0, -2 * T)
		cs.name = "Shape"
		sb.add_child(cs)
		_own(sb)
		cs.owner = room


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


# ---- Room 2 (stub) --------------------------------------------------------------

func _build_room2() -> void:
	room = Node2D.new()
	room.name = "Room2"
	room.set_script(load("res://scripts/systems/room2.gd"))
	room.set("limits", Rect2i(0, 24, 20 * T, 360))
	var w := 20 * T

	var sky := ColorRect.new()
	sky.name = "SkyFill"
	sky.color = Color("0c1030")
	sky.position = Vector2(-64, -200)
	sky.size = Vector2(w + 128, 700)
	_own(sky)
	var exterior := NightBackdrop.new()
	exterior.name = "Exterior"
	exterior.position = Vector2(0, 250)
	exterior.moon_position = Vector2(-120, -141)
	_own(exterior)

	tiles = TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	_own(tiles)
	# A loading dock: a steel slab with a girder lip and a crate stack on the left.
	for x in range(0, 20):
		_cell(x, G, STEEL, BEVEL)
		_cell(x, G + 1, MAROON, GIRDER_H)
		_cell(x, G + 2, MAROON, FLAT if x % 2 == 0 else RIVET)
	for y in range(0, ROWS):
		_cell(-1, y, BULKHEAD, FLAT)
		_cell(20, y, BULKHEAD, FLAT)
	_crates(15, 16, 1)
	_crates(16, 16, 2)

	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = _p(3, G)
	_own(start)

	# Rain over the whole dock (the procedural rain shader: it renders the same
	# on the web as on desktop), in front of everything but the HUD.
	var rain := WindowRain.new()
	rain.name = "Rain"
	rain.position = Vector2(0, 0)
	rain.size = Vector2(w, 330)
	rain.intensity = 0.55
	rain.z_index = 8
	_own(rain)
	var z := PuddleZone.new()
	z.name = "Puddle"
	z.width = 128.0
	z.position = Vector2(10 * T, G * T)
	_own(z)
	_lamp("LampDock", Vector2(17 * T + 16, G * T - 7), false, 1.6)

	var label := Label.new()
	label.name = "ComingSoon"
	label.text = "Room 2 - coming soon"
	label.add_theme_font_override("font", load("res://assets/fonts/monogram.ttf"))
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(0.86, 0.91, 1.0) * 1.1)
	label.position = Vector2(7 * T, 4 * T)
	label.size = Vector2(12 * T, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_own(label)

	var cat: Node = load("res://scenes/player/cat.tscn").instantiate()
	cat.name = "Cat"
	_own(cat)
	var rig := LightingRig.new()
	rig.name = "LightingRig"
	rig.night_tint = Color(0.36, 0.40, 0.58)
	rig.moon_angle = SHAFT_ANGLE
	rig.moon_energy = 0.9
	rig.glow_intensity = 0.8
	rig.vignette = 0.30
	var solid: Array[TileMapLayer] = [tiles]
	rig.solid_layers = solid
	_own(rig)
	var amb := Ambience.new()
	amb.name = "Ambience"
	_own(amb)
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	_own(hud)
	_save(room, "res://scenes/levels/room2.tscn")
