class_name WorldMap
extends Node2D
## The world map between levels, in the spirit of Secret Agent's: the district
## from the warehouse to the cat's home, side-on, with the route drawn across
## it. Shown after each level's exit; the game itself starts in the warehouse.
##
## Opening it:
##     WorldMap.open("yard")     # the yard is finished: fade out, open the map
## A RoomExit whose next_scene is the map scene works too: the map sees which
## level the cat came from (SaveSystem.session_scene) and treats it as
## finished. Either way the level is completed in LevelRegistry (its unlocks
## open) and the map plays the reveal: the finished plate stamps, the new
## path draws itself in while the camera pans along it (the parallax), the new
## level lights up and the cat walks there. Then the player has the cat.
##
## Controls are movement only (the jam rule): left/right (and up/down where a
## path forks) walk the cat from node to node along open paths; on a level,
## Up or Jump goes in, like walking into a door in Secret Agent. Going in
## eases the view in on the door (CineZoom), fades and loads the level's scene.
## Finished levels can be revisited. Home is the last node: going in plays the
## ending.
##
## Time of day follows the route: night and rain at the warehouse end, the
## rain easing over the stacks, pre-dawn at the fence, morning over the
## suburbs. The sky, the tint of every painted layer and the lamps are worked
## out per screen column from where that column is on the map (see
## shaders/map_layer.gdshader), so a pan carries the dawn across the frame.
## Layers, back to front: sky (with moon and sun), clouds, far skyline (city
## towers dissolving into hills), mid district, street, landmarks, stairs,
## path, markers, cat, rain, foreground (poles, cables, scrub).
##
## The registry is data/levels.json (LevelRegistry); adding a level is a data
## edit plus a scene (docs/WORLD_MAP.md). Progress is saved in GameState
## (map_completed, map_unlocked, map_node).

## The player chose a level (emitted before the transition starts).
signal level_chosen(id: String, scene_path: String)
## The arrival sequence is over and the player has control.
signal reveal_finished
## The cat stopped on a node.
signal arrived(id: String)

const SCENE := "res://scenes/ui/world_map.tscn"
const ART := "res://assets/art_hd/map/"
const MAP_ART_JSON := "res://assets/art_hd/map/map_art.json"
const CAT_SHADOW := preload("res://assets/fx/light_soft.png")
const HALO := preload("res://assets/fx/halo.png")
const MOON := preload("res://assets/fx/moon.png")
const CONE := preload("res://assets/fx/light_cone.png")
const LAYER_SHADER := preload("res://shaders/map_layer.gdshader")
const GLOW_SHADER := preload("res://shaders/map_glow.gdshader")
const SKY_SHADER := preload("res://shaders/map_sky.gdshader")
const FONT := preload("res://assets/fonts/monogram.ttf")
const RAIN_LOOP := "res://assets/audio/amb/rain_loop.ogg"
const BIRDS_LOOP := "res://assets/audio/amb/amb_home.ogg"

const VIEW := Vector2(640, 360)
## Walking speed along the path (px/s); stairs and ladders are slower.
const SPEED := 165.0
const CLIMB_SPEED := 100.0
## Parallax scroll rates (1 = the map itself).
const FAR_SCROLL := 0.16
const MID_SCROLL := 0.45
const CLOUD_SCROLL := 0.07
const FG_SCROLL := 1.3
const MID_X0 := -200.0
const MID_BOTTOM := 290.0
const FAR_BOTTOM := 262.0
const HILLS_BOTTOM := 282.0
## How far the reveal's drawing head travels per second.
const DRAW_SPEED := 300.0

## Time-of-day tint (albedo multiplier) along the map's p, for the map's own
## plane (street, landmarks, stairs, foreground): lighter than the rooms'
## night tint, since nothing on the map is lit by a moon light.
const FRONT_TINT := [
	[0.00, Color(0.58, 0.63, 0.92)],
	[0.30, Color(0.58, 0.63, 0.92)],
	[0.50, Color(0.64, 0.68, 0.94)],
	[0.66, Color(0.76, 0.74, 0.94)],
	[0.76, Color(0.92, 0.82, 0.88)],
	[0.86, Color(1.00, 0.92, 0.86)],
	[0.94, Color(1.00, 0.98, 0.94)],
	[1.00, Color(1.00, 0.99, 0.96)],
]
## The distance (far skyline, mid district, clouds): darker at night, so the
## landmarks stand out against it.
const BACK_TINT := [
	[0.00, Color(0.40, 0.44, 0.64)],
	[0.30, Color(0.40, 0.44, 0.64)],
	[0.50, Color(0.47, 0.51, 0.72)],
	[0.66, Color(0.62, 0.62, 0.84)],
	[0.76, Color(0.84, 0.76, 0.84)],
	[0.86, Color(0.98, 0.90, 0.86)],
	[0.94, Color(1.00, 0.98, 0.95)],
	[1.00, Color(1.00, 1.00, 0.98)],
]
## Clouds: a dark storm deck at night, white fair-weather clouds by morning
## (the cloud art is Home's, painted for daylight).
const CLOUD_TINT := [
	[0.00, Color(0.25, 0.28, 0.42)],
	[0.45, Color(0.29, 0.32, 0.47)],
	[0.66, Color(0.55, 0.50, 0.68)],
	[0.80, Color(0.92, 0.80, 0.82)],
	[0.92, Color(1.00, 0.98, 0.97)],
	[1.00, Color(1.00, 1.00, 1.00)],
]
## Rim light on landmark top edges: silver moonlight, then warm sunrise, then
## a faint sun.
const RIM_KEYS := [
	[0.00, Color(0.30, 0.36, 0.55)],
	[0.55, Color(0.30, 0.34, 0.52)],
	[0.72, Color(0.42, 0.30, 0.34)],
	[0.84, Color(0.40, 0.30, 0.18)],
	[1.00, Color(0.14, 0.12, 0.08)],
]

## The level to treat as just finished when the map opens (open()).
static var _pending := ""
## Tests: false makes going in emit level_chosen without changing scene.
static var load_levels := true
static var _deep_link_used := false

@export var camera: Camera2D

var cat: Node2D
var cat_sprite: AnimatedSprite2D
## The node the cat stands on ("" while walking).
var at_node := ""
## True while the arrival sequence runs (input ignored but for skipping).
var auto := false
var leaving := false
var markers := {}           # level id -> MapMarker
var landmarks := {}         # level id -> [albedo Sprite2D, glow Sprite2D or null]
var cam_x := 320.0
## Audit hook: the last level handed to level_chosen.
var chosen := ""

