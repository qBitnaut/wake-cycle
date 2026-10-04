class_name RoomExit
extends Area2D
## An exit (a loading door): when the cat walks in, the room fades to black and
## `next_scene` loads. `enabled` lets a level keep the exit shut until a beat
## is done. Size it with the CollisionShape2D child it builds from `size`.

signal used

@export_file("*.tscn") var next_scene := ""
@export var size := Vector2(24, 96)
@export var enabled := true

var _fired := false


func _ready() -> void:
	collision_layer = 32
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	cs.position = Vector2(0, -size.y / 2.0)
	add_child(cs)
	body_entered.connect(_on_body)


func _on_body(body: Node) -> void:
	if _fired or not enabled or not body is Cat:
		return
	_fired = true
	used.emit()
	(body as Cat).set_can_move(false)
	RoomTransition.go(self, next_scene)
