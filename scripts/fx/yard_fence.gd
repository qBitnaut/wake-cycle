class_name YardFence
extends Node2D
## A chain-link security fence along the yard, drawn in code: posts on a fixed
## spacing, top and bottom rails, a diamond mesh, and a coil of razor wire on
## top. `gaps` are x ranges (px, local) where the mesh has been cut away and
## the wires hang bent (the way through). Origin = the foot of the fence's left
## end. This is the fence that later turns into the quarantine perimeter.

@export var length := 1024.0
@export var fence_height := 128.0
@export var post_spacing := 128.0
@export var mesh_step := 12.0
@export var gaps: Array[Vector2] = []

const POST := Color("2a4658")
const POST_LIT := Color("5b7280")
const POST_INK := Color("141a2c")
const MESH := Color(0.55, 0.66, 0.72, 0.55)
const MESH_DIM := Color(0.30, 0.40, 0.48, 0.55)
const WIRE := Color(0.62, 0.70, 0.74, 0.8)


func _in_gap(x: float) -> bool:
	for g in gaps:
		if x > g.x and x < g.y:
			return true
	return false


func _draw() -> void:
	var top := -fence_height
	# Mesh: two families of diagonals between the rails, skipping the gaps.
	var x := 0.0
	while x < length:
		if not _in_gap(x + mesh_step * 0.5):
			var step := mesh_step
			var n := int(fence_height / step)
			for i in n:
				var y0 := top + i * step
				draw_line(Vector2(x, y0), Vector2(x + step, y0 + step), MESH, 1.0)
				draw_line(Vector2(x + step, y0), Vector2(x, y0 + step), MESH_DIM, 1.0)
		x += mesh_step
	# Rails.
	var segs: Array[Vector2] = []
	var start := 0.0
	for g in gaps:
		segs.append(Vector2(start, g.x))
		start = g.y
	segs.append(Vector2(start, length))
	for s in segs:
		draw_rect(Rect2(s.x, top - 2, s.y - s.x, 4), POST)
		draw_rect(Rect2(s.x, top - 2, s.y - s.x, 1), POST_LIT)
		draw_rect(Rect2(s.x, -3, s.y - s.x, 3), POST)
		# Razor wire: a row of small loops above the top rail.
		var wx: float = s.x
		while wx < s.y - 6.0:
			draw_arc(Vector2(wx + 5, top - 8), 5.0, PI, TAU + PI * 0.15, 8, WIRE, 1.0)
			wx += 9.0
	# Posts (leaning at the gap edges).
	var px := 0.0
	while px <= length:
		var lean := 0.0
		for g in gaps:
			if absf(px - g.x) < post_spacing * 0.6 or absf(px - g.y) < post_spacing * 0.6:
				lean = 0.0
		if not _in_gap(px):
			draw_rect(Rect2(px - 3, top - 6, 6, fence_height + 6), POST_INK)
			draw_rect(Rect2(px - 2, top - 6, 4, fence_height + 6), POST)
			draw_rect(Rect2(px - 2, top - 6, 1, fence_height + 6), POST_LIT)
		px += post_spacing
	# The cut: frayed wires hanging from the edges.
	for g in gaps:
		for edge in [g.x, g.y]:
			var dir := -1.0 if edge == g.x else 1.0
			for k in 7:
				var y0 := top + 4 + k * 14.0
				draw_line(Vector2(edge, y0), Vector2(edge + dir * (6.0 + (k * 7) % 9), y0 + 10.0 + (k * 5) % 7), MESH, 1.0)
		draw_rect(Rect2(g.x - 3, top - 6, 6, fence_height + 6), POST_INK)
		draw_rect(Rect2(g.x - 2, top - 6, 4, fence_height + 6), POST)
		draw_rect(Rect2(g.y - 3, top - 6, 6, fence_height + 6), POST_INK)
		draw_rect(Rect2(g.y - 2, top - 6, 4, fence_height + 6), POST)
