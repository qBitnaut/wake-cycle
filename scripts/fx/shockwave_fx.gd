class_name ShockwaveFX
extends Node2D
## Ground-pound shockwave: an expanding ring that refracts the screen, a light
## flash, a dust puff and a camera shake. Frees itself when done.
##
##     ShockwaveFX.spawn(level, cat.global_position, 56.0, FXPalette.IMPACT)
##
## `pos` is a global position. Draw order: it refracts what is drawn before
## it, so the default z_index sits above the level.

signal finished

const SHADER := preload("res://shaders/shockwave.gdshader")
const PUFFS := preload("res://assets/fx/puff_sheet.png")
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")

@export var radius := 48.0
@export var color: Color = FXPalette.IMPACT
@export var duration := 0.55
## 1 = circle, lower squashes the ring along the ground.
@export_range(0.1, 1.0, 0.01) var flatten := 0.5
@export_range(0.0, 1.0, 0.01) var shake_strength := 0.55
@export var dust := true

var _ring: ColorRect
var _light: PointLight2D
var _puff: CPUParticles2D


## Spawn and play a shockwave under `parent` at global `pos`.
static func spawn(parent: Node, pos: Vector2, radius_px := 48.0, ring_color: Color = FXPalette.IMPACT, shake := 0.55) -> ShockwaveFX:
	var fx := ShockwaveFX.new()
	fx.radius = radius_px
	fx.color = ring_color
	fx.shake_strength = shake
	parent.add_child(fx)
	fx.global_position = pos
	return fx


func _ready() -> void:
	z_index = 50
	# Fresh copy of the screen under the ring, so it refracts everything drawn
	# so far (not a stale copy made earlier in the frame).
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_RECT
	bbc.rect = Rect2(-Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	add_child(bbc)
	_ring = ColorRect.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.size = Vector2.ONE * radius * 2.0
	_ring.position = -_ring.size * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("ring_color", color)
	mat.set_shader_parameter("rect_size", radius * 2.0)
	mat.set_shader_parameter("flatten", flatten)
	mat.set_shader_parameter("progress", 0.0)
	_ring.material = mat
	add_child(_ring)
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.texture_scale = radius / 48.0
	_light.color = color
	_light.energy = 2.5
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	add_child(_light)
	if dust:
		_puff = CPUParticles2D.new()
		_puff.texture = PUFFS
		var pm := CanvasItemMaterial.new()
		pm.particles_animation = true
		pm.particles_anim_h_frames = 5
		pm.particles_anim_v_frames = 1
		_puff.material = pm
		_puff.anim_speed_min = 1.0
		_puff.anim_speed_max = 1.0
		_puff.one_shot = true
		_puff.explosiveness = 0.95
		_puff.amount = 12
		_puff.lifetime = 0.7
		_puff.direction = Vector2(0, -1)
		_puff.spread = 80.0
		_puff.gravity = Vector2(0, 20)
		_puff.initial_velocity_min = radius * 0.6
		_puff.initial_velocity_max = radius * 1.4
		_puff.damping_min = radius * 1.4
		_puff.damping_max = radius * 2.0
		_puff.color = Color(0.72, 0.76, 0.86, 0.7)
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
		_puff.color_ramp = ramp
		add_child(_puff)
		_puff.emitting = true
	var tw := create_tween()
	tw.tween_method(_set_progress, 0.0, 1.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(0.25)
	tw.tween_callback(_done)
	if shake_strength > 0.0:
		ScreenShake.shake_at(self, shake_strength, 0.35)


func _set_progress(p: float) -> void:
	(_ring.material as ShaderMaterial).set_shader_parameter("progress", p)
	_light.energy = 2.5 * pow(1.0 - p, 2.0)
	_light.enabled = p < 0.98


func _done() -> void:
	finished.emit()
	queue_free()
