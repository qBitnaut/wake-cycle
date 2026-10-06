## Generates res://scenes/levels/room2.tscn (Room 2, "The Yard"). Room 3 is built by
## tools/build_room3.gd; this script no longer touches room3.tscn. Run:
##   godot --headless --path . res://tools/build_runner.tscn -- --builder=res://tools/build_room2.gd
##
## A TALL yard (camera_follow = TIERS, 220 x 39 tiles = 7040 x 1248 px, about 3.5 screens high), in
## the Secret Agent / Duke Nukem spirit. Four tiers, from the top:
##
##   CRANE   a gantry crane cab (row 8) with a lift down to the dock, reached by girder rungs
##   ROOFS   floating shipping containers (surface row 16) over the yard: the high route, run
##           on Surge, with a moving hanging-container bridge over one gap
##   YARD    the floor (row 24): the original three Surge lessons, the dock, the drone chase,
##           the fence. This is the route every beat of the story sits on
##   UNDER   a drainage underpass (floor row 32) below the yard slab: entered by falling through
##           the Surge gap or the pit (a safe drop), left by grates (flush one-way tiles in the
##           yard floor, with rungs below). The low route, with three secrets
##   VAULT   (floor row 38) a sealed chamber under the underpass floor
##
## Sizes come from the measured reach (tools/audit/reach.gd), centre travel:
##                 single   double jump
##   plain           122 px   223 px
##   Surge           182 px   334 px
## A gap of N px needs travel >= N - 22 (the cat is 22 px wide). The Surge-only gap is 9 tiles
## (288 px): it needs 266, a plain double jump reaches 223, a Surge double jump 334. A plain jump
## rises 95 px (3 tiles), a double jump 171: every step in this room is 64 px (two tiles) or less.
##
## Beats, left to right on the yard floor (column numbers; 32 px tiles):
##   A    0-29    arrival: out of the warehouse door into the rain, a walker (Bot1)
##   B1  30-56    SURGE 1, discovery: a pad in a low service tunnel under a container
##                (32 px of headroom: the pad cannot be hopped over), then 18 tiles of clear run
##   B2  57-95    SURGE 2, use it: checkpoint A, pad, a 9-tile gap (a hole into the underpass:
##                falling is a detour, not death); landing, checkpoint B, a turret above, a walker
##   B3  98-130   SURGE 3, the clock: pad, the plate (col 102) starts the gate (col 127) closing
##                after 3.5 s; 25 tiles away: 3.1 s on Surge, 4.6 s plain
##   D  131-162   checkpoint C, the loading dock: conveyors, falling crates, the docked bot, a
##                security camera whose alarm shuts the guard door (hut) and wakes a turret;
##                the detour goes over the hut; checkpoint D
##   B4 165-202   SURGE 4, combine: pad, the searchlight drone chases from col 168; crate steps, a
##                5-tile hole (the underpass again), a crawl vent (cover) and out
##   E  203-219   the fence: a cut in it at cols 213-217 and the exit to Room 3
##
## The high route (ROOFS): a girder stair (cols 88-93) from the landing to the first roof, a Surge
## pad on it, a turret, a patrol bot with a laser, a moving bridge, a hover drone, a crane stair
## to the cab (loot, checkpoint), a lift down to the dock. The low route (UNDER): west culvert
## (a hopper, the VAULT lane: a turret, an explosive barrel and a blast-only hatch in the floor),
## the main drain (a hopper, an under-floor crawl cache, an electric floor under a broken
## floodlight, acid, a hopper) to a grate at col 132, and a dead-end spur with a hover drone
## over a blast-only hatch: the bomb is the key. Three secrets: S1 crawl cache (the golden bone),
## S2 the supply closet (the hatch under the drone: its bomb opens it), S3 the vault (the turret's bolt, the
## barrel and the hatch; the memory fragment).
##
## Builder for tools/build_runner.gd (autoloads are live there; --script mode lacks them).
## Rebuilds are deterministic: names are fixed and the runner re-uses the committed
## scene's unique_ids (see build_runner.gd).
extends RefCounted

## Set by _save on a pack or save failure; the runner turns it into the exit code.
var errors := 0


const T := 32
const G := 24          ## yard floor surface row (y = 768)
const U := 32          ## underpass floor surface row (y = 1024)
const V := 36          ## vault floor surface row (y = 1152)
const ROWS := 39       ## 1248 px
const COLS := 220

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
## One-way grating: the standing surface is the tile's top edge (the rungs and the yard grates).
const GRATING := Vector2i(10, 7)

# ---- the yard floor ------------------------------------------------------------
const START_COL := 3
const TUNNEL := [30, 38]
const PAD1_COL := 34
const PAD2_COL := 62
const HOLES := [[70, 78], [180, 184]]     ## inclusive columns with no yard floor (into the underpass)
const CP_B_COL := 81
const PAD3_COL := 98
const PLATE_COL := 102
const GATE_COL := 127
const CP_C_COL := 133
const GRATES := [[83, 87], [128, 132], [186, 190]]   ## flush one-way yard floor over a 5-wide zigzag rung shaft
const CONVEYORS := [[138, 140, -70.0], [149, 152, 70.0]]
const DOCK_COL := 142
const HUT := [155, 159]                    ## the guard-door container (a lintel over the floor)
const HUT_DOOR_COL := 157
const CP_D_COL := 162
const PAD4_COL := 165
const DRONE_TRIGGER_COL := 168
const DRONE_END_COL := 203
const VENT := [192, 195]                   ## container over the crawl vent
const EXIT_COL := 215
const FENCE_GAP := [213, 217]

