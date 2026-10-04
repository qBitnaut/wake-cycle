class_name Level
extends Node2D
## Base level script: starts the save session, places the cat at the active
## checkpoint, applies camera limits and the pit kill height.

@export var player_path: NodePath = ^"Cat"
@export var start_path: NodePath = ^"PlayerStart"
@export var limits := Rect2i(0, 0, 1280, 288)
@export var death_margin := 48

var cat: Cat
var _checkpoint_id := ""


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
