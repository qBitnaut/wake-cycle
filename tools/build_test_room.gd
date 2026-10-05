## Generates res://scenes/levels/test_room.tscn: the HD test room at 640x360 on
## the 32 px wake_hd TileSet, lit like Mock C (LightingRig, moon shafts, warning
## lamps), with every actor from scenes/actors. Run:
##   godot --headless --path . --script res://tools/build_test_room.gd
##
## Sizes are chosen against the real jump arcs (see tools/audit/reach.gd):
## a plain jump is 3.1 tiles high; the double jump adds about 2.5; Surge and
## Spring scale speed and jump. Beats, left to right:
##   A wake-up, continue pad, checkpoint   B double-jump pit, shockwave pad, crate corridor
##   C surge pad, wide pit                 D spring pad, tall wall
##   E crawl tunnel                        F push crate onto plate (fence)
##   G shock switch, timed fence           H phase pad, dash fence, key, door
##   I patrol bot, spikes, impact pad, cracked floor over the T chamber
extends SceneTree

const T := 32
const G := 10          ## ground surface row (y = 320)
const ROWS := 14       ## 448 px: rows G+1..G+3 are the underfloor
const COLS := 151

# Pits (inclusive column ranges). Sized against the reach audit.
const PIT_A := [17, 21]
const PIT_C := [41, 48]

# Material blocks in tiles_wake_hd.png (atlas row = row + 10 * block).
const STEEL := 0
const BULKHEAD := 1
const RUST := 2
const MAROON := 3
const TEAL := 4
const VIOLET := 5

# Tile addresses inside a block.
const PIPE_H := [Vector2i(0, 0), Vector2i(1, 0)]
const PIPE_V := [Vector2i(2, 0), Vector2i(2, 1)]
const ELBOW_UP_RIGHT := Vector2i(4, 1)
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

var room: Node2D
var tiles: TileMapLayer


func _initialize() -> void:
	room = Node2D.new()
	room.name = "TestRoom"
	room.set_script(load("res://scripts/systems/test_room.gd"))
	room.set("limits", Rect2i(0, 24, COLS * T, 360))
	room.set("deep_bottom", ROWS * T)
	var w := COLS * T

	# ---- back to front -----------------------------------------------------
	var sky := ColorRect.new()
	sky.name = "SkyFill"
	sky.color = Color("0c1030")
	sky.position = Vector2(-64, -200)
	sky.size = Vector2(w + 128, ROWS * T + 400)
	_own(sky)

	var exterior := NightBackdrop.new()
	exterior.name = "Exterior"
	exterior.position = Vector2(0, 250)  # horizon, behind the windows
	exterior.moon_position = Vector2(-210, -141)  # world x = this + 0.98 * camera x
	_own(exterior)

	var window_a := Rect2(44, 88, 88, 108)
	var window_b := Rect2(128 * T + 16, 88, 88, 108)
	var skylights: Array[Rect2] = [
		Rect2(7 * T, 0, 2 * T, 2 * T),
		Rect2(72 * T, 0, 2 * T, 2 * T),
		Rect2(136 * T, 0, 2 * T, 2 * T),
	]
	var holes: Array[Rect2] = [window_a, window_b]
	holes.append_array(skylights)
	var windows: Array[Rect2] = [window_a, window_b]
	var wall := BackWall.new()
	wall.name = "BackWall"
	wall.size = Vector2(w, G * T)
	wall.floor_y = G * T
	wall.holes = holes
	wall.windows = windows
	_own(wall)

	_build_props()

	# Moon shafts through the skylights: behind the tiles, in front of the wall.
	for sk in skylights:
		_shaft(sk)

	_underfloor(w)

	tiles = TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	_own(tiles)
	_build_geometry(skylights)

	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = _p(9, G)
	_own(start)

	_place_actors()
	_low_beam()
	_stoppers()

	# Warning lamps: on the girder decks (open truss: no lamp shadows) and one
	# on the floor beside the bot.
	_lamp("LampB", Vector2(28 * T + 16, (G - 3) * T + 4 - 7), false)
	_lamp("LampKey", Vector2(114 * T + 16, (G - 3) * T + 4 - 7), false)
	_lamp("LampBot", Vector2(131 * T + 16, G * T - 7), true)

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

	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "Hud"
	_own(hud)

	var packed := PackedScene.new()
	print("pack: ", packed.pack(room))
	print("save: ", ResourceSaver.save(packed, "res://scenes/levels/test_room.tscn"))
	quit()


# ---- helpers --------------------------------------------------------------

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
	shaft.ray_intensity = 0.10  # as Room 1: a soft lift, the dust stays the sparkle
	shaft.ray_start = 2.0 * T - shaft.position.y  # under the two-row roof
	shaft.light_energy = 1.0
	shaft.floor_glow = 0.30
	shaft.dust_amount = 60
	shaft.dust_px = 1  # HD: motes are one art pixel, not FXScale.whole (2)
	_own(shaft)


