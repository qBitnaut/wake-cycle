class_name TileOccluderBaker
extends RefCounted
## Replaces a TileMapLayer's per-tile occluders with merged occluders whose
## exposed edges are inset by a few pixels.
##
## Why: with full-cell occluders, a tile's own face sits inside its shadow, so
## a lamp never lights the floor it stands on. Insetting only the edges that
## face open air leaves a lit rim on every surface the light can see, without
## opening seams between neighbouring tiles.
##
## Usage (once, after the level is built):
##     TileOccluderBaker.bake($Solid, 3)
## Slopes and rail-only occluders keep their own polygon. One-way tiles have no
## cell occluder and stay open.


## Bakes occluders for `layer` and disables its built-in occlusion. Returns the
## Node2D holding the new LightOccluder2D nodes (a child of `layer`).
static func bake(layer: TileMapLayer, inset_px: int = 3, occlusion_layer: int = 0) -> Node2D:
	var holder := Node2D.new()
	holder.name = "BakedOccluders"
	var ts := layer.tile_set
	if ts == null:
		return holder
	var cell := Vector2(ts.tile_size)
	var light_mask := ts.get_occlusion_layer_light_mask(occlusion_layer)
	var solid := {}
	var slopes: Array[Vector2i] = []
	for c in layer.get_used_cells():
		var td := layer.get_cell_tile_data(c)
		if td == null or td.get_occluder_polygons_count(occlusion_layer) == 0:
			continue
		var poly := td.get_occluder_polygon(occlusion_layer, 0)
		if poly == null:
			continue
		if _is_full_cell(poly.polygon, cell):
			solid[c] = true
		else:
			slopes.append(c)  # slopes and rail-only occluders keep their own polygon
	# Row runs of cells that share the same top/bottom exposure merge into one rect.
	var rows := {}
	for c: Vector2i in solid:
		if not rows.has(c.y):
			rows[c.y] = []
		rows[c.y].append(c.x)
	var rects: Array[Rect2] = []
	for y: int in rows:
		var xs: Array = rows[y]
		xs.sort()
		var run_start := -1
		var prev := -99999
		var prev_key := -1
		for i in xs.size() + 1:
			var x: int = xs[i] if i < xs.size() else -99999
			var key := -1
			if i < xs.size():
				key = int(not solid.has(Vector2i(x, y - 1))) + 2 * int(not solid.has(Vector2i(x, y + 1)))
			if run_start != -1 and (x != prev + 1 or key != prev_key):
				rects.append(_run_rect(run_start, prev, y, prev_key, solid, cell, inset_px))
				run_start = -1
			if i < xs.size() and run_start == -1:
				run_start = x
			prev = x
			prev_key = key
	for r in rects:
		_add(holder, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), light_mask)
	for c in slopes:
		var poly := layer.get_cell_tile_data(c).get_occluder_polygon(occlusion_layer, 0).polygon
		var origin := layer.map_to_local(c)
		var pts := PackedVector2Array()
		for p in poly:
			pts.append(origin + p)
		_add(holder, pts, light_mask)
	layer.occlusion_enabled = false
	layer.add_child(holder)
	return holder


## True for a 4-point polygon that covers the whole tile cell. Rail-only
## occluders (girder trusses) are 4 points too, but must not be merged or
## inset like a solid cell.
static func _is_full_cell(poly: PackedVector2Array, cell: Vector2) -> bool:
	if poly.size() != 4:
		return false
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r.size.is_equal_approx(cell)


static func _run_rect(x0: int, x1: int, y: int, key: int, solid: Dictionary, cell: Vector2, inset: int) -> Rect2:
	var top := float(y) * cell.y + (inset if key & 1 else 0)
	var bottom := float(y + 1) * cell.y - (inset if key & 2 else 0)
	var left := float(x0) * cell.x + (inset if not solid.has(Vector2i(x0 - 1, y)) else 0)
	var right := float(x1 + 1) * cell.x - (inset if not solid.has(Vector2i(x1 + 1, y)) else 0)
	return Rect2(left, top, right - left, bottom - top)


static func _add(holder: Node2D, pts: PackedVector2Array, light_mask: int) -> void:
	var occ := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.polygon = pts
	poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
	occ.occluder = poly
	occ.occluder_light_mask = light_mask
	holder.add_child(occ)
