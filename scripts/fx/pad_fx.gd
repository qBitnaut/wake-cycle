@tool
class_name PadFX
extends Node2D
## Visual for an enhancement pad or checkpoint: a steel plate with an emissive
## strip, a soft light column, rising motes and a glow light.
##
## API: set_color(c), set_kind(kind), pulse(), set_enabled(on).
## The origin is the centre of the pad's bottom edge: put it on the floor.

const BASE := preload("res://assets/fx/pad_base.png")
const GLOW := preload("res://assets/fx/pad_glow.png")
const BEAM := preload("res://shaders/pad_beam.gdshader")
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")
const BEAM_SIZE := Vector2(18, 40)

@export var kind: FXPalette.Pad = FXPalette.Pad.SURGE:
	set(v):
		kind = v
		if not use_custom_color:
			set_color(FXPalette.pad_color(v))
## Use `custom_color` instead of the kind's palette colour.
@export var use_custom_color := false
@export var custom_color := Color.WHITE:
	set(v):
		custom_color = v
		if use_custom_color:
			set_color(v)
## Keep near 1: higher clips the hue (blue turns cyan); the 2D glow blooms it.
@export_range(0.0, 6.0, 0.05) var glow_energy := 1.3
@export_range(0.0, 4.0, 0.05) var light_energy := 0.9
@export_range(0.0, 2.0, 0.01) var beam_intensity := 0.6
@export var enabled := true:
	set(v):
		enabled = v
		_refresh()

var _color := FXPalette.SURGE
var _base: Sprite2D
var _glow: Sprite2D
var _beam: ColorRect
var _light: PointLight2D
var _motes: CPUParticles2D
var _burst: CPUParticles2D
var _boost := 0.0
var _t := 0.0


func _ready() -> void:
	_base = Sprite2D.new()
	_base.texture = BASE
	_base.centered = false
	_base.position = Vector2(-12, -7)
	add_child(_base)
	_glow = Sprite2D.new()
	_glow.texture = GLOW
	_glow.centered = false
	_glow.position = Vector2(-12, -7)
	_glow.material = _mat(false)
	add_child(_glow)
	_beam = ColorRect.new()
	_beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_beam.size = BEAM_SIZE
	_beam.position = Vector2(-BEAM_SIZE.x * 0.5, -7 - BEAM_SIZE.y)
	var bm := ShaderMaterial.new()
	bm.shader = BEAM
	bm.set_shader_parameter("rect_width", BEAM_SIZE.x)
	bm.set_shader_parameter("rect_height", BEAM_SIZE.y)
	_beam.material = bm
	add_child(_beam)
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.texture_scale = 0.85
	_light.position = Vector2(0, -7)
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	add_child(_light)
	_motes = _make_motes(7, 1.5, 7.0, 15.0)
	_burst = _make_motes(14, 0.8, 20.0, 45.0)
	_burst.one_shot = true
	_burst.explosiveness = 0.9
	_burst.emitting = false
	_t = randf() * 6.0
	if use_custom_color:
		_color = custom_color
	else:
		_color = FXPalette.pad_color(kind)
	_refresh()


## Recolour the whole pad (plate strip, beam, light, motes).
func set_color(c: Color) -> void:
	_color = c
	_refresh()


func set_kind(k: FXPalette.Pad) -> void:
	use_custom_color = false
	kind = k


## A short flare when the pad fires: light spike, brighter beam, mote burst.
func pulse() -> void:
	_boost = 1.0
	if _burst:
		_burst.restart()


## Dim the pad (spent or locked) or bring it back.
func set_enabled(on: bool) -> void:
	enabled = on


func _process(delta: float) -> void:
	if _light == null:
		return
	_t += delta
	_boost = maxf(_boost - delta * 1.8, 0.0)
	_refresh()


func _refresh() -> void:
	if _light == null:
		return
	var on := 1.0 if enabled else 0.2
	var breathe := 0.85 + 0.15 * sin(_t * 2.6)
	var b := _boost * _boost
	_glow.modulate = Color(_color * glow_energy * on * breathe * (1.0 + b * 0.8), 1.0)
	_light.color = _color
	_light.energy = light_energy * on * breathe * (1.0 + b * 3.0)
	var bm := _beam.material as ShaderMaterial
	bm.set_shader_parameter("beam_color", _color)
	bm.set_shader_parameter("intensity", beam_intensity * on * (1.0 + b * 2.5))
	_motes.color = Color(_color * 1.8, 1.0)
	_motes.emitting = enabled
	_burst.color = Color(_color * 2.2, 1.0)


func _make_motes(n: int, life: float, vmin: float, vmax: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = n
	p.lifetime = life
	p.position = Vector2(0, -7)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(8, 0.5)
	p.direction = Vector2(0, -1)
	p.spread = 8.0
	p.gravity = Vector2(0, -6)
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.material = _mat(false)
	add_child(p)
	return p


func _mat(additive: bool) -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	if additive:
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m
