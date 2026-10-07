class_name Level
extends Node2D
## Base level script: starts the save session, places the cat at the active
## checkpoint, applies camera limits and the pit kill height.
##
## ---- Room size and camera (tall rooms) -----------------------------------------
## A room is any size. `limits` is the camera rectangle in world px; build it from the
## room's tile bounds, e.g. in a builder:
##     room.set("limits", Rect2i(0, 0, COLS * T, ROWS * T))      # or Level.tile_limits(layer)
## The camera never shows outside it, and `death_y` is its bottom plus `death_margin`.
## The viewport is 640x360, so a room 360 px tall pins the camera vertically (rooms 1,
## 2, 4, home and the test room); anything taller scrolls.
##
## camera_follow selects how the view follows the cat:
##   CENTRED (default)  the camera sits on the cat (view centre 25 px above its feet),
##                      limits clamp it. This is how every 360 px room and Room 3 play.
##                      `deep_bottom` (the floor dropping while the cat is below it) and a
##                      room's own limit_bottom easing (Room 1 pool, Room 4 hatch) work only here.
##   TIERS              for tall mazes: a vertical dead zone (`dead_zone_up` px above the
##                      view centre, `dead_zone_down` below) inside which the view stays
##                      still, so hops and plain jumps do not scroll; a bigger climb or fall
##                      does. Fast falls look ahead downward, and standing on a new tier the
##                      view eases back to the cat. Pixel-snapped. Horizontally the camera is
##                      on the cat. Do not use `deep_bottom` here: put the basement inside
##                      `limits`.
## Which rectangle: with CENTRED and no zones Godot clamps the camera before applying its
## offset, so the view sits 25 px above `limits` (hence the 24 in `Rect2i(0, 24, w, 360)`).
## With TIERS or any CameraZone, LevelCamera clamps for itself and `limits` (and a zone's
## rect) is the EXACT world rect the view stays inside: use Rect2i(0, 0, w, h).
## Optional CameraZone nodes (scripts/systems/camera_zone.gd) override the limits or lock
## the framing while the cat is inside (one-screen puzzle rooms, a tight shaft).
## The driver is `camera_rig` (LevelCamera); a CineZoom cutscene lifts the limits and the
## driver waits until it is over. Backdrops: NightBackdrop/DayBackdrop `extend_vertically`;
## rain: RainFX `follow_camera`. Details and the build checklist: docs/LEVELS.md.

enum CameraFollow { CENTRED, TIERS }

@export var player_path: NodePath = ^"Cat"
@export var start_path: NodePath = ^"PlayerStart"
## Camera rectangle in px (see above). 640x360 pins the camera vertically.
@export var limits := Rect2i(0, 24, 1280, 360)
@export var camera_follow := CameraFollow.CENTRED
## TIERS: how far the cat may rise above / sink below the view centre before it scrolls.
## 80 up keeps a plain jump (95 px) from scrolling; a double jump does scroll.
@export var dead_zone_up := 80.0
@export var dead_zone_down := 48.0
## Camera-zone limit transitions move this many px per physics frame.
@export var zone_ease_px := 12.0
## When > 0, the camera floor drops to this y while the cat is below the normal
## floor (a chamber, falling into a pit), then comes back up. CENTRED only.
@export var deep_bottom := 0
@export var death_margin := 64

var cat: Cat
var camera_rig: LevelCamera
var _checkpoint_id := ""
var _normal_bottom := 0


func _enter_tree() -> void:
	# Runs before any child's _ready, so pickups see the restored GameState.
	_checkpoint_id = SaveSystem.begin_level(scene_file_path)


func _ready() -> void:
	cat = get_node(player_path)
	var cp_id := _checkpoint_id
	var spawn: Vector2 = get_node(start_path).global_position
	if cp_id != "":
		for cp in get_tree().get_nodes_in_group("checkpoint"):
			if cp.checkpoint_id == cp_id:
				spawn = cp.spawn_position()
				cp_id = ""
		if cp_id != "":
			# A checkpoint id this room no longer has: the room start.
			SaveSystem.session_checkpoint = ""
	cat.global_position = spawn
	cat.death_y = limits.end.y + death_margin
	cat.set_camera_limits(limits)
	_normal_bottom = limits.end.y
	camera_rig = LevelCamera.new()
	add_child(camera_rig)
	camera_rig.setup(self, cat, camera_follow == CameraFollow.TIERS)
	cat.shockwave.connect(_on_cat_shockwave)
	if GameState.intelligence:
		# The mind is awake (a reload, a later room): the augments show without the reveal.
		CatAugments.attach(cat, true)
	if RoomTransition.arriving:
		# Came in through a RoomExit: fade up, and save at the start of this room.
		RoomTransition.arriving = false
		SaveSystem.save_checkpoint("", scene_file_path)
		RoomTransition.fade_in(self)
	elif RoomTransition.pending_title != "":
		# Came in through the Continue pad: fade up with the room's title card.
		RoomTransition.fade_in(self)


## The cat's double-jump burst and ground pound become the ShockwaveFX ring
## (refraction, flash, dust) plus a camera shake. Ground pounds hit harder.
func _on_cat_shockwave(pos: Vector2, radius: float, source: String) -> void:
	if source == "pound":
		ShockwaveFX.spawn(self, pos, radius, FXPalette.IMPACT, 0.55)
	else:
		ShockwaveFX.spawn(self, pos, radius, FXPalette.SHOCKWAVE, 0.25)


func _physics_process(_delta: float) -> void:
	if deep_bottom <= 0 or cat == null or camera_tiers():
		return
	var want := deep_bottom if cat.global_position.y > _normal_bottom - 24 else _normal_bottom
	cat.camera.limit_bottom = int(move_toward(cat.camera.limit_bottom, want, 6.0))


func camera_tiers() -> bool:
	return camera_follow == CameraFollow.TIERS


## Camera limits from a tile layer's used rect (plus `pad` tiles each side), in world px.
static func tile_limits(layer: TileMapLayer, pad := Vector2i.ZERO) -> Rect2i:
	var t := Vector2i(layer.tile_set.tile_size) if layer.tile_set else Vector2i(32, 32)
	var u := layer.get_used_rect().grow_individual(pad.x, pad.y, pad.x, pad.y)
	return Rect2i(u.position * t, u.size * t)
