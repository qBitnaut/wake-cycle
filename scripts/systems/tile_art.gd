class_name TileArt
extends RefCounted
## Reads single tiles out of the recoloured sheet (assets/art_hd/tiles_wake_hd.png)
## for actors that draw tile art directly (crates, spikes, doors, emitters).
## Same addressing as the TileSet: (col, row) inside a material block.

const SHEET := preload("res://assets/art_hd/tiles_wake_hd.png")
const T := 32
const MATERIALS := ["steel", "bulkhead", "rust", "maroon", "teal", "violet", "hazard"]
const BLOCK_ROWS := 10

# Tiles that actors use (col, row).
const BEVEL := Vector2i(0, 2)
const VENTBOX := Vector2i(1, 2)
const CROSS := Vector2i(2, 2)
const FRAMED := Vector2i(3, 2)
const RECESS := Vector2i(2, 3)
const FLAT := Vector2i(4, 3)
const PLATE_A := Vector2i(6, 3)
const PLATE_B := Vector2i(7, 3)
const SPIKES_UP := Vector2i(9, 4)


## Atlas region of tile (c, r) in `material`, optionally cropped to a sub-rect
## in tile-local px.
static func region(material: String, tile: Vector2i, crop := Rect2i(0, 0, T, T)) -> Rect2:
	var block := MATERIALS.find(material)
	var origin := Vector2i(tile.x * T, (tile.y + block * BLOCK_ROWS) * T)
	return Rect2(origin + crop.position, crop.size)


## A Sprite2D showing the tile. `centered = false`; position its top-left.
static func sprite(material: String, tile: Vector2i, crop := Rect2i(0, 0, T, T)) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = SHEET
	s.centered = false
	s.region_enabled = true
	s.region_rect = region(material, tile, crop)
	return s
