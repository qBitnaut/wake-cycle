class_name FlickerLight
extends Node3D
## A tired sodium or warning lamp: a steady hum with now and then a burst of
## stutters. Drives a light and an emissive material together so the lens,
## halo and the light it throws always agree.

@export var light: Light3D
## Meshes whose material_override has an "energy" shader parameter.
@export var glow_meshes: Array[MeshInstance3D] = []
@export var base_energy := 1.6
@export var stutter_every_min := 3.0
@export var stutter_every_max := 9.0
## 0 = never fully drops out during a stutter, 1 = goes fully dark.
@export_range(0.0, 1.0) var stutter_depth := 0.85

var _glow_base: Array[float] = []
var _next := 0.0
var _stutter := 0.0
var _t := 0.0


func _ready() -> void:
	for mi in glow_meshes:
		var mat := mi.material_override as ShaderMaterial
		_glow_base.append(mat.get_shader_parameter("energy") if mat else 1.0)
	_next = randf_range(stutter_every_min, stutter_every_max)


func _process(delta: float) -> void:
	_t += delta
	_next -= delta
	if _next <= 0.0:
		_stutter = randf_range(0.25, 0.7)
		_next = randf_range(stutter_every_min, stutter_every_max)
	var k := 1.0 + sin(_t * 47.0) * 0.015 + sin(_t * 3.1) * 0.03
	if _stutter > 0.0:
		_stutter -= delta
		# Square-ish chatter, like a failing starter.
		var chatter := 1.0 if sin(_t * 60.0 + sin(_t * 23.0) * 4.0) > 0.2 else 1.0 - stutter_depth
		k *= chatter
	if light:
		light.light_energy = base_energy * k
	for i in glow_meshes.size():
		var mat := glow_meshes[i].material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("energy", _glow_base[i] * k)