func _lamp(node_name: String, pos: Vector2, shadows: bool) -> void:
	var lamp := WarningLight.new()
	lamp.name = node_name
	lamp.art_scale = 1
	lamp.mode = WarningLight.Mode.FLICKER if shadows else WarningLight.Mode.STEADY
	lamp.energy = 1.7
	lamp.light_radius_scale = 3.0
	lamp.halo_strength = 0.4
	lamp.shadows = shadows  # off when the lamp sits on a truss
	lamp.position = pos
	_own(lamp)


func _build_props() -> void:
	var props := Node2D.new()
	props.name = "Props"
	_own(props)
	# Back-wall props on the floor line, dimmed with the wall for depth.
	var floor_y := float(G * T)
	var defs := [
		["servers", 452.0],
		["terminal", 548.0],
		["big-computer", 40 * T + 8.0],
		["cryo-pod", 62 * T],
		["servers", 80 * T + 4.0],
		["terminal", 100 * T + 20.0],
		["big-computer", 104 * T + 8.0],
		["cryo-pod", 124 * T + 10.0],
		["servers", 140 * T],
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


func _underfloor(w: int) -> void:
	## Ink backing under the ground runs, so the girder tile's lattice reads.
	var runs := [[0, PIT_A[0] - 1], [PIT_A[1] + 1, PIT_C[0] - 1], [PIT_C[1] + 1, COLS - 1]]
	for r in runs:
		var rect := ColorRect.new()
		rect.name = "Underfloor%d" % r[0]
		rect.color = Color("1d1230")
		rect.position = Vector2(r[0] * T, (G + 1) * T)
		rect.size = Vector2((r[1] - r[0] + 1) * T, (ROWS - G - 1) * T)
		_own(rect)


# ---- geometry -------------------------------------------------------------

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


func _girder(x0: int, x1: int, row: int) -> void:
	## One-way girder deck with a truss post under each end.
	for x in range(x0, x1 + 1):
		_cell(x, row, STEEL, GIRDER_H)
	for x in [x0, x1]:
		for y in range(row + 1, G):
			_cell(x, y, STEEL, GIRDER_V)


func _build_geometry(skylights: Array[Rect2]) -> void:
	_ground(0, PIT_A[0] - 1)
	_ground(PIT_A[1] + 1, PIT_C[0] - 1)
	_ground(PIT_C[1] + 1, COLS - 1)
	# Chamber under the cracked floor: one tile of air under cols 142-143.
	for x in [142, 143]:
		tiles.erase_cell(Vector2i(x, G))
		tiles.erase_cell(Vector2i(x, G + 1))
		_cell(x, G + 2, MAROON, FLAT)
	# Ceiling: bulkhead with the skylight gaps.
	var sky_cols := {}
	for sk in skylights:
		for x in range(int(sk.position.x / T), int((sk.position.x + sk.size.x) / T)):
			sky_cols[x] = true
	for x in range(0, COLS):
		if sky_cols.has(x):
			continue
		_cell(x, 0, BULKHEAD, FLAT if x % 3 != 0 else RIVET)
		_cell(x, 1, BULKHEAD, BEVEL if x % 2 == 1 else VENTBOX)
	# Boundary walls (outside the camera limits).
	for y in range(0, ROWS):
		_cell(-1, y, BULKHEAD, FLAT)
		_cell(COLS, y, BULKHEAD, FLAT)
	# Start corner: teal riser as the left wall, a 3-2-1 crate stack.
	for y in range(2, G):
		_cell(0, y, TEAL, PIPE_V[y % 2])
	for c_r in [[1, 9, FRAMED], [2, 9, CROSS], [3, 9, FRAMED], [1, 8, CROSS], [2, 8, FRAMED], [1, 7, FRAMED]]:
		_cell(c_r[0], c_r[1], MAROON, c_r[2])
	# Overhead rust line, as in Mock C (out of reach, pure dressing).
	_cell(11, 2, RUST, PIPE_V[0])
	_cell(11, 3, RUST, ELBOW_UP_RIGHT)
	for x in range(12, 20):
		_cell(x, 3, RUST, PIPE_H[x % 2])
	# Right end: violet riser.
	for y in range(2, G):
		_cell(COLS - 2, y, VIOLET, PIPE_V[y % 2])

	# B: girder deck over the pad (one jump high), then the crate corridor.
	_girder(24, 28, G - 3)
	_block(30, 34, 2, G - 4)
	# D: the tall wall (6 high) with a top slab.
	_block(55, 56, G - 6, G - 1, STEEL)
	_block(55, 58, G - 6, G - 6, STEEL)
	# E: crawl tunnel ceiling (one tile of headroom).
	_block(63, 69, 2, G - 2)
	# F/G/H: ceilings over every fence and the door so they cannot be jumped.
	_block(83, 85, 2, G - 4)
	_block(89, 91, 2, G - 4)
	_block(98, 100, 2, G - 4)
	_block(107, 109, 2, G - 4)
	_block(119, 121, 2, G - 3)
	# G: the switch pillar. H: the key girder.
	_block(95, 95, G - 1, G - 1, STEEL)
	_girder(112, 114, G - 3)


func _place_actors() -> void:
	# --- A: wake-up, continue pad, checkpoint ---
	_put("res://scenes/actors/continue_pad.tscn", "ContinuePad", 6, G)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointA", 12, G, {"checkpoint_id": "cp_a"})
	_put("res://scenes/actors/gem.tscn", "GemA1", 14, G - 1)
	_put("res://scenes/actors/gem.tscn", "GemA2", 15, G - 2)
	# --- B: double jump over the pit, shockwave unlock, crate corridor ---
	_put("res://scenes/actors/gem.tscn", "GemPit", 19, G - 4)
	_put("res://scenes/actors/pad.tscn", "PadShockwave", 25, G, {"power": 99})
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
	_put("res://scenes/actors/crate_pushable.tscn", "PushCrate", 76, G)
	_put("res://scenes/actors/floor_plate.tscn", "PlateA", 80, G)
	_put("res://scenes/actors/laser_fence.tscn", "FenceA", 84, G,
		{"height_tiles": 3, "timed": false, "controller": NodePath("../PlateA")})
	# --- G: shock switch + timed fence ---
	_put("res://scenes/actors/laser_fence.tscn", "FenceTimed", 90, G,
		{"height_tiles": 3, "timed": true, "on_time": 1.4, "off_time": 1.8})
	_put("res://scenes/actors/shock_switch.tscn", "SwitchA", 95, G - 1, {"auto_off": 6.0, "_dy": -16.0})
	_put("res://scenes/actors/laser_fence.tscn", "FenceB", 99, G,
		{"height_tiles": 3, "timed": false, "controller": NodePath("../SwitchA")})
	# --- H: phase pad + dash through a timed fence, then key and door ---
	_put("res://scenes/actors/pad.tscn", "PadPhase", 103, G, {"power": 3})
	_put("res://scenes/actors/laser_fence.tscn", "FenceDash", 108, G,
		{"height_tiles": 3, "timed": true, "on_time": 2.0, "off_time": 0.6})
	_put("res://scenes/actors/key.tscn", "KeyBrass", 113, G - 3, {"key_color": "brass"})
	_put("res://scenes/actors/locked_door.tscn", "DoorBrass", 120, G, {"key_color": "brass"})
	# --- I: bot, spikes, impact pad, cracked floor over the T chamber ---
	_put("res://scenes/actors/patrol_bot.tscn", "Bot", 127, G)
	_put("res://scenes/actors/spikes.tscn", "Spikes1", 134, G)
	_put("res://scenes/actors/spikes.tscn", "Spikes2", 135, G)
	_put("res://scenes/actors/pad.tscn", "PadImpact", 139, G, {"power": 4})
	_put("res://scenes/actors/cracked_floor.tscn", "Cracked1", 142, G + 1)
	_put("res://scenes/actors/cracked_floor.tscn", "Cracked2", 143, G + 1)
	_put("res://scenes/actors/letter.tscn", "LetterT", 142, G + 2, {"letter_index": 2})
	_put("res://scenes/actors/fish.tscn", "FishChamber", 143, G + 2)
	_put("res://scenes/actors/checkpoint.tscn", "CheckpointC", 147, G, {"checkpoint_id": "cp_c"})


func _low_beam() -> void:
	## Hangs 12 px from the tunnel ceiling over cols 64-68, leaving a 20 px gap
	## above the floor: the standing cat (26) cannot pass, the crouched cat (14) can.
	var beam := StaticBody2D.new()
	beam.name = "LowBeam"
	beam.position = Vector2(66 * T + T / 2.0, (G - 1) * T)
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
	## Invisible walls on physics layer 7 ("bot_bounds"), solid only to bots and
	## pushable crates (the cat passes through them):
	##  - the bot patrols cols 124-132 and cannot wander onto the door, spikes,
	##    pad or cracked floor;
	##  - col 81 stops the push crate centred on the plate (col 80), so it can
	##    never be shoved past the plate and soft-lock the fence.
	for col in [124, 132, 81]:
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
	## Roof occluders past both level edges, so low moonlight cannot sneak in
	## sideways under the open ends.
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
