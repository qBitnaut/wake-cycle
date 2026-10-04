@tool
class_name GooPool
extends Node2D
## Nanotech goo pool: a dark oily strip with circuit traces pulsing blue and
## green, a glow light that breathes between the two, and slow bubbles.
## The origin is the pool's top-left (the surface line).

const SHADER := preload("res://shaders/goo_pool.gdshader")
const NOISE := preload("res://assets/fx/noise_small.png")
const CIRCUIT := preload("res://assets/fx/goo_circuit.png")
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")

@export var width := 72.0:
	set(v):
		width = v
		_apply()
@export var depth := 14.0:
	set(v):
		depth = v
		_apply()
@export var color_a: Color = FXPalette.NANO_BLUE:
	set(v):
		color_a = v
		_apply()
@export var color_b: Color = FXPalette.NANO_GREEN:
	set(v):
		color_b = v
		_apply()
## Keep near 1: higher clips the hue towards white; the 2D glow adds the bloom.
@export_range(0.0, 6.0, 0.05) var trace_energy := 1.4:
	set(v):
		trace_energy = v
		_apply()
@export_range(0.0, 6.0, 0.05) var light_energy := 2.0
@export var bubbles := true

var _rect: ColorRect
var _light: PointLight2D
var _bubbles: CPUParticles2D
var _t := 0.0
var _surge := 0.0


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("noise", NOISE)
	mat.set_shader_parameter("circuit", CIRCUIT)
	_rect.material = mat
	add_child(_rect)
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	add_child(_light)
	_bubbles = CPUParticles2D.new()
	_bubbles.amount = 6
	_bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_bubbles.direction = Vector2(0, -1)
	_bubbles.spread = 5.0
	_bubbles.gravity = Vector2.ZERO
	_bubbles.initial_velocity_min = 3.0
	_bubbles.initial_velocity_max = 6.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.3, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	_bubbles.color_ramp = ramp
	var bm := CanvasItemMaterial.new()
	bm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_bubbles.material = bm
	add_child(_bubbles)
	_apply()


## Flare the pool (0..1), e.g. when the cat steps in. Decays on its own.
func surge(amount := 1.0) -> void:
	_surge = clampf(maxf(_surge, amount), 0.0, 1.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _light == null:
		return
	_t += delta
	_surge = maxf(_surge - delta * 0.8, 0.0)
	var k := 0.5 + 0.5 * sin(_t * 0.9)
	_light.color = color_a.lerp(color_b, k)
	_light.energy = light_energy * (0.8 + 0.2 * sin(_t * 2.3)) * (1.0 + _surge * 1.5)
	(_rect.material as ShaderMaterial).set_shader_parameter("surge", _surge)
	_bubbles.color = Color(color_a.lerp(color_b, 1.0 - k) * 1.8, 1.0)


func _apply() -> void:
	if _rect == null:
		return
	_rect.size = Vector2(width, depth)
	var mat := _rect.material as ShaderMaterial
	mat.set_shader_parameter("color_a", color_a)
	mat.set_shader_parameter("color_b", color_b)
	mat.set_shader_parameter("glow_energy", trace_energy)
	mat.set_shader_parameter("rect_width", width)
	mat.set_shader_parameter("rect_height", depth)
	_light.position = Vector2(width * 0.5, -2)
	_light.texture_scale = maxf(width / 128.0 * 2.2, 0.6)
	_light.color = color_a
	_light.energy = light_energy
	_bubbles.position = Vector2(width * 0.5, depth * 0.8)
	_bubbles.emission_rect_extents = Vector2(width * 0.42, 1)
	_bubbles.lifetime = maxf(depth * 0.8 / 4.5, 0.4)
	_bubbles.emitting = bubbles
