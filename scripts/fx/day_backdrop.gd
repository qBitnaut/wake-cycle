class_name DayBackdrop
extends Node2D
## The morning sky for the Home ending, the day counterpart of NightBackdrop:
## a banded clear-blue sky, the low sun on the right with its halo (HDR, so
## the 2D glow blooms it), a faint rainbow over the way the cat came, slow
## clouds, and two parallax bands of distance (hazy hills, then rooftops and
## trees). Art by tools/art/home_art.py. Everything here is unshaded: the
## day CanvasModulate and the sun light the world, not the sky.
##
## The sky, sun, rainbow and clouds are pinned to the view in both axes, so they cover a room
## of any height; the hill and tree bands sit on the horizon (the node's origin).
## Parallax by hand, as in NightBackdrop: a layer with scroll s moves at s of
## the camera, so it is shifted by (1 - s) of the camera position. The node's
## origin is the horizon (the band bottoms sit on it); the sky and the sun are
## pinned to the view.

const DIR := "res://assets/art_hd/home/"
const HALO := preload("res://assets/fx/halo.png")
const SOFT := preload("res://assets/fx/light_soft.png")

## The sun's centre in view px (640x360).
@export var sun_view_pos := Vector2(548, 78)
@export var sun_color := Color(1.75, 1.62, 1.32)
@export var halo_color := Color(0.75, 0.55, 0.28)
## The rainbow's foot-to-foot centre in view px at the level's start; it
## drifts left as the cat walks on (scroll `rainbow_scroll`).
@export var rainbow_view_pos := Vector2(170, 66)
@export_range(0.0, 1.0, 0.01) var rainbow_alpha := 0.4
@export_range(0.0, 1.0, 0.01) var rainbow_scroll := 0.3
## Clouds drift left this fast (view px/s) on top of their parallax.
@export var wind := 2.2

const CLOUDS := [
	# texture, view x, view y, scroll
	["cloud_c.png", 300.0, 52.0, 0.05],
	["cloud_b.png", 40.0, 104.0, 0.07],
	["cloud_a.png", 690.0, 30.0, 0.04],
	["cloud_d.png", 520.0, 140.0, 0.08],
	["cloud_b.png", 960.0, 96.0, 0.06],
]
const CLOUD_SPAN := 1180.0  # clouds wrap round this many view px

var _sky: Sprite2D
var _sun: Node2D
var _rainbow: Sprite2D
var _clouds: Array = []     # [Sprite2D, base x, y, scroll]
var _bands: Array = []      # [holder, Sprite2D, scroll]
var _t := 0.0
var _unshaded: CanvasItemMaterial
var _add: CanvasItemMaterial


func _ready() -> void:
	_unshaded = CanvasItemMaterial.new()
	_unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_add = CanvasItemMaterial.new()
	_add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sky = _sprite("sky.png")
	_sky.name = "Sky"
	add_child(_sky)
	_build_sun()
	_rainbow = _sprite("rainbow.png")
	_rainbow.name = "Rainbow"
	_rainbow.modulate = Color(1, 1, 1, rainbow_alpha)
	add_child(_rainbow)
	for def in CLOUDS:
		var c := _sprite(def[0])
		c.name = "Cloud%d" % _clouds.size()
		add_child(c)
		_clouds.append([c, def[1], def[2], def[3]])
	_band("hills.png", 0.10, -2.0)
	_band("treeline.png", 0.28, 4.0)
	_scroll()


func _sprite(file: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(DIR + file)
	s.centered = false
	s.material = _unshaded
	s.light_mask = 0
	return s


func _build_sun() -> void:
	_sun = Node2D.new()
	_sun.name = "Sun"
	add_child(_sun)
	var wide := Sprite2D.new()
	wide.texture = SOFT
	wide.scale = Vector2(5.5, 5.5)
	wide.modulate = Color(halo_color * 0.55, 1.0)
	wide.material = _add
	_sun.add_child(wide)
	var halo := Sprite2D.new()
	halo.texture = HALO
	halo.scale = Vector2(1.6, 1.6)
	halo.modulate = Color(halo_color, 1.0)
	halo.material = _add
	_sun.add_child(halo)
	var disc := _sprite("sun.png")
	disc.centered = true
	disc.modulate = sun_color
	_sun.add_child(disc)


## A tiled horizontal band whose bottom sits `drop` px below the horizon.
func _band(file: String, scroll: float, drop: float) -> void:
	var holder := Node2D.new()
	holder.name = file.get_basename().capitalize().replace(" ", "")
	var s := _sprite(file)
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.region_enabled = true
	s.position.y = drop - s.texture.get_height()
	holder.add_child(s)
	add_child(holder)
	_bands.append([holder, s, scroll])


func _process(delta: float) -> void:
	_t += delta
	_scroll()


func _scroll() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var c := cam.get_screen_center_position()
	var view := get_viewport_rect().size
	var tl := c - view * 0.5   # the view's top-left in world px
	_sky.global_position = Vector2(roundf(tl.x), roundf(tl.y))
	_sun.global_position = (tl + sun_view_pos).round()
	var start_cam := view.x * 0.5  # the camera centre at the level's start
	_rainbow.global_position = (tl + rainbow_view_pos - Vector2(_rainbow.texture.get_width() * 0.5, 0)
		- Vector2((c.x - start_cam) * rainbow_scroll, 0)).round()
	for cl in _clouds:
		var spr: Sprite2D = cl[0]
		var x: float = cl[1] - c.x * cl[3] - _t * wind
		x = fposmod(x + 200.0, CLOUD_SPAN) - 200.0
		spr.global_position = Vector2(roundf(tl.x + x), roundf(tl.y + cl[2]))
	for b in _bands:
		var holder: Node2D = b[0]
		var spr: Sprite2D = b[1]
		var sc: float = b[2]
		var tw := float(spr.texture.get_width())
		holder.position.x = roundf(c.x * (1.0 - sc))
		spr.region_rect = Rect2(0, 0, view.x + tw * 2.0, spr.texture.get_height())
		spr.position.x = floorf((c.x * sc - view.x * 0.5) / tw) * tw
