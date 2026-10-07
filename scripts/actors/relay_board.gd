class_name RelayBoard
extends Node2D
## The Master Gate's relay status board: a steel plate with one lamp per power relay (lit when the
## relay is, dark when it is not) and where that relay is, so a player who has missed one can see which
## and where. Reads the saved relay state (PowerRelay.is_lit), so it is right after a Continue too.
## Origin = bottom-centre (the floor line, or the plate's bottom edge when `legs` is 0). No collision.

const FONT := preload("res://assets/fonts/monogram.ttf")
const INK := Color("10121f")
const STEEL := Color("354655")
const STEEL_LIT := Color("536a74")
const SIZE := 16
const PLACES := ["TOWER", "CISTERN", "VAULT"]

@export var legs := 18.0

var _mask := -1
var _t := 0.0


func _ready() -> void:
	z_index = -1


func _process(delta: float) -> void:
	_t += delta
	var mask := PowerRelay.lit_mask()
	if mask != _mask:
		_mask = mask
		queue_redraw()
	elif mask != 7:
		queue_redraw()   # the dark lamps pulse


func _draw() -> void:
	var size := Vector2(112.0, 3 * 15.0 + 28.0)
	var top := -legs - size.y
	if legs > 0.0:
		for sx in [-size.x * 0.3, size.x * 0.3]:
			draw_rect(Rect2(sx - 2, -legs, 4, legs), STEEL)
			draw_rect(Rect2(sx - 2, -legs, 1, legs), STEEL_LIT)
	var r := Rect2(-size.x / 2.0, top, size.x, size.y)
	draw_rect(r.grow(2), INK)
	draw_rect(r, STEEL)
	draw_rect(r.grow(-2), INK)
	var lit := PowerRelay.lit_count()
	var accent := FXPalette.INDICATOR if lit >= 3 else FXPalette.SODIUM
	draw_string(FONT, Vector2(r.position.x, top + 15.0), "RELAYS %d/3" % lit, HORIZONTAL_ALIGNMENT_CENTER, size.x, SIZE, accent)
	draw_rect(Rect2(r.position.x + 4, top + 20.0, size.x - 8, 1), Color(accent, 0.35))
	for i in 3:
		var y := top + 24.0 + i * 15.0
		var on := PowerRelay.is_lit(i + 1)
		var pulse := 1.0 if on else 0.35 + 0.35 * (0.5 + 0.5 * sin(_t * 4.0 + i))
		var c := FXPalette.INDICATOR if on else Color("d07a26")
		draw_rect(Rect2(r.position.x + 8, y + 3, 10, 9), INK)
		draw_rect(Rect2(r.position.x + 9, y + 4, 8, 7), Color(c, pulse) if on else Color(c, pulse * 0.6).darkened(0.35))
		draw_string(FONT, Vector2(r.position.x + 24, y + 12.0), "%d %s" % [i + 1, PLACES[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(c, 1.0 if on else 0.8))
