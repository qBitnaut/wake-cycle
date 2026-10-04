@tool
class_name FogLayer
extends Parallax2D
## A drifting fog band on its own parallax plane. Stack two or three: one
## behind the action (scroll_scale < 1, denser, darker) and a thin one in front
## (scroll_scale > 1). Noise comes from the baked assets/fx/fog_noise.png.
##
## The band's top-left is the node origin; it repeats horizontally forever.

const SHADER := preload("res://shaders/fog.gdshader")
const NOISE := preload("res://assets/fx/fog_noise.png")

@export var band_width := 512.0:
	set(v):
		band_width = v
		_apply()
@export var band_height := 48.0:
	set(v):
		band_height = v
		_apply()
@export var fog_color: Color = FXPalette.FOG:
	set(v):
		fog_color = v
		_apply()
## Fog is lit like the world, so under a dark night tint it needs to be
## brighter than 1 to read as haze; in a light pool it then glows.
@export_range(0.0, 6.0, 0.05) var brightness := 2.4:
	set(v):
		brightness = v
		_apply()
@export_range(0.0, 1.0, 0.01) var density := 0.45:
	set(v):
		density = v
		_apply()
## Drift in px per second.
@export var drift := Vector2(5.0, 0.0):
	set(v):
		drift = v
		_apply()
@export_range(0.25, 4.0, 0.05) var noise_scale := 1.0:
	set(v):
		noise_scale = v
		_apply()
## Fraction of the band height that fades in from the top and out at the bottom.
@export_range(0.0, 1.0, 0.01) var fade_top := 0.6:
	set(v):
		fade_top = v
		_apply()
@export_range(0.0, 1.0, 0.01) var fade_bottom := 0.15:
	set(v):
		fade_bottom = v
		_apply()
## >0 posterises the fog into that many density steps (retro banding).
@export_range(0, 8) var steps := 0:
	set(v):
		steps = v
		_apply()
var _rect: ColorRect


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.name = "Fog"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("noise", NOISE)
	_rect.material = mat
	add_child(_rect)
	_apply()


func _apply() -> void:
	if _rect == null:
		return
	_rect.size = Vector2(band_width, band_height)
	repeat_size = Vector2(band_width, 0)
	repeat_times = 2
	var mat := _rect.material as ShaderMaterial
	mat.set_shader_parameter("fog_color", fog_color)
	mat.set_shader_parameter("density", density)
	mat.set_shader_parameter("brightness", brightness)
	mat.set_shader_parameter("scroll", drift)
	mat.set_shader_parameter("noise_scale", noise_scale)
	mat.set_shader_parameter("rect_width", band_width)
	mat.set_shader_parameter("rect_height", band_height)
	mat.set_shader_parameter("repeats", maxf(roundf(band_width / 256.0), 1.0))
	mat.set_shader_parameter("fade_top", fade_top)
	mat.set_shader_parameter("fade_bottom", fade_bottom)
	mat.set_shader_parameter("steps", float(steps))
	_rect.light_mask = LightingRig.MASK_WORLD
