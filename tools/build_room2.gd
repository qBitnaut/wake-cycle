## Generates res://scenes/levels/room2.tscn (Room 2, "The Yard"). Room 3 is built by
## tools/build_room3.gd; this script no longer touches room3.tscn. Run:
##   godot --headless --path . --script res://tools/build_room2.gd
##
## Sizes come from the measured reach (tools/audit/reach.gd), centre travel:
##                 single   double jump
##   plain           122 px   223 px
##   Surge           182 px   334 px
## A gap of N px needs travel >= N - 22 (the cat is 22 px wide). The Surge-only
## gap is 9 tiles (288 px): it needs 266, a plain double jump reaches 223 (43
## short), a Surge double jump 334 (68 spare: it lands in the human-timed double
## jumps from the apex on, tools/audit/margins.gd). It stays 9: at 8 tiles the plain
## double jump just reached the lip. The 5-tile pit in the
## combined beat (160 px, needs 138) is a plain double jump (85 spare) or a Surge
## single jump (44 spare); a plain single jump (122) falls short. (Both were a tile
## wider and too tight: Surge single 0%, plain double 61% of the human sweep.)
##
## Beats, left to right (column numbers; 32 px tiles, floor surface at row 10):
##   A    0-28   arrival: out of the warehouse door into the rain, a walker (Bot1)
##   B1  30-56   SURGE 1, discovery: a pad in a low service tunnel under a
##               container (32 px of headroom: the pad cannot be hopped over),
##               then 18 tiles of clear run
##   B2  57-95   SURGE 2, use it: checkpoint A, pad, a 9-tile gap; landing,
##               checkpoint B, a second walker (Bot2)
##   B3  98-130  SURGE 3, the clock: pad, the plate (col 102) starts the gate
##               (col 127) closing after 3.5 s; 25 tiles away: 3.1 s on Surge, 4.6 s plain
##   D  131-151  checkpoint C, the docked bot (col 139), checkpoint D
##   B4 154-191  SURGE 4, combine: pad, the searchlight drone chases from col 157;
##               crate steps, a 6-tile pit, a crawl vent (cover) and out
##   E  193-208  the fence: a cut in it at cols 202-206 and the exit to Room 3
extends SceneTree

const T := 32
const G := 10          ## ground surface row (y = 320)
const ROWS := 14       ## 448 px
const COLS := 209

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
const PLATE_A := Vector2i(6, 3)
const GIRDER_V := Vector2i(12, 4)
const GIRDER_H := Vector2i(13, 4)

const START_COL := 3
const TUNNEL := [30, 38]
const PAD1_COL := 34
const PAD2_COL := 62
const PITS := [[70, 78], [169, 173]]     ## inclusive columns with no floor
const PAD3_COL := 98
const PLATE_COL := 102
const GATE_COL := 127
const DOCK_COL := 139
const PAD4_COL := 154
const DRONE_TRIGGER_COL := 157
const VENT := [181, 184]                 ## container over the crawl vent
const EXIT_COL := 204
const FENCE_GAP := [202, 206]

var room: Node2D
var tiles: TileMapLayer
var back_tiles: TileMapLayer


func _initialize() -> void:
	_build_room2()
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


func _in_pit(x: int) -> bool:
	for p in PITS:
		if x >= p[0] and x <= p[1]:
			return true
	return false


func _ground() -> void:
	for x in range(0, COLS):
		if _in_pit(x):
			continue
		var lip := x + 1 < COLS and _in_pit(x + 1) or x > 0 and _in_pit(x - 1)
		_cell(x, G, HAZARD if lip else STEEL, BEVEL)
		_cell(x, G + 1, MAROON, GIRDER_H)
		_cell(x, G + 2, MAROON, FLAT if x % 2 == 0 else RIVET)
		_cell(x, G + 3, MAROON, RIVET if x % 2 == 0 else FLAT)


func _crates(x0: int, x1: int, h: int) -> void:
	for x in range(x0, x1 + 1):
		for k in range(h):
			_cell(x, G - 1 - k, MAROON, FRAMED if (x + k) % 2 == 0 else CROSS)


