@tool
class_name MoonShaft
extends Node2D
## A shaft of moonlight through a roof hole or window: an additive god-ray
## quad with scrolling noise streaks, a cone-textured PointLight2D, and dust
## motes that only show where light actually falls on them.
##
## The node's origin is the opening (top centre of the shaft). The shaft runs
## `length` px down, leaning `angle` degrees (positive leans right).

const RAY_SHADER := preload("res://shaders/god_ray.gdshader")
const NOISE := preload("res://assets/fx/noise_small.png")
const CONE := preload("res://assets/fx/light_cone.png")
const MOTE_SHADER := preload("res://shaders/mote.gdshader")
const HALO := preload("res://assets/fx/halo.png")

@export var length := 140.0:
	set(v):
		length = v
		_rebuild()
@export var top_width := 26.0:
	set(v):
		top_width = v
		_rebuild()
@export var bottom_width := 54.0:
	set(v):
		bottom_width = v
		_rebuild()
@export_range(-60.0, 60.0, 0.5) var angle := 18.0:
	set(v):
		angle = v
		_rebuild()
@export var color: Color = FXPalette.MOON_RAY:
	set(v):
		color = v
		_rebuild()

@export_group("Ray")
@export_range(0.0, 2.0, 0.01) var ray_intensity := 0.32:
	set(v):
		ray_intensity = v
		_rebuild()
@export_range(0.0, 1.0, 0.01) var ray_flicker := 0.0:
	set(v):
		ray_flicker = v
		_rebuild()

## Soft additive pool where the shaft meets the floor (0 = off).
@export_range(0.0, 2.0, 0.01) var floor_glow := 0.35:
	set(v):
		floor_glow = v
		_rebuild()

@export_group("Light")
@export var light_enabled := true:
	set(v):
		light_enabled = v
		_rebuild()
@export_range(0.0, 6.0, 0.01) var light_energy := 1.2:
	set(v):
		light_energy = v
		_rebuild()
## Shadowed lights are costly on the web; the moon DirectionalLight2D usually
## already shades the room, so this is off by default.
@export var light_shadows := false:
	set(v):
		light_shadows = v
		_rebuild()
## Whether the light also reveals light-only motes (dust, hole rain). Turn it
## off for weak spill shafts so motes appear only in the main beams.
@export var light_motes := true:
	set(v):
		light_motes = v
		_rebuild()

@export_group("Dust")
@export_range(0, 200) var dust_amount := 40:
	set(v):
		dust_amount = v
		_rebuild()
@export var dust_color := Color(1.6, 1.7, 2.0):
	set(v):
		dust_color = v
		_rebuild()

var _ray: Polygon2D
var _light: PointLight2D
var _dust: CPUParticles2D
var _pool: Sprite2D


func _ready() -> void:
	_ray = Polygon2D.new()
	_ray.name = "Ray"
	var mat := ShaderMaterial.new()
	mat.shader = RAY_SHADER
	mat.set_shader_parameter("noise", NOISE)
	_ray.material = mat
	add_child(_ray)
	_pool = Sprite2D.new()
	_pool.name = "FloorGlow"
	_pool.texture = HALO
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	pm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_pool.material = pm
	add_child(_pool)
	_light = PointLight2D.new()
	_light.name = "Light"
	_light.texture = CONE
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	add_child(_light)
	_dust = CPUParticles2D.new()
	_dust.name = "Dust"
	var lm := ShaderMaterial.new()
	lm.shader = MOTE_SHADER
	_dust.material = lm
	_dust.light_mask = LightingRig.MASK_MOTES
	_dust.lifetime = 7.0
	_dust.preprocess = 7.0
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.direction = Vector2(1, 0)
	_dust.spread = 180.0
	_dust.gravity = Vector2(0.4, 0.8)
	_dust.initial_velocity_min = 0.5
	_dust.initial_velocity_max = 3.0
	_dust.damping_min = 0.1
	_dust.damping_max = 0.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	_dust.color_ramp = ramp
	add_child(_dust)
	_rebuild()


## Brighten or dim the whole shaft (ray and light) at once, e.g. clouds passing.
func set_strength(s: float) -> void:
	if _ray == null:
		return
	(_ray.material as ShaderMaterial).set_shader_parameter("intensity", ray_intensity * s)
	_light.energy = light_energy * s
	_pool.modulate = Color(color * floor_glow * s, 1.0)


func _rebuild() -> void:
	if _ray == null:
		return
	var lean := tan(deg_to_rad(angle)) * length
	var ht := top_width * 0.5
	var hb := bottom_width * 0.5
	_ray.polygon = PackedVector2Array([
		Vector2(-ht, 0), Vector2(ht, 0), Vector2(lean + hb, length), Vector2(lean - hb, length)])
	_ray.uv = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var mat := _ray.material as ShaderMaterial
	mat.set_shader_parameter("ray_color", color)
	mat.set_shader_parameter("intensity", ray_intensity)
	mat.set_shader_parameter("flicker", ray_flicker)
	# Cone light: the texture's apex is its top centre, so offset it down by
	# half its height and lean it with the shaft. Uniform scale only: a
	# non-uniform scale on a rotated Light2D shears its texture.
	_light.enabled = light_enabled
	_light.color = color.lerp(Color.WHITE, 0.25)
	_light.energy = light_energy
	_light.shadow_enabled = light_shadows
	_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	_light.shadow_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | (LightingRig.MASK_MOTES if light_motes else 0)
	var tex_h := float(CONE.get_height())
	_light.texture_scale = length * 1.08 / tex_h
	_light.offset = Vector2(0, tex_h * 0.5)
	_light.rotation = deg_to_rad(-angle)
	_light.scale = Vector2.ONE
	_pool.visible = floor_glow > 0.0
	_pool.position = Vector2(lean, length - 2.0)
	_pool.scale = Vector2(bottom_width * 1.5, 14.0) / float(HALO.get_width())
	_pool.modulate = Color(color * floor_glow, 1.0)
	_dust.amount = maxi(dust_amount, 1)
	_dust.emitting = dust_amount > 0
	_dust.visible = dust_amount > 0
	_dust.color = dust_color
	_dust.position = Vector2(lean * 0.5, length * 0.5)
	_dust.emission_rect_extents = Vector2(maxf(top_width, bottom_width) * 0.5 + absf(lean) * 0.5, length * 0.5)
