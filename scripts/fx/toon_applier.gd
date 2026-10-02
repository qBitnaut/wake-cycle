@tool
class_name ToonApplier
extends Node
## Swaps every surface under a node tree to the Wake Cycle toon shader,
## keeping each source material's albedo texture and colour, and adds the
## inverted-hull outline as next_pass.
##
## Drop it as a child of an imported GLB instance (it applies to its parent on
## ready), or call it from code:
##     ToonApplier.apply_to(cat_root)
##     ToonApplier.apply_to(robot, {"outline_width": 0.02, "rim_strength": 1.2})

const TOON_SHADER := preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://shaders/toon_outline.gdshader")

## Node whose subtree is converted. Empty = parent.
@export var target: NodePath
@export var apply_on_ready := true
@export var outline := true
@export var outline_width := 0.015
@export var outline_color := Color(0.02, 0.03, 0.07)
## Bake averaged normals into TANGENT so hulls do not crack on hard edges.
## Duplicates each mesh once (cached), so leave it off for huge level meshes.
@export var smooth_outline_normals := true
@export_range(1, 4) var band_count := 3
@export var rim_strength := 0.8
@export var rim_color := Color(0.62, 0.74, 1.0)

static var _material_cache := {}
static var _mesh_cache := {}


func _ready() -> void:
	if apply_on_ready and not Engine.is_editor_hint():
		var root := get_node_or_null(target) if not target.is_empty() else get_parent()
		if root:
			apply_to(root, {
				"outline": outline,
				"outline_width": outline_width,
				"outline_color": outline_color,
				"smooth_outline_normals": smooth_outline_normals,
				"band_count": band_count,
				"rim_strength": rim_strength,
				"rim_color": rim_color,
			})


## Converts all MeshInstance3D nodes under root. Options (all optional):
## outline, outline_width, outline_color, smooth_outline_normals,
## band_count, rim_strength, rim_color.
static func apply_to(root: Node, options := {}) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect(root, meshes)
	for mi in meshes:
		_apply_mesh(mi, options)


static func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect(child, out)


static func _apply_mesh(mi: MeshInstance3D, options: Dictionary) -> void:
	if mi.mesh == null:
		return
	var use_outline: bool = options.get("outline", true)
	var smooth: bool = use_outline and options.get("smooth_outline_normals", true)
	if smooth:
		var smoothed := _smoothed_mesh(mi.mesh)
		if smoothed:
			mi.mesh = smoothed
		else:
			smooth = false
	for i in mi.mesh.get_surface_count():
		var src := mi.get_active_material(i)
		mi.set_surface_override_material(i, _toon_material(src, options, smooth))
	# material_override would otherwise win over the per-surface materials.
	mi.material_override = null


static func _toon_material(src: Material, options: Dictionary, smooth: bool) -> ShaderMaterial:
	var key := "%s|%s|%s" % [src.get_instance_id() if src else 0, smooth, str(options)]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	if src is BaseMaterial3D:
		var base := src as BaseMaterial3D
		mat.set_shader_parameter("albedo_color", base.albedo_color)
		if base.albedo_texture:
			mat.set_shader_parameter("albedo_texture", base.albedo_texture)
		mat.set_shader_parameter("use_vertex_color", base.vertex_color_use_as_albedo)
		if base.emission_enabled:
			mat.set_shader_parameter("emission_color", base.emission)
			mat.set_shader_parameter("emission_energy", base.emission_energy_multiplier)
	elif src is ShaderMaterial and (src as ShaderMaterial).shader == TOON_SHADER:
		mat = (src as ShaderMaterial).duplicate()
	mat.set_shader_parameter("band_count", options.get("band_count", 3))
	mat.set_shader_parameter("rim_strength", options.get("rim_strength", 0.8))
	mat.set_shader_parameter("rim_color", options.get("rim_color", Color(0.62, 0.74, 1.0)))
	if options.get("outline", true):
		var outline_mat := ShaderMaterial.new()
		outline_mat.shader = OUTLINE_SHADER
		outline_mat.set_shader_parameter("outline_width", options.get("outline_width", 0.015))
		outline_mat.set_shader_parameter("outline_color", options.get("outline_color", Color(0.02, 0.03, 0.07)))
		outline_mat.set_shader_parameter("use_smoothed_normals", smooth)
		mat.next_pass = outline_mat
	else:
		mat.next_pass = null
	_material_cache[key] = mat
	return mat


## Returns a copy of mesh whose TANGENT channel holds per-position averaged
## normals, or null if the mesh cannot be converted (no normals, or blend
## shapes, whose arrays would no longer match). Skin data is kept.
static func _smoothed_mesh(mesh: Mesh) -> ArrayMesh:
	var id := mesh.get_instance_id()
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var src: ArrayMesh = mesh if mesh is ArrayMesh else _to_array_mesh(mesh)
	if src.get_blend_shape_count() > 0:
		return null
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		if normals == null or (normals as PackedVector3Array).is_empty():
			return null
		var sums := {}
		for v in verts.size():
			var k := _pos_key(verts[v])
			sums[k] = sums.get(k, Vector3.ZERO) + normals[v]
		var tangents := PackedFloat32Array()
		tangents.resize(verts.size() * 4)
		for v in verts.size():
			var n: Vector3 = sums[_pos_key(verts[v])]
			n = n.normalized() if n.length_squared() > 0.000001 else normals[v]
			tangents[v * 4] = n.x
			tangents[v * 4 + 1] = n.y
			tangents[v * 4 + 2] = n.z
			tangents[v * 4 + 3] = 1.0
		arrays[Mesh.ARRAY_TANGENT] = tangents
		var flags := src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays, [], {}, flags)
		out.surface_set_material(s, src.surface_get_material(s))
		out.surface_set_name(s, src.surface_get_name(s))
	_mesh_cache[id] = out
	_mesh_cache[out.get_instance_id()] = out
	return out


static func _to_array_mesh(mesh: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out


static func _pos_key(v: Vector3) -> Vector3i:
	return Vector3i((v * 1000.0).round())
