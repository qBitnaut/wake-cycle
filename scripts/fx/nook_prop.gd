class_name NookProp
extends Node2D
## The cat's sleeping nook, drawn in the muted back-layer tones: a flattened
## cardboard mat on the floor, a box on its side and a tarp hung from a pipe.
## Origin = the floor line at the nook's left. Pure dressing, no collision.
## Warm is the cat's colour (palette rule 4), so the cardboard is a dim grey brown.

const CARD := Color("5d4a47")
const CARD_LIT := Color("7a6460")
const CARD_DARK := Color("3b2c33")
const TARP := Color("2f4152")
const TARP_FOLD := Color("22303f")
const TARP_LIT := Color("3f566a")
const INK := Color("161630")


func _draw() -> void:
	# Flattened mat under the cat (x 70..200).
	draw_rect(Rect2(70, -5, 130, 5), INK)
	draw_rect(Rect2(71, -4, 128, 3), CARD)
	draw_rect(Rect2(71, -4, 128, 1), CARD_LIT)
	for x in [96, 131, 168]:
		draw_rect(Rect2(x, -4, 1, 3), CARD_DARK)
	# Box on its side, open to the right (x -16..42, drawn shifted: the letter A
	# sits behind its right edge, half hidden and peeking out).
	draw_set_transform(Vector2(-24, 0))
	draw_rect(Rect2(8, -50, 58, 50), INK)
	draw_rect(Rect2(10, -48, 54, 46), CARD)
	draw_rect(Rect2(10, -48, 54, 3), CARD_LIT)
	draw_rect(Rect2(10, -48, 3, 46), CARD_LIT)
	draw_rect(Rect2(14, -44, 46, 38), CARD_DARK)  # the dark inside
	draw_rect(Rect2(10, -3, 54, 3), CARD_DARK)
	# Torn flap.
	draw_colored_polygon(PackedVector2Array([Vector2(64, -48), Vector2(80, -40), Vector2(66, -36)]), CARD_LIT)
	draw_set_transform(Vector2.ZERO)
	# Tarp hung from a pipe above, folds falling to the floor (x 204..250).
	draw_rect(Rect2(200, -74, 56, 4), INK)
	var pts := PackedVector2Array([Vector2(204, -70), Vector2(250, -70), Vector2(256, -8), Vector2(246, -2),
		Vector2(236, -12), Vector2(224, -2), Vector2(212, -10), Vector2(202, -2)])
	draw_colored_polygon(pts, TARP)
	for x in [214.0, 226.0, 238.0]:
		draw_line(Vector2(x, -68), Vector2(x + 2, -12), TARP_FOLD, 1.0)
	draw_line(Vector2(206, -69), Vector2(248, -69), TARP_LIT, 1.0)
