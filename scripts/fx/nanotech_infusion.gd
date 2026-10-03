class_name NanotechInfusion
extends Node
## Puts the nanotech_veins overlay on every mesh under a body and keeps it in
## body space. Add as a child of the body (or set body), then drive it:
##     infusion.infuse(4.0)                       # goo rises, veins grow
##     infusion.set_color(NanoPalette.SPRING)     # a pad recolours the veins
##     infusion.clear_goo(1.5)                    # goo fades, veins stay
##     infusion.drain(1.5)                        # veins recede
## or set progress directly every frame.

const VEINS_SHADER := preload("res://shaders/nanotech_veins.gdshader")

## Body root. Empty = parent.
@export var body: NodePath
@export_range(0.0, 1.0) var progress := 0.0:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		if _mat:
			_mat.set_shader_parameter("progress", progress)
@export var vein_color := NanoPalette.SURGE:
	set(v):
		vein_color = v
		if _mat:
			_mat.set_shader_parameter("vein_color", vein_color)
## Body-space height range. Leave both 0 to measure the meshes on ready.
@export var height_min := 0.0
@export var height_max := 0.0
## Vein noise frequency per metre; raise it for small bodies.
@export var vein_scale := 6.0

var _mat: ShaderMaterial
var _body: Node3D
var _tween: Tween


func _ready() -> void:
	_body = (get_node_or_null(body) if not body.is_empty() else get_parent()) as Node3D
	if _body == null:
		push_warning("NanotechInfusion: no Node3D body")
		return
	_mat = ShaderMaterial.new()
	_mat.shader = VEINS_SHADER
	var meshes := _body.find_children("*", "MeshInstance3D", true, false)
	if _body is MeshInstance3D:
		meshes.append(_body)
	if is_zero_approx(height_min) and is_zero_approx(height_max):
		_measure(meshes)
	_mat.set_shader_parameter("height_min", height_min)
	_mat.set_shader_parameter("height_max", height_max)
	_mat.set_shader_parameter("vein_scale", vein_scale)
	_mat.set_shader_parameter("progress", progress)
	_mat.set_shader_parameter("vein_color", vein_color)
	for mi in meshes:
		(mi as MeshInstance3D).material_overlay = _mat


func _process(_delta: float) -> void:
	if _mat and _body:
		_mat.set_shader_parameter("body_inv", Projection(_body.global_transform.affine_inverse()))


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
	_tween.tween_method(func(v: float) -> void: _mat.set_shader_parameter("goo_opacity", v), 0.92, 0.0, duration)
	return _tween


func reset() -> void:
	_kill_tween()
	progress = 0.0
	if _mat:
		_mat.set_shader_parameter("goo_opacity", 0.92)


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
