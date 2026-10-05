@tool
class_name LightingRig
extends Node2D
## Night lighting base for a level: one CanvasModulate night tint, one moon
## DirectionalLight2D that only gets in through roof holes and windows (tile
## occluders do the masking), and the 2D glow environment.
##
## Drop scenes/fx/lighting_rig.tscn into a level, point `solid_layers` at the
## TileMapLayers that should cast shadows, and you are done. Shadowed lights
## are the expensive ones on the web: keep about 4-6 on screen.
##
## Light mask convention (CanvasItem.light_mask / Light2D cull masks):
##   bit 1 (1)  world: tiles, props, the cat. Occluders use this bit.
##   bit 2 (2)  motes: light-only dust and rain that should show only in light.
##              Shadowed lights include it in shadow_item_cull_mask, so motes
##              under the roof stay dark.
##   bit 3 (4)  backdrop: exterior parallax, lit by lightning only.

const MASK_WORLD := 1
const MASK_MOTES := 2
const MASK_BACKDROP := 4

@export var night_tint: Color = FXPalette.NIGHT_TINT:
	set(v):
		night_tint = v
		if _modulate:
			_modulate.color = v

@export_group("Moon")
@export var moon_enabled := true:
	set(v):
		moon_enabled = v
		_apply()
@export var moon_color: Color = FXPalette.MOON:
	set(v):
		moon_color = v
		_apply()
@export_range(0.0, 4.0, 0.01) var moon_energy := 0.9:
	set(v):
		moon_energy = v
		_apply()
## Degrees from straight down. Positive: light travels to the right.
@export_range(-80.0, 80.0, 0.5) var moon_angle := 22.0:
	set(v):
		moon_angle = v
		_apply()
@export var moon_shadows := true:
	set(v):
		moon_shadows = v
		_apply()
## NONE gives hard, pixel-true shadow edges; PCF5 softens them by a pixel or two.
@export var moon_shadow_filter: Light2D.ShadowFilter = Light2D.SHADOW_FILTER_NONE:
	set(v):
		moon_shadow_filter = v
		_apply()
@export_range(0.0, 8.0, 0.1) var moon_shadow_smooth := 0.0:
	set(v):
		moon_shadow_smooth = v
		_apply()
## Off for a day sun: motes then show only in shafts and lamps, not everywhere.
@export var moon_lights_motes := true:
	set(v):
		moon_lights_motes = v
		_apply()
## Extra light-mask bits the moon (or sun) lights, e.g. a room it should not
## reach is left out by giving that room's items a bit not listed here.
@export_flags_2d_render var moon_extra_mask := 0:
	set(v):
		moon_extra_mask = v
		_apply()

@export_group("Glow")
## WorldEnvironment glow (background mode Canvas). Verified working in the
## Compatibility/WebGL2 web export with hdr_2d.
@export var glow_enabled := true:
	set(v):
		glow_enabled = v
		_apply()
@export_range(0.0, 4.0, 0.01) var glow_intensity := 0.9:
	set(v):
		glow_intensity = v
		_apply()
@export_range(0.0, 4.0, 0.01) var glow_threshold := 1.0:
	set(v):
		glow_threshold = v
		_apply()

@export_group("Vignette")
## Darkens the frame edges to pull the eye to the light pools (0 = off). Drawn
## on its own CanvasLayer under the title.
@export_range(0.0, 1.0, 0.01) var vignette := 0.35:
	set(v):
		vignette = v
		_apply()

@export_group("Shadows")
## TileMapLayers whose solid tiles cast shadows. At runtime their occluders are
## replaced by merged, edge-inset ones (see TileOccluderBaker) so lamps light
## the surfaces they shine on.
@export var solid_layers: Array[TileMapLayer] = []
## Lit rim depth in px. -1 = auto: a sixth of the tile height (3 px on
## 18 px tiles, 5 px on 32 px tiles).
@export_range(-1, 16) var occluder_inset_px := -1

var _modulate: CanvasModulate
var _moon: DirectionalLight2D
var _env: WorldEnvironment
var _vignette: ColorRect

const VIGNETTE_SHADER := preload("res://shaders/vignette.gdshader")


func _ready() -> void:
	_modulate = CanvasModulate.new()
	_modulate.name = "NightTint"
	_modulate.color = night_tint
	add_child(_modulate)
	_moon = DirectionalLight2D.new()
	_moon.name = "Moon"
	add_child(_moon)
	_env = WorldEnvironment.new()
	_env.name = "Glow"
	_env.environment = Environment.new()
	_env.environment.background_mode = Environment.BG_CANVAS
	_env.environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_env.environment.glow_bloom = 0.0
	_env.environment.glow_strength = 1.0
	for i in 7:
		_env.environment.set_glow_level(i, 1.0 if i in [0, 1, 2, 3] else 0.0)
	add_child(_env)
	var vlayer := CanvasLayer.new()
	vlayer.name = "Vignette"
	vlayer.layer = 90
	add_child(vlayer)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = VIGNETTE_SHADER
	_vignette.material = vm
	vlayer.add_child(_vignette)
	_apply()
	if not Engine.is_editor_hint():
		for layer in solid_layers:
			if layer:
				var inset := occluder_inset_px
				if inset < 0 and layer.tile_set:
					inset = maxi(roundi(layer.tile_set.tile_size.y / 6.0), 1)
				TileOccluderBaker.bake(layer, inset)


## The CanvasModulate that tints the unlit world (lightning tweens it).
## How far directional shadows are cast, in world px: 3.4x the internal
## viewport height (612 at 320x180), so it follows the resolution.
static func shadow_reach(node: Node) -> float:
	return FXScale.factor(node) * FXScale.REFERENCE_HEIGHT * 3.4


func get_canvas_modulate() -> CanvasModulate:
	return _modulate


func get_moon() -> DirectionalLight2D:
	return _moon


func get_environment() -> Environment:
	return _env.environment if _env else null


func _apply() -> void:
	if _moon == null:
		return
	_moon.enabled = moon_enabled
	_moon.color = moon_color
	_moon.energy = moon_energy
	_moon.rotation = deg_to_rad(-moon_angle)
	_moon.shadow_enabled = moon_shadows
	_moon.shadow_filter = moon_shadow_filter
	_moon.shadow_filter_smooth = moon_shadow_smooth
	_moon.shadow_color = Color(0, 0, 0, 1)
	var motes := MASK_MOTES if moon_lights_motes else 0
	_moon.range_item_cull_mask = MASK_WORLD | motes | moon_extra_mask
	_moon.shadow_item_cull_mask = MASK_WORLD | motes | moon_extra_mask
	_moon.max_distance = shadow_reach(self)
	_vignette.visible = vignette > 0.0
	(_vignette.material as ShaderMaterial).set_shader_parameter("strength", vignette)
	var env := _env.environment
	env.glow_enabled = glow_enabled
	env.glow_intensity = glow_intensity
	env.glow_hdr_threshold = glow_threshold
