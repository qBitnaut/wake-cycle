class_name NanofluidCrate
extends Node2D
## The wrecked "EXPERIMENTAL NANOFLUID" shipping container by the exit: a
## battered steel crate with its lid sprung and a hole in the side, dark goo
## trickling out and pooling on the floor. Dressing only (no collision): the
## cat walks past it. Origin = the floor line at the crate's horizontal centre.
## The stencilled label is real monogram text, drawn bright so it reads under
## the night tint; a faint teal PointLight2D hints at what is leaking.

const FONT := preload("res://assets/fonts/monogram.ttf")
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")
const INK := Color("161630")
const STEEL := Color("56677a")
const STEEL_LIT := Color("7f93a6")
const STEEL_DARK := Color("37445a")
const RIB := Color("2c3a4e")
const PANEL := Color("1d2638")
const STENCIL := Color(2.4, 2.5, 2.6)
const STENCIL_DIM := Color(1.5, 1.6, 1.7)
const HAZARD := Color("d9a21f")
const GOO := Color("0b0d16")
const GOO_EDGE := Color("1a2236")
const SPECK := Color(0.2, 1.4, 1.5)

const W := 112.0
const H := 72.0

var _t := randf() * 10.0
var _light: PointLight2D


func _ready() -> void:
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.texture_scale = 2.4
	_light.color = Color(0.35, 0.9, 1.0)
	_light.energy = 0.7
	_light.position = Vector2(34, -22)
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	_light.energy = 0.6 + 0.15 * sin(_t * 1.7)
	queue_redraw()


func _draw() -> void:
	var x0 := -W / 2.0
	var top := -H
	# Floor puddle first (the crate sits in it), a dark lobe creeping right.
	draw_rect(Rect2(10, -3, 78, 3), GOO)
	draw_rect(Rect2(14, -4, 66, 1), GOO_EDGE)
	draw_rect(Rect2(22, -5, 40, 1), GOO)
	# Body.
	draw_rect(Rect2(x0 - 2, top - 2, W + 4, H + 2), INK)
	draw_rect(Rect2(x0, top, W, H), STEEL)
	draw_rect(Rect2(x0, top, W, 3), STEEL_LIT)
	draw_rect(Rect2(x0, -6, W, 6), STEEL_DARK)
	for rx in [x0 + 4.0, x0 + 34.0, x0 + 66.0, x0 + W - 8.0]:
		draw_rect(Rect2(rx, top + 3, 4, H - 9), RIB)
	for rx in [x0 + 4.0, x0 + W - 8.0]:
		for ry in [top + 8.0, -14.0]:
			draw_rect(Rect2(rx + 1, ry, 2, 2), STEEL_LIT)
	# Dented left corner: a crushed wedge.
	draw_colored_polygon(PackedVector2Array([Vector2(x0 - 2, top - 2), Vector2(x0 + 14, top - 2),
		Vector2(x0 + 6, top + 12), Vector2(x0 - 2, top + 20)]), INK)
	draw_colored_polygon(PackedVector2Array([Vector2(x0 + 14, top), Vector2(x0 + 6, top + 11),
		Vector2(x0 + 12, top + 11)]), STEEL_DARK)
	# The lid, sprung: lifted at the right with a gap of dark inside.
	draw_rect(Rect2(x0 - 4, top - 6, W - 20, 5), INK)
	draw_rect(Rect2(x0 - 3, top - 5, W - 22, 3), STEEL_LIT)
	draw_colored_polygon(PackedVector2Array([Vector2(x0 + W - 24, top - 6), Vector2(x0 + W + 6, top - 16),
		Vector2(x0 + W + 7, top - 11), Vector2(x0 + W - 24, top - 1)]), INK)
	draw_colored_polygon(PackedVector2Array([Vector2(x0 + W - 23, top - 5), Vector2(x0 + W + 4, top - 14),
		Vector2(x0 + W + 5, top - 12), Vector2(x0 + W - 23, top - 3)]), STEEL_LIT)
	draw_rect(Rect2(x0 + W - 24, top - 1, 24, 2), GOO)
	# The label panel and its stencil.
	var px := x0 + 10.0
	draw_rect(Rect2(px - 1, top + 6, 85, 59), INK)
	draw_rect(Rect2(px, top + 7, 83, 57), PANEL)
	draw_string(FONT, Vector2(px + 5, top + 21), "EXPERIMENTAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, STENCIL)
	draw_string(FONT, Vector2(px + 14, top + 34), "NANOFLUID", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, STENCIL)
	for i in 8:  # hazard stripes
		draw_rect(Rect2(px + 3 + i * 10, top + 38, 5, 4), HAZARD)
	draw_string(FONT, Vector2(px + 5, top + 54), "BATCH 7 - DO NOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, STENCIL_DIM)
	draw_string(FONT, Vector2(px + 5, top + 64), "HANDLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, STENCIL_DIM)
	# The hole low on the right and the crack running up to the lid.
	draw_colored_polygon(PackedVector2Array([Vector2(24, -26), Vector2(38, -30), Vector2(44, -20),
		Vector2(40, -10), Vector2(28, -8), Vector2(22, -16)]), INK)
	draw_colored_polygon(PackedVector2Array([Vector2(27, -23), Vector2(36, -26), Vector2(40, -19),
		Vector2(36, -12), Vector2(28, -11), Vector2(25, -17)]), GOO)
	var crack := PackedVector2Array([Vector2(34, -30), Vector2(30, -40), Vector2(36, -48), Vector2(31, -58), Vector2(35, -68)])
	draw_polyline(crack, INK, 2.0)
	# The trickle: out of the hole, down the plating, into the puddle.
	var run := fmod(_t * 0.45, 1.0)
	draw_rect(Rect2(31, -12, 4, 12), GOO)
	draw_rect(Rect2(33, -12, 1, 12), GOO_EDGE)
	draw_rect(Rect2(30 + roundf(sin(_t * 2.0)), -12 + run * 10.0, 2, 2), SPECK * 0.7)
	# A bead of goo falling from the lid gap now and then, a ripple where it lands.
	var fall := fmod(_t, 2.2)
	if fall < 0.5:
		draw_rect(Rect2(x0 + W - 12, top + fall * 2.0 * (H - 8), 2, 3), GOO_EDGE)
	elif fall < 0.9:
		var r := (fall - 0.5) * 22.0
		draw_rect(Rect2(x0 + W - 13 - r, -3, 2.0 * r + 3.0, 1), GOO_EDGE)
	# Machine specks glinting in the puddle and the trickle: the nanofluid.
	for i in 6:
		var a := fmod(_t * 0.7 + i * 0.37, 1.0)
		if a < 0.35:
			var k := sin(a / 0.35 * PI)
			draw_rect(Rect2(16.0 + i * 11.0 + roundf(sin(i * 5.1) * 3.0), -4.0 - float(i % 2), 2, 1),
				Color(SPECK.r, SPECK.g, SPECK.b, k))