## A shipping container, two rows tall: corrugated side tiles (10..12, 5..6),
## solid (the back layer has no colliders and varies the panels). `top` is the
## row of its upper course.
func _container(x0: int, x1: int, top: int, mat: int, layer: TileMapLayer = null) -> void:
	for x in range(x0, x1 + 1):
		# Only the middle panel (11, 5..6) has a full cell collider; the end panels are art.
		var c := 11 if layer == null else 10 + (x - x0) % 3
		_cell(x, top, mat, Vector2i(c, 5), layer)
		_cell(x, top + 1, mat, Vector2i(c, 6), layer)


## Three containers high, the lowest with 32 px of headroom under it.
func _stack(x0: int, x1: int, mats: Array) -> void:
	for k in mats.size():
		_container(x0, x1, G - 3 - 2 * k, mats[k])


# ---- the room -----------------------------------------------------------------

func _build_room2() -> void:
	room = Node2D.new()
	room.name = "Room2"
	room.set_script(load("res://scripts/systems/room2.gd"))
	room.set("limits", Rect2i(0, 24, COLS * T, 360))
	var w := COLS * T

	var sky := ColorRect.new()
	sky.name = "SkyFill"
	sky.color = Color("0c1030")
	sky.position = Vector2(-64, -200)
	sky.size = Vector2(w + 128, 700)
	sky.z_index = -10
	_own(sky)

	var exterior := NightBackdrop.new()
	exterior.name = "Exterior"
	exterior.position = Vector2(0, 250)
	exterior.moon_position = Vector2(-120, -141)
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
	_pit_voids()

	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = _p(START_COL, G)
	_own(start)

	_place_actors()
	_low_vent()
	_stoppers()
	_puddles()
	_poles()
	_gantry()

	# Rain: two RainFX layers that follow the camera (Room2 moves them), one
	# behind the foreground, a sparser one in front.
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
	_own(amb)

	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	_own(hud)

	_save(room, "res://scenes/levels/room2.tscn")


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


func _warehouse() -> void:
	## The back of the warehouse on the left: a panelled wall under a flat roof
	## with the loading door the cat has just come out of, light spilling out.
	var wall := BackWall.new()
	wall.name = "WarehouseWall"
	wall.position = Vector2(0, 3 * T)
	wall.size = Vector2(7 * T, (G - 3) * T)
	wall.floor_y = (G - 3) * T
	wall.band_gaps = [Vector2(0, 5 * T)]
	wall.z_index = -5
	_own(wall)
	var interior := ColorRect.new()
	interior.name = "DoorInterior"
	interior.color = Color("2b2230")
	interior.position = Vector2(14, 6 * T)
	interior.size = Vector2(4 * T + 4, 4 * T)
	interior.z_index = -4
	_own(interior)
	var glow := ColorRect.new()
	glow.name = "DoorGlow"
	glow.color = Color(0.95, 0.62, 0.30, 0.18)
	glow.position = Vector2(14, 8 * T)
	glow.size = Vector2(4 * T + 4, 2 * T)
	glow.z_index = -4
	_own(glow)
	for r in [Rect2(8, 5 * T + 8, 4 * T + 16, 8), Rect2(8, 6 * T, 8, 4 * T), Rect2(4 * T + 18, 6 * T, 8, 4 * T)]:
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
	spill.position = Vector2(88, 8.4 * T)
	_own(spill)


func _back_stacks() -> void:
	## [x0, x1, courses, material]
	var defs := [
		[8, 14, 2, TEAL], [16, 21, 1, RUST], [22, 28, 2, MAROON], [41, 47, 1, TEAL],
		[50, 55, 2, RUST], [60, 66, 1, TEAL], [81, 87, 2, TEAL], [89, 94, 1, RUST],
		[96, 101, 2, MAROON], [104, 111, 2, TEAL], [113, 120, 1, RUST], [127, 133, 2, MAROON],
		[141, 147, 1, TEAL], [149, 155, 2, RUST], [159, 166, 1, MAROON], [176, 180, 2, TEAL],
		[187, 193, 2, RUST], [195, 200, 1, TEAL],
	]
	for d in defs:
		for k in range(d[2]):
			_container(d[0], d[1], G - 2 - 2 * k, d[3], back_tiles)


