extends Node2D
## Goo lab (scenes/lab/goo_lab.tscn): a one-screen night room with a goo pit
## under a moon shaft and a normal water puddle on the way in, so the two
## liquids can be compared. The cat runs in on scripted input, the goo takes
## it (TransformSequence), the augmented cat cycles the four pad colours,
## jumps out and runs about, then everything resets and loops.
##
## Keys: R restart, C toggle the zoom mode (magnifier / Camera2D).
## URL (web): ?zoom=camera  ?show=pads  ?show=anims  ?zoom_level=3  ?noloop=1
## Web builds publish window.__goo = {phase, pt, loops} every frame
## (phase: walk, a..f, m (the awakened mind), g, pads, moves, anims) for
## Playwright captures.

const T := 32
const G := 10                 ## floor row (y = 320)
const COLS := 20
const PIT := [11, 13]         ## goo pit columns
const START_X := 72.0

const STEEL := 0
const BULKHEAD := 1
const MAROON := 3
const TEAL := 4
const BEVEL := Vector2i(0, 2)
const FRAMED := Vector2i(3, 2)
const CROSS := Vector2i(2, 2)
const FLAT := Vector2i(4, 3)
const RIVET := Vector2i(5, 3)
const VENTBOX := Vector2i(1, 2)
const GIRDER_H := Vector2i(13, 4)
const PIPE_V := [Vector2i(2, 0), Vector2i(2, 1)]

var cat: Cat
var pool: GooPool
var seq: TransformSequence
var aug: CatAugments
var phase := "walk"
var loops := 0

var _phase_t := 0.0
var _show := ""
var _noloop := false
var _tiles: TileMapLayer


var _zoom_mode := TransformSequence.ZoomMode.MAGNIFIER


func _ready() -> void:
	_read_url()
	_build_room()
	if _url("zoom") == "camera":
		_zoom_mode = TransformSequence.ZoomMode.CAMERA
	_run.call_deferred()


func _unhandled_input(e: InputEvent) -> void:
	if OS.is_debug_build() and e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_R and seq == null:
			get_tree().reload_current_scene()
		elif e.keycode == KEY_C:
			_zoom_mode = (1 - _zoom_mode) as TransformSequence.ZoomMode
			print("zoom mode: ", ["magnifier", "camera"][_zoom_mode])


func _process(delta: float) -> void:
	_phase_t += delta
	if OS.has_feature("web") and OS.is_debug_build():
		JavaScriptBridge.eval("window.__goo = {phase: '%s', pt: %.3f, loops: %d}" % [phase, _phase_t, loops])


func _set_phase(p: String) -> void:
	phase = p
	_phase_t = 0.0


# ---- the show -----------------------------------------------------------------

func _run() -> void:
	if _show == "pads":
		await _pads_only()
		return
	if _show == "anims":
		await _anims()
		return
	while true:
		await _walk_in()
		# The level's own way in: TransformSequence.play(cat). Built by hand
		# here only so the lab can pick the zoom mode before it starts.
		seq = TransformSequence.new()
		seq.cat = cat
		seq.pool = pool
		seq.zoom_mode = _zoom_mode
		add_child(seq)
		seq.phase_started.connect(_on_phase)
		seq.augments_revealed.connect(_set_phase.bind("m"))
		seq.mind_awakened.connect(_set_phase.bind("g"))
		_mark_later("b", TransformSequence.T_STUCK)
		seq.start()
		await seq.finished
		seq = null
		aug = CatAugments.attach(cat)
		await _wait(1.0)
		await _pad_cycle()
		await _moves()
		loops += 1
		if _noloop:
			_set_phase("done")
			return
		await _reset()


func _on_phase(p: StringName) -> void:
	match p:
		TransformSequence.GOO_RISES:
			_set_phase("a")
		TransformSequence.VEINS_REACH_EYES:
			_set_phase("c")
		TransformSequence.ABSORB:
			_set_phase("d")
		TransformSequence.LOOKS_NORMAL:
			_set_phase("e")
		TransformSequence.AUGMENTS_APPEAR:
			_set_phase("f")


func _mark_later(p: String, t: float) -> void:
	await _wait(t)
	_set_phase(p)


func _walk_in() -> void:
	_set_phase("walk")
	var target := (PIT[0] + PIT[1] + 1) * T * 0.5 - 6.0
	Input.action_press("move_right")
	while cat.global_position.x < target - 8.0:
		await get_tree().physics_frame
	Input.action_release("move_right")
	await _wait(0.35)


