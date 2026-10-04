extends Node2D
## Wall switch toggled by the cat's double-jump shockwave. With auto_off > 0 it
## resets itself after that many seconds. Emits state_changed like a plate.

signal state_changed(active: bool)

@export var auto_off := 6.0

var active := false
var _t := 0.0
var _left := 0.0


## Box centre (offset from origin) and half size, used for shockwave range checks.
var shock_offset := Vector2.ZERO
var shock_half := Vector2(7, 7)


func _ready() -> void:
	add_to_group("shock_receiver")


func on_shockwave(_origin: Vector2, _radius: float, source: String) -> void:
	if source != "shock":
		return
	_set_active(not active or auto_off > 0.0)
	_left = auto_off


func _set_active(v: bool) -> void:
	if v == active:
		return
	active = v
	Sfx.play(self, "door", -8.0, 1.5)
	state_changed.emit(active)


func _process(delta: float) -> void:
	_t += delta
	if active and auto_off > 0.0:
		_left -= delta
		if _left <= 0.0:
			_set_active(false)
	queue_redraw()


func _draw() -> void:
	var c := Color("7dffb0") if active else Color("ff5a5a")
	draw_rect(Rect2(-7, -7, 14, 14), Color("445566"))
	draw_rect(Rect2(-5, -5, 10, 10), Color("1b2430"))
	draw_circle(Vector2.ZERO, 3.0, c)
	if not active:
		var p := 0.5 + 0.5 * sin(_t * 4.0)
		draw_arc(Vector2.ZERO, 6.0 + p, 0.0, TAU, 12, Color(NanoPalette.SHOCKWAVE, 0.5), 1.0)
	if active and auto_off > 0.0:
		draw_rect(Rect2(-5, 8, 10.0 * (_left / auto_off), 1), c)