# ---- the high route ------------------------------------------------------------
const ROOF := 16                           ## the roofs' surface row (y = 512)
const R1 := [93, 101]
const R2 := [107, 114]
const R3 := [120, 126]
const BRIDGE_GAP := [115, 119]
const CAB := [130, 134]                    ## crane cab floor (rows 8-9), surface row 8
const LIFT_COLS := [135, 137]

# ---- the underpass -------------------------------------------------------------
const CAVITIES := [[43, 151], [177, 190]]  ## columns with open air under the yard slab
const VAULT := [44, 53]                    ## sealed chamber under the underpass floor (rows 33-35)
const HATCH := [49, 53]
const TURRET3_COL := 43
const BARREL3_COL := 48
const DIP := [98, 99]                      ## S1: a dip in the floor and a crawl tunnel under it
const TUNNEL1 := [100, 110]
const CHAMBER1 := [111, 115]
const CLOSET := [141, 148]                ## S2: a second sealed chamber under the spur floor
const HATCH2 := [143, 147]

var room: Node2D
var tiles: TileMapLayer
var back_tiles: TileMapLayer
var _yarn := 0


func build() -> void:
	_build_room2()
	print("yarn (Gem*) nodes: ", _yarn)


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


func _put_at(path: String, node_name: String, pos: Vector2, props := {}) -> Node:
	var n: Node2D = load(path).instantiate()
	n.name = node_name
	for k in props:
		n.set(k, props[k])
	n.position = pos
	_own(n)
	return n


func _cell(x: int, y: int, mat: int, tile: Vector2i, layer: TileMapLayer = null) -> void:
	var l := layer if layer else tiles
	l.set_cell(Vector2i(x, y), 0, Vector2i(tile.x, tile.y + mat * 10))


func _erase(x: int, y: int) -> void:
	tiles.erase_cell(Vector2i(x, y))