func _pad_cycle() -> void:
	_set_phase("pads")
	for c in [FXPalette.SURGE, FXPalette.SPRING, FXPalette.PHASE, FXPalette.IMPACT]:
		aug.set_power(c)
		await _wait(0.5)
		aug.flare()
		await _wait(0.9)
	aug.clear_power()
	await _wait(0.6)


func _moves() -> void:
	_set_phase("moves")
	Input.action_press("move_left")
	Input.action_press("jump")
	await _wait(0.25)
	Input.action_release("jump")
	await _wait(0.9)
	Input.action_press("jump")
	await _wait(0.2)
	Input.action_release("jump")
	await _wait(0.8)
	Input.action_release("move_left")
	await _wait(0.6)


func _reset() -> void:
	aug.set_shown(false)
	aug.clear_power()
	cat.global_position = Vector2(START_X, G * T)
	cat.velocity = Vector2.ZERO
	await _wait(0.6)


## ?show=pads: the augmented cat in the pit, cycling the four pad colours.
func _pads_only() -> void:
	await _walk_in()
	cat.set_physics_process(false)  # hold the side-on idle (no sitting down)
	cat.sprite.play("idle")
	_close_up()
	aug = CatAugments.attach(cat, true)
	while true:
		for i in 4:
			_set_phase("pad%d" % i)
			aug.set_power([FXPalette.SURGE, FXPalette.SPRING, FXPalette.PHASE, FXPalette.IMPACT][i])
			await _wait(1.4)
		_set_phase("pad_idle")
		aug.clear_power()
		await _wait(1.4)


## ?show=anims: the augmented cat held on chosen frames (walk, run, jump,
## fall, crouch, sit, stretch), flipped both ways, to prove the anchors.
func _anims() -> void:
	aug = CatAugments.attach(cat, true)
	cat.set_physics_process(false)
	cat.global_position = Vector2(232, G * T)
	_close_up()
	var shots := [["walk", 2], ["walk", 5], ["run", 1], ["run", 4], ["jump", 0], ["fall", 0],
		["crouch", 0], ["sit", 0], ["stretch", 6], ["meow", 1]]
	while true:
		for s in shots:
			for flip in [false, true]:
				cat.sprite.play(s[0])
				cat.sprite.pause()
				cat.sprite.frame = s[1]
				cat.sprite.flip_h = flip
				_set_phase("%s%d%s" % [s[0], s[1], "L" if flip else "R"])
				await _wait(0.8)


## Hold a CineZoom close-up on the cat (zoom 3, or ?zoom_level=).
func _close_up() -> void:
	var cz := CineZoom.new()
	add_child(cz)
	cz.target = cat
	cz.target_offset = Vector2(0, -16)
	var z := _url("zoom_level")
	cz.zoom = float(z) if z != "" else 3.0


func _wait(t: float) -> Signal:
	return get_tree().create_timer(t).timeout


# ---- room -----------------------------------------------------------------------

