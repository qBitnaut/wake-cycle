## Builds res://scenes/lab/fx_lab.tscn: a two-screen warehouse interior that
## shows every piece of the FX kit. Regenerate after changing the layout:
##     godot --headless --path . --script res://scenes/lab/build_fx_lab.gd
## The saved scene is a normal scene: open it in the editor and tweak freely
## (but re-running this script overwrites it).
extends SceneTree

const T := 18
const COLS := 36
const ROWS := 10
const SRC_METAL := 2

# Metal-expansion atlas coords.
const BRICK := Vector2i(13, 1)
const BRICK_B := Vector2i(13, 2)
const SLAB_TOP := Vector2i(19, 8)
const SLAB := Vector2i(19, 9)
const ROOF := Vector2i(20, 9)
const BRICKS := [Vector2i(12, 1), Vector2i(13, 1), Vector2i(14, 1), Vector2i(12, 2), Vector2i(13, 2), Vector2i(14, 2)]
const GIRDER_L := Vector2i(8, 9)
const GIRDER := Vector2i(9, 9)
const GIRDER_R := Vector2i(10, 9)
const POST := Vector2i(6, 9)
const CRATE := Vector2i(1, 10)
const CRATE_B := Vector2i(0, 10)
const CRATE_O := Vector2i(3, 10)
const PIPE_V := Vector2i(19, 3)
const PIPE_TOP := Vector2i(19, 2)
const CHAIN := Vector2i(12, 9)
const CHAIN_END := Vector2i(12, 14)
const BARREL := Vector2i(18, 12)

const MOON_HOLE := [8, 9]
const MOON_HOLE_2 := [21]
const PIT := [22, 23, 24, 25]
const WINDOWS := [Vector2i(1, 2), Vector2i(4, 2), Vector2i(27, 2)]  # top-left cell, 3x2 each

var lab: Node2D


func _fx(path: String, name: String, parent: Node, pos: Vector2, props := {}) -> Node:
	var n: Node = load(path).instantiate()
	n.name = name
	for k in props:
		n.set(k, props[k])
	parent.add_child(n)
	n.owner = lab
	if n is Node2D:
		n.position = pos
	elif n is Control:
		n.position = pos
	return n


func _node(n: Node, name: String, parent: Node) -> Node:
	n.name = name
	parent.add_child(n)
	n.owner = lab
	return n


