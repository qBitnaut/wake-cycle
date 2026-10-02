@tool
class_name Puddle
extends MeshInstance3D
## Drives puddle.gdshader / nanotech_pool.gdshader on a flat PlaneMesh:
## feeds drip ripples (add_ripple) and gathers every Moonbeam in the
## "moonbeams" group into the fake reflection. Lay the plane flat; size it
## with the PlaneMesh rather than node scale so ripples stay round.

const MAX_RIPPLES := 6
const MAX_BEAMS := 6

## Re-read moonbeams every frame (only needed if beams move).
@export var track_beams := false

var _clock := 0.0
var _ripples: Array[Vector4] = []
var _editor_refresh := 0.0


func _ready() -> void:
	# Each puddle needs its own ripple state, so own the material at runtime.
	if not Engine.is_editor_hint() and material_override:
		material_override = material_override.duplicate()
	refresh_beams.call_deferred()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		# Keep the editor preview in step with beams being moved around.
		_editor_refresh -= delta
		if _editor_refresh <= 0.0:
			_editor_refresh = 0.5
			refresh_beams()
		return
	if track_beams:
		refresh_beams()
	if _ripples.is_empty():
		return
	_clock += delta
	var mat := _material()
	if mat == null:
		return
	var life: float = mat.get_shader_parameter("ripple_life")
	_ripples = _ripples.filter(func(r: Vector4) -> bool: return _clock - r.z < life)
	mat.set_shader_parameter("fx_time", _clock)
	_push_ripples(mat)


## Starts a ripple ring at a world position (called by WaterDrip on impact).
func add_ripple(world_pos: Vector3, strength := 1.0) -> void:
	var local := to_local(world_pos)
	if _ripples.size() >= MAX_RIPPLES:
		_ripples.pop_front()
	_ripples.append(Vector4(local.x, local.z, _clock, strength))
	var mat := _material()
	if mat:
		mat.set_shader_parameter("fx_time", _clock)
		_push_ripples(mat)


func refresh_beams() -> void:
	var mat := _material()
	if mat == null or not is_inside_tree():
		return
	var tops := PackedVector4Array()
	var bottoms := PackedVector4Array()
	var colors := PackedVector4Array()
	for beam in get_tree().get_nodes_in_group("moonbeams"):
		if tops.size() >= MAX_BEAMS or not beam.has_method("get_reflection_data"):
			continue
		var data: Array = beam.get_reflection_data()
		tops.append(data[0])
		bottoms.append(data[1])
		colors.append(data[2])
	var count := tops.size()
	tops.resize(MAX_BEAMS)
	bottoms.resize(MAX_BEAMS)
	colors.resize(MAX_BEAMS)
	mat.set_shader_parameter("beam_count", count)
	mat.set_shader_parameter("beam_tops", tops)
	mat.set_shader_parameter("beam_bottoms", bottoms)
	mat.set_shader_parameter("beam_colors", colors)


func _push_ripples(mat: ShaderMaterial) -> void:
	var arr := PackedVector4Array(_ripples)
	var count := arr.size()
	arr.resize(MAX_RIPPLES)
	mat.set_shader_parameter("ripple_count", count)
	mat.set_shader_parameter("ripples", arr)


func _material() -> ShaderMaterial:
	if material_override is ShaderMaterial:
		return material_override
	if mesh and mesh.surface_get_material(0) is ShaderMaterial:
		return mesh.surface_get_material(0)
	return null
