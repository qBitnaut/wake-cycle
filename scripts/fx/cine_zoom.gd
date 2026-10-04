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
## The close-up is opaque and full screen: it is drawn over a black
## backdrop with blending off, so nothing of the normal frame shows
## through, and as the zoom passes 1..fill_zoom the view grows from the
## game's own letterboxed rect (identical to the normal frame at zoom 1)
## to cover the whole window, whatever its aspect.
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
##
## HD effects: fx_item() hands out canvas items drawn at native resolution
## between the magnified frame and the letterbox (additive by default,
## optionally clipped), and game_to_window() / window_scale() map game
## pixels onto them. NanoHD draws the transformation's glow there.
##
## Overlay (subtitles, captions): attach_overlay(layer) draws a CanvasLayer
## unmagnified, above the close-up and the letterbox, for as long as the
## pass lasts. Its controls keep their 640x360 layout and sit where they
## sit in normal play, at the game's own integer scale (crisp pixel text).
## The layer renders into a transparent SubViewport (its custom_viewport)
## and is handed back to the game frame by itself when the pass ends.
##
##     var cz := CineZoom.current()        # the live pass, or null
##     if cz:
##         cz.attach_overlay(subtitle_layer)
##
## pass_started / pass_ended fire as the pass is created and freed, and
## every CineZoom is in the "cine_zoom" group.

signal pass_started
signal pass_ended

const SHADER := preload("res://shaders/cine_zoom.gdshader")
const OVERLAY_INDEX := 2000  # above the letterbox (1000)

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
## The zoom at which the close-up has grown to fill the whole window.
@export_range(1.0, 3.0, 0.01) var fill_zoom := 1.5
## The world node to keep in view, and an offset from it (world px). With
## no target the view centre is `focus` in game px.
var target: Node2D
var target_offset := Vector2.ZERO
var focus := Vector2(320, 180)

var _mat: ShaderMaterial
var _vp := RID()
var _canvas := RID()
var _item := RID()
var _bars := RID()
var _fx: Array[RID] = []
var _add_mat: CanvasItemMaterial
var _back := RID()
var _rect := Rect2()        # the close-up's window rect this frame
var _drawn := Rect2()       # the rect last given to the canvas item
var _win := Vector2(1280, 720)
var _fit := Rect2()         # the game's own rect in the window (zoom 1)
var _k_fit := 2.0           # window px per game px in _fit
var _k_fill := 2.0          # window px per game px covering the window
var _k := 2.0               # window px per game px at zoom 1, this frame
var _src := Vector2(640, 360)
var _c := Vector2(320, 180)
var _shake := 0.0
var _shake_decay := 3.0
var _t := 0.0
var _overlay: SubViewport
var _overlay_item := RID()
var _overlay_mat: CanvasItemMaterial
var _overlay_layers: Array[CanvasLayer] = []
var _overlay_prev := {}     # layer -> the viewport it drew into before

static var _current: CineZoom


func _ready() -> void:
	add_to_group("cine_zoom")
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_overlay_mat = CanvasItemMaterial.new()
	_overlay_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	get_tree().root.size_changed.connect(_layout)
	process_priority = 1000  # after the camera and the target have moved


## The CineZoom whose pass is live (zoom > 1 or bars > 0), or null.
static func current() -> CineZoom:
	if is_instance_valid(_current) and _current.has_fx():
		return _current
	return null


## Draw `layer` unmagnified over the close-up and the letterbox until the
## pass ends (then it goes back to the game frame by itself). Does nothing
## without a live pass.
func attach_overlay(layer: CanvasLayer) -> void:
	if not _vp.is_valid() or layer == null or _overlay_layers.has(layer):
		return
	if _overlay == null:
		_open_overlay()
	_overlay_prev[layer] = layer.custom_viewport
	layer.custom_viewport = _overlay
	_overlay_layers.append(layer)


## Hand `layer` back to the game frame before the pass ends.
func detach_overlay(layer: CanvasLayer) -> void:
	if not _overlay_layers.has(layer):
		return
	_overlay_layers.erase(layer)
	_restore(layer)


