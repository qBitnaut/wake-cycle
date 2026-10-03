class_name NanotechInfusion
extends Node
## Puts the nanotech_veins overlay on every mesh under a body and keeps it in
## body space. Add as a child of the body (or set body), then drive it:
##     infusion.infuse(4.0)                       # goo rises, veins grow
##     infusion.set_color(NanoPalette.SPRING)     # a pad recolours the veins
##     infusion.clear_goo(1.5)                    # goo fades, veins stay
##     infusion.drain(1.5)                        # veins recede
## or set progress directly every frame.
##
## Skinned meshes baked by CatSkin carry their bind-pose position in CUSTOM0.
## Those get a second material that reads it (use_bind_pose), so the veins stay
## on the fur while the skeleton animates. Meshes without CUSTOM0 keep the
## body_inv path. Add this node after CatSkin so the meshes are baked first,
## and call refresh() if the body is rescaled afterwards.

const VEINS_SHADER := preload("res://shaders/nanotech_veins.gdshader")

## Body root. Empty = parent.
@export var body: NodePath
@export_range(0.0, 1.0) var progress := 0.0:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		_set_all("progress", progress)
@export var vein_color := NanoPalette.SURGE:
	set(v):
		vein_color = v
		_set_all("vein_color", vein_color)
## Body-space height range. Leave both 0 to measure the meshes on ready.
@export var height_min := 0.0
@export var height_max := 0.0
## Vein noise frequency per metre; raise it for small bodies (the cat uses 22).
@export var vein_scale := 6.0

var _mats: Array[ShaderMaterial] = []
var _live_mat: ShaderMaterial ## Material for meshes without CUSTOM0 (needs body_inv).
var _bind_mat: ShaderMaterial ## Material for meshes with a CUSTOM0 bind pose.
var _body: Node3D
var _measured := false
var _tween: Tween


func _ready() -> void:
	_body = (get_node_or_null(body) if not body.is_empty() else get_parent()) as Node3D
	if _body == null:
		push_warning("NanotechInfusion: no Node3D body")
		return
	refresh()


## (Re)builds the overlay materials, measures the body and captures the static
## bind_to_body matrix from the body's current transforms.
func refresh() -> void:
	if _body == null:
		return
	var meshes := _body.find_children("*", "MeshInstance3D", true, false)
	if _body is MeshInstance3D:
		meshes.append(_body)
	if _measured or (is_zero_approx(height_min) and is_zero_approx(height_max)):
		_measure(meshes)
	_mats.clear()
	_live_mat = null
	_bind_mat = null
	for node in meshes:
		var mi := node as MeshInstance3D
		var baked := _has_bind_pose(mi)
		if baked and _bind_mat == null:
			_bind_mat = _make_material()
			_bind_mat.set_shader_parameter("use_bind_pose", true)
			_bind_mat.set_shader_parameter("bind_to_body", Projection(_body.global_transform.affine_inverse() * mi.global_transform))
		elif not baked and _live_mat == null:
			_live_mat = _make_material()
		mi.material_overlay = _bind_mat if baked else _live_mat


func _make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = VEINS_SHADER
	mat.set_shader_parameter("height_min", height_min)
	mat.set_shader_parameter("height_max", height_max)
	mat.set_shader_parameter("vein_scale", vein_scale)
	mat.set_shader_parameter("progress", progress)
	mat.set_shader_parameter("vein_color", vein_color)
	_mats.append(mat)
	return mat


func _has_bind_pose(mi: MeshInstance3D) -> bool:
	var mesh := mi.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	for s in mesh.get_surface_count():
		if mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_CUSTOM0 == 0:
			return false
	return true


func _set_all(param: StringName, value: Variant) -> void:
	for mat in _mats:
		mat.set_shader_parameter(param, value)


func _process(_delta: float) -> void:
	if _live_mat and _body:
		_live_mat.set_shader_parameter("body_inv", Projection(_body.global_transform.affine_inverse()))


## Animates progress from its current value to 1 over duration seconds.
func infuse(duration := 4.0) -> Tween:
	return _tween_param("progress", 1.0, duration)


func set_color(color: Color) -> void:
	vein_color = color


## Veins recede back down to the feet.
func drain(duration := 1.5) -> Tween:
	return _tween_param("progress", 0.0, duration)


## Fades the goo out while the veins keep glowing.
func clear_goo(duration := 1.5) -> Tween:
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void: _set_all(&"goo_opacity", v), 0.92, 0.0, duration)
	return _tween


func reset() -> void:
	_kill_tween()
	progress = 0.0
	_set_all(&"goo_opacity", 0.92)


func _tween_param(prop: String, to: float, duration: float) -> Tween:
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, prop, to, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return _tween


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()


func _measure(meshes: Array) -> void:
	var inv := _body.global_transform.affine_inverse()
	var lo := INF
	var hi := -INF
	for node in meshes:
		var mi := node as MeshInstance3D
		var aabb := mi.get_aabb()
		for i in 8:
			var p: Vector3 = inv * (mi.global_transform * aabb.get_endpoint(i))
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	if lo < hi:
		height_min = lo
		height_max = hi
		_measured = true
