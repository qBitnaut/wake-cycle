class_name NightBackdrop
extends Node2D
## Exterior night view from the ansimuz city layers, recoloured to moonlit
## blues (warm lit windows kept) and layered with Parallax2D. Seen through
## windows and the exit: draw it behind the back wall, which has holes.
##
## The node's origin is the horizon: layer bottoms sit on it.

const SHADER := preload("res://shaders/backdrop_map.gdshader")
const LAYERS := [
	# texture, scroll scale, brightness (far layers lighter: atmospheric depth)
	["res://assets/backgrounds/sky.png", 0.04, 1.9],
	["res://assets/backgrounds/far_buildings.png", 0.12, 1.0],
	["res://assets/backgrounds/buildings.png", 0.25, 0.62],
	["res://assets/backgrounds/foreground.png", 0.45, 0.4],
]
const HALO := preload("res://assets/fx/halo.png")
const MOON := preload("res://assets/fx/moon.png")

@export var brightness := 1.0:
	set(v):
		brightness = v
		_apply()
## How many repeats to draw each side; raise it for wide levels.
@export var repeat_times := 3
@export var dark := Color(0.03, 0.04, 0.09)
@export var mid := Color(0.12, 0.16, 0.30)
@export var light := Color(0.46, 0.56, 0.80)
@export var lamp := Color(1.0, 0.70, 0.38)
## A small pixel moon in the sky layer, relative to the horizon (origin).
@export var moon_visible := true
## In reference art px from the horizon (multiplied by the art scale).
@export var moon_position := Vector2(99, -107)
## Pixel scale for the 272 px ansimuz art. 0 = auto (FXScale.whole), so the
## city keeps its on-screen size at 640x360. Use 1 with HD replacement art.
@export_range(0, 8) var art_scale := 0

var _s := 1.0
@export var moon_color := Color(1.25, 1.3, 1.45)

var _mats: Array[ShaderMaterial] = []


func _ready() -> void:
	_s = float(art_scale if art_scale > 0 else FXScale.whole(self))
	for i in LAYERS.size():
		var def: Array = LAYERS[i]
		var tex: Texture2D = load(def[0])
		var px := Parallax2D.new()
		px.name = "Layer%d" % i
		px.scroll_scale = Vector2(def[1], def[1])
		px.repeat_size = Vector2(tex.get_width() * _s, 0)
		px.repeat_times = repeat_times
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.scale = Vector2(_s, _s)
		spr.position = Vector2(0, -tex.get_height() * _s)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("brightness", def[2])
		spr.material = mat
		spr.light_mask = LightingRig.MASK_BACKDROP
		_mats.append(mat)
		px.add_child(spr)
		add_child(px)
		if i == 0 and moon_visible:
			_add_moon()
	_apply()


func _add_moon() -> void:
	# Its own Parallax2D without repeat, nearly fixed to the screen.
	var px := Parallax2D.new()
	px.name = "MoonLayer"
	px.scroll_scale = Vector2(0.02, 0.02)
	add_child(px)
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
	for i in _mats.size():
		_mats[i].set_shader_parameter("flash", v * (1.0 - i * 0.18))


func _apply() -> void:
	for i in _mats.size():
		var m := _mats[i]
		m.set_shader_parameter("dark", dark)
		m.set_shader_parameter("mid", mid)
		m.set_shader_parameter("light", light)
		m.set_shader_parameter("lamp", lamp)
		m.set_shader_parameter("brightness", float(LAYERS[i][2]) * brightness)
