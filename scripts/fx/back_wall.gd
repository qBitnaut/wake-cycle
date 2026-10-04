class_name BackWall
extends Node2D
## The interior back wall: a dark panelled fill with an ansimuz machinery band
## along the floor line (harmonised, assets/art_hd/bg/wall_machinery.png), and
## holes cut for windows and skylights so the NightBackdrop shows through.
## Everything here is "back" art in the BACKWALL value band; only solid things
## use the bright tile style (palette.md rule 1).
##
## The machinery art carries aqua status lights. Those pixels are also lifted
## into an unshaded child layer (the emissive indicator dots), so they stay
## readable under the night tint. That child draws right after the wall and
## before any prop or actor.
##
## Origin = top-left of the wall. `size` is the wall extent in px; `floor_y` is
## where the machinery band sits.

const BAND := preload("res://assets/art_hd/bg/wall_machinery.png")
const COLUMN := preload("res://assets/art_hd/bg/column.png")
const FILL := Color("1a2431")
const SEAM := Color("141c27")
const SEAM_LIT := Color("212d3b")
const FRAME_LIT := Color("3d5866")
const FRAME_MID := Color("2a3d4b")
const FRAME_DARK := Color("0f1620")
const INDICATOR_RGB := Color("41b5c0")

@export var size := Vector2(1280, 320)
@export var floor_y := 320.0
## Openings in the wall, in px: windows and skylights (see NightBackdrop).
@export var holes: Array[Rect2] = []
## Subset of `holes` that get a window frame, mullions and sill.
@export var windows: Array[Rect2] = []
## X positions of structural columns (ansimuz support).
@export var columns: Array[float] = []
## Seam spacing for the big wall panels; 0 disables them.
@export var panel_width := 96
## Back layers sit darker than the foreground at night: depth by value.
@export_range(0.2, 1.0, 0.01) var back_dim := 0.7
## Indicator brightness (unshaded, so the night tint does not dim it).
@export_range(0.0, 2.0, 0.05) var dot_level := 0.8
## X ranges (x0, x1 in px) where the machinery band and its dots are left out,
## e.g. a loading door that opens straight onto the night.
@export var band_gaps: Array[Vector2] = []

var _dots_tex: ImageTexture


func _ready() -> void:
	self_modulate = Color(back_dim, back_dim, back_dim)
	_dots_tex = _extract_dots(BAND)
	var um := CanvasItemMaterial.new()
	um.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var n := 0
	for seg in _segments():
		var band := _repeated(BAND, seg)
		band.name = "Band%d" % n if n > 0 else "Band"
		band.position = Vector2(seg.x, floor_y - BAND.get_height())
		band.self_modulate = Color(back_dim, back_dim, back_dim)
		add_child(band)
		# Emissive indicator dots: unshaded, right after the wall art.
		var dots := _repeated(_dots_tex, seg)
		dots.name = "IndicatorDots%d" % n if n > 0 else "IndicatorDots"
		dots.position = band.position
		dots.material = um
		dots.self_modulate = Color(dot_level, dot_level, dot_level)
		add_child(dots)
		n += 1
	for x in columns:
		var col := Sprite2D.new()
		col.texture = COLUMN
		col.centered = false
		col.position = Vector2(x, floor_y - COLUMN.get_height() + 8)
		col.self_modulate = Color(back_dim, back_dim, back_dim)
		add_child(col)


## Tiles `tex` along x range `seg` (a Sprite2D with a repeating region; the
## region starts at seg.x so the pattern stays continuous across gaps).
func _repeated(tex: Texture2D, seg := Vector2(-1, -1)) -> Sprite2D:
	if seg.x < 0.0:
		seg = Vector2(0, size.x)
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.region_enabled = true
	s.region_rect = Rect2(seg.x, 0, seg.y - seg.x, tex.get_height())
	return s


## The x ranges the band covers: the wall width minus `band_gaps`.
func _segments() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var x := 0.0
	var gaps := band_gaps.duplicate()
	gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for g in gaps:
		if g.x > x:
			out.append(Vector2(x, g.x))
		x = maxf(x, g.y)
	if x < size.x:
		out.append(Vector2(x, size.x))
	return out


