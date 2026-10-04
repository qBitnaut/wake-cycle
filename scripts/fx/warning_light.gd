class_name WarningLight
extends Node2D
## A failing sodium warning lamp: the Kenney beacon housing, an emissive glass
## dome pushed into HDR, an additive halo, and a shadow-casting PointLight2D.
## The origin is the centre of the 18x18 beacon tile.

enum Mode { FLICKER, PULSE, STEADY, ROTATE }

const BASE := preload("res://assets/fx/beacon_base.png")
const GLASS := preload("res://assets/fx/beacon_glass.png")
const HALO := preload("res://assets/fx/halo.png")
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")

@export var color: Color = FXPalette.SODIUM:
	set(v):
		color = v
		_level_changed()
@export var mode := Mode.FLICKER
@export_range(0.0, 8.0, 0.05) var energy := 1.3
@export_range(0.25, 8.0, 0.05) var light_radius_scale := 1.5:
	set(v):
		light_radius_scale = v
		if _light:
			_light.texture_scale = v
## Keep near 1: higher clips sodium orange to yellow; the 2D glow blooms it.
@export_range(0.0, 6.0, 0.05) var glass_energy := 1.15
@export_range(0.0, 2.0, 0.01) var halo_strength := 0.45
@export var shadows := true
## Let the lamp reveal light-only motes (dust, hole rain). Off by default so
## dust reads only inside the moon shafts.
@export var lights_motes := false
@export var on := true:
	set(v):
		on = v
		_level_changed()

var _base: Sprite2D
var _glass: Sprite2D
var _halo: Sprite2D
var _light: PointLight2D
var _t := 0.0
var _level := 1.0
var _stutter := 0.0
var _next_stutter := 2.0


func _ready() -> void:
	_base = Sprite2D.new()
	_base.texture = BASE
	add_child(_base)
	_glass = Sprite2D.new()
	_glass.texture = GLASS
	_glass.material = _unshaded()
	add_child(_glass)
	_halo = Sprite2D.new()
	_halo.texture = HALO
	_halo.position = Vector2(0, 1)
	_halo.scale = Vector2(0.9, 0.9)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_halo.material = add
	add_child(_halo)
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.texture_scale = light_radius_scale
	_light.position = Vector2(0, 1)
	_light.shadow_enabled = shadows
	_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	_light.shadow_filter_smooth = 1.5
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | (LightingRig.MASK_MOTES if lights_motes else 0)
	_light.shadow_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	add_child(_light)
	_t = randf() * 10.0
	_level_changed()


func _process(delta: float) -> void:
	_t += delta
	var l := 1.0
	match mode:
		Mode.FLICKER:
			# Mostly on with a faint mains hum; every few seconds it stutters.
			l = 0.92 + 0.08 * sin(_t * 31.0) * sin(_t * 7.0)
			_next_stutter -= delta
			if _next_stutter <= 0.0:
				_stutter = randf_range(0.25, 0.7)
				_next_stutter = randf_range(1.5, 5.0)
			if _stutter > 0.0:
				_stutter -= delta
				l = 0.08 if fmod(_t * 17.0 + sin(_t * 41.0), 1.0) < 0.55 else 0.85
		Mode.PULSE:
			l = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(_t * 3.2), 2.0)
		Mode.ROTATE:
			l = 0.25 + 0.75 * pow(maxf(sin(_t * 5.0), 0.0), 3.0)
	_level = l if on else 0.0
	_level_changed()


func _level_changed() -> void:
	if _light == null:
		return
	var lv := _level if on else 0.0
	_light.color = color
	_light.energy = energy * lv
	_light.enabled = lv > 0.01
	_glass.modulate = Color(color * lerpf(0.3, glass_energy, lv), 1.0)
	_halo.modulate = Color(color * halo_strength * lv, 1.0)


func _unshaded() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m