var _map_w := 2070.0
var _p0 := 200.0
var _p1 := 1870.0
var _layer_mats: Array[ShaderMaterial] = []
var _glow_mats: Array[ShaderMaterial] = []
var _sky_mat: ShaderMaterial
var _rim_lut: Texture2D
# Held here: a texture loaded inside a draw callback and dropped at once is
# freed before the frame renders (it draws as a white block).
var _arrow_tex: Texture2D
var _gem_tex: Texture2D
var _sky: ColorRect
var _sky_holder: Node2D
var _moon: Node2D
var _sun: Node2D
var _clouds: Array = []      # [Sprite2D, base x, y, keep_until]
var _bands: Array = []       # [holder, Sprite2D, scroll, tiled]
var _rain_holder: Node2D
var _rain: RainFX
var _paths: Node2D
var _label: Node2D
var _label_id := ""
var _label_a := 0.0
var _cone: Sprite2D
var _rain_snd: AudioStreamPlayer
var _birds_snd: AudioStreamPlayer
var _rig: LightingRig
var _art := {}
var _t := 0.0

# Walking state.
var _seg := PackedVector2Array()
var _seg_len := 0.0
var _dist := 0.0
var _from := ""
var _to := ""
var _route: Array = []       # node ids still to walk to (auto walks)
var _hold_t := 0.0
var _idle_t := 0.0
var _hop := 0.0

# The arrival sequence.
var _seq_speed := 1.0
var _reveal := {}            # path index -> [drawn length, drawn from the a end]
var _draw_head := Vector2.INF
var _cam_focus := Vector2.INF
var _cam_hold_x := INF
var _js_callbacks: Array = []


# ---- opening ---------------------------------------------------------------------

## Leave the current scene for the map, treating level `completed_id` as just
## finished (its unlocks open and the map plays the reveal). Pass "" to just
## show the map where the cat was.
static func open(completed_id: String) -> void:
	_pending = completed_id
	var tree := Engine.get_main_loop() as SceneTree
	var from: Node = tree.current_scene if tree.current_scene else tree.root
	RoomTransition.go(from, SCENE)


## Web audit deep link: index.html?start=map&completed=<level id>[&letters=3]
## opens the map as that level's exit would (a fresh game with the mind awake;
## the shockwave too from the Stacks on; `letters` = C-A-T letters held).
static func web_deep_link() -> void:
	if _deep_link_used or not OS.has_feature("web"):
		return
	_deep_link_used = true
	var q := "new URLSearchParams(window.location.search).get('%s') || ''"
	if str(JavaScriptBridge.eval(q % "start")) != "map":
		return
	var done := str(JavaScriptBridge.eval(q % "completed"))
	var letters := int(str(JavaScriptBridge.eval(q % "letters")))
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	gs.new_game()
	gs.awaken_mind()
	if LevelRegistry.order_of(done) >= 3.0:
		gs.unlock_shockwave()
	for i in clampi(letters, 0, 3):
		gs.collect_letter(i)
	Engine.get_main_loop().root.get_node("Monologue").reset()
	var ss: Node = Engine.get_main_loop().root.get_node("SaveSystem")
	ss.session_scene = ""
	ss.session_checkpoint = ""
	_pending = done
	RoomTransition.arriving = true
	(Engine.get_main_loop() as SceneTree).change_scene_to_file.call_deferred(SCENE)


var _came_from := ""


func _enter_tree() -> void:
	# The scene the cat left (a level whose RoomExit points here), then the
	# map's own save session (a Continue onto the map restores its snapshot).
	_came_from = SaveSystem.session_scene
	SaveSystem.begin_level(scene_file_path if scene_file_path != "" else SCENE)


func _ready() -> void:
	LevelRegistry.load_data()
	LevelRegistry.ensure_start()
	_map_w = LevelRegistry.map_size().x
	_p0 = LevelRegistry.position_of(LevelRegistry.start_id()).x
	_p1 = LevelRegistry.position_of(LevelRegistry.final_id()).x
	_art = _read_json(MAP_ART_JSON)
	var arriving := RoomTransition.arriving
	RoomTransition.arriving = false
	var done := _pending
	_pending = ""
	if done == "" and arriving:
		done = LevelRegistry.id_for_scene(_came_from)
	if done != "" and not LevelRegistry.has(done):
		push_warning("WorldMap: unknown level '%s'" % done)
		done = ""
	var fresh: Array = []
	var newly_done := false
	if done != "":
		newly_done = not LevelRegistry.is_completed(done)
		fresh = LevelRegistry.complete(done)
		GameState.map_node = done
	if GameState.map_node == "" or not LevelRegistry.is_open(GameState.map_node):
		GameState.map_node = _furthest_open()
	_build()
	at_node = GameState.map_node
	cat.position = LevelRegistry.position_of(at_node)
	cam_x = _clamp_cam(cat.position.x)
	_update_camera(0.0, true)
	_refresh_markers(fresh)
	if newly_done and markers.has(done):
		# It was a lit plate until now: the reveal stamps it done.
		(markers[done] as MapMarker).set_state(MapMarker.State.OPEN)
	SaveSystem.save_checkpoint("", SCENE)
	if arriving:
		RoomTransition.fade_in(self, 0.9)
	_start_audio()
	if OS.has_feature("web"):
		_setup_web()
	if done != "" and (newly_done or not fresh.is_empty()):
		_play_reveal(done, fresh, newly_done)
	else:
		_show_label(at_node)
		reveal_finished.emit.call_deferred()


func _furthest_open() -> String:
	var best := LevelRegistry.start_id()
	for id in LevelRegistry.open_levels():
		if LevelRegistry.is_main(id) and LevelRegistry.order_of(id) > LevelRegistry.order_of(best):
			best = id
	return best


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## 0 at the warehouse, 1 at home: the time of day at world x.
func p_at(x: float) -> float:
	return (x - _p0) / maxf(_p1 - _p0, 1.0)


# ---- building the map -------------------------------------------------------------------

