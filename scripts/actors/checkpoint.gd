class_name Checkpoint
extends Area2D
## Step on it to save (user://save.json) and set the respawn point.

const FONT := preload("res://assets/fonts/m5x7.ttf")

@export var checkpoint_id := "cp1"

var _active := false
var _pulse := 0.0
var _t := 0.0


func _ready() -> void:
	add_to_group("checkpoint")
	collision_layer = 32
	collision_mask = 2
	body_entered.connect(_on_body)
	_active = SaveSystem.session_scene == get_tree().current_scene.scene_file_path \
		and SaveSystem.session_checkpoint == checkpoint_id


func spawn_position() -> Vector2:
	return global_position


func _on_body(body: Node) -> void:
	if not body is Cat or _active:
		return
	for cp in get_tree().get_nodes_in_group("checkpoint"):
		cp._active = false
	_active = true
	_pulse = 1.0
	SaveSystem.save_checkpoint(checkpoint_id, get_tree().current_scene.scene_file_path)
	Sfx.play(self, "checkpoint")


func _process(delta: float) -> void:
	_t += delta
	_pulse = maxf(_pulse - delta * 1.6, 0.0)
	queue_redraw()


func _draw() -> void:
	var lit := Color("7dffb0") if _active else Color("5a6a78")
	draw_rect(Rect2(-1, -30, 2, 30), Color("8fa0b0"))
	draw_rect(Rect2(-5, -2, 10, 2), Color("667788"))
	var glow := 0.6 + 0.4 * sin(_t * 4.0) if _active else 0.0
	draw_circle(Vector2(0, -32), 4.0, lit)
	if _active:
		draw_circle(Vector2(0, -32), 8.0, Color(lit, 0.15 + 0.15 * glow))
	if _pulse > 0.0:
		var r := 4.0 + 28.0 * (1.0 - _pulse)
		draw_arc(Vector2(0, -32), r, 0.0, TAU, 32, Color(lit, _pulse), 2.0)
		draw_string(FONT, Vector2(-22, -44), "SAVED", HORIZONTAL_ALIGNMENT_CENTER, 44.0, 16, Color(lit, _pulse))
