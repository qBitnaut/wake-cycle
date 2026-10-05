## Generates res://scenes/levels/home.tscn (Home, the ending) and
## res://scenes/ui/credits.tscn. Run under a display (MultiMesh-free, but the
## FX nodes build their children in _ready, so a GL context is safest):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/build_home.gd
##
## World, left to right (floor surface y 320; the sidewalk's back edge 312):
##     0-700   the end of the road: a street sign, the first tree, the dusty
##             blue house behind a picket fence; home_arrival on the first steps
##   700-1360  a utility pole, the sage cottage behind its hedge
##  1360-1800  the small tree, the butter house, sparrows on the fence, the big puddle
##  1800-2500  the second big tree, a lamp post, the rose house
##  2500-3150  the home's own garden: its tree, fence and open gate, flowers, pots
##  3150-3692  the cat's house: steps, porch, the door with the flap; inside, the
##             living room and the sunbeam on the cushion under the window
## Art: tools/art/home_art.py (assets/art_hd/home/).
extends SceneTree

const G := 320            ## floor surface
const BACK := 314         ## the sidewalk's back edge: fence feet
const LAWN_Y := 290       ## lawn strip top
const HOUSE_BASE := 292
const HOME_X := 3200      ## the house footprint's left edge
const HOME_W := 480
const HOME_OX := 52       ## canvas margin left of the footprint (home_art.HOME_OX)
const HOME_FLOOR := 304   ## interior floor (home_art FLOOR_Y 260 in a canvas at y 44)
const HOME_TOP := 44
const WORLD_W := 3692
const SPOT_X := 3520.0
const A := "res://assets/art_hd/home/"
const MASK_INTERIOR := 8

var room: Node2D
var glints_front: WetGlints
var glints_back: WetGlints
var front_areas: Array[Rect2] = []
var back_areas: Array[Rect2] = []
var front_drips: Array[Vector4] = []
var back_drips: Array[Vector4] = []
var occluders: Node2D


func _initialize() -> void:
	_build_home()
	_build_credits()
	quit()


