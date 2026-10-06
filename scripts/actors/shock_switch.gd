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
var shock_half := Vector2(14, 14)


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
	Sfx.play(self, "plate_click" if v else "plate_release")
	state_changed.emit(active)


func _process(delta: float) -> void:
	_t += delta
	if active and auto_off > 0.0:
		_left -= delta
		if _left <= 0.0:
			_set_active(false)
	queue_redraw()


func _draw() -> void:
	# Steel box with an ink window. Amber while armed, muted aqua while on
	# (no power-hue green, no hostile red); the gold ring hints at the shockwave.
	var c := FXPalette.INDICATOR if active else Color("d07a26")
	draw_rect(Rect2(-14, -14, 28, 28), Color("161630"))
	draw_rect(Rect2(-13, -13, 26, 26), Color("5b7280"))
	draw_rect(Rect2(-13, -13, 26, 2), Color("8aa7ab"))
	draw_rect(Rect2(-10, -10, 20, 20), Color("141a2c"))
	draw_circle(Vector2.ZERO, 6.0, c)
	draw_circle(Vector2(-2, -2), 2.0, c.lightened(0.5))
	if not active:
		var p := 0.5 + 0.5 * sin(_t * 4.0)
		draw_arc(Vector2.ZERO, 12.0 + 2.0 * p, 0.0, TAU, 24, Color(NanoPalette.SHOCKWAVE, 0.5), 2.0)
	if active and auto_off > 0.0:
		draw_rect(Rect2(-10, 17, 20.0 * (_left / auto_off), 2), c)
