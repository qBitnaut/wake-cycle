class_name KitLab
extends Level
## The actor kit test gallery: every kit actor in a row of small arenas, on the real
## tileset and lighting. Debug keys (not in the input map):
##   F1 toggle shockwave   F2..F5 Surge / Spring / Phase / Impact   F6 clear power
##   [ and ]  previous / next arena      R  reset this arena
## Reach it with scenes/lab/kit_lab.tscn, or ?start=kit on a debug web build.

const T := 32
const G := 10  ## floor row (y = 320)
const CEIL := 64
const ARENA_W := 576
const FONT := preload("res://assets/fonts/monogram.ttf")
const STEEL := 0
const BULKHEAD := 1
const MAROON := 3
const BEVEL := Vector2i(0, 2)
const FLAT := Vector2i(4, 3)
const RIVET := Vector2i(5, 3)

const ARENAS := [
	"KIT LAB", "SENTRY TURRET", "PATROL BOT", "HOVER DRONE", "HOPPER BOT", "CRAWLER",
	"CAMERA + ALARM", "HEAVY MECH", "BARRELS", "WALLS", "TIMED HAZARDS", "VENTS AND DEBRIS",
	"CONVEYORS", "PLATFORMS", "COLLECTIBLES",
]

var tiles: TileMapLayer
var arena_nodes: Array[Node2D] = []
var _rig: LightingRig


func _init() -> void:
	limits = Rect2i(0, 24, ARENAS.size() * ARENA_W, 360)


func _ready() -> void:
	_build_world()
	super()
	for i in ARENAS.size():
		_build_arena(i)
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)


func _build_world() -> void:
	var back := ColorRect.new()
	back.name = "Backdrop"
	back.color = Color("141c27")
	back.position = Vector2(-64, -64)
	back.size = Vector2(ARENAS.size() * ARENA_W + 128, 640)
	back.z_index = -20
	add_child(back)
	move_child(back, 0)
	tiles = TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = load("res://assets/tiles/wake_hd.tres")
	add_child(tiles)
	var cols := ARENAS.size() * ARENA_W / T
	for x in cols:
		_cell(x, G, STEEL, BEVEL)
		for r in range(1, 4):
			_cell(x, G + r, MAROON, FLAT if (x + r) % 2 == 0 else RIVET)
		_cell(x, 0, BULKHEAD, FLAT)
		_cell(x, 1, BULKHEAD, FLAT)
	for y in range(0, G):
		_cell(0, y, STEEL, FLAT)
		_cell(cols - 1, y, STEEL, FLAT)
	var solid: Array[TileMapLayer] = [tiles]
	_rig = LightingRig.new()
	_rig.name = "LightingRig"
	_rig.night_tint = Color(0.5, 0.54, 0.7)
	_rig.moon_energy = 0.7
	_rig.glow_intensity = 0.8
	_rig.vignette = 0.2
	_rig.solid_layers = solid
	add_child(_rig)
	# Arena name boards.
	for i in ARENAS.size():
		var s := LabLabel.new()
		s.text = "%d  %s" % [i, ARENAS[i]]
		s.position = Vector2(i * ARENA_W + 48, 108)
		add_child(s)


func _cell(x: int, y: int, mat: int, tile: Vector2i) -> void:
	tiles.set_cell(Vector2i(x, y), 0, Vector2i(tile.x, tile.y + mat * 10))


func arena_x(i: int) -> float:
	return float(i * ARENA_W)


# ---- helpers ---------------------------------------------------------------------

func _put(arena: Node2D, scene: String, lx: float, y: float, props := {}) -> Node:
	var n: Node = load("res://scenes/kit/%s.tscn" % scene).instantiate()
	for k in props:
		n.set(k, props[k])
	arena.add_child(n)
	n.position = Vector2(lx, y)
	return n


func _block(arena: Node2D, lx: int, ly: int, w: int, h: int) -> void:
	# Solid tile block recorded for cleanup on reset (tiles are shared, so these are persistent).
	for x in w:
		for y in h:
			_cell(int(arena_x(arena.get_meta("idx")) / T) + lx + x, ly + y, STEEL, FLAT)


