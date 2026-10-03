@tool
class_name EnhancementPad
extends Node3D
## Visual for an enhancement pad: glowing rim, a soft light column, rising
## specks and a slow pulse. Pick a power (sets the colour from NanoPalette)
## or set pad_color directly. Visual only: gameplay triggers live elsewhere.

@export var power: NanoPalette.Power = NanoPalette.Power.SURGE:
	set(v):
		power = v
		pad_color = NanoPalette.color_of(v)
@export var pad_color := NanoPalette.SURGE:
	set(v):
		pad_color = v
		_apply_color()
@export_range(0.0, 8.0) var glow_energy := 2.2:
	set(v):
		glow_energy = v
		_apply_color()
@export var light_energy := 0.9
## Seconds between strong pulses.
@export var pulse_period := 2.8

@onready var _plate: MeshInstance3D = $Plate
@onready var _rim: MeshInstance3D = $Rim
@onready var _column: MeshInstance3D = $Column
@onready var _specks: CPUParticles3D = $Specks
@onready var _light: OmniLight3D = $Light

var _t := 0.0


func _ready() -> void:
	_t = randf() * pulse_period
	_apply_color()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	# Fast attack, slow release, once per period, over a gentle breath.
	var phase := fmod(_t, pulse_period) / pulse_period
	var burst := exp(-phase * 7.0) * smoothstep(0.0, 0.02, phase)
	var breath := 0.5 + 0.5 * sin(_t * 1.3)
	var pulse := clampf(burst * 0.85 + breath * 0.15, 0.0, 1.0)
	(_plate.material_override as ShaderMaterial).set_shader_parameter("pulse", pulse)
	(_rim.material_override as ShaderMaterial).set_shader_parameter("energy", glow_energy * (0.8 + pulse * 0.8))
	(_column.material_override as ShaderMaterial).set_shader_parameter("energy", 0.14 + pulse * 0.22)
	_light.light_energy = light_energy * (0.75 + pulse * 0.6)


func _apply_color() -> void:
	if not is_node_ready():
		return
	(_plate.material_override as ShaderMaterial).set_shader_parameter("pad_color", pad_color)
	(_plate.material_override as ShaderMaterial).set_shader_parameter("energy", glow_energy)
	(_rim.material_override as ShaderMaterial).set_shader_parameter("glow_color", pad_color)
	(_column.material_override as ShaderMaterial).set_shader_parameter("beam_color", pad_color)
	(_specks.material_override as ShaderMaterial).set_shader_parameter("glow_color", pad_color.lightened(0.25))
	_light.light_color = pad_color