func _build_geometry() -> void:
	_ground()
	for y in range(0, ROWS):
		_cell(-1, y, BULKHEAD, FLAT)
		_cell(COLS, y, BULKHEAD, FLAT)
	# A: a few crates to hop over on the way out.
	_crates(13, 14, 1)
	_crates(16, 17, 2)
	# B1: the service tunnel. A stack of three containers on a gantry with 32 px
	# of headroom under it, too tall (224 px) to climb over: a double jump rises 171.
	_stack(TUNNEL[0], TUNNEL[1], [RUST, TEAL, MAROON])
	# B4: crate steps (1, 2 high), then a ground-level pit (see PITS), then the vent.
	_crates(161, 162, 1)
	_crates(163, 164, 2)
	_stack(VENT[0], VENT[1], [TEAL, MAROON, RUST])
	# Right end: a stack the fence ends against.
	for y in range(2, G):
		_cell(COLS - 1, y, BULKHEAD, FLAT)


func _pit_voids() -> void:
	var i := 0
	for p in PITS:
		var v := ColorRect.new()
		v.name = "PitVoid%d" % i
		v.color = Color("05060d")
		v.position = Vector2(p[0] * T, G * T)
		v.size = Vector2((p[1] - p[0] + 1) * T, 160)
		_own(v)
		i += 1


func _gantry() -> void:
	## Decor behind the tunnel container: two truss posts and a crossbeam.
	for x in [TUNNEL[0] - 1, TUNNEL[1] + 1]:
		for y in range(G - 8, G):
			_cell(x, y, STEEL, GIRDER_V, back_tiles)
	for x in range(TUNNEL[0] - 1, TUNNEL[1] + 2):
		_cell(x, G - 9, STEEL, GIRDER_H, back_tiles)


func _place_actors() -> void:
	# --- A: arrival ---
	_put("res://scenes/actors/gem.tscn", "GemA1", 14, G - 2)
	_put("res://scenes/actors/gem.tscn", "GemA2", 17, G - 3)
	var bot1 := _put("res://scenes/actors/patrol_bot.tscn", "Bot1", 23, G, {"stomps_to_befriend": 99})
	bot1.set("dir", -1)
	_put("res://scenes/actors/gem.tscn", "GemA3", 21, G - 1)
	_put("res://scenes/actors/gem.tscn", "GemA4", 25, G - 1)
	_mono("YardArrival", "yard_arrival", Vector2(START_COL * T + 16, G * T), Vector2(192, 96))

	# --- B1: discovery ---
	_pad("PadSurge1", PAD1_COL)
	_mono("SurgeFirst", "surge_first", _p(PAD1_COL, G), Vector2(44, 40))
	for c in range(41, 57, 2):
		_put("res://scenes/actors/gem.tscn", "GemRun%d" % c, c, G - 1)

	# --- B2: use it ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointA", 57, G, {"checkpoint_id": "cp_a"})
	_pad("PadSurge2", PAD2_COL)
	for c in range(80, 84):
		pass
	_put("res://scenes/actors/gem.tscn", "GemGap1", 72, G - 4)
	_put("res://scenes/actors/gem.tscn", "GemGap2", 74, G - 5)
	_put("res://scenes/actors/gem.tscn", "GemGap3", 76, G - 4)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointB", 82, G, {"checkpoint_id": "cp_b"})
	var bot2 := _put("res://scenes/actors/patrol_bot.tscn", "Bot2", 90, G, {"stomps_to_befriend": 99})
	bot2.set("dir", 1)

	# --- B3: the clock ---
	_pad("PadSurge3", PAD3_COL)
	var plate := _put("res://scenes/actors/floor_plate.tscn", "GatePlate", PLATE_COL, G)
	plate.name = "GatePlate"
	var gate: Node2D = load("res://scripts/actors/timed_gate.gd").new()
	gate.name = "TimedGate"
	gate.set("controller", NodePath("../GatePlate"))
	gate.position = _p(GATE_COL, G)
	_own(gate)
	_mono("SurgeGate", "surge_gate", _p(PLATE_COL, G), Vector2(72, 48))
	for c in range(106, 125, 3):
		_put("res://scenes/actors/gem.tscn", "GemLane%d" % c, c, G - 1)

	# --- D: the dock ---
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointC", 131, G, {"checkpoint_id": "cp_c"})
	var dock: Node2D = load("res://scripts/actors/dock_bot.gd").new()
	dock.name = "DockBot"
	dock.position = Vector2(DOCK_COL * T + 16, G * T)
	_own(dock)
	_mono("DockBotLine", "dock_bot", Vector2(DOCK_COL * T + 16, G * T), Vector2(192, 96))
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointD", 151, G, {"checkpoint_id": "cp_d"})
	_put("res://scenes/actors/gem.tscn", "GemDock1", 144, G - 1)
	_put("res://scenes/actors/gem.tscn", "GemDock2", 146, G - 2)

	# --- B4: combine ---
	_pad("PadSurge4", PAD4_COL)
	var drone: Node2D = load("res://scripts/actors/search_drone.gd").new()
	drone.name = "SearchDrone"
	drone.set("trigger_x", float(DRONE_TRIGGER_COL * T))
	drone.set("start_x", float((DRONE_TRIGGER_COL - 5) * T))
	drone.set("end_x", float(192 * T))
	drone.set("speed", 150.0)
	drone.set("height", 260.0)
	drone.set("beam_length", 330.0)
	drone.set("half_angle", 10.0)
	drone.set("sway", 7.0)
	_own(drone)
	_put("res://scenes/actors/gem.tscn", "GemStep1", 161, G - 3)
	_put("res://scenes/actors/gem.tscn", "GemStep2", 164, G - 4)
	_put("res://scenes/actors/gem.tscn", "GemPit1", 171, G - 4)
	_put("res://scenes/actors/gem.tscn", "GemPit2", 173, G - 4)
	_put("res://scenes/actors/gem.tscn", "GemVent", 183, G - 1)

	# --- E: the fence ---
	_mono("ExitFence", "exit_fence", _p(197, G), Vector2(96, 96))
	_put("res://scenes/actors/gem.tscn", "GemExit", 200, G - 1)


