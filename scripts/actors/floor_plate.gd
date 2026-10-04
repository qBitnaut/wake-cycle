extends Area2D
## Big floor pressure plate (2 tiles wide). Held while the cat or a pushable
## crate stands on it, plus hold_time seconds after release.

signal state_changed(active: bool)

@export var width := 36.0
@export var hold_time := 0.0

var active := false
var _release := 0.0


func _ready() -> void:
	collision_layer = 32
	collision_mask = 3
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(width - 4.0, 6.0)
	cs.shape = r
	cs.position = Vector2(0, -3)
	add_child(cs)


func _physics_process(delta: float) -> void:
	var pressed := false
	for b in get_overlapping_bodies():
		if b.is_in_group("player") or b.is_in_group("pushable"):
			pressed = true
			break
	if pressed:
		_release = hold_time
	else:
		_release = maxf(_release - delta, 0.0)
	var now := pressed or _release > 0.0
	if now != active:
		active = now
		Sfx.play(self, "land" if now else "door", -10.0, 1.2)
		state_changed.emit(active)
		queue_redraw()


func _draw() -> void:
	var c := Color("ffb02e") if not active else Color("7dffb0")
	var d := 2.0 if active else 0.0
	draw_rect(Rect2(-width / 2.0, -2 + d, width, 2), Color("667788"))
	draw_rect(Rect2(-width / 2.0 + 2, -5 + d, width - 4, 3), c)
	draw_rect(Rect2(-width / 2.0 + 2, -5 + d, width - 4, 1), c.lightened(0.5))