## A copy of `tex` holding only the indicator-coloured pixels.
static func _extract_dots(tex: Texture2D) -> ImageTexture:
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and c.is_equal_approx(INDICATOR_RGB):
				out.set_pixel(x, y, c)
	return ImageTexture.create_from_image(out)


func _in_hole(p: Vector2) -> bool:
	for h in holes:
		if h.has_point(p):
			return true
	return false


func _draw() -> void:
	# Fill, minus the holes: split into vertical strips at every hole edge.
	var xs: Array[float] = [0.0, size.x]
	for h in holes:
		xs.append(clampf(h.position.x, 0.0, size.x))
		xs.append(clampf(h.end.x, 0.0, size.x))
	xs.sort()
	for i in xs.size() - 1:
		var x0 := xs[i]
		var x1 := xs[i + 1]
		if x1 - x0 < 0.5:
			continue
		var mid := (x0 + x1) * 0.5
		var ys: Array[float] = [0.0, size.y]
		for h in holes:
			if mid > h.position.x and mid < h.end.x:
				ys.append(clampf(h.position.y, 0.0, size.y))
				ys.append(clampf(h.end.y, 0.0, size.y))
		ys.sort()
		for j in ys.size() - 1:
			var y0 := ys[j]
			var y1 := ys[j + 1]
			if y1 - y0 < 0.5 or _in_hole(Vector2(mid, (y0 + y1) * 0.5)):
				continue
			draw_rect(Rect2(x0, y0, x1 - x0, y1 - y0), FILL)
			if panel_width > 0:
				var first := int(floor(x0 / panel_width)) * panel_width
				for sx in range(first, int(x1) + 1, panel_width):
					if sx >= x0 and sx < x1:
						draw_line(Vector2(sx, maxf(y0, 40.0)), Vector2(sx, y1), SEAM)
						if sx + 1 < x1:
							draw_line(Vector2(sx + 1, maxf(y0, 40.0)), Vector2(sx + 1, y1), SEAM_LIT)
				if y0 <= 120.0 and y1 > 121.0:
					draw_line(Vector2(x0, 120), Vector2(x1, 120), SEAM)
					draw_line(Vector2(x0, 121), Vector2(x1, 121), SEAM_LIT)
	for w in windows:
		_draw_window(w)


func _draw_window(w: Rect2) -> void:
	var x0 := w.position.x
	var y0 := w.position.y
	var x1 := w.end.x
	var y1 := w.end.y
	# Frame bands around the opening (the opening itself stays a hole).
	draw_rect(Rect2(x0 - 6, y0 - 6, x1 - x0 + 12, 6), FRAME_DARK)
	draw_rect(Rect2(x0 - 6, y0 - 6, 6, y1 - y0 + 13), FRAME_DARK)
	draw_rect(Rect2(x1, y0 - 6, 6, y1 - y0 + 13), FRAME_DARK)
	draw_rect(Rect2(x0 - 5, y0 - 5, x1 - x0 + 10, 5), FRAME_MID)
	draw_rect(Rect2(x0 - 5, y0 - 5, 5, y1 - y0 + 10), FRAME_MID)
	draw_rect(Rect2(x1, y0 - 5, 5, y1 - y0 + 10), FRAME_MID)
	draw_line(Vector2(x0 - 5, y0 - 5), Vector2(x1 + 4, y0 - 5), FRAME_LIT)
	draw_line(Vector2(x0 - 5, y0 - 5), Vector2(x0 - 5, y1 + 5), FRAME_LIT)
	draw_rect(Rect2(x0 - 8, y1, x1 - x0 + 16, 4), FRAME_LIT)  # sill
	draw_rect(Rect2(x0 - 8, y1 + 4, x1 - x0 + 16, 1), FRAME_DARK)
	# Mullions.
	var mx := roundf((x0 + x1) * 0.5)
	draw_rect(Rect2(mx - 1, y0, 2, y1 - y0), FRAME_MID)
	draw_line(Vector2(mx - 1, y0), Vector2(mx - 1, y1), FRAME_LIT)
	var my := y0 + roundf((y1 - y0) * 0.4)
	draw_rect(Rect2(x0, my, x1 - x0, 2), FRAME_MID)
	draw_line(Vector2(x0, my), Vector2(x1, my), FRAME_LIT)
