## Builds res://assets/tiles/wake_hd.tres from the recoloured sheet
## res://assets/art_hd/tiles_wake_hd.png (32 px tiles, seven 16x10 material
## blocks stacked vertically: steel, bulkhead, rust, maroon, teal, violet,
## hazard). A tile keeps its (col, row) in every block, so the atlas position
## is (col, row + 10 * block) and one classification table serves all blocks.
##
## Run: godot --headless --path . --script res://tools/build_tileset_hd.gd
##
## Physics layer 0 = "world" (collision layer 1). Occlusion layer 0 casts 2D
## light shadows (light mask 1).
##   solid   full-cell collider and full-cell occluder (TileOccluderBaker
##           merges these and insets the exposed edges, 5 px at 32 px).
##   oneway  thin top strip, one-way, no cell occluder. Girder trusses get a
##           rail-only occluder: only the steel rail casts, not the open
##           lattice (so light passes through the X-bracing).
##   slope   triangular collider and occluder where exactly three corners of
##           the tile are opaque.
##   decor   art only.
extends SceneTree

const T := 32
const H := T / 2.0
const SHEET := "res://assets/art_hd/tiles_wake_hd.png"
const OUT := "res://assets/tiles/wake_hd.tres"
const COLS := 16
const BLOCK_ROWS := 10
const BLOCKS := 7
const STRIP := 8.0  ## one-way strip depth in px

const GIRDER_V := Vector2i(12, 4)
const GIRDER_H := Vector2i(13, 4)
## Grating (see-through floor): the catwalk deck.
const GRATING := [Vector2i(10, 7), Vector2i(11, 7), Vector2i(12, 7)]
## Rail geometry inside a girder tile, in tile-local px (top-left origin).
const RAIL_H_Y := 4.0
const RAIL_H_DEPTH := 6.0
const RAIL_V_X := 4.0
const RAIL_V_W := 6.0


func _is_solid_cell(c: int, r: int) -> bool:
	if c <= 7 and r <= 7:
		return not (c == 7 and r >= 6)  # (7,6) and (7,7) are nozzle domes
	if c >= 10 and c <= 12 and r >= 5 and r <= 6:
		return true  # container sides
	return c >= 13 and c <= 14 and r >= 5 and r <= 7  # louvred vents


func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0 - H, y0 - H), Vector2(x1 - H, y0 - H),
		Vector2(x1 - H, y1 - H), Vector2(x0 - H, y1 - H)])


func _slope_polygon(img: Image, region: Rect2i) -> PackedVector2Array:
	var corners := [Vector2i(2, 2), Vector2i(T - 3, 2), Vector2i(T - 3, T - 3), Vector2i(2, T - 3)]
	var pts := [Vector2(-H, -H), Vector2(H, -H), Vector2(H, H), Vector2(-H, H)]
	var out := PackedVector2Array()
	for i in 4:
		var p: Vector2i = region.position + corners[i]
		if img.get_pixelv(p).a > 0.5:
			out.append(pts[i])
	return out if out.size() == 3 else PackedVector2Array()


func _set_poly(td: TileData, poly: PackedVector2Array, one_way: bool) -> void:
	td.add_collision_polygon(0)
	td.set_collision_polygon_points(0, 0, poly)
	td.set_collision_polygon_one_way(0, 0, one_way)
	if one_way:
		td.set_collision_polygon_one_way_margin(0, 0, 1.0)


func _set_occluder(td: TileData, poly: PackedVector2Array) -> void:
	var o := OccluderPolygon2D.new()
	o.polygon = poly
	td.set_occluder(0, o)


func _initialize() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(T, T)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_occlusion_layer()
	ts.set_occlusion_layer_light_mask(0, 1)
	var tex: Texture2D = load(SHEET)
	var img := tex.get_image()
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(T, T)
	ts.add_source(src, 0)  # must be in the TileSet before tile data is edited
	var counts := {"solid": 0, "oneway": 0, "slope": 0, "rail": 0, "decor": 0}
	for block in BLOCKS:
		for r in BLOCK_ROWS:
			for c in COLS:
				var coords := Vector2i(c, r + block * BLOCK_ROWS)
				var region := Rect2i(coords * T, Vector2i(T, T))
				var cell := img.get_region(region)
				if cell.is_invisible():
					continue
				src.create_tile(coords)
				var td := src.get_tile_data(coords, 0)
				var local := Vector2i(c, r)
				var full := true
				for y in T:
					for x in T:
						if cell.get_pixel(x, y).a < 0.5:
							full = false
							break
					if not full:
						break
				var slope := PackedVector2Array()
				if c >= 8 and r <= 3:
					slope = _slope_polygon(img, region)
				if not slope.is_empty():
					_set_poly(td, slope, false)
					_set_occluder(td, slope)
					counts["slope"] += 1
				elif _is_solid_cell(c, r) and full:
					var rect := _rect(0, 0, T, T)
					_set_poly(td, rect, false)
					_set_occluder(td, rect)
					counts["solid"] += 1
				elif local == GIRDER_H:
					_set_poly(td, _rect(0, RAIL_H_Y, T, RAIL_H_Y + STRIP), true)
					_set_occluder(td, _rect(0, RAIL_H_Y, T, RAIL_H_Y + RAIL_H_DEPTH))
					counts["oneway"] += 1
					counts["rail"] += 1
				elif local == GIRDER_V:
					_set_occluder(td, _rect(RAIL_V_X, 0, RAIL_V_X + RAIL_V_W, T))
					counts["rail"] += 1
				elif local in GRATING:
					_set_poly(td, _rect(0, 0, T, STRIP), true)
					counts["oneway"] += 1
				else:
					counts["decor"] += 1
	print("tiles: ", counts)
	print("save: ", ResourceSaver.save(ts, OUT))
	quit()
