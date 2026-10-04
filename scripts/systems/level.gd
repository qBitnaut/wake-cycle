class_name Level
extends Node2D
## Base level script: starts the save session, places the cat at the active
## checkpoint, applies camera limits and the pit kill height.

@export var player_path: NodePath = ^"Cat"
@export var start_path: NodePath = ^"PlayerStart"
## Camera rectangle in px. Exactly one screen tall (640x360) keeps the camera
## pinned vertically; the level scrolls sideways only.
@export var limits := Rect2i(0, 24, 1280, 360)
## When > 0, the camera floor drops to this y while the cat is below the normal
## floor (a chamber, falling into a pit), then comes back up.
@export var deep_bottom := 0
@export var death_margin := 64

var cat: Cat
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
	cat.global_position = spawn
	cat.death_y = limits.end.y + death_margin
	cat.set_camera_limits(limits)
	_normal_bottom = limits.end.y
	cat.shockwave.connect(_on_cat_shockwave)
	if GameState.intelligence:
		# The mind is awake (a reload, a later room): the augments show without the reveal.
		CatAugments.attach(cat, true)
	if RoomTransition.arriving:
		# Came in through a RoomExit: fade up, and save at the start of this room.
		RoomTransition.arriving = false
		SaveSystem.save_checkpoint("", scene_file_path)
		RoomTransition.fade_in(self)


## The cat's double-jump burst and ground pound become the ShockwaveFX ring
## (refraction, flash, dust) plus a camera shake. Ground pounds hit harder.
func _on_cat_shockwave(pos: Vector2, radius: float, source: String) -> void:
	if source == "pound":
		ShockwaveFX.spawn(self, pos, radius, FXPalette.IMPACT, 0.55)
	else:
		ShockwaveFX.spawn(self, pos, radius, FXPalette.SHOCKWAVE, 0.25)


func _physics_process(_delta: float) -> void:
	if deep_bottom <= 0 or cat == null:
		return
	var want := deep_bottom if cat.global_position.y > _normal_bottom - 24 else _normal_bottom
	cat.camera.limit_bottom = int(move_toward(cat.camera.limit_bottom, want, 6.0))