func _pad(node_name: String, col: int) -> void:
	_put("res://scenes/actors/pad.tscn", node_name, col, G, {"power": 1, "duration": 10.0, "cooldown": 3.0})


func _mono(node_name: String, line_id: String, pos: Vector2, size: Vector2) -> void:
	# Loaded by path: the class references autoloads, which a --script run lacks at compile time.
	var t: Area2D = load("res://scripts/actors/monologue_trigger.gd").new()
	t.name = node_name
	t.set("line_id", line_id)
	t.set("require_mind", true)
	t.set("size", size)
	t.position = pos
	_own(t)


func _low_vent() -> void:
	## Hangs 12 px from the container over the crawl vent, leaving a 20 px gap:
	## the standing cat (26) cannot pass, the crouched cat (14) can.
	var c0: int = VENT[0] + 1
	var c1: int = VENT[1] - 1
	var n := c1 - c0 + 1
	var beam := StaticBody2D.new()
	beam.name = "LowVent"
	beam.position = Vector2(c0 * T + n * T / 2.0, (G - 1) * T)
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
	## Invisible bot walls (physics layer 7): Bot1 walks cols 19-28, Bot2 cols 86-95.
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
	## [name, centre col, width px]
	var defs := [
		["PuddleA1", 10.0, 128.0], ["PuddleA2", 24.5, 160.0], ["PuddleRun1", 44.0, 160.0],
		["PuddleRun2", 52.0, 128.0], ["PuddleGap", 66.0, 96.0], ["PuddleLand", 85.0, 128.0],
		["PuddleLane1", 108.0, 128.0], ["PuddleLane2", 116.0, 160.0], ["PuddleDock", 134.0, 96.0],
		["PuddleDock2", 147.0, 128.0], ["PuddleChase", 159.0, 96.0], ["PuddleChase2", 178.0, 96.0],
		["PuddleExit", 193.0, 160.0],
	]
	for d in defs:
		var z := PuddleZone.new()
		z.name = d[0]
		z.width = d[2]
		z.position = Vector2(d[1] * T, G * T)
		_own(z)


func _poles() -> void:
	## Floodlights on poles. [col, flicker, energy, height px]
	var defs := [
		[14, false, 1.5, 170], [27, true, 1.7, 180], [46, true, 1.7, 180], [67, false, 1.5, 170],
		[75, true, 1.5, 150], [92, false, 1.5, 170], [109, true, 1.7, 180], [119, false, 1.5, 170],
		[143, false, 1.6, 170], [153, true, 1.6, 180], [167, false, 1.4, 170], [179, true, 1.6, 180],
		[195, false, 1.5, 170],
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
