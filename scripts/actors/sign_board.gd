class_name SignBoard
extends Node2D
## A lit sign in monogram: a dark steel plate with an inked border and glowing
## text, optionally on two legs. Origin = bottom-centre (the floor line, or the
## bottom edge of the plate when `legs` is 0). Warning signs, placards that
## hint at a pad's power. No collision.

const FONT := preload("res://assets/fonts/monogram.ttf")
const INK := Color("10121f")
const STEEL := Color("354655")
const STEEL_LIT := Color("536a74")
const SIZE := 16

@export var lines := PackedStringArray(["AUTHORISED UNITS ONLY"])
@export var accent := Color(1.0, 0.55, 0.16)
@export var legs := 18.0
@export var title_size := 16
@export var glow := 1.15

var _size := Vector2.ZERO


func _ready() -> void:
	z_index = -1
	var w := 0.0
	for l in lines:
		w = maxf(w, FONT.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x)
	_size = Vector2(w + 18.0, lines.size() * 14.0 + 12.0)
	queue_redraw()


func _draw() -> void:
	var top := -legs - _size.y
	if legs > 0.0:
		for sx in [-_size.x * 0.3, _size.x * 0.3]:
			draw_rect(Rect2(sx - 2, -legs, 4, legs), STEEL)
			draw_rect(Rect2(sx - 2, -legs, 1, legs), STEEL_LIT)
	var r := Rect2(-_size.x / 2.0, top, _size.x, _size.y)
	draw_rect(r.grow(2), INK)
	draw_rect(r, STEEL)
	draw_rect(r.grow(-2), INK)
	draw_rect(Rect2(r.position.x + 2, r.position.y + 2, r.size.x - 4, 1), Color(accent, 0.35))
	var c := Color(accent.r * glow, accent.g * glow, accent.b * glow, 1.0)
	var y := top + 6.0 + 11.0
	for l in lines:
		draw_string(FONT, Vector2(-_size.x / 2.0, y), l, HORIZONTAL_ALIGNMENT_CENTER, _size.x, SIZE, c)
		y += 14.0