func _save(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	print("pack ", path, ": ", packed.pack(root))
	print("save ", path, ": ", ResourceSaver.save(packed, path))


func _own(n: Node, parent: Node = null) -> Node:
	(parent if parent else room).add_child(n)
	n.owner = room
	return n


## A sprite with its bottom-centre (feet) at `feet`.
func _prop(file: String, node_name: String, feet: Vector2, z: int, flip := false) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = node_name
	s.texture = load(A + file)
	s.centered = false
	s.flip_h = flip
	var sz := s.texture.get_size()
	s.position = (feet - Vector2(sz.x * 0.5, sz.y)).round()
	s.z_index = z
	_own(s)
	return s


## A tiled strip (region repeat) from x0 to x1 with its top at y.
func _strip(file: String, node_name: String, x0: float, x1: float, y: float, z: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = node_name
	s.texture = load(A + file)
	s.centered = false
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, x1 - x0, s.texture.get_height())
	s.position = Vector2(x0, y)
	s.z_index = z
	_own(s)
	return s


func _fence(node_name: String, x0: float, x1: float) -> void:
	var f := _strip("fence.png", node_name, x0, x1, BACK - 46, -6)
	var x := x0
	var i := 0
	while x <= x1 + 1:
		var p := _prop("fence_post.png", "%sPost%d" % [node_name, i], Vector2(x, BACK + 2), -6)
		p.z_index = -6
		x += 80.0
		i += 1
	front_areas.append(Rect2(x0, BACK - 42, x1 - x0, 2))
	front_drips.append(Vector4(x0, x1, BACK - 30, G - 2))
	f.z_index = -6


func _hedge(node_name: String, x0: float, x1: float) -> void:
	_strip("hedge.png", node_name, x0, x1, BACK - 40, -6)
	front_areas.append(Rect2(x0, BACK - 38, x1 - x0, 4))


func _house(file: String, node_name: String, x: float) -> void:
	var s := Sprite2D.new()
	s.name = node_name
	s.texture = load(A + file)
	s.centered = false
	var sz := s.texture.get_size()
	s.position = Vector2(x, HOUSE_BASE - sz.y)
	s.z_index = -10
	_own(s)
	# Wet roof edge and gutter: glints, and drips onto the lawn.
	var wall_h: int = {"house_sage.png": 128, "house_butter.png": 120, "house_dusty.png": 132, "house_rose.png": 124}[file]
	var gutter: int = HOUSE_BASE - wall_h + 2
	back_areas.append(Rect2(x + sz.x * 0.5, gutter - 30, sz.x * 0.45, 26))
	back_drips.append(Vector4(x + 10, x + sz.x - 10, gutter + 2, HOUSE_BASE + 8))


func _tree(file: String, node_name: String, x: float, big: bool) -> void:
	var feet := Vector2(x, LAWN_Y + 16)
	var s := _prop(file, node_name, feet, -8)
	var sz := s.texture.get_size()
	var top := s.position.y
	var canopy_h := sz.y * (0.58 if big else 0.55)
	var cy := top + canopy_h * 0.5
	back_areas.append(Rect2(x - sz.x * 0.1, top + 6, sz.x * 0.45, canopy_h * 0.6))
	back_drips.append(Vector4(x - sz.x * 0.35, x + sz.x * 0.35, top + canopy_h * 0.85, LAWN_Y + 18))
	# Sun rays through the leaves (the sun is high on the right).
	var shaft := MoonShaft.new()
	shaft.name = node_name + "Rays"
	shaft.position = Vector2(x + sz.x * 0.12, top + canopy_h * 0.62)
	shaft.angle = -30.0
	shaft.length = G - shaft.position.y
	shaft.top_width = sz.x * 0.22
	shaft.bottom_width = sz.x * 0.5
	shaft.color = Color(1.0, 0.82, 0.5)
	shaft.ray_intensity = 0.1
	shaft.floor_glow = 0.0
	shaft.light_energy = 0.22
	shaft.dust_amount = 14 if big else 8
	shaft.dust_color = Color(1.5, 1.35, 0.95)
	shaft.z_index = -7
	_own(shaft)
	# Dappled shade: a few leaf masses block the sun.
	var masses := [[0.0, 0.0, 0.34, 0.26], [-0.2, 0.06, 0.18, 0.16], [0.21, 0.04, 0.17, 0.15], [0.02, -0.14, 0.2, 0.12]]
	var i := 0
	for m in masses:
		var occ := LightOccluder2D.new()
		occ.name = "%sShade%d" % [node_name, i]
		var poly := OccluderPolygon2D.new()
		var pts := PackedVector2Array()
		for k in 14:
			var a := TAU * k / 14.0
			pts.append(Vector2(cos(a) * sz.x * m[2], sin(a) * canopy_h * m[3] * 1.4))
		poly.polygon = pts
		occ.occluder = poly
		occ.position = Vector2(x + sz.x * m[0], cy + canopy_h * m[1])
		_own(occ, occluders)
		i += 1


func _puddle(node_name: String, x: float, w: float) -> void:
	# (Loaded by path: PuddleZone reaches the Cat, and through it the
	# autoloads, which a --script run lacks at compile time.)
	var z: Area2D = load("res://scripts/fx/puddle_zone.gd").new()
	z.name = node_name
	z.set("width", w)
	z.position = Vector2(x, G)
	_own(z)
	front_areas.append(Rect2(x - w * 0.5 + 6, G + 1, w - 12, 5))


func _build_home() -> void:
	room = Node2D.new()
	room.name = "Home"
	room.set_script(load("res://scripts/systems/home.gd"))
	room.set("limits", Rect2i(0, 24, WORLD_W, 360))
	room.set("spot_x", SPOT_X)

	var back := DayBackdrop.new()
	back.name = "Backdrop"
	back.position = Vector2(0, 300)
	back.z_index = -20
	_own(back)

	occluders = Node2D.new()
	occluders.name = "Shade"
	_own(occluders)

	_house("house_dusty.png", "HouseDusty", 260)
	_house("house_sage.png", "HouseSage", 900)
	_house("house_butter.png", "HouseButter", 1400)
	_house("house_rose.png", "HouseRose", 2090)

	_strip("lawn.png", "Lawn", -64, HOME_X, LAWN_Y, -9)
	back_areas.append(Rect2(-64, LAWN_Y + 3, HOME_X + 64, 6))

	_tree("tree_big.png", "TreeA", 226, true)
	_tree("tree_small.png", "TreeB", 1326, false)
	_tree("tree_big.png", "TreeC", 1880, true)
	_tree("tree_big.png", "TreeHome", 2790, true)

	# Gardens: flower beds, bushes (on the lawn, behind the fences).
	_prop("flowers_a.png", "BedA", Vector2(470, LAWN_Y + 18), -8)
	_prop("bush_a.png", "BushA", Vector2(610, LAWN_Y + 20), -8)
	_prop("flowers_b.png", "BedB", Vector2(1480, LAWN_Y + 18), -8)
	_prop("bush_b.png", "BushB", Vector2(1700, LAWN_Y + 20), -8)
	_prop("bush_c.png", "BushC", Vector2(2440, LAWN_Y + 20), -8)
	_prop("flowers_a.png", "BedC", Vector2(2210, LAWN_Y + 18), -8, true)
	_prop("flowers_b.png", "BedHome1", Vector2(2990, LAWN_Y + 18), -8)
	_prop("flowers_a.png", "BedHome2", Vector2(3080, LAWN_Y + 18), -8, true)
	_prop("bush_a.png", "BushHome", Vector2(2620, LAWN_Y + 20), -8, true)

	var lines := PowerLines.new()
	lines.name = "PowerLines"
	lines.poles.assign([760.0, 1960.0, 3060.0])
	lines.foot_y = BACK
	lines.pole_height = 214.0
	lines.sag = 26.0
	lines.drop_to = Vector2(HOME_X + 120, HOME_TOP + 70)
	lines.z_index = -8
	_own(lines)

	_fence("FenceA", 120, 680)
	_hedge("HedgeB", 880, 1360)
	_fence("FenceC", 1380, 1780)
	_fence("FenceD", 2080, 2480)
	_fence("FenceHome", 2520, 2920)
	_prop("gate.png", "Gate", Vector2(2934, BACK + 2), -6)

	_prop("street_sign.png", "StreetSign", Vector2(26, BACK + 2), -5)
	_prop("mailbox.png", "Mailbox", Vector2(700, BACK + 4), -5)
	_prop("lamp_post.png", "LampPost", Vector2(2000, BACK + 2), -5)
	_prop("pot_a.png", "PotA", Vector2(3112, G), -3)
	_prop("pot_b.png", "PotB", Vector2(3136, G), -3)

	# The street: sidewalk, curb, gutter, wet road (from the back edge down).
	_strip("ground.png", "Street", -64, WORLD_W + 64, G - 8, -4)
	var road := Puddle.new()
	road.name = "WetRoad"
	road.position = Vector2(-64, G + 17)
	road.size = Vector2(WORLD_W + 128, 48)
	road.water_tint = Color(0.30, 0.32, 0.42)
	road.reflectivity = 0.32
	road.reflect_scale = 3.2
	road.wave_amp = 0.25
	road.edge_fade = 0.0
	road.highlight = Color(0.55, 0.5, 0.42)
	road.z_index = 6
	_own(road)
	front_areas.append(Rect2(-64, G + 19, WORLD_W + 128, 10))

	_puddle("Puddle1", 352, 72)
	_puddle("Puddle2", 880, 120)
	_puddle("Puddle3", 1606, 150)
	_puddle("Puddle4", 2064, 64)
	_puddle("Puddle5", 2566, 96)

	_build_house()

	# Collision: the street, the steps up to the porch and the floor, the ends.
	var ground := StaticBody2D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	_own(ground)
	var gpoly := CollisionPolygon2D.new()
	gpoly.name = "Shape"
	var sx := HOME_X - 46.0
	gpoly.polygon = PackedVector2Array([
		Vector2(-120, G), Vector2(sx, G), Vector2(sx + 38, HOME_FLOOR), Vector2(WORLD_W + 40, HOME_FLOOR),
		Vector2(WORLD_W + 40, G + 80), Vector2(-120, G + 80)])
	_own(gpoly, ground)
	# The ends: the road out of view on the left, the house's right wall.
	for w in [[-12.0, "WallLeft"], [float(HOME_X + HOME_W) - 4.0, "WallRight"]]:
		var cs := CollisionShape2D.new()
		cs.name = w[1]
		var r := RectangleShape2D.new()
		r.size = Vector2(8, 420)
		cs.shape = r
		cs.position = Vector2(w[0], 160)
		_own(cs, ground)

	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = Vector2(56, G)
	_own(start)

	_mono("ArrivalTalk", "home_arrival", Vector2(150, G), Vector2(48, 96))
	_mono("FlapTalk", "home_flap", Vector2(3112, G), Vector2(40, 96))

	var cat: Node = load("res://scenes/player/cat.tscn").instantiate()
	cat.name = "Cat"
	_own(cat)

	glints_back = WetGlints.new()
	glints_back.name = "GlintsBack"
	glints_back.areas = back_areas
	glints_back.drip_lines = back_drips
	glints_back.glint_rate = 1.6
	glints_back.drip_rate = 0.16
	glints_back.z_index = -7
	_own(glints_back)
	glints_front = WetGlints.new()
	glints_front.name = "Glints"
	glints_front.areas = front_areas
	glints_front.drip_lines = front_drips
	glints_front.glint_rate = 2.6
	glints_front.drip_rate = 0.2
	glints_front.z_index = 7
	_own(glints_front)

	var birds := Birds.new()
	birds.name = "Birds"
	var perches: Array[Vector2] = [
		Vector2(330, BACK - 41), Vector2(352, BACK - 41),
		Vector2(1470, BACK - 41), Vector2(1494, BACK - 41), Vector2(1560, BACK - 41),
		Vector2(1180, 0), Vector2(1214, 0),
		Vector2(2700, BACK - 41),
	]
	# Two on the wire between the first poles (its height at their x).
	for i in perches.size():
		if perches[i].y == 0:
			perches[i].y = lines.wire_y(perches[i].x, 1)
	birds.perches = perches
	birds.z_index = -5
	_own(birds)

	var rig := LightingRig.new()
	rig.name = "LightingRig"
	# Cool shade, warm sun: lit surfaces land a touch over 1, shade at 0.8.
	rig.night_tint = Color(0.78, 0.79, 0.9)
	rig.moon_color = Color(1.0, 0.86, 0.62)
	rig.moon_energy = 0.33
	rig.moon_angle = -52.0
	rig.moon_shadows = true
	rig.moon_shadow_filter = Light2D.SHADOW_FILTER_PCF13
	rig.moon_shadow_smooth = 2.0
	rig.moon_lights_motes = false
	rig.glow_intensity = 0.55
	rig.glow_threshold = 1.12
	rig.vignette = 0.12
	_own(rig)

	var amb: Node = load("res://scripts/systems/ambience.gd").new()
	amb.name = "Ambience"
	amb.set("rain_stream", load("res://assets/audio/ambient/birdsong.ogg"))
	amb.set("rain_db", -13.0)
	amb.set("hum_stream", load("res://assets/audio/ambient/drip_loop.ogg"))
	amb.set("hum_db", -27.0)
	amb.set("step_db", -24.0)
	_own(amb)

	_save(room, "res://scenes/levels/home.tscn")


func _mono(node_name: String, line_id: String, pos: Vector2, size: Vector2) -> void:
	var t: Area2D = load("res://scripts/actors/monologue_trigger.gd").new()
	t.name = node_name
	t.set("line_id", line_id)
	t.set("size", size)
	t.position = pos
	_own(t)


## The cat's house: the interior (behind) and the facade (dissolves), the
## steps, the flap, the cushion, the window's sunbeam and the triggers.
func _build_house() -> void:
	var cx := float(HOME_X - HOME_OX)
	var inside := Sprite2D.new()
	inside.name = "Interior"
	inside.texture = load(A + "home_inside.png")
	inside.centered = false
	inside.position = Vector2(cx, HOME_TOP)
	inside.z_index = -3
	inside.light_mask = MASK_INTERIOR
	_own(inside)
	# The window glass, glowing with the sun (four panes round the mullions).
	var wx := cx + 356 + HOME_OX
	var wy := float(HOME_TOP + 150)
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var panes := [Rect2(0, 0, 28, 27), Rect2(31, 0, 27, 27), Rect2(0, 30, 28, 26), Rect2(31, 30, 27, 26)]
	var i := 0
	for p in panes:
		var g := ColorRect.new()
		g.name = "Pane%d" % i
		g.position = Vector2(wx, wy) + p.position
		g.size = p.size
		g.color = Color(1.32, 1.2, 0.92) if p.position.y == 0 else Color(1.25, 1.08, 0.78)
		g.material = glow_mat
		g.z_index = -4  # behind the room: the plant on the sill stands in front
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_own(g)
		i += 1
	var beam := MoonShaft.new()
	beam.name = "Sunbeam"
	beam.position = Vector2(wx + 29, wy + 14)
	beam.angle = -36.0
	beam.length = HOME_FLOOR - beam.position.y
	beam.top_width = 52.0
	beam.bottom_width = 78.0
	beam.color = Color(1.0, 0.84, 0.52)
	beam.ray_intensity = 0.42
	beam.floor_glow = 0.55
	beam.light_energy = 0.6
	beam.dust_amount = 34
	beam.dust_color = Color(1.7, 1.5, 1.05)
	beam.z_index = 4
	_own(beam)
	var land := PointLight2D.new()
	land.name = "BeamLight"
	land.texture = load("res://assets/fx/light_soft.png")
	land.texture_scale = 1.3
	land.color = Color(1.0, 0.82, 0.55)
	land.energy = 0.32
	land.range_item_cull_mask = MASK_INTERIOR
	land.position = Vector2(SPOT_X + 4, HOME_FLOOR - 14)
	_own(land)
	var warm := PointLight2D.new()
	warm.name = "RoomLight"
	warm.texture = load("res://assets/fx/light_soft.png")
	warm.texture_scale = 6.0
	warm.color = Color(1.0, 0.78, 0.55)
	warm.energy = 0.16
	warm.range_item_cull_mask = MASK_INTERIOR
	warm.position = Vector2(HOME_X + HOME_W * 0.55, HOME_FLOOR - 70)
	_own(warm)
	# The cushion (its front rim covers the sleeping cat's lower edge).
	var cb := _prop("cushion_back.png", "CushionBack", Vector2(SPOT_X, HOME_FLOOR + 2), -2)
	cb.light_mask = MASK_INTERIOR
	var cf := _prop("cushion_front.png", "CushionFront", Vector2(SPOT_X, HOME_FLOOR + 2), 6)
	cf.light_mask = MASK_INTERIOR
	# Steps up to the porch.
	_prop("steps.png", "Steps", Vector2(HOME_X - 22, G), -2)
	# The facade: dissolves (shaders/dither_fade.gdshader) as the cat goes in.
	var facade := Node2D.new()
	facade.name = "Facade"
	facade.z_index = 2
	_own(facade)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/dither_fade.gdshader")
	mat.set_shader_parameter("sweep_dir", Vector2(-1.2, 0.5))
	var front := Sprite2D.new()
	front.name = "Front"
	front.texture = load(A + "home_front.png")
	front.centered = false
	front.position = Vector2(cx, HOME_TOP)
	front.material = mat
	_own(front, facade)
	var flap := Sprite2D.new()
	flap.name = "Flap"
	flap.texture = load(A + "flap.png")
	flap.centered = false
	flap.position = Vector2(cx + HOME_OX + 52 + 8, HOME_TOP + 260 - 18 - 3)
	flap.material = mat
	_own(flap, facade)
	front_areas.append(Rect2(cx + HOME_OX + 190, HOME_TOP + 144, 64, 30))
	front_areas.append(Rect2(cx + HOME_OX + 330, HOME_TOP + 144, 64, 30))
	front_drips.append(Vector4(cx + 8, cx + 190, 217, HOME_FLOOR))
	front_drips.append(Vector4(HOME_X - 6, HOME_X + HOME_W + 6, HOME_TOP + 112, HOME_FLOOR))
	# The porch roof shades the door.
	var occ := LightOccluder2D.new()
	occ.name = "PorchShade"
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(cx + 8, 202), Vector2(cx + 196, 202), Vector2(cx + 196, 216), Vector2(cx + 8, 216)])
	occ.occluder = poly
	_own(occ, occluders)
	# Triggers: the flap (walk into the door) and the spot (walk into the sun).
	var ft := Area2D.new()
	ft.name = "FlapTrigger"
	ft.collision_layer = 0
	ft.collision_mask = 2
	ft.position = Vector2(cx + HOME_OX + 52 + 14, HOME_FLOOR)
	_own(ft)
	var fs := CollisionShape2D.new()
	fs.name = "Shape"
	var fr := RectangleShape2D.new()
	fr.size = Vector2(10, 40)
	fs.shape = fr
	fs.position = Vector2(0, -20)
	_own(fs, ft)
	var st := Area2D.new()
	st.name = "SpotTrigger"
	st.collision_layer = 0
	st.collision_mask = 2
	st.position = Vector2(SPOT_X - 22, HOME_FLOOR)
	_own(st)
	var ss := CollisionShape2D.new()
	ss.name = "Shape"
	var sr := RectangleShape2D.new()
	sr.size = Vector2(16, 40)
	ss.shape = sr
	ss.position = Vector2(0, -20)
	_own(ss, st)


# ---- credits -------------------------------------------------------------------------

func _build_credits() -> void:
	var c := Node2D.new()
	c.name = "Credits"
	c.set_script(load("res://scripts/ui/credits.gd"))
	_save(c, "res://scenes/ui/credits.tscn")
