class_name NightBackdrop
extends Node2D
## Exterior night view from the ansimuz Warped City layers (harmonised to the
## Wake Cycle palette by tools/art/harmonize_bg.py) layered with a small camera-driven parallax (each layer
## shifts by (1 - scroll scale) of the camera and tiles sideways to fill the view).
## Seen through windows and skylights: draw it behind the back wall, which has
## holes. The layers are drawn at 1:1 (HD art).
##
## The node's origin is the horizon: layer bottoms sit on it.

const LAYERS := [
	# texture, scroll scale, brightness (far layers lighter: atmospheric depth)
	["res://assets/art_hd/bg/sky.png", 0.04, 1.0],
	["res://assets/art_hd/bg/towers.png", 0.12, 1.0],
]
const HALO := preload("res://assets/fx/halo.png")
const MOON := preload("res://assets/fx/moon.png")

@export var brightness := 1.0:
	set(v):
		brightness = v
		_apply()
## A small pixel moon in the sky layer, relative to the horizon (origin).
@export var moon_visible := true
## In reference art px from the horizon (multiplied by the art scale).
@export var moon_position := Vector2(99, -107)
## Pixel scale for the layer art. 1 = HD art at 1:1 (0 = auto FXScale.whole,
## for the old 272 px art at 640x360).
@export_range(0, 8) var art_scale := 1

var _s := 1.0
@export var moon_color := Color(1.25, 1.3, 1.45)

var _layers: Array[Sprite2D] = []
var _holders: Array[Node2D] = []
var _moon_holder: Node2D
var _flash := 0.0
const MOON_SCROLL := 0.02


func _ready() -> void:
	_s = float(art_scale if art_scale > 0 else FXScale.whole(self))
	for i in LAYERS.size():
		var def: Array = LAYERS[i]
		var tex: Texture2D = load(def[0])
		var holder := Node2D.new()
		holder.name = "Layer%d" % i
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.scale = Vector2(_s, _s)
		spr.position = Vector2(0, -tex.get_height() * _s)
		spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		spr.region_enabled = true
		spr.light_mask = LightingRig.MASK_BACKDROP
		_layers.append(spr)
		_holders.append(holder)
		holder.add_child(spr)
		add_child(holder)
		if i == 0 and moon_visible:
			_add_moon()
	_apply()
	_scroll()


func _process(_delta: float) -> void:
	_scroll()


## Parallax by hand: a layer with scroll scale s moves at s of the camera, so it
## is shifted by (1 - s) of the camera position, and tiled to cover the view.
func _scroll() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null or _layers.is_empty():
		return
	var c := cam.get_screen_center_position()
	var view_w := get_viewport_rect().size.x
	for i in _layers.size():
		var sc: float = LAYERS[i][1]
		var spr := _layers[i]
		var tw := float(spr.texture.get_width()) * _s
		_holders[i].position.x = roundf(c.x * (1.0 - sc))
		spr.region_rect = Rect2(0, 0, (view_w + tw * 2.0) / _s, spr.texture.get_height())
		spr.position.x = floorf((c.x * sc - view_w * 0.5) / tw) * tw
	if _moon_holder:
		_moon_holder.position.x = roundf(c.x * (1.0 - MOON_SCROLL))


func _add_moon() -> void:
	# Its own holder without repeat, nearly fixed to the screen.
	_moon_holder = Node2D.new()
	_moon_holder.name = "MoonLayer"
	add_child(_moon_holder)
	var px := _moon_holder
	var halo := Sprite2D.new()
	halo.texture = HALO
	halo.position = moon_position * _s
	halo.scale = Vector2(0.9, 0.9) * _s
	halo.modulate = Color(0.35, 0.42, 0.62)
	var am := CanvasItemMaterial.new()
	am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	am.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	halo.material = am
	px.add_child(halo)
	var disc := Sprite2D.new()
	disc.name = "Moon"
	disc.texture = MOON
	disc.position = moon_position * _s
	disc.scale = Vector2(_s, _s)
	disc.modulate = moon_color
	var um := CanvasItemMaterial.new()
	um.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	disc.material = um
	px.add_child(disc)


## 0..1 lightning brightness (LightningFX drives this).
func set_flash(v: float) -> void:
	_flash = v
	_apply()


func _apply() -> void:
	for i in _layers.size():
		var b := float(LAYERS[i][2]) * brightness * (1.0 + _flash * (2.0 - i * 0.6))
		_layers[i].modulate = Color(b, b, b)