func _build_arena(i: int) -> void:
	if i < arena_nodes.size() and arena_nodes[i] != null and is_instance_valid(arena_nodes[i]):
		arena_nodes[i].queue_free()
	var a := Node2D.new()
	a.name = "Arena%d" % i
	a.position = Vector2(arena_x(i), 0)
	a.set_meta("idx", i)
	add_child(a)
	while arena_nodes.size() <= i:
		arena_nodes.append(null)
	arena_nodes[i] = a
	var f := float(G * T)
	match i:
		0:
			_put(a, "barrel_plain", 300, f)
			_put(a, "pickup_yarn", 200, f - 8, {"persist": false})
			_put(a, "pickup_fish", 240, f - 8, {"persist": false})
		1:
			_put(a, "sentry_turret", 500, f, {"detect_range": 360.0})
			_block(a, 17, 4, 1, 6)
			_put(a, "sentry_turret", 544, 7 * T, {"mount": SentryTurret.Mount.WALL_RIGHT, "detect_range": 360.0, "cooldown": 3.0})
			_put(a, "sentry_turret", 300, float(CEIL), {"mount": SentryTurret.Mount.CEILING, "cooldown": 3.2})
			_put(a, "pickup_yarn", 120, f - 8, {"persist": false})
		2:
			_put(a, "kit_patrol_bot", 460, f)
			_put(a, "pickup_bell", 150, f - 8, {"persist": false})
		3:
			_put(a, "hover_drone", 330, 210.0, {"patrol_range": 120.0})
			_put(a, "pickup_yarn", 150, f - 8, {"persist": false})
		4:
			_put(a, "hopper_bot", 470, f)
			_put(a, "pickup_mouse", 120, f - 8, {"persist": false})
		5:
			_put(a, "crawler_bot", 300, float(CEIL))
			_put(a, "crawler_bot", 440, float(CEIL), {"crawl_range": 30.0})
		6:
			_put(a, "security_camera", 200, float(CEIL), {"sweep_min": 40.0, "sweep_max": 140.0, "view_range": 250.0})
			_put(a, "sentry_turret", 500, f, {"dormant": true, "detect_range": 400.0})
			_put(a, "kit_shutter", 400, f, {"height_tiles": 3})
			_block(a, 12, 2, 2, 4)
		7:
			_put(a, "heavy_mech", 470, f)
			_put(a, "pickup_bone", 100, f - 8, {"persist": false})
		8:
			for k in 3:
				_put(a, "barrel_explosive", 300 + k * 26, f)
			_put(a, "barrel_acid", 180, f)
			_put(a, "kit_patrol_bot", 420, f, {"speed": 20.0})
			_put(a, "pickup_yarn", 80, f - 8, {"persist": false})
		9:
			_put(a, "wall_cracked", 160, f, {"size_tiles": Vector2i(1, 2), "persist": false, "reward": 1})
			_put(a, "wall_reinforced", 280, f, {"size_tiles": Vector2i(1, 2), "persist": false, "reward": 2})
			_put(a, "wall_blast", 400, f, {"size_tiles": Vector2i(1, 2), "persist": false, "reward": 4})
			_put(a, "barrel_explosive", 440, f)
		10:
			_put(a, "electric_floor", 130, f, {"width_tiles": 3})
			_put(a, "spike_trap", 300, f, {"width_tiles": 2})
			_block(a, 14, 5, 2, 1)
			_put(a, "crusher", 480, 192.0, {"stroke": 104.0})
			_put(a, "pickup_mouse", 480, f - 8, {"persist": false})
		11:
			_put(a, "vent_steam", 100, f)
			_put(a, "vent_flame", 220, f)
			_put(a, "acid_pool", 350, f, {"width": 96.0})
			_put(a, "falling_debris", 490, float(CEIL))
		12:
			_put(a, "conveyor", 120, f, {"width_tiles": 4, "speed": 70.0})
			_put(a, "conveyor", 330, f, {"width_tiles": 4, "speed": -70.0})
			_put(a, "barrel_plain", 440, f)
		13:
			_put(a, "platform_horizontal", 140, 250.0, {"travel": 100.0})
			_put(a, "platform_vertical", 330, 170.0, {"travel": 110.0})
			_put(a, "platform_falling", 480, 250.0, {"width_tiles": 2})
			_put(a, "pickup_bell", 480, 226.0, {"persist": false})
		14:
			var kinds := ["pickup_fish", "pickup_yarn", "pickup_bell", "pickup_mouse", "pickup_bone", "pickup_chip", "pickup_memory"]
			for k in kinds.size():
				_put(a, kinds[k], 70 + k * 68, f - 6, {"persist": false})


func goto_arena(i: int) -> void:
	i = clampi(i, 0, ARENAS.size() - 1)
	cat.global_position = Vector2(arena_x(i) + 60.0, float(G * T))
	cat.velocity = Vector2.ZERO


func current_arena() -> int:
	return clampi(int(cat.global_position.x / ARENA_W), 0, ARENAS.size() - 1)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_F1:
			GameState.shockwave_unlocked = not GameState.shockwave_unlocked
		KEY_F2:
			GameState.grant_power(NanoPalette.Power.SURGE, 600.0)
		KEY_F3:
			GameState.grant_power(NanoPalette.Power.SPRING, 600.0)
		KEY_F4:
			GameState.grant_power(NanoPalette.Power.PHASE, 600.0)
		KEY_F5:
			GameState.grant_power(NanoPalette.Power.IMPACT, 600.0)
		KEY_F6:
			GameState.clear_power()
		KEY_BRACKETRIGHT:
			goto_arena(current_arena() + 1)
		KEY_BRACKETLEFT:
			goto_arena(current_arena() - 1)
		KEY_R:
			_build_arena(current_arena())


class LabLabel extends Node2D:
	var text := ""

	func _draw() -> void:
		var c := Color(0.75, 0.88, 0.9, 0.9)
		draw_string(preload("res://assets/fonts/monogram.ttf"), Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.06, 0.07, 0.12))
		draw_string(preload("res://assets/fonts/monogram.ttf"), Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)