func _build() -> void:
	if camera == null:
		camera = Camera2D.new()
		camera.name = "Camera"
		add_child(camera)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(_map_w)
	camera.limit_bottom = int(VIEW.y)
	camera.position_smoothing_enabled = false
	camera.make_current()
	_rig = get_node_or_null("LightingRig") as LightingRig
	if _rig:
		_rig.night_tint = Color.WHITE
		_rig.moon_enabled = false
		_rig.vignette = 0.28
		_rig.glow_intensity = 0.85
		_rig.glow_threshold = 1.0
	_arrow_tex = load(ART + "arrow.png")
	_gem_tex = load(ART + "gem.png")
	var lut := _lut(FRONT_TINT)
	var back := _lut(BACK_TINT)
	_rim_lut = _lut(RIM_KEYS)
	_build_sky()
	_build_clouds(_lut(CLOUD_TINT))
	_band("Far", "res://assets/art_hd/bg/towers.png", FAR_SCROLL, FAR_BOTTOM, true, back, Vector2(-1, -1), Vector2(0.6, 0.84), 0.85)
	_band("Hills", "res://assets/art_hd/home/hills.png", FAR_SCROLL + 0.02, HILLS_BOTTOM, true, back, Vector2(0.6, 0.84), Vector2(2, 3), 1.0)
	_band("Mid", ART + "mid.png", MID_SCROLL, MID_BOTTOM, false, back, Vector2(-1, -1), Vector2(2, 3), 1.0)
	var street := Sprite2D.new()
	street.name = "Street"
	street.texture = load(ART + "street.png")
	street.centered = false
	street.position = Vector2(0, float(_art.get("strip_y", 284)))
	street.material = _layer_mat(lut)
	add_child(street)
	_build_landmarks(lut)
	_paths = Node2D.new()
	_paths.name = "Paths"
	_paths.material = _layer_mat(lut)
	_paths.draw.connect(_draw_structures)
	add_child(_paths)
	var dots := Node2D.new()
	dots.name = "Dots"
	dots.draw.connect(_draw_dots.bind(dots))
	add_child(dots)
	_paths.set_meta("dots", dots)
	_build_markers()
	_build_cat()
	_build_rain()
	_band("Foreground", ART + "foreground.png", FG_SCROLL, 0.0, false, lut, Vector2(-1, -1), Vector2(2, 3), 1.0)
	_label = Node2D.new()
	_label.name = "Label"
	_label.z_index = 50
	_label.draw.connect(_draw_label)
	add_child(_label)


