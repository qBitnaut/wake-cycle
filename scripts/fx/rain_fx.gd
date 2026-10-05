class_name RainFX
extends Node2D
## Rain over an area. Drops are spawned along the top edge (the node's origin
## is the top centre) and die exactly at `floor_y`, where a RainSplash takes
## over. Use one RainFX per floor height.
##
## lighting:
##   SHADED      lit like the world (outdoors under the moon).
##   LIGHT_ONLY  invisible except where a light falls on it: rain through a
##               roof hole that only shows inside the moonbeam.
##   UNSHADED    flat colour, ignores the night tint.

enum Lighting { SHADED, LIGHT_ONLY, UNSHADED }

const STREAK := preload("res://assets/fx/rain_streak.png")
const MOTE_SHADER := preload("res://shaders/mote.gdshader")

@export var width := 320.0:
	set(v):
		width = v
		_apply()
@export var floor_y := 160.0:
	set(v):
		floor_y = v
		_apply()
## Drops per second per 100 px of width.
@export var density := 60.0:
	set(v):
		density = v
		_apply()
## Fall speed, reference px per second (scaled by FXScale). width and
## floor_y are world px and are not scaled.
@export var speed := 260.0:
	set(v):
		speed = v
		_apply()
## Horizontal drift, reference px per second (positive blows right).
@export var wind := 40.0:
	set(v):
		wind = v
		_apply()
@export var rain_color: Color = FXPalette.RAIN:
	set(v):
		rain_color = v
		_apply()
@export var lighting := Lighting.SHADED:
	set(v):
		lighting = v
		_apply()
@export var splash := true:
	set(v):
		splash = v
		_apply()
@export var splash_rate_scale := 0.5:
	set(v):
		splash_rate_scale = v
		_apply()

var _drops: CPUParticles2D
var _splash: RainSplash
var _intensity := 1.0


func _ready() -> void:
	_drops = CPUParticles2D.new()
	_drops.name = "Drops"
	_drops.texture = STREAK
	_drops.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_drops.spread = 0.0
	_drops.gravity = Vector2.ZERO
	_drops.particle_flag_align_y = true
	_drops.local_coords = false
	add_child(_drops)
	_splash = RainSplash.new()
	_splash.name = "Splash"
	add_child(_splash)
	_apply()


## Rain intensity multiplier (0 stops it), for weather changes. Changing it
## rebuilds the particles, so call it in coarse steps (a few per minute).
func set_intensity(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	if is_equal_approx(k, _intensity):
		return
	_intensity = k
	_apply()


func get_intensity() -> float:
	return _intensity


func _apply() -> void:
	if _drops == null:
		return
	var f := FXScale.factor(self)
	var v := Vector2(wind, speed) * f
	var life := floor_y / v.y
	_drops.lifetime = life
	_drops.preprocess = life
	_drops.direction = v.normalized()
	_drops.initial_velocity_min = v.length()
	_drops.initial_velocity_max = v.length()
	_drops.amount = maxi(int(density * width / 100.0 * life * _intensity) + 1, 1)
	_drops.emitting = _intensity > 0.01
	# Spawn upwind so the slanted rain still covers the whole floor span.
	_drops.position = Vector2(-v.x * life * 0.5, 0)
	_drops.emission_rect_extents = Vector2(width * 0.5 + absf(v.x) * life * 0.25, 0.5)
	_drops.scale_amount_min = float(FXScale.whole(self))
	_drops.scale_amount_max = _drops.scale_amount_min
	_drops.color = rain_color
	var mat: Material
	match lighting:
		Lighting.LIGHT_ONLY:
			var sm := ShaderMaterial.new()
			sm.shader = MOTE_SHADER
			mat = sm
			_drops.light_mask = LightingRig.MASK_MOTES
		Lighting.UNSHADED:
			var um := CanvasItemMaterial.new()
			um.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			mat = um
		_:
			mat = CanvasItemMaterial.new()
			_drops.light_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	_drops.material = mat
	_splash.visible = splash and _intensity > 0.01
	_splash.emitting = splash and _intensity > 0.01
	_splash.position = Vector2(0, floor_y)
	_splash.width = width
	_splash.rate = density * splash_rate_scale * _intensity
	_splash.splash_color = Color(rain_color, 0.9)
	_splash.material = mat
	_splash.light_mask = _drops.light_mask
