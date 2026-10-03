class_name CatSkin
extends Node
## Dresses the player cat ("cat toon shader" by ssombrinha570, CC BY 4.0) as
## a lit mackerel tabby. The source model is an unlit black cat; this swaps
## its materials for shaders/tabby_cat.gdshader, bakes the bind-pose
## position, skin regions and bind-pose normal the stripes need into CUSTOM0,
## CUSTOM1 and CUSTOM2, and removes the magenta inverted-hull outline
## (Object_11).
##
## Add as a child of the imported cat (it dresses its parent on ready), or:
##     CatSkin.apply_to(cat_root)
##     CatSkin.apply_to(cat_root, CatSkin.Coat.GINGER, {"stripe_width": 0.35})
## Overrides go to the body material only (any tabby_cat.gdshader uniform).

const TABBY_SHADER := preload("res://shaders/tabby_cat.gdshader")

enum Coat { BROWN, GINGER, GREY_BROWN }

## Coat palettes (sRGB). Ears take a darker mix of fur and stripe.
const COATS := {
	Coat.BROWN: {
		"fur_color": Color(0.74, 0.52, 0.31),
		"stripe_color": Color(0.33, 0.20, 0.11),
		"cream_color": Color(0.93, 0.84, 0.68),
	},
	Coat.GINGER: {
		"fur_color": Color(0.86, 0.52, 0.24),
		"stripe_color": Color(0.50, 0.24, 0.09),
		"cream_color": Color(0.98, 0.87, 0.68),
	},
	Coat.GREY_BROWN: {
		"fur_color": Color(0.62, 0.55, 0.46),
		"stripe_color": Color(0.27, 0.21, 0.16),
		"cream_color": Color(0.90, 0.86, 0.78),
	},
}

## Mesh nodes in the source GLB.
const BODY := "Object_7"
const EARS := "Object_8"
const MOUTH := "Object_9"
const TEETH := "Object_10"
const OUTLINE := "Object_11"

## Skin bind-name prefixes per region, in CUSTOM1 channel order (x lower
## legs, y tail, z head). Bones not listed count as torso, including the hips
## and shoulders, so the flank bands run down over the thighs.
const REGION_PREFIXES := [
	["osso_do_joelho", "osso_do_jeolho", "pata"],
	["Bone.016", "Bone.017", "Bone.018", "Bone.019"],
	["Bone.005", "Bone.006", "Bone.007", "Bone.008"],
]

## Node whose subtree is dressed. Empty = parent.
@export var target: NodePath
@export var coat := Coat.BROWN
@export var apply_on_ready := true

static var _mesh_cache := {}
static var _material_cache := {}


func _ready() -> void:
	if not apply_on_ready:
		return
	var root := get_node_or_null(target) if not target.is_empty() else get_parent()
	if root:
		apply_to(root, coat)


## Dresses every cat mesh under root. Safe to call again to change coat.
static func apply_to(root: Node, coat_id := Coat.BROWN, overrides := {}) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var part := _part_of(mi)
		if part == "":
			continue
		if part == OUTLINE:
			mi.visible = false
			mi.get_parent().remove_child(mi)
			mi.queue_free()
			continue
		var src := mi.get_active_material(0)
		var tex: Texture2D = null
		if src is BaseMaterial3D:
			tex = (src as BaseMaterial3D).albedo_texture
		elif src is ShaderMaterial:
			tex = (src as ShaderMaterial).get_shader_parameter("albedo_texture")
		var baked := _baked_mesh(mi.mesh, mi.skin, mi.get_node_or_null(mi.skeleton) as Skeleton3D)
		if baked:
			mi.mesh = baked
		mi.material_override = null
		mi.set_surface_override_material(0, _material(part, tex, coat_id, overrides if part == BODY else {}))


static func _part_of(mi: MeshInstance3D) -> String:
	for part in [BODY, EARS, MOUTH, TEETH, OUTLINE]:
		if mi.name == part or mi.name.begins_with(part + "_"):
			return part
	return ""


