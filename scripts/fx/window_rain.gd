@tool
class_name WindowRain
extends ColorRect
## Rain seen through a window: size the rect to the opening and draw it in
## front of the exterior backdrop, behind the window frame. Procedural (no
## particles), so it clips to the rect for free. Add it to LightningFX
## `flash_targets` and the streaks flare with each strike.

const SHADER := preload("res://shaders/window_rain.gdshader")

@export var rain_color: Color = FXPalette.RAIN:
	set(v):
		rain_color = v
		_sync()
@export_range(0.0, 2.0, 0.01) var intensity := 0.4:
	set(v):
		intensity = v
		_sync()
## Horizontal shift per pixel of fall (slant).
@export_range(-1.0, 1.0, 0.01) var wind := 0.22:
	set(v):
		wind = v
		_sync()
## Reference px per second (scaled by FXScale).
@export var speed := 220.0:
	set(v):
		speed = v
		_sync()
@export_range(0.0, 1.0, 0.01) var density := 0.5:
	set(v):
		density = v
		_sync()


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	material = mat
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync()


func _sync() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("rain_color", rain_color)
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("wind", wind)
	mat.set_shader_parameter("speed", speed)
	mat.set_shader_parameter("density", density)
	mat.set_shader_parameter("px_scale", FXScale.factor(self))