func _fill(x0: int, x1: int, y0: int, y1: int, mat: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			_cell(x, y, mat, FLAT if (x + y) % 2 == 0 else RIVET)


func _in_ranges(x: int, ranges: Array) -> bool:
	for r in ranges:
		if x >= r[0] and x <= r[1]:
			return true
	return false


func _in_hole(x: int) -> bool:
	return _in_ranges(x, HOLES)


func _grate_of(x: int) -> Array:
	for g in GRATES:
		if x >= g[0] and x <= g[1]:
			return g
	return []


func _in_conveyor(x: int) -> bool:
	for c in CONVEYORS:
		if x >= c[0] and x <= c[1]:
			return true
	return false


func _cavity_of(x: int) -> Array:
	for c in CAVITIES:
		if x >= c[0] and x <= c[1]:
			return c
	return []


## A shipping container, two rows tall: corrugated side tiles (10..12, 5..6),
## solid (the back layer has no colliders and varies the panels). `top` is the
## row of its upper course.
func _container(x0: int, x1: int, top: int, mat: int, layer: TileMapLayer = null) -> void:
	for x in range(x0, x1 + 1):
		# Only the middle panel (11, 5..6) has a full cell collider; the end panels are art.
		var c := 11 if layer == null else 10 + (x - x0) % 3
		_cell(x, top, mat, Vector2i(c, 5), layer)
		_cell(x, top + 1, mat, Vector2i(c, 6), layer)


func _crates(x0: int, x1: int, h: int) -> void:
	for x in range(x0, x1 + 1):
		for k in range(h):
			_cell(x, G - 1 - k, MAROON, FRAMED if (x + k) % 2 == 0 else CROSS)


## Three containers high, the lowest with 32 px of headroom under it.
func _stack(x0: int, x1: int, mats: Array) -> void:
	for k in mats.size():
		_container(x0, x1, G - 3 - 2 * k, mats[k])


## A rung (one-way grating) row: the cat stands at y = 32 * row.
func _rungs(x0: int, x1: int, row: int, mat := STEEL) -> void:
	for x in range(x0, x1 + 1):
		_cell(x, row, mat, Vector2i(GRATING.x + x % 3, GRATING.y))


## Girder posts under a floating container (back layer, no collision): decor that explains
## why it stays up.
func _posts(x0: int, x1: int, y0: int, y1: int) -> void:
	for x in [x0, x1]:
		for y in range(y0, y1):
			_cell(x, y, STEEL, GIRDER_V, back_tiles)


func _interior(node_name: String, rect: Rect2, col: Color, z := -6) -> void:
	var c := ColorRect.new()
	c.name = node_name
	c.color = col
	c.position = rect.position
	c.size = rect.size
	c.z_index = z
	_own(c)


# ---- the room -----------------------------------------------------------------

func _build_room2() -> void:
	room = Node2D.new()
	room.name = "Room2"
	room.set_script(load("res://scripts/systems/room2.gd"))
	var w := COLS * T
	var h := ROWS * T
	room.set("limits", Rect2i(0, 0, w, h))
	room.set("camera_follow", Level.CameraFollow.TIERS)
	var covered: Array[Rect2] = []
	for c in CAVITIES:
		covered.append(Rect2(c[0] * T, (G + 2) * T, (c[1] + 1 - c[0]) * T, (ROWS - G - 2) * T))
	room.set("covered", covered)

	var sky := ColorRect.new()
	sky.name = "SkyFill"
	sky.color = Color("0c1030")
	sky.position = Vector2(-64, -200)
	sky.size = Vector2(w + 128, h + 400)
	sky.z_index = -10
	_own(sky)

	var exterior := NightBackdrop.new()
	exterior.name = "Exterior"
	exterior.position = Vector2(0, G * T - 70)
	exterior.moon_position = Vector2(-120, -141)
	exterior.extend_vertically = true
	exterior.z_index = -9
	_own(exterior)

	_warehouse()

	# Far side of the yard: dim container stacks and the fence in front of them.
	back_tiles = TileMapLayer.new()
	back_tiles.name = "BackTiles"
	back_tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	back_tiles.collision_enabled = false
	back_tiles.occlusion_enabled = false
	back_tiles.z_index = -4
	back_tiles.self_modulate = Color(0.5, 0.52, 0.62)
	_own(back_tiles)
	_back_stacks()

	var fence := YardFence.new()
	fence.name = "Fence"
	fence.position = Vector2(8 * T, G * T)
	fence.length = float(COLS * T - 8 * T)
	fence.fence_height = 144.0
	fence.gaps.assign([Vector2((FENCE_GAP[0] - 8) * T, (FENCE_GAP[1] + 1 - 8) * T)])
	fence.z_index = -3
	fence.self_modulate = Color(0.8, 0.84, 0.9)
	_own(fence)

	tiles = TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	_own(tiles)
	_build_geometry()
	_interiors()
	_crane_decor()

	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = _p(START_COL, G)
	_own(start)

	_place_actors()
	_underpass_actors()
	_roof_actors()
	_dock_actors()
	_low_vent(VENT[0] + 1, VENT[1] - 1, G - 1, "LowVent")
	_stoppers()
	_puddles()
	_poles()
	_gantry()

	# Rain: two RainFX windows on the camera view (the node is driven by RainFX itself); the
	# near layer stays out of the underpass (Room2 fades it in `covered`).
	_rain("RainFar", -2, 45.0, 0.0, 60.0)
	_rain("RainNear", 7, 38.0, 0.0, 110.0)

	# (Loaded by path: RoomExit reaches the autoloads, which a --script run lacks at compile time.)
	var exit_area: Area2D = load("res://scripts/systems/room_exit.gd").new()
	exit_area.name = "RoomExit"
	exit_area.set("next_scene", "res://scenes/ui/world_map.tscn")
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
	lightning.interval_min = 9.0
	lightning.interval_max = 18.0
	lightning.light_shadows = false
	_own(lightning)

	var amb := Ambience.new()
	amb.name = "Ambience"
	amb.bed = "amb_yard"
	amb.surface = "step_wet"
	_own(amb)

	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	_own(hud)

	_save(room, "res://scenes/levels/room2.tscn")


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


func _warehouse() -> void:
	## The back of the warehouse on the left: a panelled wall under a flat roof
	## with the loading door the cat has just come out of, light spilling out.
	var dy := (G - 10) * T
	var wall := BackWall.new()
	wall.name = "WarehouseWall"
	wall.position = Vector2(0, 3 * T + dy)
	wall.size = Vector2(7 * T, (G - 3) * T - dy)
	wall.floor_y = (G - 3) * T - dy
	wall.band_gaps = [Vector2(0, 5 * T)]
	wall.z_index = -5
	_own(wall)
	var interior := ColorRect.new()
	interior.name = "DoorInterior"
	interior.color = Color("2b2230")
	interior.position = Vector2(14, 6 * T + dy)
	interior.size = Vector2(4 * T + 4, 4 * T)
	interior.z_index = -4
	_own(interior)
	var glow := ColorRect.new()
	glow.name = "DoorGlow"
	glow.color = Color(0.95, 0.62, 0.30, 0.18)
	glow.position = Vector2(14, 8 * T + dy)
	glow.size = Vector2(4 * T + 4, 2 * T)
	glow.z_index = -4
	_own(glow)
	for r in [Rect2(8, 5 * T + 8 + dy, 4 * T + 16, 8), Rect2(8, 6 * T + dy, 8, 4 * T), Rect2(4 * T + 18, 6 * T + dy, 8, 4 * T)]:
		var b := ColorRect.new()
		b.name = "DoorFrame%d" % int(r.position.x + r.position.y)
		b.color = Color("354655")
		b.position = r.position
		b.size = r.size
		b.z_index = -3
		_own(b)
	var spill := PointLight2D.new()
	spill.name = "DoorLight"
	spill.texture = load("res://assets/fx/light_soft.png")
	spill.texture_scale = 3.4
	spill.color = Color(1.0, 0.72, 0.42)
	spill.energy = 1.1
	spill.position = Vector2(88, 8.4 * T + dy)
	_own(spill)


func _back_stacks() -> void:
	## [x0, x1, courses, material]: dim stacks standing on the far side of the yard.
	var defs := [
		[8, 14, 2, TEAL], [16, 21, 1, RUST], [22, 28, 2, MAROON], [41, 47, 1, TEAL],
		[50, 55, 2, RUST], [60, 66, 1, TEAL], [81, 87, 2, TEAL], [89, 94, 1, RUST],
		[96, 101, 2, MAROON], [104, 111, 2, TEAL], [113, 120, 1, RUST], [127, 133, 2, MAROON],
		[141, 147, 1, TEAL], [149, 155, 2, RUST], [161, 166, 1, MAROON], [170, 176, 2, TEAL],
		[186, 192, 1, RUST], [198, 204, 2, TEAL], [206, 211, 1, RUST], [218, 219, 2, MAROON],
	]
	for d in defs:
		for k in range(d[2]):
			_container(d[0], d[1], G - 2 - 2 * k, d[3], back_tiles)


# ---- geometry -------------------------------------------------------------------

func _build_geometry() -> void:
	_terrain()
	_vault_and_crawl()
	# A: a few crates to hop over on the way out.
	_crates(13, 14, 1)
	_crates(16, 17, 2)
	# B1: the service tunnel. A stack of three containers on a gantry with 32 px
	# of headroom under it, too tall (224 px) to climb over: a double jump rises 171.
	_stack(TUNNEL[0], TUNNEL[1], [RUST, TEAL, MAROON])
	# B4: crate steps (1, 2 high), then the hole (see HOLES), then the vent.
	_crates(172, 173, 1)
	_crates(174, 176, 2)
	_stack(VENT[0], VENT[1], [TEAL, MAROON, RUST])
	_roofs()
	_dock_geometry()
	# Right end: a stack the fence ends against.
	for y in range(2, G):
		_cell(COLS - 1, y, BULKHEAD, FLAT)


## The ground: the yard slab (rows 24-25) with its holes and grates, the foundation under it
## and the underpass cavities (rows 26-31, floor row 32).
func _terrain() -> void:
	for x in range(0, COLS):
		var cav := _cavity_of(x)
		var gr := _grate_of(x)
		# Yard floor (row 24) and slab (row 25).
		if _in_hole(x):
			pass
		elif not gr.is_empty():
			_cell(x, G, STEEL, Vector2i(GRATING.x + x % 3, GRATING.y))
		else:
			var lip := (x + 1 < COLS and _in_hole(x + 1)) or (x > 0 and _in_hole(x - 1))
			if not _in_conveyor(x):
				_cell(x, G, HAZARD if lip else STEEL, BEVEL)
			_cell(x, G + 1, MAROON, FLAT if x % 2 == 0 else RIVET)
		# Under the slab.
		if cav.is_empty():
			_fill(x, x, G + 2, ROWS - 1, MAROON)
		else:
			if not gr.is_empty():
				# A zigzag rung shaft (rungs 64 px apart): left, right, left, then the grate.
				var left: bool = x <= gr[0] + 2
				var right: bool = x >= gr[0] + 2
				if left:
					_cell(x, U - 2, STEEL, Vector2i(GRATING.x + x % 3, GRATING.y))
					_cell(x, U - 6, STEEL, Vector2i(GRATING.x + x % 3, GRATING.y))
				if right:
					_cell(x, U - 4, STEEL, Vector2i(GRATING.x + x % 3, GRATING.y))
			_cell(x, U, STEEL, BEVEL)
			_fill(x, x, U + 1, ROWS - 1, MAROON)
	for y in range(0, ROWS):
		_cell(-1, y, BULKHEAD, FLAT)
		_cell(COLS, y, BULKHEAD, FLAT)


## S3 (the vault under the underpass floor) and S1 (the dip and the crawl tunnel).
func _vault_and_crawl() -> void:
	# Vault: rows 33-35 open, the hatch opening in the floor above, rungs inside.
	for x in range(VAULT[0], VAULT[1] + 1):
		for y in range(U + 1, V):
			_erase(x, y)
	for x in range(HATCH[0], HATCH[1] + 1):
		_erase(x, U)
	_rungs(49, 53, V - 1)    # +32 from the vault floor
	_rungs(51, 53, V - 3)    # +64, under the hatch; then a 32 px step onto the floor lip at col 54
	# S1: a dip (rows 32-33 open: floor at row 34), a crawl tunnel (row 33), a small chamber.
	for x in range(DIP[0], DIP[1] + 1):
		_erase(x, U)
		_erase(x, U + 1)
	for x in range(TUNNEL1[0], TUNNEL1[1] + 1):
		_erase(x, U + 1)
	for x in range(CHAMBER1[0], CHAMBER1[1] + 1):
		_erase(x, U + 1)
		_erase(x, U + 2)
	# S2: the supply closet under the spur, the same shape as the vault (hatch above, +32 and +64
	# rungs under it, a 32 px step onto the lip at col 148).
	for x in range(CLOSET[0], CLOSET[1] + 1):
		for y in range(U + 1, V):
			_erase(x, y)
	for x in range(HATCH2[0], HATCH2[1] + 1):
		_erase(x, U)
	_rungs(143, 147, V - 1)
	_rungs(145, 147, V - 3)


func _roofs() -> void:
	# C1: a girder stair from the landing to the first roof (rungs 64 px apart).
	_rungs(84, 86, 22)
	_rungs(87, 89, 20)
	_rungs(90, 92, 18)
	_container(R1[0], R1[1], ROOF, RUST)
	_container(R2[0], R2[1], ROOF, TEAL)
	_container(R3[0], R3[1], ROOF, MAROON)
	# The stub over the landing (a container hung from the gantry: the turret's perch).
	_container(79, 82, G - 6, RUST)
	# The crane: rungs from the last roof up to the cab floor (rows 8-9), a cab roof over it.
	_rungs(127, 129, 14)
	_rungs(124, 126, 12)
	_rungs(127, 129, 10)
	for x in range(CAB[0], CAB[1] + 1):
		_cell(x, 8, STEEL, BEVEL)
		_cell(x, 9, MAROON, FLAT if x % 2 == 0 else RIVET)
		_cell(x, 3, MAROON, FLAT if x % 2 == 0 else RIVET)
		_cell(x, 4, STEEL, FLAT)
	# Posts under the floating containers.
	_posts(R1[0], R1[1], ROOF + 2, G)
	_posts(R2[0], R2[1], ROOF + 2, G)
	_posts(R3[0] + 1, R3[1] - 1, ROOF + 2, G)
	_posts(79, 82, G - 4, G)
	_posts(CAB[0], CAB[1], 10, G)


func _dock_geometry() -> void:
	# The gantry crate over conveyor A (the falling crate's ceiling), the canopy over conveyor B,
	# the guard-door lintel, and the C2 rungs onto the canopy (the detour).
	_container(138, 141, G - 6, MAROON)
	_container(149, 154, G - 6, TEAL)
	_container(HUT[0], HUT[1], G - 4, RUST)
	_rungs(143, 145, 22)
	_rungs(146, 148, 20)
	_crates(161, 161, 1)
	_posts(138, 141, G - 4, G)
	_posts(149, 154, G - 4, G)
	_posts(HUT[0], HUT[1], G - 2, G)


# ---- decor ----------------------------------------------------------------------

func _interiors() -> void:
	## Dark back walls behind the open underpass and the vault (so the sky does not show).
	var i := 0
	for c in CAVITIES:
		_interior("UnderInterior%d" % i, Rect2(c[0] * T, (G + 2) * T, (c[1] + 1 - c[0]) * T, (U - G - 2) * T), Color("0e1320"))
		i += 1
	_interior("VaultInterior", Rect2(VAULT[0] * T, (U + 1) * T, (VAULT[1] + 1 - VAULT[0]) * T, (V - U - 1) * T), Color("141026"))
	_interior("CrawlInterior", Rect2(DIP[0] * T, (U + 1) * T, (CHAMBER1[1] + 1 - DIP[0]) * T, 2 * T), Color("0a0d17"))
	_interior("ClosetInterior", Rect2(CLOSET[0] * T, (U + 1) * T, (CLOSET[1] + 1 - CLOSET[0]) * T, (V - U - 1) * T), Color("141026"))
	_interior("CabInterior", Rect2(CAB[0] * T, 5 * T, (CAB[1] + 1 - CAB[0]) * T, 3 * T), Color("1e2736"), -4)
	# Under-yard ribs and pipes along the drain.
	for c in CAVITIES:
		var x: int = c[0] + 2
		while x < c[1]:
			var rib := ColorRect.new()
			rib.name = "DrainRib%d" % x
			rib.color = Color("1a2638")
			rib.position = Vector2(x * T, (G + 2) * T)
			rib.size = Vector2(6, (U - G - 2) * T)
			rib.z_index = -5
			_own(rib)
			x += 6
		var pipe := ColorRect.new()
		pipe.name = "DrainPipe%d" % c[0]
		pipe.color = Color("2a4658")
		pipe.position = Vector2(c[0] * T, (G + 2) * T + 12)
		pipe.size = Vector2((c[1] + 1 - c[0]) * T, 8)
		pipe.z_index = -5
		_own(pipe)


func _crane_decor() -> void:
	## The crane: legs on the back layer, a boom out to the lift, a trolley rail over the bridge.
	for x in [CAB[0] - 1, CAB[1] + 1]:
		for y in range(3, 10):
			_cell(x, y, STEEL, GIRDER_V, back_tiles)
	for x in range(CAB[0] - 1, LIFT_COLS[1] + 2):
		_cell(x, 2, STEEL, GIRDER_H, back_tiles)
	for x in range(BRIDGE_GAP[0] - 1, BRIDGE_GAP[1] + 2):
		_cell(x, ROOF - 5, STEEL, GIRDER_H, back_tiles)
	for x in [BRIDGE_GAP[0] - 1, BRIDGE_GAP[1] + 1]:
		for y in range(ROOF - 5, ROOF):
			_cell(x, y, STEEL, GIRDER_V, back_tiles)
	# Lift guide rails.
	for x in [LIFT_COLS[0] - 1, LIFT_COLS[1] + 1]:
		for y in range(3, G):
			_cell(x, y, STEEL, GIRDER_V, back_tiles)


func _gantry() -> void:
	## Decor behind the tunnel container: two truss posts and a crossbeam.
	for x in [TUNNEL[0] - 1, TUNNEL[1] + 1]:
		for y in range(G - 8, G):
			_cell(x, y, STEEL, GIRDER_V, back_tiles)
	for x in range(TUNNEL[0] - 1, TUNNEL[1] + 2):
		_cell(x, G - 9, STEEL, GIRDER_H, back_tiles)


# ---- actors ---------------------------------------------------------------------

func _yarn_at(node_name: String, cx: int, cy: int, dy := 0.0) -> void:
	## A ball of yarn (100), standing on the surface of row `cy`. The world map counts the
	## "Gem*" names (levels.json yard.collectibles.gems).
	_yarn += 1
	_put("res://scenes/kit/pickup_yarn.tscn", node_name, cx, cy, {"_dy": -8.0 + dy})


func _item(scene: String, node_name: String, cx: int, cy: int, dy := 0.0, props := {}) -> Node:
	var p := props.duplicate()
	p["_dy"] = -8.0 + dy
	return _put("res://scenes/kit/%s.tscn" % scene, node_name, cx, cy, p)


func _place_actors() -> void:
	# --- A: arrival ---
	_yarn_at("GemA1", 14, G - 2)
	_yarn_at("GemA2", 17, G - 3)
	var bot1 := _put("res://scenes/actors/patrol_bot.tscn", "Bot1", 23, G, {"stomps_to_befriend": 99})
	bot1.set("dir", -1)
	_yarn_at("GemA3", 21, G)
	_yarn_at("GemA4", 25, G)
	_mono("YardArrival", "yard_arrival", Vector2(START_COL * T + 16, G * T), Vector2(192, 96))

	# --- B1: discovery ---
	_pad("PadSurge1", PAD1_COL, G)
	_mono("SurgeFirst", "surge_first", _p(PAD1_COL, G), Vector2(44, 40))
	for c in range(41, 57, 2):
		_yarn_at("GemRun%d" % c, c, G)

	# --- B2: use it ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointA", 57, G, {"checkpoint_id": "cp_a"})
	_pad("PadSurge2", PAD2_COL, G)
	_yarn_at("GemGap1", 72, G - 4)
	_yarn_at("GemGap2", 74, G - 5)
	_yarn_at("GemGap3", 76, G - 4)
	_item("pickup_bell", "BellGap", 75, G - 3)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointB", CP_B_COL, G, {"checkpoint_id": "cp_b"})
	var bot2 := _put("res://scenes/actors/patrol_bot.tscn", "Bot2", 90, G, {"stomps_to_befriend": 99})
	bot2.set("dir", 1)
	_yarn_at("GemLand1", 88, G)
	_item("pickup_fish", "FishLand", 94, G)
	# The stub's turret: bolts down at the landing (a dodge, never a corner).
	_put_at("res://scenes/kit/sentry_turret.tscn", "TurretLand", Vector2(80 * T + 16, (G - 6) * T), {"detect_range": 300.0, "cooldown": 2.8})

	# --- B3: the clock ---
	_pad("PadSurge3", PAD3_COL, G)
	var plate := _put("res://scenes/actors/floor_plate.tscn", "GatePlate", PLATE_COL, G)
	plate.name = "GatePlate"
	var gate: Node2D = load("res://scripts/actors/timed_gate.gd").new()
	gate.name = "TimedGate"
	gate.set("controller", NodePath("../GatePlate"))
	gate.position = _p(GATE_COL, G)
	_own(gate)
	_mono("SurgeGate", "surge_gate", _p(PLATE_COL, G), Vector2(72, 48))
	for c in range(106, 125, 3):
		_yarn_at("GemLane%d" % c, c, G)

	# --- B4: combine ---
	_pad("PadSurge4", PAD4_COL, G)
	var drone: Node2D = load("res://scripts/actors/search_drone.gd").new()
	drone.name = "SearchDrone"
	drone.set("trigger_x", float(DRONE_TRIGGER_COL * T))
	drone.set("start_x", float((DRONE_TRIGGER_COL - 5) * T))
	drone.set("end_x", float(DRONE_END_COL * T))
	drone.set("speed", 150.0)
	drone.set("floor_y", float(G * T))
	drone.set("height", 260.0)
	drone.set("beam_length", 330.0)
	drone.set("half_angle", 10.0)
	drone.set("sway", 7.0)
	_own(drone)
	_yarn_at("GemStep1", 172, G - 3)
	_yarn_at("GemStep2", 175, G - 3)
	_yarn_at("GemPit1", 181, G - 4)
	_yarn_at("GemPit2", 183, G - 4)
	_item("pickup_bell", "BellPit", 182, G - 3)
	_yarn_at("GemVent", 194, G)

	# --- E: the fence ---
	_mono("ExitFence", "exit_fence", _p(208, G), Vector2(96, 96))
	_yarn_at("GemExit", 211, G)


func _pad(node_name: String, col: int, row: int) -> void:
	_put("res://scenes/actors/pad.tscn", node_name, col, row, {"power": 1, "duration": 10.0, "cooldown": 3.0})


func _mono(node_name: String, line_id: String, pos: Vector2, size: Vector2) -> void:
	# Loaded by path: the class references autoloads, which a --script run lacks at compile time.
	var t: Area2D = load("res://scripts/actors/monologue_trigger.gd").new()
	t.name = node_name
	t.set("line_id", line_id)
	t.set("require_mind", true)
	t.set("size", size)
	t.position = pos
	_own(t)


func _dock_actors() -> void:
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointC", CP_C_COL, G, {"checkpoint_id": "cp_c"})
	# Conveyors: embedded in the floor line (the floor tile row is left out under them).
	var i := 0
	for c in CONVEYORS:
		var n: int = c[1] - c[0] + 1
		_put_at("res://scenes/kit/conveyor.tscn", "Conveyor%d" % i, Vector2((c[0] + n / 2.0) * T, G * T), {"width_tiles": n, "speed": c[2]})
		i += 1
	# The falling crate over conveyor A (the gantry crate is the ceiling).
	_put_at("res://scenes/kit/falling_debris.tscn", "CrateDrop", Vector2(139 * T + 16, (G - 4) * T), {"warn_time": 0.8, "trigger_half": 28.0})
	var dock: Node2D = load("res://scripts/actors/dock_bot.gd").new()
	dock.name = "DockBot"
	dock.position = Vector2(DOCK_COL * T + 16, G * T)
	_own(dock)
	_mono("DockBotLine", "dock_bot", Vector2(DOCK_COL * T + 16, G * T), Vector2(192, 96))
	# The guard door: a roller shutter in the hut tunnel (the container is its ceiling).
	_put("res://scenes/kit/kit_shutter.tscn", "HutShutter", HUT_DOOR_COL, G, {"height_tiles": 2})
	# The security camera on the canopy, sweeping the dock: spotted -> alarm -> the shutter shuts
	# and the dormant turret wakes.
	var cam := _put_at("res://scenes/kit/security_camera.tscn", "DockCamera", Vector2(151 * T, (G - 4) * T),
			{"sweep_min": 55.0, "sweep_max": 125.0, "view_range": 230.0, "alarm_time": 6.0, "alarm_radius": 360.0})
	var sh: Array[NodePath] = [NodePath("../HutShutter")]
	cam.set("shutters", sh)
	_put_at("res://scenes/kit/sentry_turret.tscn", "TurretDock", Vector2(153 * T + 16, (G - 4) * T),
			{"mount": SentryTurret.Mount.CEILING, "dormant": true, "detect_range": 300.0})
	_yarn_at("GemDock1", 136, G)
	_item("pickup_bell", "BellBelt", 139, G - 2)
	_item("pickup_fish", "FishDock", 130, G)
	_yarn_at("GemDock2", 144, G)
	_yarn_at("GemDock3", 152, G)
	_item("pickup_bell", "BellCanopy", 152, G - 8)
	_yarn_at("GemHut1", 156, G - 4)
	_yarn_at("GemHut2", 158, G - 4)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointD", CP_D_COL, G, {"checkpoint_id": "cp_d"})


func _roof_actors() -> void:
	# The first roof: a pad (Surge for the run), yarn, a turret to dodge.
	_pad("PadSurge5", 94, ROOF)
	_mono("YardRoof", "yard_roof", _p(94, ROOF), Vector2(96, 64))
	_put("res://scenes/kit/sentry_turret.tscn", "TurretRoof", 97, ROOF, {"detect_range": 260.0, "cooldown": 2.6})
	_yarn_at("GemRoof1", 99, ROOF)
	_yarn_at("GemRoof2", 101, ROOF)
	_item("pickup_bell", "BellRoofGap1", 104, ROOF - 4)
	# The second roof: a patrol bot with a laser.
	_put("res://scenes/kit/kit_patrol_bot.tscn", "RoofBot", 112, ROOF, {"speed": 30.0, "laser_range": 170.0})
	_yarn_at("GemRoof3", 108, ROOF)
	_yarn_at("GemRoof4", 110, ROOF - 3)
	# The hanging-container bridge over the 5-tile gap (it touches both roofs at its ends).
	_put_at("res://scenes/kit/platform_horizontal.tscn", "Bridge",
			Vector2((BRIDGE_GAP[0] + 1.5) * T, ROOF * T), {"width_tiles": 3, "travel": 64.0, "speed": 40.0, "pause": 1.0})
	_item("pickup_mouse", "MouseBridge", 117, ROOF - 4)
	# The third roof: a hover drone bombs the approach to the crane stair.
	_put_at("res://scenes/kit/hover_drone.tscn", "DroneRoof", Vector2(123 * T, ROOF * T - 100.0), {"patrol_range": 56.0, "cooldown": 3.0})
	_yarn_at("GemRoof5", 121, ROOF)
	_yarn_at("GemRoof6", 125, ROOF)
	# The crane stair and the cab.
	_yarn_at("GemCrane1", 128, 14)
	_yarn_at("GemCrane2", 125, 12)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointR", 131, 8, {"checkpoint_id": "cp_r"})
	_item("pickup_mouse", "MouseCab", 133, 8)
	_item("pickup_bell", "BellCab", 130, 8)
	# The lift down to the dock (top y = 256, bottom y = 736).
	_put_at("res://scenes/kit/platform_vertical.tscn", "Lift",
			Vector2((LIFT_COLS[0] + 1.5) * T, 8 * T), {"width_tiles": 3, "travel": 480.0, "speed": 90.0, "pause": 1.2})
	_yarn_at("GemLift", 136, 10)


func _underpass_actors() -> void:
	# --- the landing under the Surge gap (a safe drop) ---
	_mono("YardUnder", "yard_underpass", _p(74, U), Vector2(288, 128))
	_yarn_at("GemUnder1", 72, U - 2)
	_yarn_at("GemUnder2", 76, U - 2)
	# --- the west culvert and the vault lane (S3) ---
	_item("pickup_fish", "FishCulvert", 67, U)
	_yarn_at("GemCul1", 61, U)
	_yarn_at("GemCul2", 59, U)
	_mono("YardVault", "yard_vault", _p(57, U), Vector2(96, 96))
	_put("res://scenes/kit/sentry_turret.tscn", "TurretVault", TURRET3_COL, U, {"detect_range": 520.0, "cooldown": 3.0})
	_put("res://scenes/kit/barrel_explosive.tscn", "BarrelVault", BARREL3_COL, U, {"persist": true})
	_put_at("res://scenes/kit/wall_blast.tscn", "VaultHatch", Vector2((HATCH[0] + 1) * T, (U + 1) * T),
			{"size_tiles": Vector2i(2, 1), "persist": true})
	_item("pickup_memory", "MemoryYard", 46, V, 0.0, {"memory_id": "memory_yard"})
	_item("pickup_bell", "BellVault", 44, V)
	# --- the main drain ---
	_yarn_at("GemUnder3", 80, U)
	_put("res://scenes/kit/hopper_bot.tscn", "HopperA", 91, U, {"detect_range": 220.0})
	_yarn_at("GemUnder4", 87, U)
	_yarn_at("GemUnder5", 94, U)
	# S1: the crawl cache. A bell glints at the dip; the golden bone is at the end of the tunnel.
	_item("pickup_bell", "BellDip", 99, U + 2)
	_yarn_at("GemCrawl1", 103, U + 2)
	_yarn_at("GemCrawl2", 106, U + 2)
	_item("pickup_bone", "BoneYard", 113, U + 3)
	_item("pickup_fish", "FishCache", 115, U + 3)
	# The electric floor under the broken floodlight, a bell over it.
	_put_at("res://scenes/kit/electric_floor.tscn", "ElectricFloor", Vector2(113.5 * T, U * T), {"width_tiles": 3})
	_item("pickup_bell", "BellElectric", 113, U - 2)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointU", 116, U, {"checkpoint_id": "cp_u"})
	_yarn_at("GemUnder6", 110, U)
	_yarn_at("GemUnder7", 120, U)
	# Acid: a leaking barrel (an obstacle to hop) and its pool (a hazard to jump).
	_put("res://scenes/kit/barrel_acid.tscn", "BarrelAcid", 118, U, {"persist": true})
	_put_at("res://scenes/kit/acid_pool.tscn", "AcidLeak", Vector2(123 * T, U * T), {"width": 64.0, "lifetime": 0.0})
	_yarn_at("GemUnder8", 123, U - 2)
	_put("res://scenes/kit/hopper_bot.tscn", "HopperB", 101, U, {"detect_range": 220.0})
	# --- the spur and the supply closet (S2) ---
	_item("pickup_fish", "FishSpur", 134, U)
	_put("res://scenes/kit/hopper_bot.tscn", "HopperC", 137, U, {"detect_range": 200.0})
	_put_at("res://scenes/kit/falling_debris.tscn", "SpurDrop", Vector2(139 * T, (G + 2) * T), {"warn_time": 0.8, "trigger_half": 28.0})
	_mono("YardCloset", "yard_closet", _p(140, U), Vector2(96, 96))
	# The drone hangs over the hatch: stand on the hatch, let it arm, run: its bomb lands on the
	# blast-only hatch and breaks it.
	_put_at("res://scenes/kit/hover_drone.tscn", "DroneSpur", Vector2((HATCH2[0] + 2.5) * T, U * T - 82.0), {"patrol_range": 96.0, "cooldown": 2.4})
	_put_at("res://scenes/kit/wall_blast.tscn", "SupplyHatch", Vector2((HATCH2[0] + 2.5) * T, (U + 1) * T),
			{"size_tiles": Vector2i(5, 1), "persist": true})
	_item("pickup_mouse", "MouseCloset", 142, V)
	_item("pickup_bell", "BellCloset1", 144, V - 2)
	_item("pickup_bell", "BellCloset2", 148, V)
	_item("pickup_fish", "FishCloset", 141, V)
	_yarn_at("GemSpur1", 150, U)
	# --- the pit's pocket ---
	_yarn_at("GemPocket1", 181, U)
	_yarn_at("GemPocket2", 183, U)
	_item("pickup_fish", "FishPocket", 186, U)
	_drain_lights()


func _drain_lights() -> void:
	## Dim drain lamps and a broken floodlight sparking over the electric floor.
	var i := 0
	for col in [50, 64, 82, 96, 108, 124, 136, 146, 180, 186]:
		var lamp := WarningLight.new()
		lamp.name = "DrainLamp%d" % i
		lamp.art_scale = 1
		lamp.mode = WarningLight.Mode.STEADY
		lamp.energy = 1.0
		lamp.light_radius_scale = 3.0
		lamp.halo_strength = 0.3
		lamp.shadows = false
		lamp.position = Vector2(col * T + 16, (G + 2) * T + 28)
		lamp.z_index = 1
		_own(lamp)
		i += 1
	var broken := WarningLight.new()
	broken.name = "BrokenFloodlight"
	broken.art_scale = 1
	broken.mode = WarningLight.Mode.FLICKER
	broken.energy = 1.6
	broken.light_radius_scale = 3.4
	broken.halo_strength = 0.4
	broken.shadows = false
	broken.position = Vector2(113.5 * T, (G + 2) * T + 44)
	broken.z_index = 1
	_own(broken)
	var cable := ColorRect.new()
	cable.name = "BrokenFloodlightCable"
	cable.color = Color("141a2c")
	cable.position = Vector2(113.5 * T - 1, (G + 2) * T)
	cable.size = Vector2(2, 38)
	cable.z_index = 0
	_own(cable)


func _low_vent(c0: int, c1: int, row: int, node_name: String) -> void:
	## Hangs 12 px from the container over the crawl vent, leaving a 20 px gap:
	## the standing cat (26) cannot pass, the crouched cat (14) can.
	var n := c1 - c0 + 1
	var beam := StaticBody2D.new()
	beam.name = node_name
	beam.position = Vector2(c0 * T + n * T / 2.0, row * T)
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(n * T, 12)
	shape.shape = rs
	shape.name = "Shape"
	shape.position = Vector2(0, 6)
	beam.add_child(shape)
	for i in n:
		var s := TileArt.sprite("hazard", TileArt.FLAT, Rect2i(0, 0, T, 12))
		s.name = "Plate%d" % i
		s.position = Vector2((i - n / 2.0) * T, 0)
		beam.add_child(s)
	_own(beam)
	for c in beam.get_children():
		c.owner = room


func _stoppers() -> void:
	## Invisible bot walls (physics layer 7): Bot1 walks cols 20-27, Bot2 cols 87-94.
	for col in [19, 28, 86, 95]:
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


func _puddles() -> void:
	## [name, centre col, width px, floor row]
	var defs := [
		["PuddleA1", 10.0, 128.0, G], ["PuddleA2", 24.5, 160.0, G], ["PuddleRun1", 44.0, 160.0, G],
		["PuddleRun2", 52.0, 128.0, G], ["PuddleGap", 66.0, 96.0, G], ["PuddleLand", 84.0, 96.0, G],
		["PuddleLane1", 108.0, 128.0, G], ["PuddleLane2", 116.0, 160.0, G], ["PuddleDock", 134.0, 64.0, G],
		["PuddleDock2", 144.0, 64.0, G], ["PuddleDock3", 160.0, 96.0, G], ["PuddleChase", 170.0, 96.0, G],
		["PuddleChase2", 189.0, 96.0, G], ["PuddleExit", 204.0, 160.0, G],
		["PuddleRoof1", 96.0, 96.0, ROOF], ["PuddleRoof2", 110.0, 96.0, ROOF], ["PuddleRoof3", 123.0, 96.0, ROOF],
		["PuddleU1", 52.0, 128.0, U], ["PuddleU2", 60.0, 96.0, U], ["PuddleU3", 74.0, 192.0, U],
		["PuddleU4", 88.0, 160.0, U], ["PuddleU5", 106.0, 96.0, U], ["PuddleU6", 124.0, 64.0, U],
		["PuddleU7", 133.0, 96.0, U], ["PuddleU8", 141.0, 128.0, U], ["PuddleU9", 182.0, 128.0, U],
	]
	for d in defs:
		var z := PuddleZone.new()
		z.name = d[0]
		z.width = d[2]
		z.position = Vector2(d[1] * T, d[3] * T)
		_own(z)


func _poles() -> void:
	## Floodlights on poles. [col, flicker, energy, height px]
	var defs := [
		[14, false, 1.5, 170], [27, true, 1.7, 180], [46, true, 1.7, 180], [67, false, 1.5, 170],
		[92, false, 1.5, 170], [109, true, 1.7, 180], [119, false, 1.5, 170],
		[143, false, 1.6, 170], [164, true, 1.6, 180], [178, false, 1.4, 170], [190, true, 1.6, 180],
		[206, false, 1.5, 170],
	]
	var i := 0
	for d in defs:
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
