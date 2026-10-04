class_name RoomTransition
extends RefCounted
## Room to room: fade to black, load the next scene, fade up from black.
## The new Level sees `arriving` and auto-saves at its start (Level._ready).

const FADE := 0.7

## True between leaving one room and the next Level finishing its _ready.
static var arriving := false
static var _busy := false


## Fade `from` to black, then load `scene_path`. Safe to call twice.
static func go(from: Node, scene_path: String, fade := FADE) -> void:
	if _busy:
		return
	_busy = true
	var tree := from.get_tree()
	var layer := _black_layer(from)
	var rect: ColorRect = layer.get_child(0)
	var tw := layer.create_tween()
	tw.tween_property(rect, "modulate:a", 1.0, fade)
	await tw.finished
	arriving = true
	_busy = false
	tree.change_scene_to_file(scene_path)


## Fade up from black over `level` (call on arrival).
static func fade_in(level: Node, fade := FADE) -> void:
	var layer := _black_layer(level)
	var rect: ColorRect = layer.get_child(0)
	rect.modulate.a = 1.0
	var tw := layer.create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, fade)
	tw.tween_callback(layer.queue_free)


static func _black_layer(host: Node) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "RoomFade"
	layer.layer = 110
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.modulate.a = 0.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	host.add_child(layer)
	return layer
