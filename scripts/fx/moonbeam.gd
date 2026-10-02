@tool
class_name Moonbeam
extends Node3D
## A shaft of moonlight from a roof hole or window. The node's origin is the
## opening; the shaft runs down its local -Y. Rotate the node to slant it
## (match the moonlight's direction). Keeps the shaft mesh, dust motes and
## the paired SpotLight3D in sync, and registers in the "moonbeams" group so
## puddles can reflect it.

@export var length := 10.0:
	set(v):
		length = maxf(v, 0.1)
		_sync()
@export var radius_top := 1.2:
	set(v):
		radius_top = maxf(v, 0.01)
		_sync()
@export var radius_bottom := 1.6:
	set(v):
		radius_bottom = maxf(v, 0.01)
		_sync()
## Stretches the shaft along local X (window-shaped shafts).
@export var aspect := 1.0:
	set(v):
		aspect = maxf(v, 0.05)
		_sync()
@export var color := Color(0.64, 0.74, 1.0):
	set(v):
		color = v
		_sync()
@export_range(0.0, 4.0) var beam_energy := 0.5:
	set(v):
		beam_energy = v
		_sync()
## Higher = softer edges and a narrower bright core.
@export_range(0.5, 8.0) var edge_power := 2.2:
	set(v):
		edge_power = v
		_sync()
@export_group("Floor light")
@export var light_enabled := true:
	set(v):
		light_enabled = v
		_sync()
@export_range(0.0, 16.0) var light_energy := 2.5:
	set(v):
		light_energy = v
		_sync()
@export var light_shadows := false:
	set(v):
		light_shadows = v
		_sync()
@export_group("Dust")
@export_range(0, 400) var mote_amount := 70:
	set(v):
		mote_amount = v
		_sync()

@onready var _shaft: MeshInstance3D = $Shaft
@onready var _motes: CPUParticles3D = $Motes
@onready var _spot: SpotLight3D = $Spot


func _ready() -> void:
	add_to_group("moonbeams")
	set_notify_transform(true)
	_sync()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_sync_motes()


## Reflection data for puddles: [top_and_radius, bottom_and_radius, color].
func get_reflection_data() -> Array:
	var top := global_position
	var bottom := global_transform * Vector3(0.0, -length, 0.0)
	var widen := (aspect + 1.0) * 0.5
	return [
		Vector4(top.x, top.y, top.z, radius_top * widen),
		Vector4(bottom.x, bottom.y, bottom.z, radius_bottom * widen),
		Vector4(color.r * beam_energy, color.g * beam_energy, color.b * beam_energy, 1.0),
	]


func _sync() -> void:
	if not is_node_ready():
		return
	var mesh := _shaft.mesh as CylinderMesh
	mesh.height = length
	mesh.top_radius = radius_top
	mesh.bottom_radius = radius_bottom
	_shaft.position = Vector3(0.0, -length * 0.5, 0.0)
	_shaft.scale = Vector3(aspect, 1.0, 1.0)
	var mat := _shaft.material_override as ShaderMaterial
	mat.set_shader_parameter("beam_length", length)
	mat.set_shader_parameter("beam_color", color)
	mat.set_shader_parameter("energy", beam_energy)
	mat.set_shader_parameter("edge_power", edge_power)

	_spot.visible = light_enabled
	_spot.light_color = color
	_spot.light_energy = light_energy
	_spot.shadow_enabled = light_shadows
	_spot.spot_range = length * 1.6
	var spread := maxf(radius_bottom * maxf(aspect, 1.0), radius_top)
	_spot.spot_angle = clampf(rad_to_deg(atan(spread / length)) * 2.2, 1.0, 89.0)

	_motes.amount = maxi(mote_amount, 1)
	_motes.emitting = mote_amount > 0
	_motes.visible = mote_amount > 0
	var rmax := maxf(radius_top, radius_bottom)
	_motes.position = Vector3(0.0, -length * 0.5, 0.0)
	_motes.emission_box_extents = Vector3(rmax * aspect, length * 0.45, rmax)
	var mote_mat := _motes.material_override as ShaderMaterial
	mote_mat.set_shader_parameter("mote_color", color.lightened(0.3))
	mote_mat.set_shader_parameter("beam_length", length)
	mote_mat.set_shader_parameter("radius_top", radius_top)
	mote_mat.set_shader_parameter("radius_bottom", radius_bottom)
	_sync_motes()


func _sync_motes() -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	var beam_frame := global_transform * Transform3D(Basis.from_scale(Vector3(aspect, 1.0, 1.0)), Vector3.ZERO)
	var mote_mat := _motes.material_override as ShaderMaterial
	mote_mat.set_shader_parameter("beam_inv", Projection(beam_frame.affine_inverse()))
