class_name CineZoom
extends Node
## Smooth, crisp cinematic zoom onto a world point, for pixel art.
##
## The game keeps rendering at its 640x360 internal size; CineZoom redraws
## that frame to the window at native resolution, magnified about a tracked
## target (shaders/cine_zoom.gdshader, sharp-bilinear). The zoom can glide
## through any value without the uneven-pixel shimmer that a fractional
## Camera2D zoom causes at the internal resolution, and the level camera's
## zoom is never touched. Letterbox bars, a soft vignette and a focus shake
## are drawn at native res too.
##
##     var cz := CineZoom.new()
##     add_child(cz)
##     cz.target = cat
##     cz.target_offset = Vector2(0, -16)
##     create_tween().tween_property(cz, "zoom", 2.5, 4.0)
##
## The extra pass exists only while zoom > 1 or bars > 0. Requires the
## project's viewport stretch mode (the game frame is the root viewport).
## The HUD and every CanvasLayer of the root viewport are magnified with
## the frame, so hide the HUD while zoomed.

const SHADER := preload("res://shaders/cine_zoom.gdshader")

## Magnification (1 = off).
@export_range(1.0, 6.0, 0.01) var zoom := 1.0:
	set(v):
		zoom = maxf(v, 1.0)
		_update()
## Letterbox bars, 0..1.
@export_range(0.0, 1.0, 0.01) var bars := 0.0:
	set(v):
		bars = v
		_update()
@export_range(0.0, 1.0, 0.01) var vignette := 0.0:
	set(v):
		vignette = v
		_update()
## The world node to keep in view, and an offset from it (world px). With
## no target the view centre is `focus` in game px.
var target: Node2D
var target_offset := Vector2.ZERO
var focus := Vector2(320, 180)

var _mat: ShaderMaterial
var _vp := RID()
var _canvas := RID()
var _item := RID()
var _shake := 0.0
var _shake_decay := 3.0
var _t := 0.0


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	get_tree().root.size_changed.connect(_layout)
	process_priority = 1000  # after the camera and the target have moved


## Shake the magnified view (0..1); dies away over about `duration` s.
func shake(strength := 0.5, duration := 0.35) -> void:
	_shake = clampf(_shake + strength, 0.0, 1.0)
	_shake_decay = 1.0 / maxf(duration, 0.05)


func _process(delta: float) -> void:
	_t += delta
	_shake = maxf(_shake - _shake_decay * delta, 0.0)
	if not _vp.is_valid():
		return
	var game := get_viewport()
	var c := focus
	if is_instance_valid(target):
		c = (target.get_global_transform_with_canvas() * target_offset)
	if _shake > 0.0:
		var k := _shake * _shake * 6.0
		c += Vector2(sin(_t * 31.0) * 0.6 + sin(_t * 71.0) * 0.4, sin(_t * 37.0) * 0.6 + sin(_t * 63.0) * 0.4) * k
	_mat.set_shader_parameter("focus", c)
	_mat.set_shader_parameter("src_size", game.get_visible_rect().size)


func _update() -> void:
	if not is_inside_tree():
		return
	var want := zoom > 1.0001 or bars > 0.0001
	if want and not _vp.is_valid():
		_create()
	elif not want and _vp.is_valid():
		_free()
	if _mat:
		_mat.set_shader_parameter("zoom", zoom)
		_mat.set_shader_parameter("bars", bars)
		_mat.set_shader_parameter("vignette", vignette)


func _create() -> void:
	var rs := RenderingServer
	_vp = rs.viewport_create()
	rs.viewport_set_active(_vp, true)
	rs.viewport_set_update_mode(_vp, RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	rs.viewport_set_clear_mode(_vp, RenderingServer.VIEWPORT_CLEAR_ALWAYS)
	_canvas = rs.canvas_create()
	rs.viewport_attach_canvas(_vp, _canvas)
	_item = rs.canvas_item_create()
	rs.canvas_item_set_parent(_item, _canvas)
	rs.canvas_item_set_material(_item, _mat.get_rid())
	_mat.set_shader_parameter("src", get_viewport().get_texture())
	_layout()
	_process(0.0)


func _layout() -> void:
	if not _vp.is_valid():
		return
	var rs := RenderingServer
	var win := Vector2(DisplayServer.window_get_size())
	var src := get_viewport().get_visible_rect().size
	var k := maxf(floorf(minf(win.x / src.x, win.y / src.y)), 1.0)
	var rect := Rect2(((win - src * k) * 0.5).floor(), src * k)
	_mat.set_shader_parameter("out_size", rect.size)
	rs.viewport_set_size(_vp, int(win.x), int(win.y))
	rs.canvas_item_clear(_item)
	rs.canvas_item_add_rect(_item, rect, Color.WHITE)
	rs.viewport_attach_to_screen(_vp, Rect2(Vector2.ZERO, win), DisplayServer.MAIN_WINDOW_ID)


func _free() -> void:
	var rs := RenderingServer
	rs.viewport_attach_to_screen(_vp, Rect2(), DisplayServer.INVALID_WINDOW_ID)
	rs.free_rid(_item)
	rs.free_rid(_canvas)
	rs.free_rid(_vp)
	_vp = RID()
	_canvas = RID()
	_item = RID()


func _exit_tree() -> void:
	if _vp.is_valid():
		_free()
