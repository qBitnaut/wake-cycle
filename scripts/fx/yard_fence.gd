class_name YardFence
extends Node2D
## A chain-link security fence along the yard, drawn in code: posts on a fixed
## spacing, top and bottom rails, a diamond mesh, and a coil of razor wire on
## top. `gaps` are x ranges (px, local) where the mesh has been cut away and
## the wires hang bent (the way through). Origin = the foot of the fence's left
## end. This is the fence that later turns into the quarantine perimeter.
##
## Drawn in pieces: one long CanvasItem with 10-25k draw commands is walked in full every frame by
## the web renderer even when a screen's width of it is visible (Room 2: 55 % of the frame's CPU,
## Room 4: 63 %). Each layer is cut into CHUNK_COLS-column pieces the renderer culls itself. The
## layers keep the original draw order (mesh, rails and wire, posts, the cut): pixel-identical.

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

const CHUNK_COLS := 48  # mesh columns per piece (48 * 12 px = 576 px)

enum Layer { MESH, RAILS, POSTS, CUT }


## One culled piece of one layer: paints its x range [lo, hi) of the fence.
class Piece extends Node2D:
	var fence: YardFence
	var layer := 0
	var lo := 0.0
	var hi := 0.0

	func _draw() -> void:
		fence._paint(self, layer, lo, hi)


func _ready() -> void:
	var step := maxf(mesh_step, 1.0)
	var span := step * CHUNK_COLS
	for layer in [Layer.MESH, Layer.RAILS, Layer.POSTS]:
		var lo := 0.0
		while lo < length:
			# (the last piece is open-ended: a post can sit exactly on `length`)
			_add_piece(layer, lo, INF if lo + span >= length else lo + span)
			lo += span
	if not gaps.is_empty():
		_add_piece(Layer.CUT, 0.0, length)


func _add_piece(layer: int, lo: float, hi: float) -> void:
	var p := Piece.new()
	p.fence = self
	p.layer = layer
	p.lo = lo
	p.hi = hi
	p.self_modulate = self_modulate
	p.light_mask = light_mask
	p.use_parent_material = true
	add_child(p, false, Node.INTERNAL_MODE_BACK)


func _in_gap(x: float) -> bool:
	for g in gaps:
		if x > g.x and x < g.y:
			return true
	return false


func _paint(ci: CanvasItem, layer: int, lo: float, hi: float) -> void:
	var top := -fence_height
	match layer:
		Layer.MESH:
			# Mesh: two families of diagonals between the rails, skipping the gaps.
			var k := int(ceilf(lo / mesh_step))
			var x := k * mesh_step
			while x < hi and x < length:
				if not _in_gap(x + mesh_step * 0.5):
					var step := mesh_step
					var n := int(fence_height / step)
					for i in n:
						var y0 := top + i * step
						ci.draw_line(Vector2(x, y0), Vector2(x + step, y0 + step), MESH, 1.0)
						ci.draw_line(Vector2(x + step, y0), Vector2(x, y0 + step), MESH_DIM, 1.0)
				k += 1
				x = k * mesh_step
		Layer.RAILS:
			var segs: Array[Vector2] = []
			var start := 0.0
			for g in gaps:
				segs.append(Vector2(start, g.x))
				start = g.y
			segs.append(Vector2(start, length))
			for s in segs:
				var a := maxf(s.x, lo)
				var b := minf(s.y, hi)
				if b > a:
					ci.draw_rect(Rect2(a, top - 2, b - a, 4), POST)
					ci.draw_rect(Rect2(a, top - 2, b - a, 1), POST_LIT)
					ci.draw_rect(Rect2(a, -3, b - a, 3), POST)
				# Razor wire: a row of small loops above the top rail.
				var wx: float = s.x
				while wx < s.y - 6.0:
					if wx >= lo and wx < hi:
						ci.draw_arc(Vector2(wx + 5, top - 8), 5.0, PI, TAU + PI * 0.15, 8, WIRE, 1.0)
					wx += 9.0
		Layer.POSTS:
			var j := int(ceilf(lo / post_spacing))
			var px := j * post_spacing
			while px < hi and px <= length:
				if not _in_gap(px):
					ci.draw_rect(Rect2(px - 3, top - 6, 6, fence_height + 6), POST_INK)
					ci.draw_rect(Rect2(px - 2, top - 6, 4, fence_height + 6), POST)
					ci.draw_rect(Rect2(px - 2, top - 6, 1, fence_height + 6), POST_LIT)
				j += 1
				px = j * post_spacing
		Layer.CUT:
			# The cut: frayed wires hanging from the edges.
			for g in gaps:
				for edge in [g.x, g.y]:
					var dir := -1.0 if edge == g.x else 1.0
					for k in 7:
						var y0 := top + 4 + k * 14.0
						ci.draw_line(Vector2(edge, y0), Vector2(edge + dir * (6.0 + (k * 7) % 9), y0 + 10.0 + (k * 5) % 7), MESH, 1.0)
				ci.draw_rect(Rect2(g.x - 3, top - 6, 6, fence_height + 6), POST_INK)
				ci.draw_rect(Rect2(g.x - 2, top - 6, 4, fence_height + 6), POST)
				ci.draw_rect(Rect2(g.y - 3, top - 6, 6, fence_height + 6), POST_INK)
				ci.draw_rect(Rect2(g.y - 2, top - 6, 4, fence_height + 6), POST)