func _initialize() -> void:
	var ts: TileSet = load("res://assets/tiles/warehouse_tileset.tres")
	lab = Node2D.new()
	lab.name = "FxLab"
	lab.set_script(load("res://scenes/lab/fx_lab.gd"))

	# --- Exterior: behind everything, seen through holes in the back wall ---
	var outside := _node(Node2D.new(), "Outside", lab)
	outside.z_index = -100
	_fx("res://scenes/fx/night_backdrop.tscn", "NightBackdrop", outside, Vector2(0, 150), {"brightness": 1.5})
	var rain_rects: Array[CanvasItem] = []
	for i in WINDOWS.size():
		var w: Vector2i = WINDOWS[i]
		var wr := ColorRect.new()
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/window_rain.gdshader")
		mat.set_shader_parameter("intensity", 0.4)
		mat.set_shader_parameter("wind", 0.22)
		wr.material = mat
		wr.position = Vector2(w * T)
		wr.size = Vector2(3 * T, 2 * T)
		wr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_node(wr, "WindowRain%d" % i, outside)
		rain_rects.append(wr)

	# --- Back wall (no occlusion), darker for depth ---
	var back := TileMapLayer.new()
	back.tile_set = ts
	back.occlusion_enabled = false
	back.z_index = -50
	back.self_modulate = Color(0.44, 0.46, 0.54)
	_node(back, "BackWall", lab)
	var win_cells := {}
	for w in WINDOWS:
		for dx in 3:
			for dy in 2:
				win_cells[w + Vector2i(dx, dy)] = true
	for x in COLS:
		for y in range(1, ROWS - 1):
			var c := Vector2i(x, y)
			if win_cells.has(c):
				continue
			back.set_cell(c, SRC_METAL, BRICKS[(x * 7 + y * 3) % BRICKS.size()])
	# Roof holes show sky: no back wall behind row 0 anywhere.

	# Window frames over the openings.
	for i in WINDOWS.size():
		var spr := Sprite2D.new()
		spr.texture = load("res://assets/fx/window_broken.png")
		spr.centered = false
		spr.position = Vector2(WINDOWS[i] * T)
		spr.z_index = -45
		if i == 1:
			spr.flip_h = true
		_node(spr, "WindowFrame%d" % i, lab)

	# Back fog, behind the props.
	_fx("res://scenes/fx/fog_layer.tscn", "FogBack", lab, Vector2(0, 96), {
		"band_width": 768.0, "band_height": 84.0, "density": 0.42,
		"drift": Vector2(4.0, 0.0), "scroll_scale": Vector2(0.9, 1.0), "fade_top": 0.7, "fade_bottom": 0.05,
	}).z_index = -40
	_fx("res://scenes/fx/fog_layer.tscn", "HighHaze", lab, Vector2(0, 14), {
		"band_width": 768.0, "band_height": 90.0, "density": 0.16, "noise_scale": 0.6,
		"drift": Vector2(-2.5, 0.0), "scroll_scale": Vector2(0.85, 1.0), "fade_top": 0.3, "fade_bottom": 0.5,
	}).z_index = -40

	# --- Decor (girder posts, chains, pipes): no collision, no occlusion ---
	var decor := TileMapLayer.new()
	decor.tile_set = ts
	decor.occlusion_enabled = false
	decor.z_index = -20
	decor.self_modulate = Color(0.8, 0.82, 0.9)
	_node(decor, "Decor", lab)
	# Steel frame on the back wall: a ring beam under the roof and columns.
	for x in range(1, COLS - 1):
		if not win_cells.has(Vector2i(x, 1)):
			decor.set_cell(Vector2i(x, 1), SRC_METAL, GIRDER)
	for x in [7]:
		for y in range(2, ROWS - 1):
			decor.set_cell(Vector2i(x, y), SRC_METAL, POST)
	# The catwalk hangs from the ring beam on chains (keeps the floor clear).
	for x in [13, 18]:
		for y in range(2, 5):
			decor.set_cell(Vector2i(x, y), SRC_METAL, CHAIN)
	for y in range(1, 4):
		decor.set_cell(Vector2i(29, y), SRC_METAL, CHAIN)
	decor.set_cell(Vector2i(29, 4), SRC_METAL, CHAIN_END)
	decor.set_cell(Vector2i(20, 7), SRC_METAL, PIPE_TOP)
	decor.set_cell(Vector2i(20, 8), SRC_METAL, PIPE_V)
	decor.set_cell(Vector2i(1, 8), SRC_METAL, BARREL)

	# --- Solid world: roof, walls, floor, crates; casts shadows ---
	var solid := TileMapLayer.new()
	solid.tile_set = ts
	_node(solid, "Solid", lab)
	for x in range(-1, COLS + 1):
		if not (x in MOON_HOLE or x in MOON_HOLE_2):
			solid.set_cell(Vector2i(x, 0), SRC_METAL, ROOF)
			solid.set_cell(Vector2i(x, -1), SRC_METAL, ROOF)
		if not x in PIT:
			solid.set_cell(Vector2i(x, ROWS - 1), SRC_METAL, SLAB_TOP)
	for y in range(-1, ROWS + 1):
		for x in [-1, 0, COLS - 1, COLS]:
			solid.set_cell(Vector2i(x, y), SRC_METAL, BRICK if y % 2 else BRICK_B)
	for x in range(-1, COLS + 1):
		if not x in PIT:
			solid.set_cell(Vector2i(x, ROWS), SRC_METAL, SLAB)
	solid.set_cell(Vector2i(2, 8), SRC_METAL, CRATE)
	solid.set_cell(Vector2i(3, 8), SRC_METAL, CRATE_B)
	solid.set_cell(Vector2i(2, 7), SRC_METAL, CRATE_O)
	# Catwalk: one-way girders (no occluder, so light passes between them).
	solid.set_cell(Vector2i(12, 5), SRC_METAL, GIRDER_L)
	for x in range(13, 19):
		solid.set_cell(Vector2i(x, 5), SRC_METAL, GIRDER)
	solid.set_cell(Vector2i(19, 5), SRC_METAL, GIRDER_R)

	# --- Lighting ---
	var rig := _fx("res://scenes/fx/lighting_rig.tscn", "LightingRig", lab, Vector2.ZERO, {
		"moon_angle": 18.0, "moon_energy": 0.7,
	}) as LightingRig
	rig.solid_layers = [solid]

	# Moon shafts: roof holes and window spill.
	var hole_x := (MOON_HOLE[0] + 1) * T
	_fx("res://scenes/fx/moon_shaft.tscn", "MoonShaft", lab, Vector2(hole_x, T), {
		"length": 144.0, "top_width": 36.0, "bottom_width": 58.0, "angle": 18.0,
		"ray_intensity": 0.34, "light_energy": 1.1, "dust_amount": 46,
	}).z_index = -10
	_fx("res://scenes/fx/moon_shaft.tscn", "MoonShaft2", lab, Vector2(MOON_HOLE_2[0] * T + 9, T), {
		"length": 144.0, "top_width": 18.0, "bottom_width": 36.0, "angle": 18.0,
		"ray_intensity": 0.22, "light_energy": 0.7, "dust_amount": 16, "floor_glow": 0.0,
	}).z_index = -10
	# Window glow: a soft cool wash on the wall around and under each window
	# (no shadows, cheap), instead of fake shafts from a back-wall window.
	for i in WINDOWS.size():
		var w: Vector2i = WINDOWS[i]
		var glow := PointLight2D.new()
		glow.texture = load("res://assets/fx/light_soft.png")
		glow.texture_scale = 1.3
		glow.position = Vector2(w * T) + Vector2(27, 40)
		glow.color = FXPalette.MOON
		glow.energy = 0.55
		glow.range_item_cull_mask = LightingRig.MASK_WORLD
		_node(glow, "WindowGlow%d" % i, lab)

	# Rain falling through the main hole: only visible inside the beam.
	_fx("res://scenes/fx/rain.tscn", "HoleRain", lab, Vector2(hole_x, 4), {
		"width": 36.0, "floor_y": 158.0, "density": 70.0, "wind": 46.0, "speed": 240.0,
		"lighting": RainFX.Lighting.LIGHT_ONLY,
	})

	# --- Hero corner: puddle, drip, cat, warning light ---
	var puddle := _fx("res://scenes/fx/puddle.tscn", "Puddle", lab, Vector2(186, 162)) as Puddle
	puddle.size = Vector2(96, 8)
	puddle.z_index = 20
	_fx("res://scenes/fx/drip.tscn", "Drip", lab, Vector2(255, T), {
		"fall_height": 144.0, "puddle": puddle,
	})
	_fx("res://scenes/fx/drip.tscn", "Drip2", lab, Vector2(229, 90 + 4), {
		"fall_height": 68.0, "puddle": puddle, "interval_min": 2.0, "interval_max": 4.5,
	})
	var cat := Sprite2D.new()
	cat.texture = load("res://assets/sprites/cat/cat_idle.png")
	cat.hframes = 10
	cat.position = Vector2(206, 155)
	cat.z_index = 2
	_node(cat, "Cat", lab)
	_fx("res://scenes/fx/warning_light.tscn", "WarningLight", lab, Vector2(306, 81), {"light_radius_scale": 1.9})

	# --- Machinery corner: steam, sparks over the goo pit, pads ---
	_fx("res://scenes/fx/steam_vent.tscn", "SteamVent", lab, Vector2(369, 128), {
		"cycle_on": 3.0, "cycle_off": 2.0,
	})
	_fx("res://scenes/fx/sparks.tscn", "Sparks", lab, Vector2(430, T), {"cable_length": 34.0})
	_fx("res://scenes/fx/goo_pool.tscn", "GooPool", lab, Vector2(PIT[0] * T, (ROWS - 1) * T + 4), {
		"width": PIT.size() * T, "depth": 14.0,
	})
	var pads := _node(Node2D.new(), "Pads", lab)
	var kinds := [FXPalette.Pad.SURGE, FXPalette.Pad.SPRING, FXPalette.Pad.PHASE, FXPalette.Pad.IMPACT, FXPalette.Pad.CHECKPOINT]
	for i in kinds.size():
		_fx("res://scenes/fx/pad_fx.tscn", "Pad%d" % i, pads, Vector2(495 + i * 30, (ROWS - 1) * T), {"kind": kinds[i], "light_energy": 0.7})

	# Front fog, over everything in the room.
	_fx("res://scenes/fx/fog_layer.tscn", "FogFront", lab, Vector2(0, 128), {
		"band_width": 768.0, "band_height": 52.0, "density": 0.32,
		"drift": Vector2(7.0, 0.0), "scroll_scale": Vector2(1.15, 1.0), "fade_top": 0.8, "fade_bottom": 0.0,
		"fog_color": Color(0.36, 0.42, 0.6),
	}).z_index = 30

	# --- Weather, camera, overlays ---
	var lightning := _fx("res://scenes/fx/lightning.tscn", "Lightning", lab, Vector2.ZERO) as LightningFX
	lightning.rig = rig
	lightning.backdrop = lab.get_node("Outside/NightBackdrop")
	lightning.flash_targets = rain_rects
	var cam := Camera2D.new()
	cam.position = Vector2(160, 90)
	_node(cam, "Camera", lab)
	_fx("res://scenes/fx/title_overlay.tscn", "TitleOverlay", lab, Vector2.ZERO)

	var packed := PackedScene.new()
	var err := packed.pack(lab)
	print("pack: ", error_string(err))
	print("save: ", error_string(ResourceSaver.save(packed, "res://scenes/lab/fx_lab.tscn")))
	lab.free()
	quit()
