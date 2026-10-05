@tool
class_name Puddle
extends ColorRect
## Reflective puddle. Place the rect so its top edge is the water line on the
## floor; it mirrors whatever is drawn above it (screen texture), with ripples
## and a dark water tint. Call ripple() when something drips or steps in it.
##
## Draw order matters: the puddle reflects only what was drawn before it, so
## give it a z_index above the level and the cat.

const SHADER := preload("res://shaders/puddle.gdshader")
const NOISE := preload("res://assets/fx/noise_small.png")
const MAX_RIPPLES := 4

@export var water_tint := Color(0.12, 0.16, 0.28, 1.0):
	set(v):
		water_tint = v
		_sync()
@export_range(0.0, 1.0, 0.01) var reflectivity := 0.9:
	set(v):
		reflectivity = v
		_sync()
## Wobble and edge softness are in reference (320x180) px, scaled by FXScale.
@export_range(0.0, 4.0, 0.05) var wave_amp := 0.6:
	set(v):
		wave_amp = v
		_sync()
@export_range(0.0, 40.0, 0.5) var edge_fade := 10.0:
	set(v):
		edge_fade = v
		_sync()
## 1 = an exact mirror; higher reaches further up the screen (shows the sky).
@export_range(1.0, 12.0, 0.1) var reflect_scale := 1.0:
	set(v):
		reflect_scale = v
		_sync()
## The bright line and ripple rings.
@export var highlight := Color(0.62, 0.74, 1.0):
	set(v):
		highlight = v
		_sync()

var _ripples: Array[Vector3] = []


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("noise", NOISE)
	material = mat
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_sync)
	_sync()


## Start a ripple ring at a global x position. `strength` 0..1.
func ripple(global_x: float, strength := 1.0) -> void:
	var local_x := global_x - global_position.x
	if _ripples.size() >= MAX_RIPPLES:
		_ripples.pop_front()
	_ripples.append(Vector3(local_x, 0.0, strength))


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or material == null:
		return
	var out := PackedVector3Array()
	var i := 0
	while i < _ripples.size():
		var r := _ripples[i]
		r.y += delta
		if r.y > 1.2:
			_ripples.remove_at(i)
			continue
		_ripples[i] = r
		out.append(r)
		i += 1
	while out.size() < MAX_RIPPLES:
		out.append(Vector3.ZERO)
	(material as ShaderMaterial).set_shader_parameter("ripples", out)


func _sync() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("water_tint", water_tint)
	mat.set_shader_parameter("reflectivity", reflectivity)
	mat.set_shader_parameter("wave_amp", wave_amp)
	mat.set_shader_parameter("edge_fade", edge_fade)
	mat.set_shader_parameter("rect_width", size.x)
	mat.set_shader_parameter("rect_height", size.y)
	mat.set_shader_parameter("px_scale", FXScale.factor(self))
	mat.set_shader_parameter("reflect_scale", reflect_scale)
	mat.set_shader_parameter("highlight", highlight)
