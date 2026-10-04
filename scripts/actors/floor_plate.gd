extends Area2D
## Big floor pressure plate (2 tiles wide). Held while the cat or a pushable
## crate stands on it, plus hold_time seconds after release.

signal state_changed(active: bool)

@export var width := 64.0
@export var hold_time := 0.0

var active := false
var _release := 0.0


func _ready() -> void:
	collision_layer = 32
	collision_mask = 3
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(width - 6.0, 10.0)
	cs.shape = r
	cs.position = Vector2(0, -5)
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
	# Hazard-amber plate with a steel rim; the lamp turns muted aqua when held
	# (never a power-hue green).
	var steel := Color("5b7280")
	var c := Color("d07a26") if not active else FXPalette.INDICATOR
	var d := 3.0 if active else 0.0
	draw_rect(Rect2(-width / 2.0, -4, width, 4), steel)
	draw_rect(Rect2(-width / 2.0, -4, width, 1), Color("8aa7ab"))
	draw_rect(Rect2(-width / 2.0 + 3, -10 + d, width - 6, 6), Color("161630"))
	draw_rect(Rect2(-width / 2.0 + 4, -9 + d, width - 8, 4), c)
	draw_rect(Rect2(-width / 2.0 + 4, -9 + d, width - 8, 1), c.lightened(0.4))