func _lut(keys: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(keys.map(func(k): return k[0]))
	g.colors = PackedColorArray(keys.map(func(k): return k[1]))
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


func _layer_mat(lut: Texture2D, show := Vector2(-1, -1), hide := Vector2(2, 3), brightness := 1.0, grey := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LAYER_SHADER
	m.set_shader_parameter("tint_lut", lut)
	m.set_shader_parameter("show", show)
	m.set_shader_parameter("hide", hide)
	m.set_shader_parameter("brightness", brightness)
	m.set_shader_parameter("grey", grey)
	_layer_mats.append(m)
	return m


func _glow_mat(dim := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("dim", dim)
	_glow_mats.append(m)
	return m


func _build_sky() -> void:
	_sky_holder = Node2D.new()
	_sky_holder.name = "Sky"
	add_child(_sky_holder)
	_sky = ColorRect.new()
	_sky.size = VIEW
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	_sky_mat.set_shader_parameter("night_sky", load("res://assets/art_hd/bg/sky.png"))
	_sky_mat.set_shader_parameter("day_sky", load("res://assets/art_hd/home/sky.png"))
	_sky_mat.set_shader_parameter("night_horizon", FAR_BOTTOM - 6.0)
	_sky_mat.set_shader_parameter("night_brightness", 0.85)
	_sky.material = _sky_mat
	_sky_holder.add_child(_sky)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# The moon: NightBackdrop's disc and halo; it sets as the view moves on.
	_moon = Node2D.new()
	_moon.name = "Moon"
	_sky_holder.add_child(_moon)
	var mh := Sprite2D.new()
	mh.texture = HALO
	mh.scale = Vector2(0.9, 0.9)
	mh.modulate = Color(0.35, 0.42, 0.62)
	mh.material = add
	_moon.add_child(mh)
	var md := Sprite2D.new()
	md.texture = MOON
	md.modulate = Color(1.25, 1.3, 1.45)
	_moon.add_child(md)
	# The sun: DayBackdrop's disc and halos; it rises over the suburbs.
	_sun = Node2D.new()
	_sun.name = "Sun"
	_sky_holder.add_child(_sun)
	var wide := Sprite2D.new()
	wide.texture = CAT_SHADOW
	wide.scale = Vector2(5.5, 5.5)
	wide.modulate = Color(Color(0.75, 0.55, 0.28) * 0.55, 1.0)
	wide.material = add
	_sun.add_child(wide)
	var sh := Sprite2D.new()
	sh.texture = HALO
	sh.scale = Vector2(1.6, 1.6)
	sh.modulate = Color(0.75, 0.55, 0.28)
	sh.material = add
	_sun.add_child(sh)
	var sd := Sprite2D.new()
	sd.texture = load("res://assets/art_hd/home/sun.png")
	sd.modulate = Color(1.75, 1.62, 1.32)
	_sun.add_child(sd)


## Clouds (Home's cloud art) in the sky layer: a heavy deck over the night end
## that breaks up towards dawn, and a few fair-weather ones that stay.
func _build_clouds(lut: Texture2D) -> void:
	var holder := Node2D.new()
	holder.name = "Clouds"
	add_child(holder)
	var mat := _layer_mat(lut)
	var defs := [
		# texture, layer x, y, gone by p (camera)
		["cloud_c", 30.0, 36.0, 0.62], ["cloud_a", 250.0, 18.0, 0.58], ["cloud_b", 470.0, 54.0, 0.66],
		["cloud_c", 600.0, 24.0, 0.55], ["cloud_a", 820.0, 46.0, 0.6], ["cloud_d", 160.0, 80.0, 0.7],
		["cloud_b", 380.0, 92.0, 0.64], ["cloud_d", 700.0, 100.0, 0.68], ["cloud_c", 960.0, 70.0, 0.6],
		["cloud_b", 120.0, 60.0, 2.0], ["cloud_d", 560.0, 120.0, 2.0], ["cloud_a", 900.0, 30.0, 2.0],
	]
	for d in defs:
		var s := Sprite2D.new()
		s.texture = load("res://assets/art_hd/home/%s.png" % d[0])
		s.centered = false
		s.material = mat
		holder.add_child(s)
		_clouds.append([s, d[1], d[2], d[3]])


## A horizontal band of art in its own holder, moved at `scroll` of the camera.
## Tiled bands repeat sideways to fill the view; the others are placed once.
func _band(nm: String, tex_path: String, scroll: float, bottom: float, tiled: bool, lut: Texture2D,
		show: Vector2, hide: Vector2, brightness: float) -> void:
	var holder := Node2D.new()
	holder.name = nm
	var s := Sprite2D.new()
	s.texture = load(tex_path)
	s.centered = false
	s.material = _layer_mat(lut, show, hide, brightness)
	if tiled:
		s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		s.region_enabled = true
		s.position.y = bottom - s.texture.get_height()
	elif nm == "Foreground":
		s.position = Vector2(0, 0)
	else:
		s.position = Vector2(MID_X0, bottom - s.texture.get_height())
	holder.add_child(s)
	add_child(holder)
	_bands.append([holder, s, scroll, tiled])


func _build_landmarks(lut: Texture2D) -> void:
	var holder := Node2D.new()
	holder.name = "Landmarks"
	add_child(holder)
	var lm: Dictionary = _art.get("landmarks", {})
	# Draw the tall ones first so the street-level ones sit in front.
	var order := LevelRegistry.level_ids()
	order.sort_custom(func(a, b): return LevelRegistry.position_of(a).y < LevelRegistry.position_of(b).y)
	for id in order:
		var name := String(LevelRegistry.get_level(id).get("landmark", ""))
		if name == "" or not lm.has(name):
			continue
		var info: Dictionary = lm[name]
		var locked := LevelRegistry.is_bonus(id) and not LevelRegistry.is_open(id)
		var s := Sprite2D.new()
		s.name = name.capitalize().replace(" ", "")
		s.texture = load(ART + name + ".png")
		s.centered = false
		s.position = Vector2(info["origin"][0], info["origin"][1])
		var lm_mat := _layer_mat(lut, Vector2(-1, -1), Vector2(2, 3), 1.0, 0.55 if locked else 0.0)
		lm_mat.set_shader_parameter("rim_lut", _rim_lut)
		lm_mat.set_shader_parameter("rim", 1.0)
		s.material = lm_mat
		holder.add_child(s)
		var g: Sprite2D = null
		if bool(info.get("glow", false)):
			g = Sprite2D.new()
			g.name = s.name + "Glow"
			g.texture = load(ART + name + "_glow.png")
			g.centered = false
			g.position = s.position
			g.material = _glow_mat(1.0 if locked else 0.0)
			holder.add_child(g)
		landmarks[id] = [s, g]
	# The perimeter's searchlight sweeps the fence line.
	if landmarks.has("perimeter"):
		_cone = Sprite2D.new()
		_cone.name = "Searchlight"
		_cone.texture = CONE
		_cone.offset = Vector2(0, CONE.get_height() * 0.5)
		var lm_s: Sprite2D = landmarks["perimeter"][0]
		_cone.position = lm_s.position + Vector2(288, 29)
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_cone.material = m
		_cone.scale = Vector2(0.55, 0.62)
		holder.add_child(_cone)


func _build_markers() -> void:
	var holder := Node2D.new()
	holder.name = "Markers"
	add_child(holder)
	for id in LevelRegistry.level_ids():
		var m := MapMarker.new()
		m.name = id.capitalize().replace(" ", "")
		m.id = id
		m.bonus = LevelRegistry.is_bonus(id) or LevelRegistry.is_secret(id)
		m.position = LevelRegistry.position_of(id)
		holder.add_child(m)
		markers[id] = m


func _build_cat() -> void:
	cat = Node2D.new()
	cat.name = "Cat"
	cat.z_index = 5
	add_child(cat)
	var sh := Sprite2D.new()
	sh.name = "Shadow"
	sh.texture = CAT_SHADOW
	sh.scale = Vector2(0.2, 0.05)  # under the paws of the 31 px cat
	sh.modulate = Color(0, 0, 0, 0.55)
	cat.add_child(sh)
	cat_sprite = AnimatedSprite2D.new()
	cat_sprite.name = "Sprite"
	cat_sprite.sprite_frames = CatFrames.build()
	cat_sprite.position = Vector2(0, CatFrames.SPRITE_Y)
	cat_sprite.play("idle")
	cat.add_child(cat_sprite)
	if GameState.intelligence:
		CatAugments.attach(cat, true)


func _build_rain() -> void:
	_rain_holder = Node2D.new()
	_rain_holder.name = "Weather"
	add_child(_rain_holder)
	_rain = RainFX.new()
	_rain.name = "Rain"
	_rain.width = VIEW.x + 160.0
	_rain.floor_y = 330.0
	_rain.density = 46.0
	_rain.rain_color = Color(0.46, 0.54, 0.72, 0.8)
	_rain.lighting = RainFX.Lighting.UNSHADED
	_rain.splash_rate_scale = 0.35
	_rain_holder.add_child(_rain)


# ---- markers and the label ---------------------------------------------------------------

func _refresh_markers(pre_reveal: Array = []) -> void:
	for id in markers:
		var m: MapMarker = markers[id]
		m.letters_here = LevelRegistry.letters_in(id)
		m.letters_found = LevelRegistry.letters_found(id)
		m.gems_total = LevelRegistry.gems_total(id)
		m.gems_found = LevelRegistry.gems_found(id)
		m.set_state(_marker_state(id, pre_reveal))


func _marker_state(id: String, pre_reveal: Array = []) -> MapMarker.State:
	if not LevelRegistry.is_visible(id):
		return MapMarker.State.HIDDEN
	if pre_reveal.has(id):
		return MapMarker.State.HIDDEN if LevelRegistry.is_secret(id) else MapMarker.State.LOCKED
	if LevelRegistry.is_completed(id) and LevelRegistry.is_open(id):
		return MapMarker.State.DONE
	if LevelRegistry.is_open(id):
		return MapMarker.State.OPEN
	return MapMarker.State.LOCKED


func _show_label(id: String) -> void:
	_label_id = id if id != "" and not LevelRegistry.is_junction(id) else ""
	if _label_id != "":
		_label.position = (LevelRegistry.position_of(_label_id) + Vector2(0, -52)).round()
	_label.queue_redraw()


## The name plate over the cat: "^ The Yard" (the arrow only where Up or Jump
## goes in), and under it the collectibles found there or BONUS / LOCKED.
func _draw_label() -> void:
	if _label_id == "" or _label_a <= 0.01:
		return
	var id := _label_id
	var title := LevelRegistry.level_name(id)
	var enter := LevelRegistry.is_enterable(id) and not auto and not leaving
	var sub := ""
	if not LevelRegistry.is_open(id):
		sub = "LOCKED"
	elif LevelRegistry.is_bonus(id):
		sub = "BONUS"
	elif LevelRegistry.is_secret(id):
		sub = "SECRET"
	var tw := FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var arrow_w := 11.0 if enter else 0.0
	var w := tw + arrow_w
	var row := _pip_row(id)
	var row_w := _row_width(row)
	var sw := FONT.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x if sub != "" else 0.0
	var box_w := maxf(w, maxf(row_w, sw)) + 12.0
	var lines := 1 + (1 if row.size() > 0 or sub != "" else 0)
	var box_h := 13.0 * lines + 5.0
	# Keep the plate on screen.
	var left := cam_x - VIEW.x * 0.5
	var gx := _label.position.x
	var shift := clampf(gx, left + box_w * 0.5 + 4.0, left + VIEW.x - box_w * 0.5 - 4.0) - gx
	var x0 := roundf(-box_w * 0.5 + shift)
	var y0 := -box_h
	var a := _label_a
	_label.draw_rect(Rect2(x0, y0, box_w, box_h), Color(0.02, 0.03, 0.07, 0.78 * a))
	_label.draw_rect(Rect2(x0 + 1, y0 - 1, box_w - 2, 1), Color(0.02, 0.03, 0.07, 0.78 * a))
	_label.draw_rect(Rect2(x0 + 1, y0 + box_h, box_w - 2, 1), Color(0.02, 0.03, 0.07, 0.78 * a))
	var tx := roundf(x0 + (box_w - w) * 0.5)
	if enter:
		var bob := roundf(sin(_t * 5.0) * 1.0)
		_label.draw_texture(_arrow_tex, Vector2(tx, y0 + 2 + bob), Color(1, 1, 1, a))
		tx += arrow_w
	_label.draw_string(FONT, Vector2(tx, y0 + 12), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.95, 0.84, a))
	if lines > 1:
		var y := y0 + 25
		if sub != "":
			var sc := Color(0.62, 0.66, 0.8, a) if sub == "LOCKED" else Color(1.0, 0.82, 0.25, a)
			_label.draw_string(FONT, Vector2(roundf(x0 + (box_w - sw) * 0.5), y), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, sc)
		else:
			_draw_row(row, Vector2(roundf(x0 + (box_w - row_w) * 0.5), y), a)


## [[text or texture, colour], ...] for a finished level's collectibles.
func _pip_row(id: String) -> Array:
	if not LevelRegistry.is_completed(id):
		return []
	var out: Array = []
	var found := LevelRegistry.letters_found(id)
	for l in LevelRegistry.letters_in(id):
		out.append([String(l), MapMarker.GOLD if found.has(l) else MapMarker.DIM])
	var total := LevelRegistry.gems_total(id)
	if total > 0:
		var n := LevelRegistry.gems_found(id)
		out.append([_gem_tex, Color.WHITE if n > 0 else MapMarker.DIM])
		out.append(["%d/%d" % [n, total], MapMarker.GOLD if n >= total else MapMarker.CREAM])
	return out


func _row_width(row: Array) -> float:
	var w := 0.0
	for p in row:
		w += ((p[0] as Texture2D).get_width() + 1.0 if p[0] is Texture2D else FONT.get_string_size(p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x) + 4.0
	return maxf(w - 4.0, 0.0)


func _draw_row(row: Array, at: Vector2, a: float) -> void:
	var x := at.x
	for p in row:
		var col: Color = p[1]
		col.a *= a
		if p[0] is Texture2D:
			_label.draw_texture(p[0], Vector2(x, at.y - 7), col)
			x += (p[0] as Texture2D).get_width() + 5.0
		else:
			_label.draw_string(FONT, Vector2(x, at.y), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
			x += FONT.get_string_size(p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 4.0


# ---- drawing the paths ---------------------------------------------------------------------

## Stairs, ladders and walkways wherever a path leaves the street: drawn for
## every path that exists (they are part of the city), lit like the albedo.
func _draw_structures() -> void:
	var dark := Color("2a4658")
	var mid := Color("5b7280")
	var lite := Color("8aa7ab")
	for i in LevelRegistry.paths().size():
		if not LevelRegistry.is_path_visible(i):
			continue
		var pts := LevelRegistry.path_points(i)
		for k in range(pts.size() - 1):
			var a := pts[k].round()
			var b := pts[k + 1].round()
			if a.y >= 300.0 and b.y >= 300.0 and absf(a.y - b.y) < 1.0:
				continue  # on the street
			var d := b - a
			if absf(d.x) < 1.0:
				# A ladder: two rails and rungs.
				var y0 := minf(a.y, b.y)
				var y1 := maxf(a.y, b.y)
				_paths.draw_rect(Rect2(a.x - 4, y0, 1, y1 - y0 + 1), mid)
				_paths.draw_rect(Rect2(a.x + 4, y0, 1, y1 - y0 + 1), lite)
				var y := y0 + 2.0
				while y < y1:
					_paths.draw_rect(Rect2(a.x - 4, y, 9, 1), lite)
					y += 4.0
			elif absf(d.y) < 1.0:
				# A walkway: deck, rail, posts.
				var x0 := minf(a.x, b.x)
				var x1 := maxf(a.x, b.x)
				_paths.draw_rect(Rect2(x0 - 3, a.y, x1 - x0 + 7, 2), mid)
				_paths.draw_rect(Rect2(x0 - 3, a.y, x1 - x0 + 7, 1), lite)
				_paths.draw_rect(Rect2(x0 - 3, a.y + 2, x1 - x0 + 7, 1), dark)
				_paths.draw_rect(Rect2(x0 - 3, a.y - 9, x1 - x0 + 7, 1), mid)
				var x := x0 - 3.0
				while x <= x1 + 3.0:
					_paths.draw_rect(Rect2(x, a.y - 9, 1, 9), dark)
					x += 8.0
			else:
				# A flight of stairs: stringer, treads, a handrail.
				var lo := a if a.y > b.y else b
				var hi := b if a.y > b.y else a
				var n := int(absf(d.y) / 4.0)
				for s in range(n + 1):
					var t := float(s) / maxf(n, 1)
					var q := lo.lerp(hi, t).round()
					_paths.draw_rect(Rect2(q.x - 3, q.y, 7, 1), lite)
					_paths.draw_rect(Rect2(q.x - 3, q.y + 1, 7, 1), dark)
				_line_px(_paths, lo + Vector2(0, 2), hi + Vector2(0, 2), dark)
				_line_px(_paths, lo + Vector2(0, -9), hi + Vector2(0, -9), mid)
				_paths.draw_rect(Rect2(lo.x, lo.y - 9, 1, 9), dark)
				_paths.draw_rect(Rect2(hi.x, hi.y - 9, 1, 9), dark)


func _line_px(ci: CanvasItem, a: Vector2, b: Vector2, col: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for i in range(n + 1):
		var q := a.lerp(b, float(i) / maxf(n, 1)).round()
		ci.draw_rect(Rect2(q.x, q.y, 1, 1), col)


## The route itself: Secret Agent style dots every 7 px. Open paths in warm
## cream, locked ones faint, fresh ones only as far as the drawing head.
func _draw_dots(ci: Node2D) -> void:
	for i in LevelRegistry.paths().size():
		if not LevelRegistry.is_path_visible(i):
			continue
		var open := LevelRegistry.is_path_open(i)
		var pts := LevelRegistry.path_points(i)
		var total := _length(pts)
		var limit := total
		if _reveal.has(i):
			limit = float(_reveal[i][0])
			if not bool(_reveal[i][1]):
				pts.reverse()
		var col := Color(1.0, 0.93, 0.76) if open else Color(0.5, 0.52, 0.62, 0.55)
		var shadow := Color(0.02, 0.03, 0.08, 0.8 if open else 0.4)
		var d := 3.0
		while d <= limit:
			var q := _point_along(pts, d).round() + Vector2(0, -1)
			ci.draw_rect(Rect2(q.x, q.y + 1, 2, 2), shadow)
			ci.draw_rect(Rect2(q.x - 1, q.y, 2, 2), col)
			d += 7.0
		if limit < total - 0.5 and limit > 0.0:
			var h := _point_along(pts, limit).round()
			ci.draw_rect(Rect2(h.x - 2, h.y - 3, 4, 4), Color(1.8, 1.5, 0.8))
			ci.draw_rect(Rect2(h.x - 1, h.y - 4, 2, 6), Color(1.6, 1.4, 0.9))


static func _point_along(pts: PackedVector2Array, dist: float) -> Vector2:
	var walked := 0.0
	for k in range(pts.size() - 1):
		var l := pts[k].distance_to(pts[k + 1])
		if walked + l >= dist:
			return pts[k].lerp(pts[k + 1], clampf((dist - walked) / maxf(l, 0.001), 0.0, 1.0))
		walked += l
	return pts[pts.size() - 1]


static func _length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for k in range(pts.size() - 1):
		l += pts[k].distance_to(pts[k + 1])
	return l


# ---- the frame -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_update_camera(delta)
	_update_layers()
	_update_label(delta)
	_update_cat_anim(delta)
	_update_audio()
	if _cone:
		_cone.rotation = deg_to_rad(42.0 + sin(_t * 0.5) * 30.0)
		var k := 1.0 - smoothstep(0.84, 0.95, p_at(_cone.global_position.x))
		_cone.modulate = Color(0.30 * k, 0.34 * k, 0.40 * k)
		_cone.visible = k > 0.01
	if OS.has_feature("web"):
		_publish()


func _physics_process(delta: float) -> void:
	if leaving:
		return
	if auto:
		if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("move_right") \
				or Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_up"):
			_seq_speed = 4.0
		_step_walk(delta * _seq_speed)
		return
	if at_node != "":
		_hold_t += delta
		_node_input()
	else:
		_walk_input()
		_step_walk(delta)


## Standing on a node: Up or Jump goes in; a direction walks the best path.
func _node_input() -> void:
	var enter := Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("move_up")
	if enter and not LevelRegistry.is_junction(at_node):
		enter_level(at_node)
		return
	var dir := _input_dir()
	if dir == Vector2.ZERO:
		return
	# Up never walks off a level: it goes in (handled above).
	if dir.y < -0.5 and not LevelRegistry.is_junction(at_node):
		return
	if _hold_t < 0.16 and not _any_just_pressed():
		return
	var next := _best_link(at_node, dir, "")
	if next == "":
		var locked := _best_link(at_node, dir, "", true)
		if locked != "" and markers.has(locked):
			(markers[locked] as MapMarker).nope()
		return
	_start_walk(at_node, next)


func _any_just_pressed() -> bool:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		if Input.is_action_just_pressed(a):
			return true
	return false


## Walking: a press against the way the cat is going turns it round.
func _walk_input() -> void:
	var dir := _input_dir()
	if dir == Vector2.ZERO or _seg.size() < 2:
		return
	var heading := _heading()
	if heading.dot(dir) < -0.5 and _any_just_pressed():
		var pts := _seg.duplicate()
		pts.reverse()
		_seg = pts
		_dist = _seg_len - _dist
		var f := _from
		_from = _to
		_to = f
		_route.clear()


func _input_dir() -> Vector2:
	var v := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_up", "move_down"))
	if v.length() < 0.5:
		return Vector2.ZERO
	# One axis at a time, the stronger wins (a pad's diagonal never splits).
	return Vector2(signf(v.x), 0) if absf(v.x) >= absf(v.y) else Vector2(0, signf(v.y))


## The neighbour of `id` whose path sets off closest to `dir` (dot > 0.4),
## not counting `except`. With `locked`, among the paths that are NOT open.
func _best_link(id: String, dir: Vector2, except: String, locked := false) -> String:
	var best := ""
	var best_dot := 0.4
	for l in LevelRegistry.links(id):
		var other := String(l[0])
		if other == except:
			continue
		var open := LevelRegistry.is_path_open(int(l[1]))
		if open == locked:
			continue
		if locked and not LevelRegistry.is_visible(other):
			continue
		var seg := LevelRegistry.segment(id, other)
		var d := (seg[1] - seg[0]).normalized()
		var dot := d.dot(dir)
		if dot > best_dot:
			best_dot = dot
			best = other
	return best


func _start_walk(from: String, to: String) -> void:
	_seg = LevelRegistry.segment(from, to)
	_seg_len = _length(_seg)
	_dist = 0.0
	_from = from
	_to = to
	at_node = ""
	_label_id = ""
	_idle_t = 0.0


func _heading() -> Vector2:
	var a := _point_along(_seg, _dist)
	var b := _point_along(_seg, minf(_dist + 2.0, _seg_len))
	if a.distance_to(b) < 0.01:
		a = _point_along(_seg, maxf(_dist - 2.0, 0.0))
		b = _point_along(_seg, _dist)
	return (b - a).normalized()


func _step_walk(delta: float) -> void:
	if at_node != "" or _seg.size() < 2:
		return
	var h := _heading()
	var speed := lerpf(SPEED, CLIMB_SPEED, clampf(absf(h.y) * 1.4, 0.0, 1.0))
	_dist += speed * delta
	if _dist >= _seg_len:
		cat.position = _seg[_seg.size() - 1]
		_arrive(_to)
		return
	cat.position = _point_along(_seg, _dist).round()
	if absf(h.x) > 0.2:
		cat_sprite.flip_h = h.x < 0.0
	var anim := "run"
	if absf(h.y) > 0.9:
		anim = "jump" if h.y < 0.0 else "fall"
	elif absf(h.y) > 0.35:
		anim = "walk"
	if cat_sprite.animation != anim:
		cat_sprite.play(anim)
	cat_sprite.speed_scale = speed / 178.0 if anim == "run" else 1.0


func _arrive(id: String) -> void:
	var came := _from
	# Auto walks follow their route.
	if not _route.is_empty():
		var nxt := String(_route.pop_front())
		_start_walk(id, nxt)
		return
	# A junction with one way on is walked straight through; at a real fork a
	# held direction picks the way, else the cat waits there.
	if LevelRegistry.is_junction(id):
		var ways: Array = []
		for l in LevelRegistry.links(id):
			if String(l[0]) != came and LevelRegistry.is_path_open(int(l[1])):
				ways.append(String(l[0]))
		if ways.size() == 1:
			_start_walk(id, ways[0])
			return
		var dir := _input_dir()
		if dir != Vector2.ZERO:
			var pick := _best_link(id, dir, came)
			if pick != "":
				_start_walk(id, pick)
				return
	at_node = id
	_seg = PackedVector2Array()
	_hold_t = 0.0
	cat_sprite.play("idle")
	cat_sprite.speed_scale = 1.0
	if not LevelRegistry.is_junction(id):
		GameState.map_node = id
		SaveSystem.save_checkpoint("", SCENE)
		_show_label(id)
	arrived.emit(id)


func _update_cat_anim(delta: float) -> void:
	if at_node == "" or leaving:
		return
	_idle_t += delta
	if _idle_t > 2.2 and cat_sprite.animation == "idle":
		cat_sprite.play("sit")


func _clamp_cam(x: float) -> float:
	return clampf(x, VIEW.x * 0.5, _map_w - VIEW.x * 0.5)


func _update_camera(delta: float, snap := false) -> void:
	var want := cat.position.x
	if _cam_focus != Vector2.INF:
		want = _cam_focus.x
	elif _cam_hold_x != INF:
		# Hold on a spot, but keep the cat in the frame.
		want = clampf(_cam_hold_x, cat.position.x - VIEW.x * 0.5 + 70.0, cat.position.x + VIEW.x * 0.5 - 70.0)
	elif at_node == "" and _seg.size() > 1:
		want += _heading().x * 48.0
	want = _clamp_cam(want)
	if snap:
		cam_x = want
	else:
		var k := 1.0 - exp(-delta * (6.0 if _cam_focus != Vector2.INF else 3.2))
		cam_x = lerpf(cam_x, want, k)
	camera.position = Vector2(roundf(cam_x), VIEW.y * 0.5)
	camera.force_update_scroll()


func _update_layers() -> void:
	var cx := roundf(cam_x)
	var left := cx - VIEW.x * 0.5
	var pl := p_at(left)
	var pr := p_at(left + VIEW.x)
	var pc := p_at(cx)
	for m in _layer_mats:
		m.set_shader_parameter("p_left", pl)
		m.set_shader_parameter("p_right", pr)
	for m in _glow_mats:
		m.set_shader_parameter("p_left", pl)
		m.set_shader_parameter("p_right", pr)
	_sky_holder.position = Vector2(left, 0)
	_sky_mat.set_shader_parameter("p_left", pl)
	_sky_mat.set_shader_parameter("p_right", pr)
	_sky_mat.set_shader_parameter("scroll", roundf(cx * 0.03))
	# Moon sets and sun rises with the view (a time-lapse as the map pans).
	var ms := smoothstep(0.1, 0.72, pc)
	_moon.position = Vector2(lerpf(150.0, 70.0, ms), lerpf(58.0, 236.0, ms)).round()
	_moon.modulate.a = 1.0 - smoothstep(0.5, 0.72, pc)
	_moon.visible = _moon.modulate.a > 0.01
	var ss := smoothstep(0.74, 1.0, pc)
	_sun.position = Vector2(lerpf(560.0, 548.0, ss), lerpf(262.0, 78.0, ss)).round()
	_sun.modulate.a = smoothstep(0.7, 0.8, pc)
	_sun.visible = _sun.modulate.a > 0.01
	for b in _bands:
		var holder: Node2D = b[0]
		var spr: Sprite2D = b[1]
		var sc: float = b[2]
		holder.position.x = roundf(cx * (1.0 - sc))
		if b[3]:
			var tw := float(spr.texture.get_width())
			spr.region_rect = Rect2(0, 0, VIEW.x + tw * 2.0, spr.texture.get_height())
			spr.position.x = floorf((cx * sc - VIEW.x * 0.5) / tw) * tw
	for c in _clouds:
		var spr: Sprite2D = c[0]
		var x: float = c[1] - cx * CLOUD_SCROLL - _t * 2.0
		x = fposmod(x + 240.0, 1160.0) - 240.0
		spr.position = Vector2(roundf(left + x), c[2])
		var keep: float = c[3]
		spr.modulate.a = 1.0 - smoothstep(keep - 0.12, keep, pc)
		spr.visible = spr.modulate.a > 0.01
	_rain_holder.position = Vector2(cx, -24.0)
	# Rain eases off by fading (RainFX.set_intensity rebuilds the particles,
	# too heavy for a per-frame pan).
	var rk := 1.0 - smoothstep(0.42, 0.76, pc)
	_rain.modulate.a = rk
	_rain.visible = rk > 0.01
	_paths.queue_redraw()
	(_paths.get_meta("dots") as Node2D).queue_redraw()


func _update_label(delta: float) -> void:
	var want := 1.0 if _label_id != "" and at_node == _label_id and not leaving else 0.0
	_label_a = move_toward(_label_a, want, delta * 5.0)
	_label.queue_redraw()


# ---- the arrival sequence -------------------------------------------------------------------

func _wait(t: float) -> void:
	var e := 0.0
	while e < t:
		await get_tree().process_frame
		e += get_process_delta_time() * _seq_speed


func _play_reveal(done: String, fresh: Array, newly_done: bool) -> void:
	auto = true
	_seq_speed = 1.0
	at_node = done
	_label_id = ""
	# Everything that just opened starts undrawn.
	var order := fresh.duplicate()
	# Extras first, the next story level last (the cat walks to that one).
	order.sort_custom(func(a, b):
		var ka := Vector2(int(LevelRegistry.is_main(a)), LevelRegistry.order_of(a))
		var kb := Vector2(int(LevelRegistry.is_main(b)), LevelRegistry.order_of(b))
		return ka < kb)
	var routes := {}
	for id in order:
		var r := LevelRegistry.route(done, id)
		routes[id] = r
		for k in range(r.size() - 1):
			for l in LevelRegistry.links(String(r[k])):
				if String(l[0]) == String(r[k + 1]) and not _reveal.has(int(l[1])):
					_reveal[int(l[1])] = [0.0, bool(l[2])]
	await _wait(0.7)
	if newly_done and markers.has(done):
		(markers[done] as MapMarker).stamp()
		Sfx.play(self, "map_node_unlock")
		await _wait(0.65)
	var main := ""
	for id in order:
		var r: Array = routes[id]
		if r.size() >= 2:
			await _draw_route(r)
		if markers.has(id):
			(markers[id] as MapMarker).light_up()
		Sfx.play(self, "map_step")
		# Optional thought as a place first lights up (levels.json "map_line",
		# an id in data/monologue.json).
		var line := String(LevelRegistry.get_level(id).get("map_line", ""))
		if line != "" and Monologue.has_set(line):
			Monologue.play_once(line)
		_show_label(id)
		_label_a = 0.0
		await _wait(0.55)
		if LevelRegistry.is_main(id) and r.size() >= 2:
			main = id
	_cam_focus = Vector2.INF
	if main != "":
		_cam_hold_x = LevelRegistry.position_of(main).x
		var r: Array = routes[main]
		_route = r.slice(2)
		_start_walk(done, String(r[1]))
		while at_node != main:
			await get_tree().process_frame
		_cam_hold_x = INF
	_reveal.clear()
	auto = false
	_seq_speed = 1.0
	_show_label(at_node)
	reveal_finished.emit()


## Draws the route's paths in, one after the other, with the camera on the head.
func _draw_route(r: Array) -> void:
	var legs: Array = []      # [path index, polyline from this route's side]
	for k in range(r.size() - 1):
		for l in LevelRegistry.links(String(r[k])):
			if String(l[0]) == String(r[k + 1]):
				legs.append([int(l[1]), LevelRegistry.segment(String(r[k]), String(r[k + 1]))])
	var total := 0.0
	for leg in legs:
		total += _length(leg[1])
	var dur := clampf(total / DRAW_SPEED, 0.9, 2.6)
	var e := 0.0
	while e < dur:
		await get_tree().process_frame
		e += get_process_delta_time() * _seq_speed
		var s := smoothstep(0.0, 1.0, clampf(e / dur, 0.0, 1.0)) * total
		var acc := 0.0
		for leg in legs:
			var ll := _length(leg[1])
			var drawn := clampf(s - acc, 0.0, ll)
			if _reveal.has(leg[0]):
				_reveal[leg[0]][0] = drawn
			if s >= acc and s <= acc + ll:
				_cam_focus = _point_along(leg[1], drawn)
			acc += ll
	for leg in legs:
		_reveal.erase(leg[0])


# ---- going in ---------------------------------------------------------------------------------

## Go into level `id` (the cat must be able to: open, with a scene). Plays the
## way in (a hop, the plate flares, the view eases in on the door, fade) and
## loads the scene; with load_levels off it only emits level_chosen. Returns
## false (and the plate shakes its padlock) when the level is not enterable.
func enter_level(id: String) -> bool:
	if leaving or auto:
		return false
	if not LevelRegistry.is_enterable(id):
		if markers.has(id):
			(markers[id] as MapMarker).nope()
		return false
	var scene := LevelRegistry.scene_of(id)
	leaving = true
	chosen = id
	GameState.map_node = id
	level_chosen.emit(id, scene)
	if markers.has(id):
		(markers[id] as MapMarker).flare()
	Sfx.play(self, "door_open", -6.0)
	cat_sprite.play("jump")
	var tw := create_tween()
	tw.tween_property(cat_sprite, "position:y", CatFrames.SPRITE_Y - 6.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(cat_sprite, "position:y", CatFrames.SPRITE_Y, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(cat_sprite.play.bind("sit"))
	if load_levels:
		_go_in(scene)
	return true


func _go_in(scene: String) -> void:
	var cz := CineZoom.new()
	cz.name = "EnterZoom"
	add_child(cz)
	cz.target = cat
	cz.target_offset = Vector2(0, -18)
	var zt := create_tween()
	zt.tween_property(cz, "zoom", 2.4, 1.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _wait_real(0.4)
	RoomTransition.go(self, scene, 0.75)


func _wait_real(t: float) -> void:
	await get_tree().create_timer(t).timeout


# ---- sound ----------------------------------------------------------------------------------------

func _start_audio() -> void:
	# The map's music and its soft bed come from the AudioDirector (by scene).
	_rain_snd = _loop(RAIN_LOOP, -60.0)
	_birds_snd = _loop(BIRDS_LOOP, -60.0)


func _loop(path: String, db: float) -> AudioStreamPlayer:
	return AudioDirector.loop_player(self, load(path) as AudioStream, db)


func _update_audio() -> void:
	var pc := p_at(cam_x)
	if _rain_snd:
		_rain_snd.volume_db = lerpf(-19.0, -60.0, smoothstep(0.4, 0.78, pc))
	if _birds_snd:
		_birds_snd.volume_db = lerpf(-60.0, -21.0, smoothstep(0.8, 0.98, pc))


# ---- web audit hooks ---------------------------------------------------------------------------------

func _setup_web() -> void:
	var win := JavaScriptBridge.get_interface("window")
	if win == null:
		return
	var cb := JavaScriptBridge.create_callback(func(a):
		# wakeMapGo(id): teleport the cat onto a node (audits).
		var id := str(a[0])
		if LevelRegistry.is_open(id):
			_seg = PackedVector2Array()
			_route.clear()
			at_node = id
			cat.position = LevelRegistry.position_of(id)
			_show_label(id))
	_js_callbacks.append(cb)
	win["wakeMapGo"] = cb


func _publish() -> void:
	var d := {
		"scene": "map", "node": at_node, "auto": auto, "leaving": leaving, "chosen": chosen,
		"cat": [cat.position.x, cat.position.y], "cam": cam_x, "p": p_at(cam_x),
		"label": _label_id, "labelA": _label_a, "anim": cat_sprite.animation,
		"completed": GameState.map_completed, "unlocked": GameState.map_unlocked,
		"open": LevelRegistry.open_levels(), "mapNode": GameState.map_node,
		"save": SaveSystem.has_save(), "fps": Engine.get_frames_per_second(),
	}
	d["loops"] = LoopSfx.census_cached(get_tree())
	d["audio"] = AudioDirector.web_state()
	JavaScriptBridge.eval("window.__map = %s;" % JSON.stringify(d))