func _build_room() -> void:
	var w := COLS * T
	var sky := ColorRect.new()
	sky.color = Color("0c1030")
	sky.position = Vector2(-64, -100)
	sky.size = Vector2(w + 128, 600)
	add_child(sky)
	var exterior := NightBackdrop.new()
	exterior.position = Vector2(0, 250)
	exterior.moon_position = Vector2(60, -150)
	add_child(exterior)
	var window := Rect2(88, 92, 96, 104)
	var skylight := Rect2(9 * T, 0, 2 * T, 2 * T)
	var wall := BackWall.new()
	wall.size = Vector2(w, G * T)
	wall.floor_y = G * T
	var holes: Array[Rect2] = [window, skylight]
	var windows: Array[Rect2] = [window]
	wall.holes = holes
	wall.windows = windows
	add_child(wall)
	for d in [["servers", 456.0], ["terminal", 548.0]]:
		var s := Sprite2D.new()
		s.texture = load("res://assets/art_hd/props/%s.png" % d[0])
		s.centered = false
		s.position = Vector2(d[1], G * T - s.texture.get_height())
		s.self_modulate = Color(0.7, 0.7, 0.7)
		add_child(s)
	var shaft := MoonShaft.new()
	shaft.position = Vector2(skylight.position.x + skylight.size.x * 0.5, 40)
	shaft.angle = 16.0
	shaft.length = G * T - 40.0
	shaft.top_width = skylight.size.x - 4.0
	shaft.bottom_width = skylight.size.x * 1.7
	shaft.ray_intensity = 0.10  # as Room 1
	shaft.ray_start = 2.0 * T - 40.0  # under the two-row roof
	shaft.light_energy = 0.6  # the cat stands in it: keep the tabby warm
	shaft.floor_glow = 0.30
	shaft.dust_amount = 50
	shaft.dust_px = 1
	add_child(shaft)
	var under := ColorRect.new()
	under.color = Color("1d1230")
	under.position = Vector2(0, (G + 1) * T)
	under.size = Vector2(w, 3 * T)
	add_child(under)
	_tiles = TileMapLayer.new()
	_tiles.name = "Tiles"
	_tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	add_child(_tiles)
	_geometry()
	# The wading floor inside the pit: the cat stands 4 px under the surface.
	var wade := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2((PIT[1] - PIT[0] + 1) * T, 26)
	shape.shape = rs
	shape.position = Vector2((PIT[0] + PIT[1] + 1) * T * 0.5, G * T + 6 + 13)
	wade.add_child(shape)
	add_child(wade)
	pool = GooPool.new()
	pool.name = "GooPool"
	pool.position = Vector2(PIT[0] * T, G * T + 2)
	pool.width = (PIT[1] - PIT[0] + 1) * T
	pool.depth = 2 * T - 2  # covers the pit floor: it reads as deep
	pool.z_index = 6  # over the cat's feet: it wades in the goo
	add_child(pool)
	var puddle := Puddle.new()
	puddle.position = Vector2(150, G * T)
	puddle.size = Vector2(72, 6)
	puddle.z_index = 6
	add_child(puddle)
	var lamp := WarningLight.new()
	lamp.art_scale = 1
	lamp.mode = WarningLight.Mode.STEADY
	lamp.energy = 1.5
	lamp.light_radius_scale = 2.6
	lamp.halo_strength = 0.4
	lamp.shadows = false
	lamp.position = Vector2(612, G * T - 7)
	add_child(lamp)
	cat = load("res://scenes/player/cat.tscn").instantiate()
	cat.name = "Cat"
	add_child(cat)
	cat.global_position = Vector2(START_X, G * T)
	cat.set_camera_limits(Rect2i(0, 24, w, 360))
	var rig := LightingRig.new()
	rig.night_tint = Color(0.36, 0.40, 0.58)
	rig.moon_angle = 16.0
	rig.moon_energy = 0.85
	rig.glow_intensity = 0.8
	rig.vignette = 0.30
	var solid: Array[TileMapLayer] = [_tiles]
	rig.solid_layers = solid
	add_child(rig)
	add_child(load("res://scenes/ui/hud.tscn").instantiate())


func _cell(x: int, y: int, mat: int, tile: Vector2i) -> void:
	_tiles.set_cell(Vector2i(x, y), 0, Vector2i(tile.x, tile.y + mat * 10))


func _geometry() -> void:
	for x in range(-1, COLS + 1):
		var pit: bool = x >= PIT[0] and x <= PIT[1]
		if not pit:
			_cell(x, G, STEEL, BEVEL)
		_cell(x, G + 1, MAROON, FLAT if pit else GIRDER_H)
		_cell(x, G + 2, MAROON, FLAT if x % 2 == 0 else RIVET)
		_cell(x, G + 3, MAROON, RIVET if x % 2 == 0 else FLAT)
		if x < 9 or x > 10:
			_cell(x, 0, BULKHEAD, FLAT if x % 3 != 0 else RIVET)
			_cell(x, 1, BULKHEAD, VENTBOX if x % 2 == 0 else BEVEL)
	for y in range(2, G):
		_cell(-1, y, TEAL, PIPE_V[y % 2])
		_cell(COLS, y, BULKHEAD, FLAT)
	for c in [[16, 9, FRAMED], [17, 9, CROSS], [17, 8, FRAMED]]:
		_cell(c[0], c[1], MAROON, c[2])


# ---- url ---------------------------------------------------------------------------

func _read_url() -> void:
	_show = _url("show")
	_noloop = _url("noloop") == "1"


func _url(key: String) -> String:
	if not (OS.has_feature("web") and OS.is_debug_build()):
		return ""
	return str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('%s') || ''" % key))