static func _material(part: String, tex: Texture2D, coat_id: Coat, overrides: Dictionary) -> ShaderMaterial:
	var key := "%s|%s|%s|%s" % [part, tex.get_instance_id() if tex else 0, coat_id, str(overrides)]
	if _material_cache.has(key):
		return _material_cache[key]
	var palette: Dictionary = COATS[coat_id]
	var mat := ShaderMaterial.new()
	mat.shader = TABBY_SHADER
	if tex:
		mat.set_shader_parameter("albedo_texture", tex)
		mat.set_shader_parameter("albedo_color_texture", tex)
	for k in palette:
		mat.set_shader_parameter(k, palette[k])
	if part != BODY:
		# Parts carry no stripes, spectacles or eye ink.
		mat.set_shader_parameter("stripe_strength", 0.0)
		mat.set_shader_parameter("spectacles", 0.0)
		mat.set_shader_parameter("eye_zone_left", Vector4(-9.0, -9.0, 0.01, 0.01))
		mat.set_shader_parameter("eye_zone_right", Vector4(-9.0, -9.0, 0.01, 0.01))
	match part:
		EARS:
			# Darker ear backs; the pink inner ear passes through.
			var fur: Color = palette["fur_color"]
			mat.set_shader_parameter("fur_color", fur.lerp(palette["stripe_color"], 0.35))
		MOUTH, TEETH:
			# Plain lit texture: maroon mouth, white teeth.
			mat.set_shader_parameter("coat_amount", 0.0)
	for k in overrides:
		mat.set_shader_parameter(k, overrides[k])
	_material_cache[key] = mat
	return mat


## Copy of mesh with CUSTOM0 = bind-pose position, CUSTOM1 = skin region
## weights and CUSTOM2 = bind-pose normal. Null if the mesh cannot be
## converted (blend shapes).
static func _baked_mesh(mesh: Mesh, skin: Skin, skeleton: Skeleton3D) -> ArrayMesh:
	if mesh == null:
		return null
	var id := mesh.get_instance_id()
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	if mesh is ArrayMesh and (mesh as ArrayMesh).get_blend_shape_count() > 0:
		push_warning("CatSkin: %s has blend shapes; stripes need a baked mesh" % mesh.resource_name)
		return null
	var regions := _bind_regions(skin, skeleton)
	var custom_flags := (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n := verts.size()
		var normals = arrays[Mesh.ARRAY_NORMAL]
		var has_normals: bool = normals != null and (normals as PackedVector3Array).size() == n
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var eight: int = mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		var per := 8 if eight else 4
		var c0 := PackedFloat32Array()
		var c1 := PackedFloat32Array()
		var c2 := PackedFloat32Array()
		c0.resize(n * 3)
		c1.resize(n * 3)
		c2.resize(n * 3)
		var skinned: bool = bones != null and weights != null and (bones as PackedInt32Array).size() == n * per
		for v in n:
			var p := verts[v]
			var nrm: Vector3 = normals[v] if has_normals else Vector3.UP
			for i in 3:
				c0[v * 3 + i] = p[i]
				c2[v * 3 + i] = nrm[i]
			if not skinned:
				continue
			for k in per:
				var b: int = bones[v * per + k]
				if b >= 0 and b < regions.size() and regions[b] >= 0:
					c1[v * 3 + regions[b]] += weights[v * per + k]
		arrays[Mesh.ARRAY_CUSTOM0] = c0
		arrays[Mesh.ARRAY_CUSTOM1] = c1
		arrays[Mesh.ARRAY_CUSTOM2] = c2
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays, [], {}, eight | custom_flags)
		out.surface_set_material(s, mesh.surface_get_material(s))
		out.surface_set_name(s, mesh.surface_get_name(s))
	out.resource_name = mesh.resource_name
	_mesh_cache[id] = out
	_mesh_cache[out.get_instance_id()] = out
	return out


## Region channel (0..2) per skin bind, or -1 for torso.
static func _bind_regions(skin: Skin, skeleton: Skeleton3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	if skin == null:
		return out
	out.resize(skin.get_bind_count())
	for b in skin.get_bind_count():
		var bind_name := String(skin.get_bind_name(b))
		if bind_name.is_empty() and skeleton and skin.get_bind_bone(b) >= 0:
			bind_name = skeleton.get_bone_name(skin.get_bind_bone(b))
		out[b] = -1
		for r in REGION_PREFIXES.size():
			for prefix in REGION_PREFIXES[r]:
				if bind_name.begins_with(prefix):
					out[b] = r
	return out
