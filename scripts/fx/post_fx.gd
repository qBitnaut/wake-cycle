class_name PostFX
extends CanvasLayer
## Optional retro filters, both off by default:
##
##   EGA  quantises the 320x180 frame to the 16-colour EGA palette with a 4x4
##        Bayer dither. `ega_strength` mixes it with the original.
##   CRT  scanlines, aperture grille and curvature drawn at the display's
##        native resolution (a RenderingServer viewport fed by the game frame),
##        so each game row gets a real beam profile instead of a fat stripe.
##
## The node joins the "post_fx" group, so a floor switch can do:
##     get_tree().get_first_node_in_group("post_fx").toggle_ega()

signal changed(ega_on: bool, crt_on: bool)

const EGA_SHADER := preload("res://shaders/ega_dither.gdshader")
const CRT_SHADER := preload("res://shaders/crt.gdshader")

@export var ega_enabled := false:
	set(v):
		ega_enabled = v
		if _ega_rect:
			_ega_rect.visible = v
		changed.emit(ega_enabled, crt_enabled)
@export_range(0.0, 1.0, 0.01) var ega_strength := 1.0:
	set(v):
		ega_strength = v
		if _ega_mat:
			_ega_mat.set_shader_parameter("strength", v)
@export var crt_enabled := false:
	set(v):
		if v == crt_enabled:
			return
		crt_enabled = v
		if is_node_ready():
			if v:
				_create_crt()
			else:
				_free_crt()
		changed.emit(ega_enabled, crt_enabled)

var _ega_rect: ColorRect
var _ega_mat: ShaderMaterial
var _crt_mat: ShaderMaterial
var _crt_vp := RID()
var _crt_canvas := RID()
var _crt_item := RID()


func _ready() -> void:
	layer = 120
	add_to_group("post_fx")
	_ega_mat = ShaderMaterial.new()
	_ega_mat.shader = EGA_SHADER
	_ega_mat.set_shader_parameter("strength", ega_strength)
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bbc)
	_ega_rect = ColorRect.new()
	_ega_rect.material = _ega_mat
	_ega_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ega_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ega_rect.visible = ega_enabled
	add_child(_ega_rect)
	_crt_mat = ShaderMaterial.new()
	_crt_mat.shader = CRT_SHADER
	get_tree().root.size_changed.connect(_layout_crt)
	if crt_enabled:
		_create_crt()


func set_ega(on: bool) -> void:
	ega_enabled = on


func set_crt(on: bool) -> void:
	crt_enabled = on


func toggle_ega() -> void:
	ega_enabled = not ega_enabled


func toggle_crt() -> void:
	crt_enabled = not crt_enabled


func is_ega_on() -> bool:
	return ega_enabled


func is_crt_on() -> bool:
	return crt_enabled


func _create_crt() -> void:
	if _crt_vp.is_valid():
		return
	var rs := RenderingServer
	_crt_vp = rs.viewport_create()
	rs.viewport_set_active(_crt_vp, true)
	rs.viewport_set_update_mode(_crt_vp, RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	rs.viewport_set_clear_mode(_crt_vp, RenderingServer.VIEWPORT_CLEAR_ALWAYS)
	_crt_canvas = rs.canvas_create()
	rs.viewport_attach_canvas(_crt_vp, _crt_canvas)
	_crt_item = rs.canvas_item_create()
	rs.canvas_item_set_parent(_crt_item, _crt_canvas)
	rs.canvas_item_set_material(_crt_item, _crt_mat.get_rid())
	var game := get_viewport()
	_crt_mat.set_shader_parameter("src", game.get_texture())
	_crt_mat.set_shader_parameter("src_size", Vector2(game.get_visible_rect().size))
	_layout_crt()


func _layout_crt() -> void:
	if not _crt_vp.is_valid():
		return
	var rs := RenderingServer
	var win := Vector2(DisplayServer.window_get_size())
	var src := get_viewport().get_visible_rect().size
	var k := maxf(floorf(minf(win.x / src.x, win.y / src.y)), 1.0)
	var rect := Rect2((win - src * k) * 0.5, src * k).abs()
	rect.position = rect.position.floor()
	rs.viewport_set_size(_crt_vp, int(win.x), int(win.y))
	rs.canvas_item_clear(_crt_item)
	rs.canvas_item_add_rect(_crt_item, rect, Color.WHITE)
	rs.viewport_attach_to_screen(_crt_vp, Rect2(Vector2.ZERO, win), DisplayServer.MAIN_WINDOW_ID)


func _free_crt() -> void:
	if not _crt_vp.is_valid():
		return
	var rs := RenderingServer
	rs.viewport_attach_to_screen(_crt_vp, Rect2(), DisplayServer.INVALID_WINDOW_ID)
	rs.free_rid(_crt_item)
	rs.free_rid(_crt_canvas)
	rs.free_rid(_crt_vp)
	_crt_vp = RID()
	_crt_canvas = RID()
	_crt_item = RID()


func _exit_tree() -> void:
	_free_crt()
