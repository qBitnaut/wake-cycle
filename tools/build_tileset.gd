## Builds res://assets/tiles/warehouse_tileset.tres from the three Kenney atlases.
## Run: godot --headless --path . --script res://tools/build_tileset.gd
##
## Physics layer 0 = "world" (collision layer 1). Occlusion layer 0 casts 2D
## light shadows. Solid tiles get a full-cell (or triangular) collider and
## occluder; one-way tiles get a thin top-edge collider and no occluder.
extends SceneTree

const T := 18
const H := T / 2.0

# [texture, columns, rows, solid ranges, one-way ranges, slope ranges]
const SOURCES := [
	{
		"name": "base", "tex": "res://assets/tiles/kenney-pixel-platformer/tilemap_packed.png",
		"cols": 20, "rows": 9,
		"solid": [[0, 6], [9, 11], [20, 26], [29, 31], [40, 43], [47, 50], [60, 63], [80, 83], [100, 104], [120, 123], [140, 143]],
		"oneway": [[12, 15], [146, 147]], "slope": [],
	},
	{
		"name": "industrial", "tex": "res://assets/tiles/kenney-industrial-expansion/tilemap_packed.png",
		"cols": 16, "rows": 7,
		"solid": [[0, 3], [16, 19], [32, 35], [48, 51], [25, 25], [60, 63], [84, 90], [100, 106]],
		"oneway": [[4, 6], [20, 22]], "slope": [[66, 67]],
	},
	{
		"name": "metal", "tex": "res://assets/tiles/kenney-metal-expansion/tilemap_packed.png",
		"cols": 22, "rows": 15,
		"solid": [[0, 17], [22, 39], [44, 61], [66, 83], [88, 103], [110, 125], [132, 147], [154, 169], [150, 153], [172, 175], [194, 197], [216, 219], [238, 241], [260, 263], [220, 224], [246, 249], [268, 271]],
		"oneway": [[184, 186], [206, 208], [228, 230], [242, 245]], "slope": [[104, 105], [126, 127], [148, 149], [170, 171]],
	},
]


func _expand(ranges: Array) -> Dictionary:
	var d := {}
	for r in ranges:
		for i in range(r[0], r[1] + 1):
			d[i] = true
	return d


func _slope_polygon(img: Image, region: Rect2i) -> PackedVector2Array:
	# Triangle = the three corners that are opaque; the transparent corner is dropped.
	var corners := [Vector2i(2, 2), Vector2i(T - 3, 2), Vector2i(T - 3, T - 3), Vector2i(2, T - 3)]
	var pts := [Vector2(-H, -H), Vector2(H, -H), Vector2(H, H), Vector2(-H, H)]
	var out := PackedVector2Array()
	for i in 4:
		var c: Vector2i = region.position + corners[i]
		if img.get_pixelv(c).a > 0.5:
			out.append(pts[i])
	return out if out.size() == 3 else PackedVector2Array()


func _initialize() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(T, T)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_occlusion_layer()
	ts.set_occlusion_layer_light_mask(0, 1)
	var rect := PackedVector2Array([Vector2(-H, -H), Vector2(H, -H), Vector2(H, H), Vector2(-H, H)])
	var strip := PackedVector2Array([Vector2(-H, -H), Vector2(H, -H), Vector2(H, -H + 6), Vector2(-H, -H + 6)])
	for s in SOURCES:
		var tex: Texture2D = load(s["tex"])
		var img := tex.get_image()
		var src := TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = Vector2i(T, T)
		ts.add_source(src)  # must be in the TileSet before tile data is edited
		var solid := _expand(s["solid"])
		var oneway := _expand(s["oneway"])
		var slope := _expand(s["slope"])
		var counts := {"solid": 0, "oneway": 0, "slope": 0, "decor": 0}
		for idx in s["cols"] * s["rows"]:
			var coords := Vector2i(idx % s["cols"], idx / s["cols"])
			var region := Rect2i(coords * T, Vector2i(T, T))
			if img.get_region(region).is_invisible():
				continue
			src.create_tile(coords)
			var td: TileData = src.get_tile_data(coords, 0)
			var poly := PackedVector2Array()
			var one := false
			if slope.has(idx):
				poly = _slope_polygon(img, region)
				counts["slope"] += 1
			elif solid.has(idx):
				poly = rect
				counts["solid"] += 1
			elif oneway.has(idx):
				poly = strip
				one = true
				counts["oneway"] += 1
			else:
				counts["decor"] += 1
			if poly.is_empty():
				continue
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, poly)
			td.set_collision_polygon_one_way(0, 0, one)
			if one:
				td.set_collision_polygon_one_way_margin(0, 0, 1.0)
			else:
				var o := OccluderPolygon2D.new()
				o.polygon = poly
				td.set_occluder(0, o)
		print("%s: %s" % [s["name"], counts])
	print("save: ", ResourceSaver.save(ts, "res://assets/tiles/warehouse_tileset.tres"))
	quit()
