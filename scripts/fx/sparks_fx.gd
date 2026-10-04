class_name SparksFX
extends Node2D
## Spark bursts from a broken cable (or anything shorting out). Pixel sparks
## with gravity, a hot-to-orange colour ramp, and a brief light flash. With
## `cable_length` > 0 it also draws the frayed cable hanging from the origin
## and bursts at its swinging tip.

signal sparked(global_pos: Vector2)

const LIGHT_TEX := preload("res://assets/fx/light_soft.png")

@export var auto := true
@export var interval_min := 0.8
@export var interval_max := 3.5
@export var color: Color = FXPalette.SPARK
@export_range(4, 64) var amount := 16
@export var cable_length := 26.0
@export var cable_color := Color(0.16, 0.17, 0.22)
@export_range(0.0, 6.0, 0.1) var flash_energy := 1.6

var _particles: CPUParticles2D
var _light: PointLight2D
var _t := 0.0
var _next := 1.0
var _flash := 0.0


func _ready() -> void:
	_particles = CPUParticles2D.new()
	_particles.emitting = false
	_particles.one_shot = true
	_particles.explosiveness = 0.9
	_particles.amount = amount
	_particles.lifetime = 0.7
	_particles.local_coords = false
	_particles.direction = Vector2(0, 1)
	_particles.spread = 75.0
	_particles.gravity = Vector2(0, 320)
	_particles.initial_velocity_min = 30.0
	_particles.initial_velocity_max = 95.0
	_particles.damping_min = 10.0
	_particles.damping_max = 30.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(3.0, 2.8, 2.2, 1.0))
	ramp.add_point(0.25, Color(color.r * 2.2, color.g * 1.8, color.b * 1.2, 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.3, 0.05, 0.0))
	_particles.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_particles.material = mat
	add_child(_particles)
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.texture_scale = 1.3
	_light.color = color
	_light.energy = 0.0
	_light.enabled = false
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	add_child(_light)
	_next = randf_range(0.3, interval_max)


## Fire a burst now.
func burst(strength := 1.0) -> void:
	var tip := _tip()
	_particles.position = tip
	_light.position = tip
	_particles.amount = maxi(int(amount * strength), 2)
	_particles.restart()
	_flash = strength
	sparked.emit(to_global(tip))


func _process(delta: float) -> void:
	_t += delta
	if auto:
		_next -= delta
		if _next <= 0.0:
			burst(randf_range(0.6, 1.0))
			# Shorts come in clusters.
			_next = randf_range(0.08, 0.2) if randf() < 0.35 else randf_range(interval_min, interval_max)
	_flash = maxf(_flash - delta * 7.0, 0.0)
	_light.energy = flash_energy * _flash * (0.7 + 0.3 * randf())
	_light.enabled = _flash > 0.01
	if cable_length > 0.0:
		queue_redraw()


func _tip() -> Vector2:
	if cable_length <= 0.0:
		return Vector2.ZERO
	var sway := sin(_t * 1.3) * 2.0 + sin(_t * 3.1) * 0.6
	return Vector2(roundf(sway), cable_length)


func _draw() -> void:
	if cable_length <= 0.0:
		return
	var tip := _tip()
	var prev := Vector2.ZERO
	var steps := int(cable_length / 3.0)
	for i in range(1, steps + 1):
		var f := float(i) / steps
		var p := Vector2(roundf(tip.x * f * f), roundf(cable_length * f))
		draw_line(prev, p, cable_color, 1.0)
		draw_line(prev + Vector2(1, 0), p + Vector2(1, 0), cable_color.darkened(0.3), 1.0)
		prev = p
	# Frayed copper ends.
	draw_rect(Rect2(tip + Vector2(-1, 0), Vector2(1, 2)), Color(0.75, 0.45, 0.2))
	draw_rect(Rect2(tip + Vector2(1, 0), Vector2(1, 2)), Color(0.65, 0.38, 0.18))