## Back to the viewport it drew into before (Godot 4.7 refuses a null
## custom_viewport, so the game frame is named explicitly).
func _restore(layer: CanvasLayer) -> void:
	var prev: Variant = _overlay_prev.get(layer)
	_overlay_prev.erase(layer)
	if not is_instance_valid(layer):
		return
	if prev == null or not is_instance_valid(prev):
		prev = get_tree().root
	layer.custom_viewport = prev


func is_overlaid(layer: CanvasLayer) -> bool:
	return _overlay_layers.has(layer)


func _open_overlay() -> void:
	_overlay = SubViewport.new()
	_overlay.name = "Overlay"
	_overlay.size = Vector2i(_src)
	_overlay.transparent_bg = true
	_overlay.disable_3d = true
	_overlay.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_overlay.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_overlay)
	var rs := RenderingServer
	_overlay_item = rs.canvas_item_create()
	rs.canvas_item_set_parent(_overlay_item, _canvas)
	rs.canvas_item_set_draw_index(_overlay_item, OVERLAY_INDEX)
	rs.canvas_item_set_material(_overlay_item, _overlay_mat.get_rid())
	rs.canvas_item_set_default_texture_filter(_overlay_item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
	_draw_overlay()


## The overlay sits exactly where the game frame sits in normal play.
func _draw_overlay() -> void:
	if not _overlay_item.is_valid():
		return
	_overlay.size = Vector2i(_src)
	RenderingServer.canvas_item_clear(_overlay_item)
	RenderingServer.canvas_item_add_texture_rect(_overlay_item, _fit, _overlay.get_texture().get_rid())


func _close_overlay() -> void:
	for l in _overlay_layers:
		_restore(l)
	_overlay_layers.clear()
	_overlay_prev.clear()
	if _overlay_item.is_valid():
		RenderingServer.free_rid(_overlay_item)
		_overlay_item = RID()
	if _overlay:
		_overlay.queue_free()
		_overlay = null


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
	_src = game.get_visible_rect().size
	_place()
	var half := (_rect.size * 0.5 / (_k * zoom)).min(_src * 0.5)
	_c = c.clamp(half, _src - half)
	_mat.set_shader_parameter("focus", _c)
	_mat.set_shader_parameter("src_size", _src)
	_draw_bars()


## The close-up's rect and scale for this zoom: the game's own rect at
## zoom 1, easing out to cover the window by fill_zoom.
func _place() -> void:
	var t := smoothstep(1.0, maxf(fill_zoom, 1.001), zoom)
	_k = lerpf(_k_fit, _k_fill, t)
	var pos := _fit.position.lerp(Vector2.ZERO, t).floor()
	var size := (_fit.size.lerp(_win, t)).ceil()
	_rect = Rect2(pos, size)
	_mat.set_shader_parameter("out_size", _rect.size)
	_mat.set_shader_parameter("scale", _k * zoom)
	if _rect != _drawn and _item.is_valid():
		_drawn = _rect
		RenderingServer.canvas_item_clear(_item)
		RenderingServer.canvas_item_add_rect(_item, _rect, Color.WHITE)


## True while the native-resolution pass exists (zoom > 1 or bars > 0).
func has_fx() -> bool:
	return _vp.is_valid()


## A canvas item drawn at native resolution over the close-up and under the
## letterbox. Additive unless `additive` is false. Freed with the pass; draw
## into it with RenderingServer.canvas_item_* (clear it every frame).
func fx_item(additive := true) -> RID:
	if not _vp.is_valid():
		return RID()
	var it := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(it, _canvas)
	RenderingServer.canvas_item_set_draw_index(it, 10 + _fx.size())
	if additive:
		RenderingServer.canvas_item_set_material(it, _add_mat.get_rid())
	_fx.append(it)
	return it


## Clip an fx item to a window rect (e.g. above a liquid's surface).
func clip_fx(it: RID, rect: Rect2) -> void:
	RenderingServer.canvas_item_set_custom_rect(it, true, rect)
	RenderingServer.canvas_item_set_clip(it, true)


## A game-pixel position (the 640x360 frame) to window pixels.
func game_to_window(p: Vector2) -> Vector2:
	return _rect.position + _rect.size * 0.5 + (p - _c) * (_k * zoom)


## Window pixels per game pixel at the current zoom.
func window_scale() -> float:
	return _k * zoom


func window_rect() -> Rect2:
	return _rect


func _draw_bars() -> void:
	if not _bars.is_valid():
		return
	RenderingServer.canvas_item_clear(_bars)
	var h := roundf(_rect.size.y * 0.1 * bars)
	if h <= 0.0:
		return
	RenderingServer.canvas_item_add_rect(_bars, Rect2(_rect.position, Vector2(_rect.size.x, h)), Color.BLACK)
	RenderingServer.canvas_item_add_rect(_bars, Rect2(_rect.position + Vector2(0, _rect.size.y - h), Vector2(_rect.size.x, h)), Color.BLACK)


func _update() -> void:
	if not is_inside_tree():
		return
	var want := zoom > 1.0001 or bars > 0.0001
	if want and not _vp.is_valid():
		_create()
	elif not want and _vp.is_valid():
		_free()
	if _mat:
		_mat.set_shader_parameter("vignette", vignette)
	if _vp.is_valid():
		_place()


func _create() -> void:
	var rs := RenderingServer
	_vp = rs.viewport_create()
	rs.viewport_set_active(_vp, true)
	rs.viewport_set_update_mode(_vp, RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	rs.viewport_set_clear_mode(_vp, RenderingServer.VIEWPORT_CLEAR_ALWAYS)
	_canvas = rs.canvas_create()
	rs.viewport_attach_canvas(_vp, _canvas)
	# An opaque black backdrop under everything: whatever the close-up does
	# not cover is black, never the clear colour or the frame below.
	_back = rs.canvas_item_create()
	rs.canvas_item_set_parent(_back, _canvas)
	rs.canvas_item_set_draw_index(_back, 0)
	_item = rs.canvas_item_create()
	rs.canvas_item_set_parent(_item, _canvas)
	rs.canvas_item_set_draw_index(_item, 1)
	rs.canvas_item_set_material(_item, _mat.get_rid())
	_bars = rs.canvas_item_create()
	rs.canvas_item_set_parent(_bars, _canvas)
	rs.canvas_item_set_draw_index(_bars, 1000)
	_mat.set_shader_parameter("src", get_viewport().get_texture())
	_layout()
	_process(0.0)
	_current = self
	pass_started.emit()


func _layout() -> void:
	if not _vp.is_valid():
		return
	var rs := RenderingServer
	var win := Vector2(DisplayServer.window_get_size())
	var src := get_viewport().get_visible_rect().size
	# Where the game itself sits in the window (stretch mode viewport, keep).
	var k := minf(win.x / src.x, win.y / src.y)
	if get_tree().root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER:
		k = maxf(floorf(k), 1.0)
	_win = win
	_src = src
	_k_fit = k
	_fit = Rect2(((win - src * k) * 0.5).floor(), src * k)
	_k_fill = maxf(win.x / src.x, win.y / src.y)
	_drawn = Rect2()
	rs.viewport_set_size(_vp, int(win.x), int(win.y))
	rs.canvas_item_clear(_back)
	rs.canvas_item_add_rect(_back, Rect2(Vector2.ZERO, win), Color.BLACK)
	_place()
	_draw_overlay()
	rs.viewport_attach_to_screen(_vp, Rect2(Vector2.ZERO, win), DisplayServer.MAIN_WINDOW_ID)


func _free() -> void:
	_close_overlay()
	var rs := RenderingServer
	rs.viewport_attach_to_screen(_vp, Rect2(), DisplayServer.INVALID_WINDOW_ID)
	for it in _fx:
		rs.free_rid(it)
	_fx.clear()
	rs.free_rid(_bars)
	_bars = RID()
	rs.free_rid(_back)
	_back = RID()
	rs.free_rid(_item)
	rs.free_rid(_canvas)
	rs.free_rid(_vp)
	_vp = RID()
	_canvas = RID()
	_item = RID()
	if _current == self:
		_current = null
	pass_ended.emit()


func _exit_tree() -> void:
	if _vp.is_valid():
		_free()
