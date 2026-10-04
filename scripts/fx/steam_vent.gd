class_name SteamVent
extends Node2D
## Steam from a vent or broken pipe. Puffs grow by swapping frames in a baked
## strip (no scaling, so pixels stay square) and are lit by nearby lamps.
## With `cycle_on` and `cycle_off` > 0 it vents on a timer and can double as a
## hazard visual: listen to `vent_started` / `vent_stopped` to arm a hurt area.

signal vent_started
signal vent_stopped

const PUFFS := preload("res://assets/fx/puff_sheet.png")
const FRAMES := 5

## Direction the steam leaves the vent (rotated with the node).
@export var direction := Vector2(0, -1)
@export var speed := 34.0
@export var spread_deg := 10.0
@export_range(1, 120) var amount := 26
@export var lifetime := 1.5
## Lit like the world, so it is brighter than 1 to survive the night tint.
@export var steam_color := Color(2.0, 2.2, 2.6, 0.5)
## Seconds on / off. Leave either at 0 for a steady vent.
@export var cycle_on := 0.0
@export var cycle_off := 0.0
@export var active := true:
	set(v):
		var changed := v != active
		active = v
		if _p == null:
			return
		_p.emitting = v
		if changed:
			if v:
				vent_started.emit()
			else:
				vent_stopped.emit()

var _p: CPUParticles2D
var _t := 0.0


func _ready() -> void:
	_p = CPUParticles2D.new()
	_p.texture = PUFFS
	var mat := CanvasItemMaterial.new()
	mat.particles_animation = true
	mat.particles_anim_h_frames = FRAMES
	mat.particles_anim_v_frames = 1
	mat.particles_anim_loop = false
	_p.material = mat
	_p.anim_speed_min = 1.0
	_p.anim_speed_max = 1.0
	_p.amount = amount
	_p.lifetime = lifetime
	_p.preprocess = lifetime if active else 0.0
	_p.local_coords = false
	_p.direction = direction
	_p.spread = spread_deg
	_p.gravity = Vector2(4, -14)
	_p.initial_velocity_min = speed * 0.7
	_p.initial_velocity_max = speed
	_p.damping_min = 8.0
	_p.damping_max = 16.0
	_p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_p.emission_rect_extents = Vector2(1.5, 0.5)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.1, Color(1, 1, 1, 1.0))
	ramp.add_point(0.55, Color(1, 1, 1, 0.6))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	_p.color_ramp = ramp
	_p.color = steam_color
	_p.emitting = active
	_p.light_mask = LightingRig.MASK_WORLD
	add_child(_p)


func set_active(on: bool) -> void:
	active = on


func is_venting() -> bool:
	return active


func _process(delta: float) -> void:
	if cycle_on <= 0.0 or cycle_off <= 0.0:
		return
	_t += delta
	var period := cycle_on + cycle_off
	var want := fmod(_t, period) < cycle_on
	if want != active:
		set_active(want)
